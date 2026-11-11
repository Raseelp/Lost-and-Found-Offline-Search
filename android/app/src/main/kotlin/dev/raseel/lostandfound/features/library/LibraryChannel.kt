package dev.raseel.lostandfound.features.library

import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf
import dev.raseel.lostandfound.MainActivity
import dev.raseel.lostandfound.core.native.FeatureChannel
import dev.raseel.lostandfound.features.model_download.ModelManager
import dev.raseel.lostandfound.features.search.EmbeddingEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel


class LibraryChannel(activity: MainActivity) : FeatureChannel(activity) {

    private val modelManager: ModelManager get() = ScanEngineHolder.modelManager(this)
    private val embeddingEngine: EmbeddingEngine get() = ScanEngineHolder.embeddingEngine(this)
    private val picker get() = (activity as MainActivity).picker

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {

            "pickFolder" -> picker.pick(SafPickerActivity.MODE_FOLDER, result)

            "scanImagesAndOrVideos" -> {
                val mode        = call.argument<String>("mode") ?: "folder"
                val uri         = call.argument<String>("uri")
                val folderId    = call.argument<String>("folderId") ?: "default"
                val contentMode = call.argument<String>("contentMode") ?: "both"

                executor.execute {
                    if (!modelManager.areModelsReady()) {
                        runOnUiThread {
                            result.error(
                                "MODELS_NOT_READY",
                                "CLIP models are not downloaded yet",
                                null
                            )
                        }
                        return@execute
                    }

                    val request = OneTimeWorkRequestBuilder<ScanWorker>()
                        .setInputData(
                            workDataOf(
                                ScanWorker.KEY_MODE to mode,
                                ScanWorker.KEY_URI to (uri ?: ""),
                                ScanWorker.KEY_FOLDER_ID to folderId,
                                ScanWorker.KEY_CONTENT_MODE to contentMode
                            )
                        )
                        .build()

                    WorkManager.getInstance(applicationContext).enqueueUniqueWork(
                        ScanWorker.UNIQUE_WORK_NAME,
                        ExistingWorkPolicy.REPLACE,
                        request
                    )

                    runOnUiThread { result.success(true) }
                }
            }

            "getEmbeddingCount" -> {
                result.success(embeddingEngine.getStoredCount())
            }

            "getEmbeddingCountForFolder" -> {
                val folderId = call.argument<String>("folderId")
                if (folderId == null) {
                    result.error("NO_FOLDERID", "folderId missing", null)
                    return true
                }
                result.success(embeddingEngine.getStoredCountForFolder(folderId))
            }

            "getLibraryStats" -> {
                searchExecutor.execute {
                    val stats = embeddingEngine.getLibraryStats()
                    runOnUiThread {
                        result.success(
                            mapOf(
                                "totalEmbeddings" to stats.totalEmbeddings,
                                "images" to stats.images,
                                "videos" to stats.videos,
                                "sizeBytes" to stats.sizeBytes,
                                "modelResetFrom" to stats.modelResetFrom
                            )
                        )
                    }
                }
            }

            "clearEmbeddings" -> {
                embeddingEngine.clearAll()
                result.success(true)
            }

            "deleteEmbeddingsByFolderId" -> {
                val folderId = call.argument<String>("folderId")

                if (folderId == null) {
                    result.error("NO_FOLDERID", "folderId missing", null)
                    return true
                }

                executor.execute {
                    try {
                        embeddingEngine.deleteEmbeddingsForFolder(folderId)
                        runOnUiThread { result.success(true) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("DELETION_FAILED", e.message, null)
                        }
                    }
                }
            }

            "cancelEmbedding" -> {
                embeddingEngine.cancelEmbedding()
                result.success(true)
            }

            "takeLatestScan" -> {
                faceCropExecutor.execute {
                    val items = try {
                        dev.raseel.lostandfound.features.library.LatestScan.take(applicationContext)
                    } catch (e: Throwable) {
                        emptyList()
                    }
                    runOnUiThread { result.success(items) }
                }
            }

            // No battery-optimization exemption is requested: Play policy allows it only for a short list of core
            // uses, and WorkManager restarts a killed scan.
            "getActiveScanProgress" -> {
                // A running scan that has not reported yet (WorkManager restarts one after a kill) shows as
                // starting. "stopping" is read live: no tick comes after Stop.
                result.success(
                    ScanForegroundService.activeProgress()
                        ?.plus("stopping" to embeddingEngine.wasCancelled())
                        ?: if (ScanForegroundService.isScanActive) mapOf(
                            "id" to "",
                            "total" to 0,
                            "processed" to 0,
                            "embedded" to 0,
                            "elapsedMs" to 0L,
                            "skipped" to 0,
                            "done" to false,
                            "path" to "",
                            "recentItems" to emptyList<Map<String, Any>>(),
                        ) else null
                )
            }

            else -> return false
        }
        return true
    }

    override fun registerStreams(messenger: BinaryMessenger) {
        EventChannel(messenger, "lostandfound/progress").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                ScanForegroundService.setProgressSink(events)
            }

            override fun onCancel(arguments: Any?) {
                ScanForegroundService.setProgressSink(null)
            }
        })
    }
}
