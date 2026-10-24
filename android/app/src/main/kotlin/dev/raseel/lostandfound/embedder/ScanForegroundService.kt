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

// Process-wide hub for everything about a scan that isn't the actual
// embedding work: the notification, the latest progress tick (for both
// the notification and a freshly (re)created Dart layer to resync from -
// see activeProgress()), the Dart-facing progress EventChannel sink, and
// the wake lock that keeps the CPU awake during the scan.
//
// No longer an Android Service - the foreground-service lifecycle itself
// now belongs to WorkManager (see ScanWorker, which calls setForeground()
// and drives onScanStarting/updateProgress/onScanEnded below). This keeps
// every one of the pieces that don't actually need a Service instance:
// they were already process-wide/static before, for the same underlying
// reason WorkManager solves more thoroughly now - a scan can outlive
// whatever component started it (an Activity recreated by Recents, or
// previously a Service instance recreated the same way).
object ScanForegroundService {

    private const val TAG = "ScanForegroundService"
    const val CHANNEL_ID = "scan_progress"
    const val NOTIFICATION_ID = 4201

    // Safety-net ceiling for the wake lock, renewed on every progress tick
    // (updateProgress) - a stalled/orphaned scan can't hold it forever,
    // but a genuinely long one never actually hits this since ticks keep
    // pushing it back out.
    private const val WAKE_LOCK_TIMEOUT_MS = 3 * 60 * 60 * 1000L // 3 hours

    private const val FACE_REPOST_INTERVAL_MS = 2_000L

    private data class Snapshot(
        val processed: Int,
        val total: Int,
        val embedded: Int,
        val elapsedMs: Long,
        // elapsedMs minus the time spent waiting for faces to be found (see ScanProgress).
        val activeMs: Long = elapsedMs,
        // Of total, the photos and the videos, and how many of each are done (see ScanProgress).
        val photos: Int = 0,
        val videos: Int = 0,
        val photosDone: Int = 0,
        val videosDone: Int = 0
    )

    // Where the face scan that works in step with this scan has got to (see
    // FaceFollower), shown in this same notification so there is only ever the one:
    // [working] while it is finding the faces in a batch (indexing waits meanwhile),
    // with processed/total counting that batch's photos.
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

    // How fast indexing goes (photos or videos embedded over the time spent indexing, so waiting for faces does
    // not slow it down) and how fast the faces of a batch are found. Each starts over on a new part or batch.
    private val indexingRate = ScanNotification.Rate()
    private var indexingRateOnVideos = false
    private val faceRate = ScanNotification.Rate()

    // Posting and taking down the notification never overlap (see onScanEnded).
    private val notifyLock = Any()

    // The user swiped this scan's notification away: it is not posted again for the rest
    // of the scan (the scan itself carries on), or it would pop straight back up.
    @Volatile
    var notificationDismissed: Boolean = false

    /** Posts the scan's notification - unless the scan is already over. */
    fun postIfActive(context: Context, notification: Notification) {
        synchronized(notifyLock) {
            if (!isScanActive || notificationDismissed) return
            try {
                androidx.core.app.NotificationManagerCompat.from(context.applicationContext)
                    .notify(NOTIFICATION_ID, notification)
            } catch (e: Exception) {
                // Most likely a revoked POST_NOTIFICATIONS permission - the
                // notification just won't be visible, which is fine.
            }
        }
    }

    /** True while an indexing scan is running - face grouping follows it, and waits for it to end. */
    @Volatile
    var isScanActive: Boolean = false
        private set

    @Volatile
    private var lastSnapshot: Snapshot? = null

    // The Dart-facing progress EventChannel's sink, and the full raw
    // payload last sent through it. Removing the app from Recents doesn't
    // kill this process (that's the whole point of the foreground work),
    // but it does recreate the Activity/Flutter engine - the scan itself
    // keeps running on its original ScanWorker coroutine. Routing through
    // a static sink means that orphaned scan's ticks still reach whichever
    // MainActivity/engine is current when they fire, and a freshly
    // (re)created Dart layer can ask activeProgress() for the last one it
    // missed instead of showing "nothing is scanning".
    @Volatile
    private var progressSink: EventChannel.EventSink? = null
    @Volatile
    private var lastProgressMap: Map<String, Any?>? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // A foreground service/Worker only keeps this process from being
    // killed - it does *not* keep the CPU awake. Once the screen turns
    // off, Android lets the CPU suspend unless something holds a wake
    // lock, which would freeze the scan mid-work even though it's still
    // technically "running" in the foreground. Same PARTIAL_WAKE_LOCK
    // pattern music/download/backup apps use to keep working with the
    // screen off. Bounded with a timeout (renewed on every progress tick)
    // rather than acquired indefinitely, so a missed release() can't leak
    // it and drain the battery forever.
    @Volatile
    private var wakeLock: PowerManager.WakeLock? = null

    fun setProgressSink(sink: EventChannel.EventSink?) {
        progressSink = sink
    }

    fun pushProgress(map: Map<String, Any?>) {
        lastProgressMap = map
        mainHandler.post { progressSink?.success(map) }
    }

    // What a freshly (re)created Dart layer asks for on init to resync
    // with a scan that's still running from before it existed. Null once
    // onScanEnded() has run - see there.
    fun activeProgress(): Map<String, Any?>? = lastProgressMap

    // Called once, right as a scan begins (from ScanWorker.doWork(),
    // before the embedding loop starts) - clears anything left over from
    // a previous run so it can't leak into this one's first notification,
    // and acquires the wake lock.
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

    // Called once the scan loop returns, however it ended (finished,
    // cancelled, or threw) - always releases the wake lock and clears the
    // cache, so activeProgress() correctly reports "nothing running" and
    // the next scan's first notification doesn't inherit stale numbers.
    fun onScanEnded(context: Context) {
        synchronized(notifyLock) {
            isScanActive = false
            faceSnapshot = null
            // WorkManager takes the notification down when the work is stopped, which can
            // be before the scan has stopped posting to it - a late post would bring it
            // back as an ongoing notification nothing would ever remove. Taking it down
            // here, after the last possible post, makes sure it is gone.
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

    // The notification to pass to setForeground() right as a scan starts -
    // reads whatever's already cached (a restart mid-scan may have ticks
    // from before this call) instead of always showing a bare "Preparing...".
    fun initialNotification(context: Context): Notification {
        return buildNotification(context, lastSnapshot ?: Snapshot(0, 0, 0, 0))
    }

    // Called on every progress tick - never throws, never blocks the scan.
    // Returns the notification to show for it; the caller is responsible
    // for actually posting it (ScanWorker, via NotificationManagerCompat),
    // since only it knows whether it's already past the initial
    // setForeground() call.
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
        // Extends the wake lock's timeout rather than letting a long scan
        // outlast it - see the field's doc.
        acquireWakeLock(context)
        return buildNotification(context, snapshot)
    }

    // Called from the face scan's own thread on each of its status ticks. The
    // notification is normally rebuilt on the indexing scan's ticks (which carry this
    // along), but those can be far apart on a long video, so it is also re-posted from
    // here - at most every couple of seconds.
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
        // Not once the scan is over - that would bring its notification back.
        val snapshot = lastSnapshot ?: return
        val now = System.currentTimeMillis()
        // Switching between "indexing" and "finding faces" shows at once; progress within
        // one of them can wait for the next couple of seconds.
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
            // Nothing to do - worst case it releases itself at its timeout.
        }
        wakeLock = null
    }

    private fun buildNotification(context: Context, snapshot: Snapshot): Notification {
        // A scan that has not said how many photos and videos it has (none yet): all of it counted as photos.
        val known = snapshot.photos + snapshot.videos > 0
        val indexing = ScanNotification.Indexing(
            photos = if (known) snapshot.photos else snapshot.total,
            videos = if (known) snapshot.videos else 0,
            photosDone = if (known) snapshot.photosDone else snapshot.processed,
            videosDone = if (known) snapshot.videosDone else 0,
            timeLeft = etaLabel(snapshot),
        )
        val ixSpeed = synchronized(indexingRate) {
            // A video takes far longer than a photo: the videos' pace is not the photos'.
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
        // While the faces of the batch just indexed are found (indexing waits for that), they are what shows.
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

    // Tapping the notification brings the app to the front, on the Library tab
    // where the scan is.
    private fun contentIntent(context: Context): PendingIntent {
        val intent = Intent(context.applicationContext, MainActivity::class.java).apply {
            action = MainActivity.ACTION_OPEN_LIBRARY
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0)
        return PendingIntent.getActivity(context.applicationContext, 0, intent, flags)
    }

    // Whole-scan average, same formula as the in-app bar's scanEtaText -
    // steadier than the instantaneous rate for an ETA.
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
