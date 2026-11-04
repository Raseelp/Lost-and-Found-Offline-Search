package dev.raseel.lostandfound.embedder.faces

import android.content.Context
import android.os.SystemClock
import android.util.Log
import kotlin.math.max
import androidx.work.WorkManager
import dev.raseel.lostandfound.embedder.BenchLog
import dev.raseel.lostandfound.embedder.IndexedImage
import dev.raseel.lostandfound.embedder.ScanForegroundService
import dev.raseel.lostandfound.embedder.ScanHandoff

/**
 * Finds faces in step with an indexing scan, in the same notification and without the two competing for the CPU. The
 * scan hands over the photos it has written. Once enough have gathered, or enough time has passed, indexing waits
 * while their faces are found, then carries on, all on the indexing scan's thread. When indexing ends ([finish])
 * FaceScanWorker takes over for the rest.
 */
object FaceFollower {

    private const val TAG = "FaceFollower"

    /**
     * When indexing waits for faces: once this many indexed photos have gathered, or [BATCH_MS] have passed since the
     * last time, whichever comes first. The same for every batch, the first included.
     */
    const val BATCH_PHOTOS = 60
    const val BATCH_MS = 30_000L

    private val lock = Any()
    private val waiting = ArrayList<IndexedImage>()

    /** Guarded by [lock]: how many batches this scan has had so far, and when the last one ended (or, before the first, when this started). */
    private var batches = 0
    private var lastBatchAt = 0L
    @Volatile private var session: FaceScanner.Session? = null
    @Volatile private var armed = false

    /**
     * Only an indexing scan in progress can be followed. ScanWorker closes this the moment its scan ends, so a late
     * request (from the app, say) cannot start another session or cancel the face worker that is about to take over.
     */
    @Volatile private var open = false

    /** True while faces are being found in step with an indexing scan. */
    fun isArmed(): Boolean = armed

    /**
     * While faces follow the scan: how many photos wait for the next batch, and how long it
     * is since the last one ended (a batch is due at [BATCH_PHOTOS] photos or [BATCH_MS],
     * whichever comes first). Null when faces do not follow.
     */
    fun queueInfo(): Pair<Int, Long>? = synchronized(lock) {
        if (!armed) null else waiting.size to (SystemClock.elapsedRealtime() - lastBatchAt)
    }

    fun openForScan() {
        open = true
    }

    fun closeForScan() {
        open = false
    }

    /**
     * Starts finding faces in step with the indexing scan in progress, unless it already does, face search is stopped
     * by the user, or no recognition model is installed. True when it is armed afterwards. A face worker still working
     * through earlier leftovers is stopped, because it would hold the face scan. It is resumable and carries on once
     * indexing ends.
     */
    fun start(context: Context): Boolean {
        synchronized(lock) {
            if (armed) return true
            val app = context.applicationContext
            if (!open || !ScanForegroundService.isScanActive) {
                BenchLog.log(app) { "faces not in step with indexing: no indexing scan is open for it (open=$open)" }
                return false
            }
            if (FaceSettings.paused(app)) {
                BenchLog.log(app) { "faces not in step with indexing: face search is stopped (resume it in People)" }
                return false
            }
            val services = FaceServices.get(app)
            if (!services.engine.isReady()) {
                BenchLog.log(app) { "faces not in step with indexing: the face models are not ready" }
                return false
            }

            try {
                WorkManager.getInstance(app).cancelUniqueWork(FaceScanWorker.UNIQUE_WORK_NAME)
            } catch (e: Exception) {
                Log.w(TAG, "could not stop the running face worker: ${e.message}")
            }

            waiting.clear()
            batches = 0
            lastBatchAt = SystemClock.elapsedRealtime()
            session = services.scanner.openSession { status -> ScanForegroundService.updateFaceProgress(app, status) }
            ScanHandoff.consumer = ScanHandoff.Consumer { photos, shouldStop -> onIndexed(app, photos, shouldStop) }
            armed = true
            BenchLog.log(app) {
                "faces in step with indexing: a batch every $BATCH_PHOTOS photos or ${BATCH_MS / 1000}s"
            }
            return true
        }
    }

    /**
     * Queues [photos] and, when a batch is due, finds their faces. Runs on the indexing scan's thread, which waits for
     * it to return. When face search is stopped by the user, the photos are left for the pass after indexing, or for
     * when they resume. The next interval counts from the end of a batch, not from when it began.
     */
    private fun onIndexed(app: Context, photos: List<IndexedImage>, shouldStop: () -> Boolean) {
        if (FaceSettings.paused(app)) {
            synchronized(lock) { waiting.clear() }
            return
        }

        val batch: List<IndexedImage>
        val current: FaceScanner.Session
        val number: Int
        val ranMs: Long
        val byCount: Boolean
        synchronized(lock) {
            current = session ?: return
            if (!armed) return
            waiting += photos
            val now = SystemClock.elapsedRealtime()
            byCount = waiting.size >= BATCH_PHOTOS
            val due = byCount || now - lastBatchAt >= BATCH_MS
            if (!due) return
            batch = ArrayList(waiting)
            waiting.clear()
            batches++
            number = batches
            ranMs = now - lastBatchAt
        }

        BenchLog.log(app) {
            "face batch #$number due: ${batch.size} photos (${if (byCount) "photo count" else "time"} reached); " +
                "indexing ran ${ranMs}ms since the last one | ${BenchLog.device(app)}"
        }
        val startedAt = SystemClock.elapsedRealtime()
        FaceScanHub.running = true
        try {
            current.processBatch(batch, shouldStop)
        } finally {
            FaceScanHub.running = false
            val endedAt = SystemClock.elapsedRealtime()
            synchronized(lock) { lastBatchAt = endedAt }
            BenchLog.log(app) {
                "face batch #$number done: faces took ${endedAt - startedAt}ms for ${batch.size} photos; " +
                    "indexing had run ${ranMs}ms (indexing:faces = ${"%.2f".format(ranMs / max(endedAt - startedAt, 1L).toDouble())}) | " +
                    BenchLog.device(app)
            }
        }
    }

    /** Stops handing photos over (the user stopped face search), without ending the session. */
    fun stop() {
        synchronized(lock) {
            armed = false
            ScanHandoff.consumer = null
            waiting.clear()
        }
    }

    /** The indexing scan is over: stop, and let the session say so. Safe to call more than once. */
    fun finish() {
        val ended: FaceScanner.Session?
        synchronized(lock) {
            armed = false
            ScanHandoff.consumer = null
            waiting.clear()
            ended = session
            session = null
        }
        ended?.finish()
        ScanForegroundService.clearFaceProgress()
    }
}
