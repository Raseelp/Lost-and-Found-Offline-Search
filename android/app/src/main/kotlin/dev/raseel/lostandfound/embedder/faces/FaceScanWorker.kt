package dev.raseel.lostandfound.embedder.faces

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import dev.raseel.lostandfound.MainActivity
import dev.raseel.lostandfound.embedder.ScanNotification
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Runs [FaceScanner] as WorkManager work - the same reasoning as the indexing
 * scan: it is resumable (finished photos are skipped), so if the system stops
 * this process the work simply starts again and carries on.
 */
class FaceScanWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        FaceScanHub.running = true
        notificationDismissed = false
        createChannelIfNeeded()

        try {
            setForeground(foregroundInfo(buildNotification(0, 0, paused = false)))
        } catch (e: Exception) {
            // Losing the keep-alive isn't worth failing the work over.
            Log.w(TAG, "setForeground failed, continuing anyway: ${e.message}")
        }

        return try {
            val services = FaceServices.get(applicationContext)
            var lastNotified = 0L
            withContext(Dispatchers.IO) {
                services.scanner.run(shouldStop = { isStopped }) { status ->
                    val now = System.currentTimeMillis()
                    if (now - lastNotified < NOTIFY_INTERVAL_MS && status["done"] != true) return@run
                    lastNotified = now
                    if (isStopped || notificationDismissed) return@run
                    val processed = (status["processed"] as? Int) ?: 0
                    val total = (status["total"] as? Int) ?: 0
                    val paused = status["paused"] == true
                    val phase = status["phase"] as? String ?: "scan"
                    synchronized(notifyLock) {
                        if (ended) return@run
                        try {
                            NotificationManagerCompat.from(applicationContext)
                                .notify(NOTIFICATION_ID, buildNotification(processed, total, paused, phase))
                        } catch (_: Exception) {
                            // Notification permission revoked - fine.
                        }
                    }
                }
            }
            Result.success()
        } catch (e: CancellationException) {
            // Stopped on purpose (the user paused, or the model changed) - not an error.
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "face scan failed: ${e.message}", e)
            FaceScanHub.publish(
                mapOf(
                    "running" to false, "paused" to false, "done" to true,
                    "processed" to 0, "total" to 0, "faces" to 0, "people" to 0,
                    "failed" to 0, "runProcessed" to 0, "elapsedMs" to 0L,
                    "error" to (e.message ?: "failed"),
                )
            )
            Result.failure()
        } finally {
            FaceScanHub.running = false
            // WorkManager takes the notification down as soon as the work is stopped,
            // which can be before the last status tick has been posted - that would
            // bring it back as an ongoing notification nothing would ever remove. So
            // nothing is posted after this, and it is taken down here, after the last post.
            synchronized(notifyLock) {
                ended = true
                try {
                    NotificationManagerCompat.from(applicationContext).cancel(NOTIFICATION_ID)
                } catch (_: Exception) {
                }
            }
        }
    }

    private val notifyLock = Any()
    private var ended = false

    // How fast the photos (or videos) are gone through, starting over on each new phase.
    private val rate = ScanNotification.Rate()
    private var ratePhase: String? = null

    private fun foregroundInfo(notification: Notification): ForegroundInfo =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ForegroundInfo(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }

    private fun buildNotification(processed: Int, total: Int, paused: Boolean, phase: String = "scan"): Notification {
        val counting = !paused && phase != "tune" && total > 0
        if (!counting || phase != ratePhase) rate.reset()
        ratePhase = if (counting) phase else null
        val speed = if (counting) {
            val perSecond = rate.add(SystemClock.elapsedRealtime(), processed)
            if (phase == "videos") ScanNotification.speed(perSecond, "video", "videos")
            else ScanNotification.speed(perSecond, "photo", "photos")
        } else {
            null
        }
        // The face scan on its own (no indexing in it): only the faces, with what they are being found in.
        val faces = when {
            paused -> ScanNotification.Faces(
                processed, total, "Finding faces", "Waits until indexing is done", null, waiting = true,
            )
            phase == "tune" -> ScanNotification.Faces(
                processed, total, "Getting face search ready", "One time, for this phone", null, waiting = true,
            )
            total <= 0 -> ScanNotification.Faces(
                processed, total, "Finding faces", "Getting the photos ready", null, waiting = true,
            )
            phase == "refine" -> ScanNotification.Faces(
                processed, total, "Finding faces", "Looking closer at small faces", null, waiting = false, speed,
            )
            phase == "videos" -> ScanNotification.Faces(
                processed, total, "Finding faces in videos", "Looking for faces in your videos", null, waiting = false,
                speed,
            )
            else -> ScanNotification.Faces(
                processed, total, "Finding faces", "Catching up on photos with no faces found yet", null, waiting = false,
                speed,
            )
        }
        // A tap opens the app on the Library tab, where the scan is.
        val intent = Intent(applicationContext, MainActivity::class.java).apply {
            action = MainActivity.ACTION_OPEN_LIBRARY
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pending = PendingIntent.getActivity(
            applicationContext, 1, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return ScanNotification.build(
            applicationContext,
            CHANNEL_ID,
            indexing = null,
            faces = faces,
            contentIntent = pending,
            deleteIntent = dev.raseel.lostandfound.embedder.NotificationDismissReceiver.pending(
                applicationContext,
                dev.raseel.lostandfound.embedder.NotificationDismissReceiver.WHICH_FACES,
            ),
        )
    }

    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = applicationContext.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Face grouping", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shows progress while Lost & Found finds and groups the people in your photos."
                setShowBadge(false)
            }
        )
    }

    companion object {
        private const val TAG = "FaceScanWorker"
        const val CHANNEL_ID = "face_progress"
        const val NOTIFICATION_ID = 4202
        const val UNIQUE_WORK_NAME = "face_scan"
        private const val NOTIFY_INTERVAL_MS = 2000L

        // The user swiped the face scan's notification away: not posted again this run.
        @Volatile
        var notificationDismissed: Boolean = false

        /**
         * Starts the face scan if there is something for it to do and it isn't
         * already running (unique work, so calling this often is harmless).
         * Returns whether work was started or is already running.
         */
        fun enqueueIfNeeded(context: Context): Boolean {
            return try {
                val app = context.applicationContext
                if (!FaceScanHub.running && !FaceServices.get(app).scanner.hasWork()) return false
                WorkManager.getInstance(app).enqueueUniqueWork(
                    UNIQUE_WORK_NAME,
                    ExistingWorkPolicy.KEEP,
                    OneTimeWorkRequestBuilder<FaceScanWorker>().build(),
                )
                true
            } catch (e: Exception) {
                Log.w(TAG, "could not start the face scan: ${e.message}")
                false
            }
        }
    }
}
