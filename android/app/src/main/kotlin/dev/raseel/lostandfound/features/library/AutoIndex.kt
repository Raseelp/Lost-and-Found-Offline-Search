package dev.raseel.lostandfound.features.library

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import dev.raseel.lostandfound.MainActivity
import dev.raseel.lostandfound.R
import dev.raseel.lostandfound.core.log.AppLog
import dev.raseel.lostandfound.core.native.NativeExecutors
import dev.raseel.lostandfound.core.storage.HashUtils
import dev.raseel.lostandfound.features.memories.MemoryNotifier
import dev.raseel.lostandfound.features.people.FaceFollower
import dev.raseel.lostandfound.features.people.FaceScanHub
import dev.raseel.lostandfound.features.people.FaceServices
import dev.raseel.lostandfound.features.people.FaceSettings
import dev.raseel.lostandfound.features.search.EmbeddingEngine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import java.text.NumberFormat
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Photos and videos that came to the phone after the marker, newest first, and the newest time any of the rows looked at
 * was added (in seconds). Only those that are not in the index yet are listed, but the newest time counts all that were
 * looked at, so the marker can move past what is already indexed.
 */
class NewMedia(val images: List<ImageSource>, val videos: List<VideoSource>, val newestAdded: Long) {
    val count: Int get() = images.size + videos.size
}

/** What a run does with the new files it found. LEAVE: none of them is indexed, and the manual scan is left to do them. */
enum class AutoPlan { NOTHING, SILENT, WITH_NOTIFICATION, ASK, LEAVE }

/** The limits of a run, apart from everything else it does, so that they can be tested. */
object AutoIndexRules {
    /** Up to this many new files are indexed silently, and up to [ASK_ABOVE] with a notification. */
    const val SILENT_MAX = 10
    const val ASK_ABOVE = 100

    /** How long the question about a big batch stays quiet after it was swiped away, unless the batch grows. */
    const val ASK_QUIET_MS = 24L * 60 * 60 * 1000

    /** How much older than the marker a file's own modified time may be and still count as new, for the clock of a camera or a copy. */
    const val MODIFIED_SLACK_S = 60L * 60

    /**
     * What to do with [count] new files. When notifications cannot be shown ([canTell] false) nothing can be said about
     * a bigger batch or asked, so only the silent size is indexed and the rest is left.
     */
    fun plan(count: Int, canTell: Boolean = true): AutoPlan = when {
        count <= 0 -> AutoPlan.NOTHING
        count <= SILENT_MAX -> AutoPlan.SILENT
        !canTell -> AutoPlan.LEAVE
        count <= ASK_ABOVE -> AutoPlan.WITH_NOTIFICATION
        else -> AutoPlan.ASK
    }

    /**
     * Whether the question about [count] new files is held back: it was swiped away at [dismissedAtMs] when it said
     * [dismissedCount], less than a day ago, and the batch has not grown since.
     */
    fun askIsQuiet(nowMs: Long, dismissedAtMs: Long, dismissedCount: Int, count: Int): Boolean =
        dismissedAtMs > 0 && nowMs >= dismissedAtMs && nowMs - dismissedAtMs < ASK_QUIET_MS && count <= dismissedCount

    /** The oldest modified time (seconds) a file added after [since] may have to count as new. */
    fun modifiedFloor(since: Long): Long = (since - MODIFIED_SLACK_S).coerceAtLeast(0L)
}

/**
 * Indexes the photos and videos that arrive on the phone, by itself.
 *
 * What is new is decided by one marker: the time the newest file that was dealt with was added to the phone. It is set
 * the first time a run can work (the search models are installed and the photos can be read) and when the switch is
 * turned on, so photos from before that are never new, and it only moves forward. A run asks the media library only
 * for files added at or after the marker, so what is older is never looked at, whatever gaps the index has. The older
 * ones stay with the manual scan. Files already in the index are left out of what is found, so a file that is listed
 * twice, or a library that the system has listed again, does not count as new. A file also has to have been modified (by
 * the camera, a download or a copy) not long before the marker. When the system builds its media library again it gives
 * every old file a new added time, and this keeps those from looking new.
 *
 * While the index waits to be made again after a change of search model, nothing is indexed by itself, and the marker
 * follows the clock, because the scan the person has to start covers everything up to then. Indexing by itself would
 * also take away the note that says to scan again.
 *
 * Android wakes the app a minute after the last change to the photos or videos, when the battery is not low, and a run
 * sets the next wake-up before it starts. Up to [AutoIndexRules.SILENT_MAX] new files are indexed without a word. Up to
 * [AutoIndexRules.ASK_ABOVE] are indexed with a notification that says so. More than that are not indexed, and a
 * notification asks first, with a button that indexes just those: it approves the files that are new at that moment,
 * up to the time the newest of them was added, and nothing that arrives later. The question is not asked again for a day
 * after it was swiped away, unless the batch has grown. When notifications cannot be shown, only the silent size is
 * indexed and a bigger batch is left to the manual scan. What is indexed follows the choice of photos, videos or both
 * made in Settings for auto indexing, and not the choice of the manual scan. The faces are found only in what a run
 * indexed, and the face scan's catch-up over the whole library is never started from here.
 */
object AutoIndex {
    const val ACTION_INDEX_NEW = "dev.raseel.lostandfound.INDEX_NEW"
    const val ACTION_ASK_DISMISSED = "dev.raseel.lostandfound.INDEX_ASK_DISMISSED"
    const val KEY_FORCE = "force"

    private const val TAG = "AutoIndex"
    private const val WATCH_TAG = "auto_index_watch"
    private const val NOW_WORK = "auto_index_now"
    private const val FORCE_WORK = "auto_index_force"
    private const val PROGRESS_CHANNEL = "auto_index_progress"
    private const val ASK_CHANNEL = "auto_index_ask"
    private const val PROGRESS_ID = 7330
    private const val ASK_ID = 7331
    private const val ACCENT = 0xFF165E59.toInt()
    private const val FOLDER_ID = "device"
    private const val SETTLE_SECONDS = 60L
    private const val MAX_WAIT_MINUTES = 10L
    private const val RETRY_MINUTES = 15L

    /** The progress notification goes by itself if the process is killed and cannot take it down. */
    private const val PROGRESS_TIMEOUT_MS = 15 * 60 * 1000L
    private const val PREFS = "auto_index"
    private const val ENABLED = "enabled"
    private const val MARKER = "marker_added_s"
    private const val APPROVED_UNTIL = "approved_until_added_s"
    private const val CONTENT = "auto_content"
    private const val LAST_INDEXED = "last_indexed_ms"
    private const val ASKED_COUNT = "asked_count"
    private const val DISMISSED_AT = "ask_dismissed_at_ms"
    private const val DISMISSED_COUNT = "ask_dismissed_count"

    private fun prefs(context: Context) = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun nowSeconds(): Long = System.currentTimeMillis() / 1000

    fun enabled(context: Context): Boolean = prefs(context).getBoolean(ENABLED, true)

    /** What auto indexing picks up: "images", "videos" or "both", which is the default. It is chosen in Settings, and the choice of the manual scan has nothing to do with it. */
    fun content(context: Context): String = prefs(context).getString(CONTENT, "both").let { if (it == "images" || it == "videos") it else "both" }

    fun setContent(context: Context, value: String) {
        if (value == "images" || value == "videos" || value == "both") prefs(context).edit().putString(CONTENT, value).apply()
    }

    /** When a run last indexed something, in milliseconds, or 0. The Library shows it as the last time of scanning. */
    fun lastIndexedMs(context: Context): Long = prefs(context).getLong(LAST_INDEXED, 0L)

    /** The index was cleared, so there is no time of scanning to show. The marker stays, so what was cleared is not indexed again by itself. */
    fun forgetLastIndexed(context: Context) {
        prefs(context).edit().remove(LAST_INDEXED).apply()
    }

    /** Turning it on starts from now, so what arrived while it was off is left to the manual scan. Turning it off stops what is waiting. */
    fun setEnabled(context: Context, on: Boolean) {
        val app = context.applicationContext
        val editor = prefs(app).edit().putBoolean(ENABLED, on).remove(APPROVED_UNTIL).remove(ASKED_COUNT).remove(DISMISSED_AT).remove(DISMISSED_COUNT)
        if (on) editor.putLong(MARKER, nowSeconds())
        editor.apply()
        NativeExecutors.executor.execute {
            if (on) {
                arm(app)
            } else {
                stopAll(app)
            }
        }
    }

    /** Called when the app starts: makes sure a wake-up is waiting, and looks once for what Android did not wake the app for. */
    fun start(context: Context) {
        val app = context.applicationContext
        if (!enabled(app)) return
        NativeExecutors.executor.execute {
            arm(app)
            checkNow(app, 0L)
        }
    }

    private fun batteryNotLow(): Constraints = Constraints.Builder().setRequiresBatteryNotLow(true).build()

    /** [armNow] for a caller that is not a coroutine. Blocks briefly, so not on the main thread. */
    fun arm(context: Context) = runBlocking { armNow(context) }

    /**
     * Makes sure one wake-up is waiting for a change to the photos or the videos, a minute after the last one, and not
     * while the battery is low (it waits for the battery to recover). A run calls this first, so a change during the run
     * is seen.
     */
    suspend fun armNow(context: Context) {
        val app = context.applicationContext
        if (!enabled(app)) return
        try {
            val manager = WorkManager.getInstance(app)
            val waiting = manager.getWorkInfosByTagFlow(WATCH_TAG).first().any {
                it.state == WorkInfo.State.ENQUEUED || it.state == WorkInfo.State.BLOCKED
            }
            if (waiting) return
            val constraints = Constraints.Builder()
                .addContentUriTrigger(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, true)
                .addContentUriTrigger(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, true)
                .setTriggerContentUpdateDelay(SETTLE_SECONDS, TimeUnit.SECONDS)
                .setTriggerContentMaxDelay(MAX_WAIT_MINUTES, TimeUnit.MINUTES)
                .setRequiresBatteryNotLow(true)
                .build()
            manager.enqueue(OneTimeWorkRequestBuilder<AutoIndexWorker>().setConstraints(constraints).addTag(WATCH_TAG).build())
        } catch (e: Exception) {
            AppLog.w(TAG, "could not set the wake-up: ${e.message}")
        }
    }

    /** One look for new files in [delayMinutes] minutes, for when Android did not wake the app. Not while the battery is low. */
    fun checkNow(context: Context, delayMinutes: Long) {
        val app = context.applicationContext
        if (!enabled(app)) return
        try {
            val request = OneTimeWorkRequestBuilder<AutoIndexWorker>()
                .setInitialDelay(delayMinutes, TimeUnit.MINUTES)
                .setConstraints(batteryNotLow())
                .build()
            WorkManager.getInstance(app).enqueueUniqueWork(NOW_WORK, ExistingWorkPolicy.KEEP, request)
        } catch (e: Exception) {
            AppLog.w(TAG, "could not schedule a look: ${e.message}")
        }
    }

    /** The button of the notification that asks: index the new ones now, whatever their number, and nothing else. */
    fun indexNew(context: Context) {
        val app = context.applicationContext
        forgetAsk(app)
        try {
            val request = OneTimeWorkRequestBuilder<AutoIndexWorker>()
                .setInputData(Data.Builder().putBoolean(KEY_FORCE, true).build())
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build()
            WorkManager.getInstance(app).enqueueUniqueWork(FORCE_WORK, ExistingWorkPolicy.REPLACE, request)
        } catch (e: Exception) {
            AppLog.w(TAG, "could not start indexing the new ones: ${e.message}")
        }
    }

    /** The question is taken down, and nothing is remembered about it being swiped away. */
    private fun forgetAsk(app: Context) {
        NotificationManagerCompat.from(app).cancel(ASK_ID)
        prefs(app).edit().remove(ASKED_COUNT).remove(DISMISSED_AT).remove(DISMISSED_COUNT).apply()
    }

    /** The question was swiped away: it stays quiet for a day unless there are more new files than it said. */
    internal fun askDismissed(context: Context) {
        val p = prefs(context)
        p.edit().putLong(DISMISSED_AT, System.currentTimeMillis()).putInt(DISMISSED_COUNT, p.getInt(ASKED_COUNT, 0)).apply()
    }

    private fun stopAll(context: Context) {
        val app = context.applicationContext
        try {
            val manager = WorkManager.getInstance(app)
            manager.cancelAllWorkByTag(WATCH_TAG)
            manager.cancelUniqueWork(NOW_WORK)
            manager.cancelUniqueWork(FORCE_WORK)
        } catch (e: Exception) {
            AppLog.w(TAG, "could not stop the waiting work: ${e.message}")
        }
        val notifications = NotificationManagerCompat.from(app)
        notifications.cancel(ASK_ID)
        notifications.cancel(PROGRESS_ID)
    }

    /** Whether all the photos and videos can be read: not only the ones the person picked (Android 14), and not nothing. */
    fun hasMediaAccess(context: Context): Boolean {
        val permission = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE
        return context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    private data class Row(val uri: Uri, val size: Long, val modified: Long, val name: String, val added: Long)

    private fun collection(images: Boolean): Uri =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            if (images) MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
            else MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            if (images) MediaStore.Images.Media.EXTERNAL_CONTENT_URI else MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        }

    /**
     * The files added at or after [since] seconds, and at or before [until], newest first. Nothing older is read from the
     * media library, and neither is a file that was last modified long before [since] (see [AutoIndexRules.modifiedFloor]).
     * No permission for one kind gives none of that kind. The numbers are written into the selection, which is safe because
     * they are numbers, so that the comparison does not depend on how the library treats a bound text.
     */
    private fun rows(context: Context, images: Boolean, since: Long, until: Long?): List<Row> {
        val base = collection(images)
        val id = if (images) MediaStore.Images.Media._ID else MediaStore.Video.Media._ID
        val size = if (images) MediaStore.Images.Media.SIZE else MediaStore.Video.Media.SIZE
        val modified = if (images) MediaStore.Images.Media.DATE_MODIFIED else MediaStore.Video.Media.DATE_MODIFIED
        val name = if (images) MediaStore.Images.Media.DISPLAY_NAME else MediaStore.Video.Media.DISPLAY_NAME
        val added = if (images) MediaStore.Images.Media.DATE_ADDED else MediaStore.Video.Media.DATE_ADDED
        val floor = AutoIndexRules.modifiedFloor(since)
        val selection = if (until == null) "$added >= $since AND $modified >= $floor" else "$added >= $since AND $modified >= $floor AND $added <= $until"
        val out = ArrayList<Row>()
        try {
            context.contentResolver.query(base, arrayOf(id, size, modified, name, added), selection, null, "$added DESC")?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(id)
                val sizeCol = cursor.getColumnIndexOrThrow(size)
                val modCol = cursor.getColumnIndexOrThrow(modified)
                val nameCol = cursor.getColumnIndexOrThrow(name)
                val addedCol = cursor.getColumnIndexOrThrow(added)
                while (cursor.moveToNext()) {
                    out.add(
                        Row(
                            ContentUris.withAppendedId(base, cursor.getLong(idCol)),
                            cursor.getLong(sizeCol),
                            cursor.getLong(modCol),
                            cursor.getString(nameCol) ?: "",
                            cursor.getLong(addedCol),
                        )
                    )
                }
            }
        } catch (e: SecurityException) {
            AppLog.w(TAG, "the media library could not be read: ${e.message}")
        }
        return out
    }

    /**
     * What came to the phone since [since] seconds, up to [until] when given, and is not in the index. The identity of a
     * file is the one a scan uses. Both kinds are always looked at, so the newest time moves past a kind that is not
     * wanted, and choosing it later does not bring in what came meanwhile. Only the kinds in [content] are listed.
     */
    fun findNew(context: Context, engine: EmbeddingEngine, since: Long, until: Long? = null, content: String = "both"): NewMedia {
        val known = engine.indexedHashes()
        var newest = since
        val images = ArrayList<ImageSource>()
        for (row in rows(context, true, since, until)) {
            newest = maxOf(newest, row.added)
            if (content != "videos" && HashUtils.identityHash(row.size, row.modified, row.name) !in known) {
                images.add(ImageSource(row.uri, row.size, row.modified, row.name))
            }
        }
        val videos = ArrayList<VideoSource>()
        for (row in rows(context, false, since, until)) {
            newest = maxOf(newest, row.added)
            if (content != "images" && HashUtils.identityHash(row.size, row.modified, row.name) !in known) {
                videos.add(VideoSource(row.uri, row.size, row.modified, row.name))
            }
        }
        return NewMedia(images, videos, newest)
    }

    private fun advance(context: Context, newest: Long) {
        val p = prefs(context)
        if (newest > p.getLong(MARKER, 0L)) p.edit().putLong(MARKER, newest).apply()
    }

    /** Whether a notification can be shown to the person: the app's notifications are on, and so are the two channels of this feature. */
    private fun canTell(app: Context): Boolean {
        if (!MemoryNotifier.allowed(app)) return false
        if (Build.VERSION.SDK_INT < 26) return true
        ensureChannels(app)
        val manager = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return listOf(PROGRESS_CHANNEL, ASK_CHANNEL).all {
            (manager.getNotificationChannel(it)?.importance ?: NotificationManager.IMPORTANCE_NONE) != NotificationManager.IMPORTANCE_NONE
        }
    }

    /**
     * One look at what is new, and what follows from how much there is. True when it is finished with, false when it has
     * to be looked at again later (a scan was running, or this was stopped part of the way).
     *
     * A batch the person approved with the Index button is finished first, and only the files that were new when they
     * approved it, however many there are. What arrived after that is judged as usual, so one approval never covers a
     * later big batch.
     */
    suspend fun run(context: Context, force: Boolean, stopped: () -> Boolean): Boolean {
        val app = context.applicationContext
        if (!enabled(app) && !force) return true
        val p = prefs(app)
        if (!ScanEngineHolder.modelManager(app).areModelsReady() || !hasMediaAccess(app)) {
            AppLog.i(TAG, "run: not yet, the models are not ready or the photos cannot be read")
            return true
        }
        if (!p.contains(MARKER)) {
            p.edit().putLong(MARKER, nowSeconds()).apply()
            AppLog.i(TAG, "run: first time, new means from now on")
            return true
        }
        if (ScanWorker.isRunning()) {
            AppLog.i(TAG, "run: a scan is running, looking again later")
            return false
        }

        val engine = ScanEngineHolder.embeddingEngine(app)
        if (engine.modelResetFrom() != 0) {
            AppLog.i(TAG, "run: the index waits to be made again, nothing is indexed by itself")
            advance(app, nowSeconds())
            return true
        }
        val content = content(app)
        if (force) {
            val all = findNew(app, engine, p.getLong(MARKER, 0L), content = content)
            if (all.count > 0) p.edit().putLong(APPROVED_UNTIL, all.newestAdded).apply()
        }
        val approvedUntil = p.getLong(APPROVED_UNTIL, 0L)
        if (approvedUntil > 0L) {
            val approved = findNew(app, engine, p.getLong(MARKER, 0L), approvedUntil, content)
            if (approved.count > 0) {
                forgetAsk(app)
                if (!ScanWorker.exclusive { index(app, engine, approved, content, stopped) }) return false
            } else {
                advance(app, approved.newestAdded)
            }
            p.edit().remove(APPROVED_UNTIL).apply()
        }

        val found = findNew(app, engine, p.getLong(MARKER, 0L), content = content)
        val plan = AutoIndexRules.plan(found.count, canTell(app))
        AppLog.i(TAG, "run: ${found.images.size} new photos and ${found.videos.size} new videos since ${p.getLong(MARKER, 0L)} ($content), plan $plan")
        return when (plan) {
            AutoPlan.NOTHING -> {
                advance(app, found.newestAdded)
                forgetAsk(app)
                true
            }
            AutoPlan.LEAVE -> {
                advance(app, found.newestAdded)
                true
            }
            AutoPlan.ASK -> {
                val quiet = AutoIndexRules.askIsQuiet(
                    System.currentTimeMillis(), p.getLong(DISMISSED_AT, 0L), p.getInt(DISMISSED_COUNT, 0), found.count,
                )
                if (!quiet) postAsk(app, found)
                true
            }
            AutoPlan.SILENT, AutoPlan.WITH_NOTIFICATION -> {
                forgetAsk(app)
                ScanWorker.exclusive { index(app, engine, found, content, stopped) }
            }
        }
    }

    /**
     * Indexes exactly [found], in the order given, then finds the faces in what was indexed. The marker moves only when
     * all of it was done. A scan that is started meanwhile stops this (see [ScanWorker.doWork]), and then it is false.
     * What it indexed is kept for the app to tag as new and to tell the person about, and the time is kept for the
     * Library.
     */
    private fun index(app: Context, engine: EmbeddingEngine, found: NewMedia, content: String, stopped: () -> Boolean): Boolean {
        val loud = AutoIndexRules.plan(found.count) != AutoPlan.SILENT
        val halted = { stopped() || engine.wasCancelled() }
        var lastShown = 0L
        if (loud) showProgress(app, found, 0)
        LatestScan.beginAuto()
        try {
            val result = engine.embedImages("device", null, FOLDER_ID, content, found) { progress ->
                if (stopped()) engine.cancelEmbedding()
                val now = System.currentTimeMillis()
                if (loud && now - lastShown > 1000) {
                    lastShown = now
                    showProgress(app, found, progress.processed)
                }
            }
            if (result.embedded > 0) prefs(app).edit().putLong(LAST_INDEXED, System.currentTimeMillis()).apply()
            val (storedPhotos, storedVideos) = engine.indexedAmong(identityHashes(found))
            AutoShown.add(app, storedPhotos.map { it.uri }, storedVideos.map { it.uri })
            if (halted()) return false
            findFaces(app, storedPhotos, storedVideos, halted)
            if (halted()) return false
            advance(app, found.newestAdded)
            return true
        } finally {
            LatestScan.finishAuto(app)
            if (loud) NotificationManagerCompat.from(app).cancel(PROGRESS_ID)
        }
    }

    /**
     * Finds the faces in the photos and videos that were just indexed, and in nothing else. The face scan's own catch-up
     * over the whole library is not started, so the older ones are left alone. [stored] and [storedVideos] are the files
     * of the run that are in the index.
     *
     * It is left to the next face scan when the person stopped face search, when the face models are not the ones the
     * stored people were made with (finding faces then would throw those people away and start the grouping over, which
     * only a scan the person started may do), and when a face scan is running right now. A photo or video whose faces
     * were found already (a scan finished them while this waited) is not done again.
     */
    private fun findFaces(app: Context, stored: List<IndexedImage>, storedVideos: List<IndexedVideo>, halted: () -> Boolean) {
        if (FaceSettings.paused(app)) return
        try {
            val services = FaceServices.get(app)
            if (!services.engine.isReady() || !services.scanner.modelsMatchStored()) return
            if (FaceScanHub.running || FaceFollower.isArmed()) return
            val finished = services.store.processedHashes()
            val photos = stored.filter { it.hash !in finished }
            val videos = storedVideos.filter { !services.store.isVideoDone(it.hash) }
            val scanVideos = FaceSettings.scanVideos(app)
            val abandoned = AtomicBoolean(false)
            val stop = { halted() || abandoned.get() }
            waitFor(halted, abandoned) {
                if (photos.isNotEmpty() && !stop()) {
                    val session = services.scanner.openSession { }
                    try {
                        session.processBatch(photos, stop)
                    } finally {
                        session.finish()
                    }
                }
                if (scanVideos) {
                    for (video in videos) {
                        if (stop()) break
                        try {
                            services.videoScanner.scan(video, stop, { true })
                        } catch (e: Exception) {
                            AppLog.w(TAG, "the faces of a new video could not be found: ${e.message}")
                        }
                    }
                }
            }
        } catch (e: Exception) {
            AppLog.w(TAG, "faces of the new media failed: ${e.message}")
        }
    }

    /**
     * Runs [work] on a thread of its own and waits for it, but stops waiting as soon as [halted] says so, and then sets
     * [abandoned], which [work] has to look at to stop too. The face scan is one at a time, and one that the person
     * started can hold it for hours; waiting for it here would hold up the scan of a person who starts one meanwhile.
     */
    private fun waitFor(halted: () -> Boolean, abandoned: AtomicBoolean, work: () -> Unit) {
        val done = CountDownLatch(1)
        Thread({
            try {
                work()
            } catch (e: Exception) {
                AppLog.w(TAG, "faces of the new media failed: ${e.message}")
            } catch (e: OutOfMemoryError) {
                AppLog.w(TAG, "faces of the new media ran out of memory")
            } finally {
                done.countDown()
            }
        }, "auto-index-faces").start()
        while (!done.await(500, TimeUnit.MILLISECONDS)) {
            if (halted()) {
                abandoned.set(true)
                return
            }
        }
    }

    /** The identity hashes of the files of [found]. */
    private fun identityHashes(found: NewMedia): HashSet<Long> {
        val out = HashSet<Long>()
        for (image in found.images) out.add(HashUtils.identityHash(image.size, image.lastModified, image.name))
        for (video in found.videos) out.add(HashUtils.identityHash(video.size, video.lastModified, video.name))
        return out
    }

    private fun number(n: Int): String = NumberFormat.getIntegerInstance().format(n)

    /** "120 photos and 4 videos", "1 video". */
    private fun describe(found: NewMedia): String {
        val parts = listOfNotNull(
            found.images.size.takeIf { it > 0 }?.let { if (it == 1) "1 photo" else "${number(it)} photos" },
            found.videos.size.takeIf { it > 0 }?.let { if (it == 1) "1 video" else "${number(it)} videos" },
        )
        return parts.joinToString(" and ")
    }

    private fun openLibrary(app: Context, code: Int): PendingIntent = PendingIntent.getActivity(
        app,
        code,
        Intent(app, MainActivity::class.java).setAction(MainActivity.ACTION_OPEN_LIBRARY)
            .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun ensureChannels(app: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(PROGRESS_CHANNEL) == null) {
            manager.createNotificationChannel(
                NotificationChannel(PROGRESS_CHANNEL, "Indexing new photos", NotificationManager.IMPORTANCE_LOW).apply {
                    description = "Shown while new photos and videos are indexed by themselves"
                    setShowBadge(false)
                }
            )
        }
        if (manager.getNotificationChannel(ASK_CHANNEL) == null) {
            manager.createNotificationChannel(
                NotificationChannel(ASK_CHANNEL, "New photos to index", NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = "Asks before indexing a big batch of new photos and videos"
                    setShowBadge(false)
                    setSound(null, null)
                    enableVibration(false)
                }
            )
        }
    }

    private fun progressNotification(app: Context, total: Int, processed: Int): android.app.Notification {
        ensureChannels(app)
        return NotificationCompat.Builder(app, PROGRESS_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_app)
            .setColor(ACCENT)
            .setContentTitle("Indexing your new photos and videos")
            .setContentText("${number(total)} new photos and videos. You can turn off automatic indexing in Settings.")
            .setStyle(NotificationCompat.BigTextStyle().bigText("${number(total)} new photos and videos are being indexed. You can turn off automatic indexing in Settings."))
            .setProgress(total, processed.coerceIn(0, total), false)
            .setContentIntent(openLibrary(app, PROGRESS_ID))
            .setOngoing(true)
            .setTimeoutAfter(PROGRESS_TIMEOUT_MS)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun showProgress(app: Context, found: NewMedia, processed: Int) {
        if (!MemoryNotifier.allowed(app)) return
        try {
            NotificationManagerCompat.from(app).notify(PROGRESS_ID, progressNotification(app, found.count, processed))
        } catch (_: SecurityException) {
        }
    }

    /** The notification that asks before indexing a big batch. Its button indexes just the new ones, in order, so none of them is missed. */
    private fun postAsk(app: Context, found: NewMedia) {
        if (!MemoryNotifier.allowed(app)) return
        ensureChannels(app)
        val index = PendingIntent.getBroadcast(
            app,
            ASK_ID,
            Intent(app, AutoIndexReceiver::class.java).setAction(ACTION_INDEX_NEW),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val swiped = PendingIntent.getBroadcast(
            app,
            ASK_ID + 1,
            Intent(app, AutoIndexReceiver::class.java).setAction(ACTION_ASK_DISMISSED),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val body = "Index them now? Only these new ones are indexed. You can turn off automatic indexing in Settings."
        val publicVersion = NotificationCompat.Builder(app, ASK_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_app)
            .setContentTitle("New photos and videos")
            .build()
        val notification = NotificationCompat.Builder(app, ASK_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_app)
            .setColor(ACCENT)
            .setContentTitle("${describe(found)} to index")
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(openLibrary(app, ASK_ID))
            .addAction(NotificationCompat.Action.Builder(R.drawable.ic_stat_app, "Index", index).build())
            .setDeleteIntent(swiped)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_RECOMMENDATION)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(publicVersion)
            .build()
        try {
            NotificationManagerCompat.from(app).notify(ASK_ID, notification)
            prefs(app).edit().putInt(ASKED_COUNT, found.count).remove(DISMISSED_AT).remove(DISMISSED_COUNT).apply()
        } catch (_: SecurityException) {
        }
    }

    /** What an expedited run shows while it works, on phones that need a foreground notification for it. */
    internal fun foregroundInfo(app: Context): ForegroundInfo {
        val notification = progressNotification(app, 0, 0)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ForegroundInfo(PROGRESS_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            ForegroundInfo(PROGRESS_ID, notification)
        }
    }
}

class AutoIndexWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val app = applicationContext
        val force = inputData.getBoolean(AutoIndex.KEY_FORCE, false)
        AppLog.i("AutoIndex", "woken${if (force) " by the Index button" else ""}")
        AutoIndex.armNow(app)
        try {
            val finished = AutoIndex.run(app, force) { isStopped }
            AppLog.i("AutoIndex", if (finished) "run finished" else "run not finished, looking again in 15 minutes")
            if (!finished) AutoIndex.checkNow(app, 15L)
        } catch (e: kotlinx.coroutines.CancellationException) {
            AutoIndex.checkNow(app, 15L)
            throw e
        } catch (e: Exception) {
            AppLog.w("AutoIndex", "a run failed: ${e.message}")
        }
        return Result.success()
    }

    override suspend fun getForegroundInfo(): ForegroundInfo = AutoIndex.foregroundInfo(applicationContext)
}

/** Takes the tap on the Index button of the notification that asks before indexing a big batch, and its being swiped away. */
class AutoIndexReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            AutoIndex.ACTION_INDEX_NEW -> AutoIndex.indexNew(context)
            AutoIndex.ACTION_ASK_DISMISSED -> AutoIndex.askDismissed(context)
        }
    }
}
