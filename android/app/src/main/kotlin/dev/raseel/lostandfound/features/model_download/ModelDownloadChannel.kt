package dev.raseel.lostandfound.features.model_download

import dev.raseel.lostandfound.MainActivity
import dev.raseel.lostandfound.core.native.FeatureChannel
import dev.raseel.lostandfound.features.library.ScanEngineHolder
import dev.raseel.lostandfound.features.library.ScanForegroundService
import dev.raseel.lostandfound.features.people.faceTask
import dev.raseel.lostandfound.features.search.EmbeddingEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel


class ModelDownloadChannel(activity: MainActivity) : FeatureChannel(activity) {

    /**
     * The sink of the model download progress. A model download is not kept alive by a foreground service, so unlike
     * the scan progress sink on ScanForegroundService it cannot outlive this Activity.
     */
    private var modelDownloadSink: EventChannel.EventSink? = null
    private val modelManager: ModelManager get() = ScanEngineHolder.modelManager(this)
    private val embeddingEngine: EmbeddingEngine get() = ScanEngineHolder.embeddingEngine(this)

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {

            "areModelsReady" -> {
                executor.execute {
                    val ready = modelManager.areModelsReady()
                    runOnUiThread { result.success(ready) }
                }
            }

            "getModelInfo" -> {
                executor.execute {
                    val statuses = modelManager.getModelStatuses().map {
                        mapOf(
                            "id"         to it.id,
                            "fileName"   to it.fileName,
                            "sizeBytes"  to it.sizeBytes,
                            "downloaded" to it.downloaded,
                            "verified"   to it.verified,
                            "group"      to it.group
                        )
                    }
                    runOnUiThread { result.success(statuses) }
                }
            }

            "downloadModels" -> {
                val requested = ModelCatalog.MODELS
                executor.execute {
                    if (requested.all { modelManager.isModelVerified(it) }) {
                        runOnUiThread { result.success(true) }
                        return@execute
                    }
                    if (!modelManager.hasEnoughFreeSpace(requested)) {
                        runOnUiThread {
                            result.error(
                                "INSUFFICIENT_STORAGE",
                                "Not enough free space to download the models",
                                null
                            )
                        }
                        return@execute
                    }

                    downloadExecutor.execute {
                        try {
                            modelManager.download(requested) { progress ->
                                runOnUiThread {
                                    modelDownloadSink?.success(
                                        mapOf(
                                            "modelId"                to progress.modelId,
                                            "modelFileName"          to progress.modelFileName,
                                            "bytesForModel"          to progress.bytesForModel,
                                            "totalBytesForModel"     to progress.totalBytesForModel,
                                            "overallBytesDownloaded" to progress.overallBytesDownloaded,
                                            "overallTotalBytes"      to progress.overallTotalBytes,
                                            "done"                   to progress.done
                                        )
                                    )
                                }
                            }
                            runOnUiThread {
                                result.success(requested.all { modelManager.isModelVerified(it) })
                            }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("DOWNLOAD_FAILED", e.message, null)
                            }
                        }
                    }
                }
            }

            "cancelModelDownload" -> {
                modelManager.cancelDownload()
                result.success(true)
            }

            "deleteModels" -> faceTask(result) {
                modelManager.deleteModels()
                true
            }

            "acknowledgeModelReset" -> {
                embeddingEngine.clearModelReset()
                result.success(true)
            }

            else -> return false
        }
        return true
    }

    override fun registerStreams(messenger: BinaryMessenger) {
        EventChannel(messenger, "lostandfound/modelDownload").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                modelDownloadSink = events
            }

            override fun onCancel(arguments: Any?) {
                modelDownloadSink = null
            }
        })
    }
}
