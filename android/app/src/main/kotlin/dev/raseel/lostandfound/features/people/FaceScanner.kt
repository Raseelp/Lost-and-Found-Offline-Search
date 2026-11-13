package dev.raseel.lostandfound.features.people

import dev.raseel.lostandfound.core.log.AppLog
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.os.SystemClock
import dev.raseel.lostandfound.features.settings.BenchLog
import dev.raseel.lostandfound.features.library.IndexedImage
import dev.raseel.lostandfound.features.library.ScanEngineHolder
import dev.raseel.lostandfound.features.library.ScanForegroundService
import io.flutter.plugin.common.EventChannel
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.max
import kotlin.math.min

/** User-facing face options, kept in plain preferences. */
object FaceSettings {
    private const val PREFS = "face_settings"

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Also search overlapping tiles for small faces: slower, finds more. */
    fun thorough(context: Context): Boolean = prefs(context).getBoolean("thorough", false)

    fun setThorough(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean("thorough", value).apply()
    }

    /**
     * Recognise the small, blurry and turned-away faces too, in a second pass
     * after the clear faces are done. Off means those are never recognised.
     */
    fun refine(context: Context): Boolean = prefs(context).getBoolean("refine", true)

    fun setRefine(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean("refine", value).apply()
    }

    /** Also find the people in videos (after the photos). */
    fun scanVideos(context: Context): Boolean = prefs(context).getBoolean("scan_videos", true)

    fun setScanVideos(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean("scan_videos", value).apply()
    }

    const val DENSITY_FAST = "fast"
    const val DENSITY_BALANCED = "balanced"
    const val DENSITY_THOROUGH = "thorough"

    /** How many frames of a video are searched: fast (about one per 3 s), balanced (2 s), thorough (1 s). */
    fun videoDensity(context: Context): String = prefs(context).getString("video_density", DENSITY_BALANCED) ?: DENSITY_BALANCED

    fun setVideoDensity(context: Context, value: String) {
        if (value == DENSITY_FAST || value == DENSITY_BALANCED || value == DENSITY_THOROUGH) {
            prefs(context).edit().putString("video_density", value).apply()
        }
    }

    /** The user stopped the scan; nothing starts it again until they resume. */
    fun paused(context: Context): Boolean = prefs(context).getBoolean("paused", false)

    fun setPaused(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean("paused", value).apply()
    }
}

/**
 * Process-wide hub between the face scan, which may run in a WorkManager worker while the app is closed, and whichever
 * Flutter engine is listening. It exists for the same reason as the indexing scan's static progress sink.
 */
object FaceScanHub {
    @Volatile var sink: EventChannel.EventSink? = null
    @Volatile var last: Map<String, Any?>? = null
    @Volatile var running: Boolean = false

    private val main = Handler(Looper.getMainLooper())

    fun publish(status: Map<String, Any?>) {
        last = status
        main.post { sink?.success(status) }
    }
}

/** The face pipeline's shared pieces, created once per process. */
class FaceServices private constructor(context: Context) {
    val engine = FaceEngine(context)
    val store = FaceStore(context)
    val clusterer = FaceClusterer(context, store)
    val scanner = FaceScanner(context, this)
    val videoScanner = VideoFaceScanner(context, this)
    val crops = FaceCrops(context, store)

    companion object {
        @Volatile private var instance: FaceServices? = null

        fun get(context: Context): FaceServices =
            instance ?: synchronized(this) {
                instance ?: FaceServices(context.applicationContext).also { instance = it }
            }
    }
}

/**
 * Finds, recognises and groups the faces of the photos in the search index, in the background and newest first.
 * Finished photos are skipped, so it is safe to stop and start. The first pass recognises the clear faces, which
 * builds the people. The second pass attaches the rest to them and never starts a person.
 * While an indexing scan runs, a [Session] works in step with it, and only the first pass happens then.
 */
/** Where the scan of one photo opened in the viewer has got to (read by the viewer while it waits). */
class PhotoScanProgress {
    /** The step the scan is at: reading, detecting, recognising, then placing. */
    @Volatile var stage = "reading"
    /** Faces found that are worth recognising. */
    @Volatile var faces = 0
    /** How many faces are being recognised at the moment. */
    @Volatile var total = 0
    /** True while a photo that was scanned before is being finished. */
    @Volatile var more = false

    /** A video: how many of its sampled frames have been looked through so far. */
    @Volatile var video = false
    @Volatile var step = 0
    @Volatile var steps = 0

    /** How loose the search is: 0 standard, 1 looser, 2 loosest (see VideoFaceScanner.Relax). */
    @Volatile var relax = 0
}

class FaceScanner(private val context: Context, private val services: FaceServices) {

    /** The photos being scanned for the viewer, by uri. */
    val photoProgress = ConcurrentHashMap<String, PhotoScanProgress>()

    private class Attempt(var processed: Int = 0, var failed: Int = 0)

    /** A photo decoded ahead of time (null photo = it could not be read), and how long the decode took. */
    private class Prepared(val item: IndexedImage, val photo: FaceImageLoader.LoadedPhoto?, val decodeNs: Long = 0L)

    /** A face found in a photo, with everything needed to store it. */
    private class PendingFace(
        val box: DetectedFace,
        val sizePx: Int,
        val yaw: Float,
        val sharpness: Float,
        val good: Boolean,
        val rank: Float,
        /** Set only for faces being recognised, and freed once they have been. */
        var aligned: Bitmap?,
        var embedding: FloatArray? = null,
    )

    /** A photo whose clear faces are waiting for recognition. */
    private class Job(
        val item: IndexedImage,
        val width: Int,
        val height: Int,
        /** The size of the small copy, for turning boxes into 0..1 fractions. */
        val boxW: Float,
        val boxH: Float,
        val faces: List<PendingFace>,
    ) {
        val toRecognise get() = faces.count { it.aligned != null }
    }

    /**
     * Where the time goes, for the performance logs (see BenchLog, adb logcat -s LostFoundBench):
     * logged every few dozen photos, and at the end of each batch in step with indexing.
     */
    private class Timing {
        var photos = 0
        var faces = 0
        var recognised = 0
        var decodeNs = 0L
        var waitNs = 0L
        var detectNs = 0L
        var alignNs = 0L
        var embedNs = 0L
        var dbNs = 0L

        /**
         * The two stages of a pass waiting on each other: the recognition thread with
         * nothing to do (detection is the slower stage), detection blocked because
         * recognition is two batches behind (recognition is).
         */
        var stageIdleNs = 0L
        var stageStallNs = 0L
        var batches = 0
        val startedAt = SystemClock.elapsedRealtime()

        fun report(context: Context, label: String) {
            if (photos == 0) return
            BenchLog.log {
                val wall = SystemClock.elapsedRealtime() - startedAt
                fun ms(ns: Long, per: Int) = if (per == 0) 0 else (ns / 1_000_000 / per).toInt()
                "faces [$label]: $photos photos in ${"%.1f".format(wall / 1000.0)}s = " +
                    "${"%.1f".format(photos * 1000.0 / max(wall, 1L))}/s | per photo: wall ${wall / photos}ms = " +
                    "decode ${ms(decodeNs, photos)}ms ($DECODE_THREADS threads, run ahead), " +
                    "waited-on-decoder ${ms(waitNs, photos)}ms, detect ${ms(detectNs, photos)}ms, " +
                    "align ${ms(alignNs, photos)}ms, recognise ${ms(embedNs, photos)}ms, db ${ms(dbNs, photos)}ms | " +
                    "faces/photo ${"%.1f".format(faces.toFloat() / photos)}, " +
                    "recognised/photo ${"%.1f".format(recognised.toFloat() / photos)}, " +
                    "${ms(embedNs, max(recognised, 1))}ms per recognised face, " +
                    "avg recognition batch ${"%.1f".format(recognised.toFloat() / max(batches, 1))} | " +
                    "recognition thread idle ${ms(stageIdleNs, photos)}ms, " +
                    "detection blocked on it ${ms(stageStallNs, photos)}ms (per photo) | " +
                    BenchLog.device(context)
            }
        }
    }

    /**
     * True if there is anything to do: photos not searched yet, faces still to
     * recognise, or a changed model that means starting over. Checked before
     * starting the background work so an idle app doesn't flash a notification
     * on every launch.
     */
    fun hasWork(): Boolean {
        val engine = services.engine
        if (FaceSettings.paused(context) || !engine.isReady()) return false
        val store = services.store
        val indexer = ScanEngineHolder.embeddingEngine(context)
        val indexed = indexer.indexedImages()
        val videos = if (FaceSettings.scanVideos(context)) indexer.indexedVideos() else emptyList()
        if (indexed.isEmpty() && videos.isEmpty()) return false
        if (!sameModels(store.getMeta(META_MODEL_KEY), engine.modelKey())) return true
        if (FaceTuner.needsTuning(context, engine.store)) return true
        val finished = store.processedHashes()
        if (indexed.any { it.hash !in finished }) return true
        if (FaceSettings.refine(context) && store.deferredPhotoCount() > 0) return true
        if (videos.isNotEmpty()) {
            val done = store.processedVideoHashes()
            if (videos.any { it.hash !in done }) return true
        }
        return false
    }

    /**
     * Blocks until everything is processed or [shouldStop] says to give up. [onTick] receives status maps, also
     * published to Flutter.
     * A later run waits for a stopped one that is still finishing its last photo. Photos are analysed at a slightly
     * raised thread priority, put back afterwards because the thread belongs to a shared pool.
     */
    fun run(shouldStop: () -> Boolean, onTick: (Map<String, Any?>) -> Unit) {
        synchronized(runLock) {
            val tid = Process.myTid()
            val previous = Process.getThreadPriority(tid)
            try {
                Process.setThreadPriority(Process.THREAD_PRIORITY_MORE_FAVORABLE)
            } catch (_: Exception) {
            }
            try {
                Run(shouldStop, onTick).execute()
            } finally {
                try {
                    Process.setThreadPriority(previous)
                } catch (_: Exception) {
                }
            }
        }
    }

    /**
     * Face scanning in step with an indexing scan. It is handed each batch of newly indexed photos (see ScanHandoff)
     * and works through it at full speed while indexing waits. Only the first pass happens here. The speed test runs
     * on the first batch, when indexing is paused and the timings are true. The refining pass and videos are left to
     * [run].
     */
    inner class Session(onTick: (Map<String, Any?>) -> Unit) {
        @Volatile private var cancelled: () -> Boolean = { false }
        private val run = Run({ cancelled() || FaceSettings.paused(context) }, onTick)

        /** True if the batch was worked through; false if stopped, or the models can't be used. */
        fun processBatch(photos: List<IndexedImage>, shouldStop: () -> Boolean): Boolean {
            cancelled = shouldStop
            return synchronized(runLock) { run.followBatch(photos) }
        }

        /** The indexing scan is over (or this was stopped): say so, and log where the time went. */
        fun finish() {
            synchronized(runLock) { run.endFollowing() }
        }
    }

    fun openSession(onTick: (Map<String, Any?>) -> Unit): Session = Session(onTick)

    private val runLock = Any()
    private val commitLock = Any()

    /**
     * Finishes a photo the scan has already been through, opened in the viewer. Its first pass left the faces beyond
     * the clearest few found but not recognised, so they are recognised here and every face in the photo can be
     * tapped. True if any were done.
     */
    private fun completeDeferred(uri: String, hash: Long, progress: PhotoScanProgress): Boolean {
        val engine = services.engine
        val store = services.store
        val faces = store.deferredFaces(hash)
        if (faces.isEmpty()) {
            store.markPhotoComplete(hash)
            return false
        }
        progress.more = true
        progress.faces = faces.size
        progress.total = faces.size

        val loaded = try {
            FaceImageLoader.loadWithInfo(context, Uri.parse(uri), SCAN_SIDE, allowSlightlySmaller = true)
        } catch (e: Exception) {
            return false
        } catch (e: OutOfMemoryError) {
            return false
        } ?: return false

        class Item(val face: FaceStore.DeferredFace, val aligned: AlignedFace)
        val items = ArrayList<Item>()
        val bitmap = loaded.bitmap
        try {
            val w = bitmap.width.toFloat()
            val h = bitmap.height.toFloat()
            for (f in faces) {
                val landmarks = FloatArray(10) { k -> f.landmarks[k] * (if (k % 2 == 0) w else h) }
                items += Item(f, engine.align(bitmap, landmarks))
            }
        } catch (e: Exception) {
            // Something odd about one face must not leak the ones already cut out.
            items.forEach { it.aligned.bitmap.recycle() }
            AppLog.w(TAG, "preparing faces failed for $uri: ${e.message}")
            return false
        } finally {
            bitmap.recycle()
        }

        try {
            progress.stage = "recognising"
            val vectors = engine.embedAligned(items.map { it.aligned.bitmap })
            progress.stage = "placing"
            synchronized(commitLock) {
                for (i in items.indices.sortedByDescending { items[it].face.rank }) {
                    val item = items[i]
                    if (!store.isDeferred(item.face.id)) continue
                    val good = FaceQuality.isGood(item.face.sizePx, item.face.score, item.aligned.sharpness, item.face.yaw)
                    store.setFaceRecognised(item.face.id, vectors[i], item.aligned.sharpness, good)
                    services.clusterer.assignRecognised(item.face.id, hash, vectors[i], good, item.face.rank)
                }
                store.markPhotoComplete(hash)
            }
        } catch (e: Exception) {
            AppLog.w(TAG, "finishing faces failed for $uri: ${e.message}")
            return false
        } finally {
            items.forEach { it.aligned.bitmap.recycle() }
        }
        return true
    }

    /**
     * Scans a video opened in the viewer if it has not been scanned: all of its sampled frames, stored and grouped as
     * the background scan would, so its people are ready for the strip. Progress is readable while it runs (see
     * [photoProgress], key "video:uri"). True if the video ends up complete; false if it already was, could not be
     * read, or is not in the search index, or there are no models.
     */
    /** What a tap on the video's scan button would do: [state] "needs" / "done" / "unavailable"; the search [level]; faces the last scan kept. */
    class VideoScanPlan(val state: String, val level: Int, val lastFaces: Int?)

    fun videoScanPlan(uri: String): VideoScanPlan {
        val engine = services.engine
        val store = services.store
        if (!engine.isReady() || !usableModels()) {
            return VideoScanPlan("unavailable", 0, null)
        }
        val video = ScanEngineHolder.embeddingEngine(context).indexedVideos().firstOrNull { it.uri == uri }
            ?: return VideoScanPlan("unavailable", 0, null)
        val stored = services.videoScanner.relaxOf(video.hash)
        val last = store.videoFaceCount(video.hash)
        /** Scanned before and nothing was found: the next look is a looser one. */
        val level = if (last != null && last == 0) (stored + 1).coerceAtMost(VideoFaceScanner.MAX_RELAX) else stored
        return VideoScanPlan(if (last != null) "done" else "needs", level, last)
    }

    /** The result of [scanVideoNow]: whether it was scanned, at what search level, and how many faces were kept. */
    class VideoScanResult(val scanned: Boolean, val level: Int, val faces: Int)

    fun scanVideoNow(uri: String): VideoScanResult {
        val engine = services.engine
        val store = services.store
        val none = VideoScanResult(false, 0, 0)
        if (!engine.isReady()) return none
        if (!usableModels()) return none
        val video = ScanEngineHolder.embeddingEngine(context).indexedVideos().firstOrNull { it.uri == uri } ?: return none

        /**
         * Scans the video when the user taps the button, even if it was scanned before, and the second look replaces
         * the first. If the last look found nothing, this one is less strict. If the background scan is on the video,
         * it waits for that to finish rather than scanning twice.
         */
        val level = videoScanPlan(uri).level
        val outcome = services.videoScanner.scan(video, { false }, { true }, background = false, relax = level)
        if (outcome == VideoFaceScanner.BUSY) {
            services.videoScanner.waitUntilFree(video.hash, 180_000L)
            return VideoScanResult(store.isVideoDone(video.hash), level, store.videoFaceCount(video.hash) ?: 0)
        }
        return VideoScanResult(outcome >= 0, level, if (outcome > 0) outcome else 0)
    }

    /**
     * Looks for faces in one photo for the viewer, before the background scan has reached it. Only photos already in
     * the search index qualify, because their identity comes from there, and only with the models the stored people
     * were made with. True if the photo has its faces stored afterwards. A photo marked complete is left alone.
     */
    fun scanOne(uri: String): Boolean {
        val store = services.store
        val known = store.photoHashForUri(uri)
        if (known != null && store.isPhotoComplete(known)) return false

        val progress = PhotoScanProgress()
        photoProgress[uri] = progress
        try {
            return scanOneInner(uri, known, progress)
        } finally {
            photoProgress.remove(uri)
        }
    }
/**
 * Scans a photo that is not complete. One scanned before has only its clearest faces recognised, so the rest are done
 * here.
 */

    private fun scanOneInner(uri: String, known: Long?, progress: PhotoScanProgress): Boolean {
        val engine = services.engine
        val store = services.store
        if (!engine.isReady()) return false
        if (!usableModels()) return false
        if (known != null) return completeDeferred(uri, known, progress)
        val item = ScanEngineHolder.embeddingEngine(context).indexedImages().firstOrNull { it.uri == uri } ?: return false

        val thorough = FaceSettings.thorough(context)
        val photo = try {
            FaceImageLoader.loadWithInfo(context, Uri.parse(uri), if (thorough) REF_SIDE else SCAN_SIDE, allowSlightlySmaller = true)
        } catch (e: Exception) {
            AppLog.w(TAG, "could not read $uri: ${e.message}")
            return false
        } catch (e: OutOfMemoryError) {
            return false
        }
        try {
            Run({ false }, {}).also { it.watch = progress }.single(Prepared(item, photo), thorough)
        } catch (e: Exception) {
            AppLog.w(TAG, "single-photo scan failed for $uri: ${e.message}")
            return false
        }
        return store.hasPhotoUri(uri)
    }

    /**
     * Whether two stored model keys name the same models. A key with the ".bundled_" prefix is the same model as
     * without it, which is not a reason to throw the people away.
     */
    private fun sameModels(stored: String?, current: String?): Boolean = ModelKeys.same(stored, current)

    /**
     * Whether faces can be added to the people already stored without starting the grouping over: nothing is stored yet,
     * or the stored key names the models in use. Unlike [usableModels] it changes nothing.
     */
    fun modelsMatchStored(): Boolean = ModelKeys.usable(services.store.getMeta(META_MODEL_KEY), services.engine.modelKey())

    /**
     * Whether the viewer may look for faces with the models in use. A scan that has not got as far as saving the key
     * (stopped before its first batch of faces) leaves none, and then there are no people to clash with, so the key is
     * saved here and the models are used.
     */
    private fun usableModels(): Boolean {
        val key = services.engine.modelKey()
        val stored = services.store.getMeta(META_MODEL_KEY)
        if (!ModelKeys.usable(stored, key)) return false
        if (stored == null) services.store.setMeta(META_MODEL_KEY, key!!)
        return true
    }

    private inner class Run(val shouldStop: () -> Boolean, val onTick: (Map<String, Any?>) -> Unit) {
        val engine = services.engine
        val store = services.store
        val clusterer = services.clusterer

        val startedAt = SystemClock.elapsedRealtime()
        val attempt = Attempt()
        var timing = Timing()
        val tried = HashSet<Long>()

        /** Set for a photo opened in the viewer, and its progress is reported here. */
        var watch: PhotoScanProgress? = null

        /** Videos this run has done, and when that part started, for a fair time left. */
        var videosDone = 0
        var videosStartedAt = 0L

        var phase = "scan"

        /**
         * True while this run belongs to an indexing scan (see [Session]) and works through one of the batches it
         * handed over.
         */
        var following = false
        @Volatile var batchActive = false
        /** Bumped by whichever thread stores a photo (see [commit]), and read when reporting. */
        @Volatile var processed = 0
        var total = 0
        var lastEmitAt = 0L
        var lastStatsAt = 0L
        var stats = Triple(0, 0, 0)
        var sinceMerge = 0
        /** Both stages of a pass (see [RecognitionStage]) count into this. */
        val consecutiveFailures = AtomicInteger(0)

        /**
         * The faces stored most recently, newest first, with what the app's square draws of them: the photo each was
         * found in, where the face and its landmarks are (as fractions of the photo) and who it was placed with. Kept
         * only while a batch of an indexing scan is worked through, and reset with each.
         */
        @Volatile var recentFaceEvents: List<Map<String, Any?>> = emptyList()

        /** Set when faces were stored, so the next [emit] goes out at once without waiting for the usual interval. */
        @Volatile var newFaces = false

        /** Photos whose clear faces are waiting for a recognition batch. */
        val jobs = ArrayList<Job>()
        var pendingFaces = 0

        /**
         * Reports the status to the app. The totals are a few queries over the whole table, so they are refreshed only
         * every [STATS_INTERVAL_MS]. A video takes far longer than a photo, so its time left comes from videos only.
         */
        fun emit(paused: Boolean = false, done: Boolean = false, error: String? = null, force: Boolean = false) {
            val now = SystemClock.elapsedRealtime()
            if (!force && !done && !newFaces && now - lastEmitAt < EMIT_INTERVAL_MS) return
            newFaces = false
            lastEmitAt = now
            if (force || done || now - lastStatsAt > STATS_INTERVAL_MS) {
                stats = store.stats()
                lastStatsAt = now
            }
            val status = mapOf<String, Any?>(
                "running" to !done,
                "paused" to paused,
                "userPaused" to FaceSettings.paused(context),
                "done" to done,
                "phase" to phase,
                "following" to following,
                "batch" to batchActive,
                "processed" to processed,
                "total" to total,
                "faces" to stats.second,
                "people" to stats.third,
                "failed" to attempt.failed,
                "recentFaceEvents" to recentFaceEvents,
                "runProcessed" to (if (phase == "videos") videosDone else attempt.processed),
                "elapsedMs" to (if (phase == "videos") now - videosStartedAt else now - startedAt),
                "error" to error,
            )
            FaceScanHub.publish(status)
            onTick(status)
        }

        /** Waits for the indexing scan to finish, because it has priority. False if stopped meanwhile. */
        fun waitForIndexing(): Boolean {
            while (ScanForegroundService.isScanActive) {
                emit(paused = true, force = true)
                if (shouldStop()) return false
                Thread.sleep(PAUSE_POLL_MS)
            }
            return true
        }

        /**
         * Starts the grouping over when the models changed, because vectors from a different model pair cannot be
         * compared. A key that differs only in the internal name (see [sameModels]) changes nothing, and a first key is
         * saved with nothing to start over, since people are only stored after a key.
         */
        private fun adoptModels() {
            val key = engine.modelKey()!!
            val stored = store.getMeta(META_MODEL_KEY)
            if (stored != key) {
                if (stored == null || sameModels(stored, key)) {
                    store.setMeta(META_MODEL_KEY, key)
                } else {
                    AppLog.i(TAG, "face model changed to $key - regrouping from scratch")
                    store.wipeAll()
                    clusterer.invalidate()
                    store.setMeta(META_MODEL_KEY, key)
                }
            }
        }

        private var modelsAdopted = false
        private var configLogged = false

        /**
         * Logs what the models run with, once per run. One side being slower than the other is often a thread count or
         * a backend, not the model itself.
         */
        private fun logConfigOnce() {
            if (configLogged) return
            configLogged = true
            BenchLog.log {
                fun cfg(kind: FaceModelKind) = engine.store.selected(kind)?.let {
                    "${it.spec.id} on ${FaceTuner.configFor(context, it.spec).describe()}"
                } ?: "none"
                "faces config: detector ${cfg(FaceModelKind.DETECTOR)}; recogniser ${cfg(FaceModelKind.EMBEDDER)}; " +
                    "tuned=${!FaceTuner.needsTuning(context, engine.store)} thorough=${FaceSettings.thorough(context)} " +
                    "cpus=${Runtime.getRuntime().availableProcessors()} bigCores=${FaceTuner.bigCores()} " +
                    "decode=${FaceScanner.SCAN_SIDE}px"
            }
        }

        /**
         * One batch of a [Session]: the photos an indexing scan has just written, worked through at full speed while
         * it waits. [processed] and [total] count this batch. The one-off speed test runs first if it has not
         * happened, because indexing is waiting and the timings are true. False if stopped, or the models cannot be
         * used.
         */
        fun followBatch(photos: List<IndexedImage>): Boolean {
            if (FaceSettings.paused(context) || !engine.isReady()) return false
            if (!modelsAdopted) {
                adoptModels()
                modelsAdopted = true
            }
            following = true
            batchActive = true
            try {
                if (FaceTuner.needsTuning(context, engine.store)) {
                    phase = "tune"
                    processed = 0
                    total = photos.size
                    emit(force = true)
                    FaceTuner.tune(context, engine.store, shouldStop)
                    engine.reloadSessions()
                    phase = "scan"
                    if (shouldStop()) {
                        emit(done = true, force = true)
                        return false
                    }
                }

                processed = 0
                total = photos.size
                timing = Timing()
                recentFaceEvents = emptyList()
                logConfigOnce()
                BenchLog.log {
                    "faces batch start: ${photos.size} just-indexed photos | ${BenchLog.device(context)}"
                }
                emit(force = true)
                val finished = processPhotos(photos, FaceSettings.thorough(context), yieldToIndexing = false)
                timing.report(context, "batch of ${photos.size}")
                return finished
            } finally {
                batchActive = false
                emit(force = true)
            }
        }

        fun endFollowing() {
            following = false
            batchActive = false
            emit(done = true, force = true)
        }

        fun execute() {
            if (FaceSettings.paused(context)) {
                emit(done = true, force = true)
                return
            }
            if (!engine.isReady()) {
                emit(done = true, error = "no_model")
                return
            }

            adoptModels()
            logConfigOnce()

            if (FaceTuner.needsTuning(context, engine.store)) {
                if (!waitForIndexing()) {
                    emit(done = true, force = true)
                    return
                }
                phase = "tune"
                emit(force = true)
                FaceTuner.tune(context, engine.store, shouldStop)
                engine.reloadSessions()
                if (shouldStop()) {
                    emit(done = true, force = true)
                    return
                }
            }

            val refine = FaceSettings.refine(context)
            while (true) {
                phase = "scan"
                if (!scanPhotos()) return
                if (!refine) break
                phase = "refine"
                if (!refineFaces()) return
                if (!hasNewPhotos()) break
            }

            if (FaceSettings.scanVideos(context)) {
                phase = "videos"
                if (!scanVideos()) return
            }

            timing.report(context, "run end")
            clusterer.mergeSimilar()
            phase = "scan"
            val (photos, _, _) = store.stats()
            processed = photos
            total = photos
            emit(done = true, force = true)
        }

        /** False if stopped. A video the viewer scanned meanwhile is skipped. */
        fun scanVideos(): Boolean {
            val indexer = ScanEngineHolder.embeddingEngine(context)
            val videos = indexer.indexedVideos()
            if (store.purgeMissingVideos(videos.map { it.hash }.toHashSet())) clusterer.invalidate()

            val done = store.processedVideoHashes()
            val pending = videos.filter { it.hash !in done }
            total = videos.size
            processed = videos.size - pending.size
            videosDone = 0
            videosStartedAt = SystemClock.elapsedRealtime()
            emit(force = true)

            for (video in pending) {
                if (shouldStop()) {
                    emit(done = true, force = true)
                    return false
                }
                if (!waitForIndexing()) {
                    emit(done = true, force = true)
                    return false
                }
                if (store.isVideoDone(video.hash)) {
                    processed++
                    continue
                }
                val outcome = services.videoScanner.scan(video, shouldStop, gate = { waitForIndexing() })
                when (outcome) {
                    VideoFaceScanner.BUSY -> continue
                    VideoFaceScanner.STOPPED -> {
                        emit(done = true, force = true)
                        return false
                    }
                    VideoFaceScanner.FAILED -> attempt.failed++
                    else -> {
                        processed++
                        videosDone++
                    }
                }
                emit()
            }
            return true
        }

        private fun hasNewPhotos(): Boolean {
            val finished = store.processedHashes()
            return ScanEngineHolder.embeddingEngine(context).indexedImages().any { it.hash !in finished && it.hash !in tried }
        }

        /** False if stopped. */
        fun scanPhotos(): Boolean {
            val thorough = FaceSettings.thorough(context)
            val indexer = ScanEngineHolder.embeddingEngine(context)

            while (true) {
                val indexed = indexer.indexedImages()
                if (store.purgeMissing(indexed.map { it.hash }.toHashSet())) clusterer.invalidate()

                val finished = store.processedHashes()
                val pending = indexed.filter { it.hash !in finished && it.hash !in tried }.asReversed()
                processed = finished.size
                total = indexed.size
                if (pending.isEmpty()) {
                    emit(force = true)
                    return true
                }

                if (!processPhotos(pending, thorough, yieldToIndexing = true)) return false
            }
        }

        /**
         * Decodes, analyses and recognises [pending], one decode ahead of the analysis. Several decoders take the
         * photos in turn so decoding keeps up with detection, and the photos reach the analysis in whatever order they
         * finish. [yieldToIndexing] makes it wait whenever an indexing scan runs, which the normal passes do but a
         * batch handed over by indexing does not. False if stopped.
         */
        private fun processPhotos(pending: List<IndexedImage>, thorough: Boolean, yieldToIndexing: Boolean): Boolean {
            val cancelled = AtomicBoolean(false)
            val queue = ArrayBlockingQueue<Any>(PREFETCH)
            val end = Any()
            val nextIndex = AtomicInteger(0)
            val decodersLeft = AtomicInteger(DECODE_THREADS)
            val producers = List(DECODE_THREADS) { n ->
                Thread({ produce(pending, thorough, queue, cancelled, end, nextIndex, decodersLeft) }, "face-decode-$n")
                    .also { it.start() }
            }
            val stage = RecognitionStage()
            recognition = stage

            try {
                while (true) {
                    stage.failure?.let { throw it }
                    if (shouldStop()) {
                        discardJobs()
                        stage.abandon()
                        emit(done = true, force = true)
                        return false
                    }
                    val waitStartedNs = System.nanoTime()
                    val next = queue.poll(300, TimeUnit.MILLISECONDS)
                    timing.waitNs += System.nanoTime() - waitStartedNs
                    if (next == null) {
                        flush()
                        continue
                    }
                    if (next === end) break
                    val prepared = next as Prepared

                    if (yieldToIndexing && ScanForegroundService.isScanActive) {
                        flush()
                        stage.awaitIdle()
                        if (!waitForIndexing()) {
                            prepared.photo?.bitmap?.recycle()
                            discardJobs()
                            stage.abandon()
                            emit(done = true, force = true)
                            return false
                        }
                    }

                    tried.add(prepared.item.hash)
                    attempt.processed++
                    timing.decodeNs += prepared.decodeNs
                    analyse(prepared, thorough)

                    if (timing.photos > 0 && timing.photos % REPORT_EVERY == 0) timing.report(context, "progress")
                    emit()
                }
                flush()
                stage.finish()
                stage.failure?.let { throw it }
            } finally {
                recognition = null
                stage.close()
                discardJobs()
                cancelled.set(true)
                while (true) {
                    val left = queue.poll() ?: break
                    (left as? Prepared)?.photo?.bitmap?.recycle()
                }
                for (producer in producers) producer.join(3000)
            }
            return true
        }

        /**
         * Finds the faces in one photo, cuts them out and decides which are worth recognising. Face sizes are quoted
         * as if the photo were at most [REF_SIDE] across. With [everyFace] every face big enough is recognised, not
         * just the clearest few. An unreadable photo is recorded as having no faces, but a model or runtime problem is
         * not recorded, so it is tried again on the next run.
         */
        private fun analyse(prepared: Prepared, thorough: Boolean, everyFace: Boolean = false) {
            val item = prepared.item
            val photo = prepared.photo

            if (photo == null) {
                synchronized(commitLock) {
                    store.insertPhoto(item.hash, item.uri, 0, 0, emptyList())
                    attempt.failed++
                    processed++
                }
                return
            }

            val small = photo.bitmap
            val built = ArrayList<PendingFace>()
            watch?.stage = "detecting"
            try {
                var t = System.nanoTime()
                val detected = engine.detect(small, thorough)
                timing.detectNs += System.nanoTime() - t
                timing.photos++
                timing.faces += detected.size

                val smallLong = max(small.width, small.height)
                val origLong = max(photo.originalWidth, photo.originalHeight)
                val refScale = min(origLong, REF_SIDE).toFloat() / smallLong
                val refW = (small.width * refScale).toInt()
                val refH = (small.height * refScale).toInt()

                t = System.nanoTime()
                for (box in detected) {
                    val size = (min(box.width, box.height) * refScale).toInt()
                    if (size < FaceQuality.MIN_EMBED_PX) continue

                    val aligned = engine.align(small, box.landmarks)
                    val yaw = FaceQuality.yaw(box.landmarks)
                    val good = FaceQuality.isGood(size, box.score, aligned.sharpness, yaw)
                    built += PendingFace(
                        box = box, sizePx = size, yaw = yaw, sharpness = aligned.sharpness, good = good,
                        rank = FaceQuality.rank(size, box.score, yaw), aligned = aligned.bitmap,
                    )
                }

                val now = if (everyFace) {
                    built.toSet()
                } else {
                    built.filter { it.good }.sortedByDescending { it.rank }.take(MAX_FACES_NOW).toSet()
                }
                for (face in built) {
                    if (face !in now) {
                        face.aligned?.recycle()
                        face.aligned = null
                    }
                }
                timing.alignNs += System.nanoTime() - t
                watch?.let {
                    it.faces = built.size
                    it.total = now.size
                    it.stage = if (now.isEmpty()) "placing" else "recognising"
                }

                val job = Job(item, refW, refH, small.width.toFloat(), small.height.toFloat(), built)
                if (job.toRecognise == 0) {
                    commit(job)
                } else {
                    jobs += job
                    pendingFaces += job.toRecognise
                    val flushAt = if (batchActive && recentFaceEvents.isEmpty()) FIRST_FLUSH_AT else FLUSH_AT
                    if (pendingFaces >= flushAt) flush()
                }
            } catch (e: Exception) {
                AppLog.e(TAG, "face analysis failed for ${item.uri}: ${e.message}", e)
                bumpFailed(1)
                built.forEach { it.aligned?.recycle() }
                if (consecutiveFailures.incrementAndGet() >= MAX_CONSECUTIVE_FAILURES) throw e
            } finally {
                small.recycle()
            }
        }

        /**
         * Gets the waiting faces (several photos' worth, up to a full batch) recognised and their photos stored.
         * During a pass they are handed to the recognition stage, which works while the next photos are decoded.
         * Outside a pass, for a single photo opened in the viewer, it all happens in place.
         */
        private fun flush() {
            if (jobs.isEmpty()) return
            val batch = ArrayList(jobs)
            jobs.clear()
            pendingFaces = 0
            val stage = recognition
            if (stage == null) {
                recogniseAndStore(batch)?.let { throw it }
            } else if (!stage.submit(batch)) {
                discardBatch(batch)
            }
        }

        /**
         * Recognises every waiting face of [batch] in one go, then stores the photos. Returns the exception if
         * recognition keeps failing, too many times in a row to carry on, and null otherwise.
         */
        private fun recogniseAndStore(batch: List<Job>): Exception? {
            val waiting = batch.flatMap { job -> job.faces.filter { it.aligned != null } }
            val vectors = try {
                val t = System.nanoTime()
                engine.embedAligned(waiting.map { it.aligned!! }).also {
                    timing.embedNs += System.nanoTime() - t
                    timing.recognised += waiting.size
                    timing.batches += (waiting.size + 7) / 8
                }
            } catch (e: Exception) {
                AppLog.e(TAG, "recognition failed for ${batch.size} photos: ${e.message}", e)
                bumpFailed(batch.size)
                discardBatch(batch)
                return if (consecutiveFailures.incrementAndGet() >= MAX_CONSECUTIVE_FAILURES) e else null
            }
            consecutiveFailures.set(0)
            watch?.stage = "placing"

            waiting.forEachIndexed { i, face -> face.embedding = vectors[i] }
            for (job in batch) commit(job)
            return null
        }

        private fun bumpFailed(count: Int) {
            synchronized(commitLock) { attempt.failed += count }
        }

        private fun discardBatch(batch: List<Job>) {
            for (job in batch) job.faces.forEach { it.aligned?.recycle(); it.aligned = null }
        }

        private fun discardJobs() {
            discardBatch(jobs)
            jobs.clear()
            pendingFaces = 0
        }

        /**
         * The recognition stage of a pass: a thread of its own, fed whole batches of photos with the faces cut out, so
         * recognising them (the slow part) carries on while the next photos are decoded and searched. One thread,
         * first in first out, so photos are stored and grouped in order.
         */
        private var recognition: RecognitionStage? = null

        private inner class RecognitionStage {
            private val queue = ArrayBlockingQueue<Any>(MAX_QUEUED_BATCHES)
            private val end = Any()

            /** Batches handed over and not yet finished, queued or being recognised. */
            private val inFlight = AtomicInteger(0)

            @Volatile private var abandoned = false
            @Volatile var failure: Exception? = null
            private val thread = Thread({ work() }, "face-recognise")

            init {
                thread.start()
            }

            /**
             * Hands a batch over. Waits while the stage is [MAX_QUEUED_BATCHES] behind (that
             * is what keeps memory bounded); false if the pass is being stopped meanwhile.
             */
            fun submit(batch: List<Job>): Boolean {
                if (failure != null || !thread.isAlive) return false
                val waitStartedNs = System.nanoTime()
                inFlight.incrementAndGet()
                try {
                    while (!queue.offer(batch, 200, TimeUnit.MILLISECONDS)) {
                        if (shouldStop() || failure != null || !thread.isAlive) {
                            inFlight.decrementAndGet()
                            return false
                        }
                    }
                    return true
                } finally {
                    timing.stageStallNs += System.nanoTime() - waitStartedNs
                }
            }

            /** Waits until everything handed over so far has been recognised and stored. */
            fun awaitIdle() {
                while (inFlight.get() > 0 && thread.isAlive && !shouldStop()) Thread.sleep(20)
            }

            /** The normal end: everything handed over is recognised and stored when this returns. */
            fun finish() {
                sendEnd()
                thread.join()
            }

            /** The early end (stopped, or something failed): what is still queued is thrown away. */
            fun abandon() {
                abandoned = true
                discardQueued()
                sendEnd()
            }

            /** Always called when a pass is over, however it ended: the thread is gone afterwards. */
            fun close() {
                if (thread.isAlive) abandon()
                thread.join(30_000)
                discardQueued()
            }

            private fun sendEnd() {
                while (thread.isAlive && !queue.offer(end, 200, TimeUnit.MILLISECONDS)) {
                    // Still busy with the batches ahead of it.
                }
            }

            @Suppress("UNCHECKED_CAST")
            private fun discardQueued() {
                while (true) {
                    val left = queue.poll() ?: break
                    if (left === end) continue
                    discardBatch(left as List<Job>)
                    inFlight.decrementAndGet()
                }
            }

            @Suppress("UNCHECKED_CAST")
            private fun work() {
                try {
                    while (true) {
                        val idleStartedNs = System.nanoTime()
                        val next = queue.take()
                        timing.stageIdleNs += System.nanoTime() - idleStartedNs
                        if (next === end) return
                        val batch = next as List<Job>
                        try {
                            if (abandoned || failure != null) {
                                discardBatch(batch)
                            } else {
                                recogniseAndStore(batch)?.let { failure = it }
                            }
                        } catch (e: Exception) {
                            // Whatever of the batch was not stored still holds its aligned bitmaps.
                            discardBatch(batch)
                            throw e
                        } finally {
                            inFlight.decrementAndGet()
                        }
                    }
                } catch (_: InterruptedException) {
                } catch (e: Exception) {
                    AppLog.e(TAG, "the recognition stage failed: ${e.message}", e)
                    failure = e
                } finally {
                    discardQueued()
                }
            }
        }

        /**
         * Stores a photo and places its recognised faces among the people. Under a lock shared with [scanOne], so a
         * photo opened in the viewer while the background scan reaches it is never stored twice. A face without an
         * embedding is stored as found but not recognised, for the second pass.
         */
        private fun commit(job: Job) {
            synchronized(commitLock) { commitLocked(job) }
        }

        private fun commitLocked(job: Job) {
            if (store.hasPhoto(job.item.hash)) {
                job.faces.forEach { it.aligned?.recycle(); it.aligned = null }
                processed++
                return
            }
            val t = System.nanoTime()
            val rows = job.faces.map { f ->
                val box = f.box
                FaceRow(
                    boxL = box.left / job.boxW, boxT = box.top / job.boxH, boxR = box.right / job.boxW, boxB = box.bottom / job.boxH,
                    landmarks = FloatArray(10) { k -> box.landmarks[k] / (if (k % 2 == 0) job.boxW else job.boxH) },
                    score = box.score,
                    sizePx = f.sizePx,
                    sharpness = f.sharpness,
                    yaw = f.yaw,
                    good = f.good && f.embedding != null,
                    rank = f.rank,
                    embedding = f.embedding ?: FloatArray(0),
                )
            }
            val ids = try {
                store.insertPhoto(job.item.hash, job.item.uri, job.width, job.height, rows)
            } catch (e: Exception) {
                job.faces.forEach { it.aligned?.recycle(); it.aligned = null }
                throw e
            }
            val placed = try {
                clusterer.assignPhotoFaces(job.item.hash, ids, rows)
            } catch (e: Exception) {
                job.faces.forEach { it.aligned?.recycle(); it.aligned = null }
                throw e
            }
            if (batchActive) {
                val events = ArrayList<Map<String, Any?>>()
                for ((i, f) in job.faces.withIndex()) {
                    val id = ids.getOrNull(i) ?: continue
                    if (f.good && f.embedding != null) {
                        val row = rows[i]
                        val person = placed.getOrNull(i)
                        events += mapOf(
                            "id" to id,
                            "photo" to job.item.uri,
                            "box" to listOf(row.boxL, row.boxT, row.boxR, row.boxB),
                            "landmarks" to row.landmarks.toList(),
                            "score" to row.score,
                            "person" to person?.personId,
                            "isNew" to (person?.isNew ?: false),
                            "photos" to (person?.photos ?: 1),
                        )
                    }
                }
                if (events.isNotEmpty()) {
                    recentFaceEvents = (events.asReversed() + recentFaceEvents).take(RECENT_FACES)
                    newFaces = true
                }
            }
            job.faces.forEach { it.aligned?.recycle(); it.aligned = null }
            if (job.faces.all { it.embedding != null }) store.markPhotoComplete(job.item.hash)
            processed++

            if (++sinceMerge >= MERGE_EVERY) {
                sinceMerge = 0
                clusterer.mergeSimilar()
            }
            timing.dbNs += System.nanoTime() - t
        }

        /** One photo, start to finish, outside the normal run (see [scanOne]). */
        fun single(prepared: Prepared, thorough: Boolean) {
            analyse(prepared, thorough, everyFace = true)
            flush()
        }

        /**
         * Recognises the faces the first pass left and attaches them to existing people. Faces are updated under the
         * lock the viewer's top-up also takes, and only if nobody recognised them meanwhile. False if stopped.
         */
        fun refineFaces(): Boolean {
            val tries = HashSet<Long>()
            var done = 0
            total = store.deferredPhotoCount()
            processed = 0
            if (total == 0) return true
            var failures = 0

            while (true) {
                val batch = store.deferredPhotos(REFINE_PHOTOS_PER_ROUND).filter { it.hash !in tries }
                if (batch.isEmpty()) return true

                class Item(val faceId: Long, val hash: Long, val aligned: AlignedFace)
                val items = ArrayList<Item>()
                try {
                    for (photo in batch) {
                        if (shouldStop()) {
                            items.forEach { it.aligned.bitmap.recycle() }
                            emit(done = true, force = true)
                            return false
                        }
                        if (!waitForIndexing()) {
                            items.forEach { it.aligned.bitmap.recycle() }
                            emit(done = true, force = true)
                            return false
                        }
                        tries.add(photo.hash)

                        val faces = store.deferredFaces(photo.hash)
                        val loaded = try {
                            FaceImageLoader.loadWithInfo(context, Uri.parse(photo.uri), SCAN_SIDE, allowSlightlySmaller = true)
                        } catch (e: Exception) {
                            null
                        }
                        if (loaded == null) {
                            store.deleteFaces(faces.map { it.id })
                            continue
                        }
                        val bitmap = loaded.bitmap
                        try {
                            val w = bitmap.width.toFloat()
                            val h = bitmap.height.toFloat()
                            for (f in faces) {
                                val landmarks = FloatArray(10) { k -> f.landmarks[k] * (if (k % 2 == 0) w else h) }
                                items += Item(f.id, photo.hash, engine.align(bitmap, landmarks))
                            }
                        } finally {
                            bitmap.recycle()
                        }
                        attempt.processed++
                    }

                    if (items.isNotEmpty()) {
                        val t = System.nanoTime()
                        val vectors = engine.embedAligned(items.map { it.aligned.bitmap })
                        timing.embedNs += System.nanoTime() - t
                        timing.recognised += items.size
                        timing.batches += (items.size + 7) / 8
                        synchronized(commitLock) {
                            items.forEachIndexed { i, item ->
                                if (!store.isDeferred(item.faceId)) return@forEachIndexed
                                store.setFaceEmbedding(item.faceId, vectors[i], item.aligned.sharpness)
                                clusterer.assignExisting(item.faceId, item.hash, vectors[i])
                            }
                        }
                    }
                    for (photo in batch) store.markPhotoComplete(photo.hash)
                    failures = 0
                } catch (e: Exception) {
                    AppLog.e(TAG, "refining faces failed: ${e.message}", e)
                    attempt.failed++
                    if (++failures >= MAX_CONSECUTIVE_FAILURES) throw e
                } finally {
                    items.forEach { it.aligned.bitmap.recycle() }
                }

                done += batch.size
                processed = min(done, total)
                emit()
            }
        }
    }

    /**
     * The decoder thread: reads photos ahead of the analysis, one decode each
     * (bigger only when the thorough option's tiled pass wants the detail).
     */
    private fun produce(
        pending: List<IndexedImage>,
        thorough: Boolean,
        queue: ArrayBlockingQueue<Any>,
        cancelled: AtomicBoolean,
        end: Any,
        nextIndex: AtomicInteger,
        decodersLeft: AtomicInteger,
    ) {
        try {
            val side = if (thorough) REF_SIDE else SCAN_SIDE
            while (true) {
                if (cancelled.get()) return
                val index = nextIndex.getAndIncrement()
                if (index >= pending.size) break
                val item = pending[index]
                val decodeStartedNs = System.nanoTime()
                val photo = try {
                    FaceImageLoader.loadWithInfo(context, Uri.parse(item.uri), side, allowSlightlySmaller = true)
                } catch (e: Exception) {
                    AppLog.w(TAG, "could not read ${item.uri}: ${e.message}")
                    null
                } catch (e: OutOfMemoryError) {
                    AppLog.w(TAG, "out of memory reading ${item.uri}")
                    null
                }
                val prepared = Prepared(item, photo, System.nanoTime() - decodeStartedNs)
                while (!queue.offer(prepared, 300, TimeUnit.MILLISECONDS)) {
                    if (cancelled.get()) {
                        photo?.bitmap?.recycle()
                        return
                    }
                }
            }
            if (decodersLeft.decrementAndGet() == 0) {
                while (!queue.offer(end, 300, TimeUnit.MILLISECONDS)) {
                    if (cancelled.get()) return
                }
            }
        } catch (_: InterruptedException) {
        }
    }

    companion object {
        private const val TAG = "FaceScanner"
        private const val META_MODEL_KEY = "model_key"

        /** The size a photo is decoded to: detection only ever sees 640px, and faces are cut from this. */
        const val SCAN_SIDE = 2048

        /** Face sizes are quoted as if the photo were at most this many pixels across. */
        const val REF_SIDE = 3072

        /** Recognised in pass 1 at most this many faces per photo (the clearest); a big group's rest wait for pass 2. */
        private const val MAX_FACES_NOW = 8

        /** Faces waiting for recognition are sent to the model once this many have gathered. */
        private const val FLUSH_AT = 8

        /**
         * The first flush of a follow batch (see [processPhotos]) goes off as soon as there are a couple of faces, so
         * the first can be shown within a photo or two.
         */
        private const val FIRST_FLUSH_AT = 2

        /**
         * Batches the detection stage may hand to the recognition stage before it has to
         * wait for it (see RecognitionStage).
         */
        private const val MAX_QUEUED_BATCHES = 2

        /** Faces the square keeps track of at a time. */
        private const val RECENT_FACES = 12

        private const val REFINE_PHOTOS_PER_ROUND = 24
        private const val MAX_CONSECUTIVE_FAILURES = 20
        private const val PREFETCH = 2

        /**
         * Photos decoded at the same time. One decoder fell behind once recognition got
         * quick: decoding a photo (~0.4-0.9 s) took nearly as long as analysing it.
         */
        private const val DECODE_THREADS = 2
        private const val EMIT_INTERVAL_MS = 800L
        private const val STATS_INTERVAL_MS = 3000L
        private const val PAUSE_POLL_MS = 1500L
        private const val MERGE_EVERY = 500
        private const val REPORT_EVERY = 25
    }
}
