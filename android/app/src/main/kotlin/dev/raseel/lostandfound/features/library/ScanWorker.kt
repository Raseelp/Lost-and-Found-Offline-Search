package dev.raseel.lostandfound.features.library

import dev.raseel.lostandfound.core.log.AppLog
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationManagerCompat
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import dev.raseel.lostandfound.features.people.FaceFollower
import dev.raseel.lostandfound.features.people.FaceScanWorker
import dev.raseel.lostandfound.features.people.FaceSettings

/**
 * Runs the scan as WorkManager work. Embedding is idempotent, because already-embedded files are skipped by hash. So
 * when the OS kills the process mid-scan, WorkManager runs this work again and [EmbeddingEngine.embedImages]
 * fast-skips what is done instead of duplicating it. The kill itself cannot be prevented on every OEM, but it no
 * longer ends the scan. That fixes the background scan that stopped after about 10 minutes and never resumed.
 */
class ScanWorker(
    context: Context,
    params: WorkerParameters
) : CoroutineWorker(context, params) {

    /**
     * Runs one scan at a time. WorkManager's cancel does not stop a scan, so the scan still running is asked to stop
     * and this one waits for it. Whatever the winding-down scan reports is dropped, above all its final done tick,
     * which the app takes to mean that the latest scan has finished.
     */
    override suspend fun doWork(): Result {
        val thisRun = latestRun.incrementAndGet()
        ScanEngineHolder.embeddingEngine(applicationContext).cancelEmbedding()
        return scanMutex.withLock {
            running.incrementAndGet()
            try {
                runScan(thisRun)
            } finally {
                running.decrementAndGet()
            }
        }
    }

    /**
     * Runs the scan and the face search that follows it, and returns when both are over. Starting a scan resumes a
     * stopped face search, because that stop is remembered across launches. An exception here sends a synthetic done
     * tick so Dart clears isScanning, and the result is failure because retry() could repeat the same failure forever.
     */
    private suspend fun runScan(thisRun: Int): Result {
        val mode = inputData.getString(KEY_MODE) ?: "folder"
        val uri = inputData.getString(KEY_URI)
        val folderId = inputData.getString(KEY_FOLDER_ID) ?: "default"
        val contentMode = inputData.getString(KEY_CONTENT_MODE) ?: "both"

        ScanForegroundService.onScanStarting(applicationContext)
        LatestScan.begin(applicationContext, resume = runAttemptCount > 0)

        try {
            setForeground(createForegroundInfo())
        } catch (e: Exception) {
            AppLog.w(TAG, "doWork: setForeground failed, continuing anyway: ${e.message}")
        }

        return try {
            FaceSettings.setPaused(applicationContext, false)
            FaceFollower.openForScan()
            if (contentMode != "videos") FaceFollower.start(applicationContext)

            val embeddingEngine = ScanEngineHolder.embeddingEngine(applicationContext)
            embeddingEngine.embedImages(mode, uri, folderId, contentMode) { progress ->
                if (isStopped) embeddingEngine.cancelEmbedding()
                LatestScan.flush(applicationContext)
                if (thisRun != latestRun.get()) {
                    embeddingEngine.cancelEmbedding()
                    return@embedImages
                }
                val queue = FaceFollower.queueInfo()
                val map = mapOf(
                    "id" to folderId,
                    "total" to progress.total,
                    "processed" to progress.processed,
                    "embedded" to progress.embedded,
                    "elapsedMs" to progress.elapsedMs,
                    "activeMs" to progress.activeMs,
                    "faceQueue" to queue?.first,
                    "faceQueueMs" to queue?.second,
                    "faceBatchPhotos" to FaceFollower.BATCH_PHOTOS,
                    "faceBatchMs" to FaceFollower.BATCH_MS,
                    "skipped" to progress.skipped,
                    "failed" to progress.failed,
                    "done" to progress.done,
                    "stopping" to (embeddingEngine.wasCancelled() && !progress.done),
                    "path" to progress.path,
                    "recentItems" to progress.recentItems.map {
                        mapOf(
                            "uri" to it.uri,
                            "isVideo" to it.isVideo,
                            "timestampMs" to it.timestampMs,
                            "frames" to it.frames
                        )
                    }
                )
                if (progress.done && !isStopped) LatestScan.finish(applicationContext)
                ScanForegroundService.pushProgress(map)

                val notification = ScanForegroundService.updateProgress(
                    applicationContext,
                    progress.processed,
                    progress.total,
                    progress.embedded,
                    progress.elapsedMs,
                    progress.activeMs,
                    progress.photos,
                    progress.videos,
                    progress.photosDone,
                    progress.videosDone,
                )
                ScanForegroundService.postIfActive(applicationContext, notification)
            }
            FaceFollower.closeForScan()
            FaceFollower.finish()
            if (!embeddingEngine.wasCancelled()) FaceScanWorker.enqueueIfNeeded(applicationContext)
            Result.success()
        } catch (e: Exception) {
            AppLog.e(TAG, "doWork: embedImages failed: ${e.message}", e)
            if (!isStopped) LatestScan.finish(applicationContext)
            if (thisRun == latestRun.get()) ScanForegroundService.pushProgress(
                mapOf(
                    "id" to folderId,
                    "total" to 0,
                    "processed" to 0,
                    "embedded" to 0,
                    "elapsedMs" to 0L,
                    "skipped" to 0,
                    "done" to true,
                    "path" to "",
                    "recentItems" to emptyList<Map<String, Any>>()
                )
            )
            Result.failure()
        } finally {
            FaceFollower.closeForScan()
            FaceFollower.finish()
            if (isStopped) LatestScan.flush(applicationContext) else LatestScan.finish(applicationContext)
            ScanForegroundService.onScanEnded(applicationContext)
            try { dev.raseel.lostandfound.features.settings.IndexNudge.arm(applicationContext) } catch (_: Exception) {}
        }
    }

    /**
     * Builds the foreground info with the specialUse type, not mediaProcessing. mediaProcessing is rejected at start by at
     * least one real Android 15 build this app was tested on (InvalidForegroundServiceTypeException, which WorkManager
     * does not catch, so the whole process crashes). See the manifest's comment on this service.
     */
    private fun createForegroundInfo(): ForegroundInfo {
        val notification = ScanForegroundService.initialNotification(applicationContext)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ForegroundInfo(
                ScanForegroundService.NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            ForegroundInfo(ScanForegroundService.NOTIFICATION_ID, notification)
        }
    }

    companion object {
        private const val TAG = "ScanWorker"
        const val KEY_MODE = "mode"
        const val KEY_URI = "uri"
        const val KEY_FOLDER_ID = "folderId"
        const val KEY_CONTENT_MODE = "contentMode"
        const val UNIQUE_WORK_NAME = "scan"

        private val scanMutex = Mutex()

        /** Counts the scans asked for. Only the latest one reports progress. */
        private val latestRun = java.util.concurrent.atomic.AtomicInteger(0)

        /** The number of scans running: one, or two while a replaced one winds down. */
        private val running = java.util.concurrent.atomic.AtomicInteger(0)

        /** Whether an indexing scan is running in this process. */
        fun isRunning(): Boolean = running.get() > 0

        /**
         * Runs [block] as the one indexing in this process, after any scan that is running has ended. A scan that starts
         * meanwhile asks this to stop first (see [doWork]), so the two never index at once.
         */
        suspend fun <T> exclusive(block: suspend () -> T): T = scanMutex.withLock {
            running.incrementAndGet()
            try {
                block()
            } finally {
                running.decrementAndGet()
            }
        }
    }
}
