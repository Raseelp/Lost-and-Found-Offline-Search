package dev.raseel.lostandfound.embedder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import dev.raseel.lostandfound.MainActivity
import io.flutter.plugin.common.EventChannel
import kotlin.math.roundToLong

/**
 * Process-wide hub for everything about a scan except the embedding work: the notification, the latest progress tick,
 * the Dart-facing progress sink and the wake lock. It is not an Android Service. ScanWorker owns the
 * foreground-service lifecycle and calls [onScanStarting], [updateProgress] and [onScanEnded]. The state is
 * process-wide because a scan can outlive the Activity that started it.
 */
object ScanForegroundService {

    private const val TAG = "ScanForegroundService"
    const val CHANNEL_ID = "scan_progress"
    const val NOTIFICATION_ID = 4201

    /**
     * Safety ceiling for the wake lock, in milliseconds (3 hours). It is renewed on every progress tick, so a stalled
     * scan cannot hold the lock forever and a long scan never reaches it.
     */
    private const val WAKE_LOCK_TIMEOUT_MS = 3 * 60 * 60 * 1000L

    private const val FACE_REPOST_INTERVAL_MS = 2_000L

    private data class Snapshot(
        val processed: Int,
        val total: Int,
        val embedded: Int,
        val elapsedMs: Long,
        /** [elapsedMs] minus the time spent waiting for faces to be found (see ScanProgress). */
        val activeMs: Long = elapsedMs,
        /** Of [total], the photos and the videos, and how many of each are done (see ScanProgress). */
        val photos: Int = 0,
        val videos: Int = 0,
        val photosDone: Int = 0,
        val videosDone: Int = 0
    )

    /**
     * Where the face scan that works in step with this scan has got to (see FaceFollower). It shows in the same
     * notification, so there is only ever one. [working] is true while the faces of a batch are found (indexing waits
     * meanwhile), with [processed] and [total] counting that batch's photos.
     */
    private data class FaceSnapshot(
        val working: Boolean,
        val tuning: Boolean,
        val processed: Int,
        val total: Int
    )

    @Volatile
    private var faceSnapshot: FaceSnapshot? = null
    @Volatile
    private var lastFacePostAt = 0L

    /**
     * How fast indexing goes (photos or videos embedded over the time spent indexing, so waiting for faces does not
     * slow it down) and how fast the faces of a batch are found. Each is cleared when the part or the batch changes.
     */
    private val indexingRate = ScanNotification.Rate()
    private var indexingRateOnVideos = false
    private val faceRate = ScanNotification.Rate()

    /** Keeps posting and taking down the notification from overlapping (see [onScanEnded]). */
    private val notifyLock = Any()

    /**
     * True once the user swiped this scan's notification away. It is then not posted again for the rest of the scan,
     * which carries on, or it would pop straight back up.
     */
    @Volatile
    var notificationDismissed: Boolean = false

    /** Posts the scan's notification unless the scan is already over. */
    fun postIfActive(context: Context, notification: Notification) {
        synchronized(notifyLock) {
            if (!isScanActive || notificationDismissed) return
            try {
                androidx.core.app.NotificationManagerCompat.from(context.applicationContext)
                    .notify(NOTIFICATION_ID, notification)
            } catch (e: Exception) {
                // Most likely POST_NOTIFICATIONS was revoked, so the notification stays hidden.
            }
        }
    }

    /** True while an indexing scan is running. Face grouping follows it and waits for it to end. */
    @Volatile
    var isScanActive: Boolean = false
        private set

    @Volatile
    private var lastSnapshot: Snapshot? = null

    /**
     * The Dart-facing progress EventChannel sink. [lastProgressMap] is the full payload last sent through it.
     * Removing the app from Recents recreates the Activity and the Flutter engine while the scan keeps running. A
     * static sink lets the ticks reach whichever engine is current, and a recreated Dart layer can ask
     * [activeProgress] for the tick it missed.
     */
    @Volatile
    private var progressSink: EventChannel.EventSink? = null
    @Volatile
    private var lastProgressMap: Map<String, Any?>? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /**
     * Holds the CPU awake during a scan. A foreground service or Worker only keeps the process from being killed. Once
     * the screen is off, Android suspends the CPU unless a wake lock is held, which would freeze the scan mid-work. The
     * lock has a timeout that every progress tick renews, so a missed release cannot drain the battery forever.
     */
    @Volatile
    private var wakeLock: PowerManager.WakeLock? = null

    fun setProgressSink(sink: EventChannel.EventSink?) {
        progressSink = sink
    }

    fun pushProgress(map: Map<String, Any?>) {
        lastProgressMap = map
        mainHandler.post { progressSink?.success(map) }
    }

    /** The last progress payload, for a recreated Dart layer to resync with a scan still running. Null once [onScanEnded] has run. */
    fun activeProgress(): Map<String, Any?>? = lastProgressMap

    /**
     * Called once as a scan begins, from ScanWorker before the embedding loop starts. Clears whatever a previous run left
     * so it cannot leak into this one's first notification, and takes the wake lock.
     */
    fun onScanStarting(context: Context) {
        isScanActive = true
        notificationDismissed = false
        faceSnapshot = null
        lastSnapshot = null
        lastProgressMap = null
        synchronized(indexingRate) { indexingRate.reset() }
        synchronized(faceRate) { faceRate.reset() }
        createChannelIfNeeded(context)
        acquireWakeLock(context)
    }

    /**
     * Called once the scan loop returns, however it ended. Releases the wake lock and clears the cache, so
     * [activeProgress] reports nothing running. The notification is taken down here, after the last possible post,
     * because WorkManager takes it down when the work is stopped, possibly before the scan stops posting, and a late
     * post would leave an ongoing notification nothing removes.
     */
    fun onScanEnded(context: Context) {
        synchronized(notifyLock) {
            isScanActive = false
            faceSnapshot = null
            try {
                androidx.core.app.NotificationManagerCompat.from(context.applicationContext)
                    .cancel(NOTIFICATION_ID)
            } catch (e: Exception) {
                // Nothing to take down.
            }
        }
        releaseWakeLock()
        lastSnapshot = null
        lastProgressMap = null
    }

    /**
     * The notification to pass to setForeground() as a scan starts. It shows the cached progress, so a restart
     * mid-scan does not show a bare "Preparing...".
     */
    fun initialNotification(context: Context): Notification {
        return buildNotification(context, lastSnapshot ?: Snapshot(0, 0, 0, 0))
    }

    /**
     * Called on every progress tick. Never throws and never blocks the scan. Returns the notification for the tick, and
     * the caller posts it (ScanWorker, via NotificationManagerCompat), since only the caller knows whether it is past the
     * initial setForeground() call. It also extends the wake lock's timeout, so a long scan does not outlast it.
     */
    fun updateProgress(
        context: Context,
        processed: Int,
        total: Int,
        embedded: Int,
        elapsedMs: Long,
        activeMs: Long = elapsedMs,
        photos: Int = 0,
        videos: Int = 0,
        photosDone: Int = 0,
        videosDone: Int = 0
    ): Notification {
        val snapshot = Snapshot(processed, total, embedded, elapsedMs, activeMs, photos, videos, photosDone, videosDone)
        lastSnapshot = snapshot
        acquireWakeLock(context)
        return buildNotification(context, snapshot)
    }

    /**
     * Called from the face scan's own thread on each of its status ticks. The notification is normally rebuilt on the
     * indexing scan's ticks, which carry this along, but those can be far apart on a long video, so it is also posted
     * from here at most every couple of seconds. Switching between indexing and finding faces shows at once. Nothing is
     * posted once the scan is over, because that would bring its notification back.
     */
    fun updateFaceProgress(context: Context, status: Map<String, Any?>) {
        val before = faceSnapshot
        if (status["done"] == true && status["batch"] != true) {
            faceSnapshot = null
        } else {
            if (before?.working != true) synchronized(faceRate) { faceRate.reset() }
            faceSnapshot = FaceSnapshot(
                working = status["batch"] == true,
                tuning = status["phase"] == "tune",
                processed = (status["processed"] as? Int) ?: 0,
                total = (status["total"] as? Int) ?: 0
            )
        }
        val snapshot = lastSnapshot ?: return
        val now = System.currentTimeMillis()
        val switched = (before?.working == true) != (faceSnapshot?.working == true)
        if (!switched && now - lastFacePostAt < FACE_REPOST_INTERVAL_MS) return
        lastFacePostAt = now
        postIfActive(context, buildNotification(context, snapshot))
    }

    fun clearFaceProgress() {
        faceSnapshot = null
    }

    private fun acquireWakeLock(context: Context) {
        try {
            val pm = context.applicationContext
                .getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
            val lock = wakeLock ?: pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "$TAG:scan"
            ).apply { setReferenceCounted(false) }
            lock.acquire(WAKE_LOCK_TIMEOUT_MS)
            wakeLock = lock
        } catch (e: Exception) {
            Log.w(TAG, "acquireWakeLock: failed: ${e.message}")
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
        } catch (e: Exception) {
            // Nothing to do. Worst case it releases itself at its timeout.
        }
        wakeLock = null
    }

    /**
     * Builds the notification for [snapshot]. A scan that has not said how many photos and videos it has counts all of
     * its items as photos. A video takes far longer than a photo, so the indexing rate starts over when the scan moves
     * between photos and videos. While the faces of the batch just indexed are found, indexing waits and the faces are
     * what shows.
     */
    private fun buildNotification(context: Context, snapshot: Snapshot): Notification {
        val known = snapshot.photos + snapshot.videos > 0
        val indexing = ScanNotification.Indexing(
            photos = if (known) snapshot.photos else snapshot.total,
            videos = if (known) snapshot.videos else 0,
            photosDone = if (known) snapshot.photosDone else snapshot.processed,
            videosDone = if (known) snapshot.videosDone else 0,
            timeLeft = etaLabel(snapshot),
        )
        val ixSpeed = synchronized(indexingRate) {
            if (indexing.onVideos != indexingRateOnVideos) {
                indexingRate.reset()
                indexingRateOnVideos = indexing.onVideos
            }
            val perSecond = if (snapshot.embedded > 0) indexingRate.add(snapshot.activeMs, snapshot.embedded) else null
            if (indexing.onVideos || indexing.photos == 0) {
                ScanNotification.speed(perSecond, "video", "videos")
            } else {
                ScanNotification.speed(perSecond, "photo", "photos")
            }
        }
        val face = faceSnapshot?.takeIf { it.working }
        val faceSpeed = face?.takeIf { !it.tuning && it.total > 0 }?.let {
            synchronized(faceRate) {
                ScanNotification.speed(faceRate.add(SystemClock.elapsedRealtime(), it.processed), "photo", "photos")
            }
        }
        val faces = face?.let {
            val batch = ScanNotification.count(it.total)
            if (it.tuning) {
                ScanNotification.Faces(
                    done = 0, total = 0,
                    title = "Getting face search ready",
                    context = "One time, for this phone. Then the faces in the photos just indexed.",
                    header = null,
                    waiting = true,
                )
            } else {
                ScanNotification.Faces(
                    done = it.processed, total = it.total,
                    title = "Finding faces",
                    context = "$batch ${if (it.total == 1) "photo" else "photos"} just indexed. Now finding the faces in them.",
                    header = "in the $batch ${if (it.total == 1) "photo" else "photos"} just indexed",
                    waiting = it.total <= 0,
                    speed = faceSpeed,
                )
            }
        }
        return ScanNotification.build(
            context,
            CHANNEL_ID,
            indexing.copy(speed = ixSpeed),
            faces,
            contentIntent(context),
            NotificationDismissReceiver.pending(context, NotificationDismissReceiver.WHICH_SCAN),
        )
    }

    /** Tapping the notification brings the app to the front, on the Library tab where the scan is. */
    private fun contentIntent(context: Context): PendingIntent {
        val intent = Intent(context.applicationContext, MainActivity::class.java).apply {
            action = MainActivity.ACTION_OPEN_LIBRARY
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        return PendingIntent.getActivity(context.applicationContext, 0, intent, flags)
    }

    /**
     * The time left, from the whole-scan average. It uses the same formula as the in-app bar's scanEtaText and is
     * steadier than the instantaneous rate for an estimate.
     */
    private fun etaLabel(snapshot: Snapshot): String? {
        val (processed, total, _, elapsedMs) = snapshot
        if (total <= 0 || processed <= 0 || processed >= total) return null
        val msPerItem = elapsedMs.toDouble() / processed
        val remainingMs = (msPerItem * (total - processed)).roundToLong()
        return ScanNotification.duration(remainingMs)
    }

    private fun createChannelIfNeeded(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.applicationContext
            .getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            CHANNEL_ID,
            "Scan progress",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Shows progress while Lost & Found is indexing your photos and videos."
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }
}
