package dev.raseel.lostandfound.features.search

import android.media.MediaMetadataRetriever
import dev.raseel.lostandfound.MainActivity
import dev.raseel.lostandfound.core.native.FeatureChannel
import dev.raseel.lostandfound.features.library.SafPickerActivity
import dev.raseel.lostandfound.features.library.ScanEngineHolder
import dev.raseel.lostandfound.features.library.VideoFrameExtractor
import dev.raseel.lostandfound.features.model_download.ModelsNotReadyException
import dev.raseel.lostandfound.features.people.FaceServices
import dev.raseel.lostandfound.features.settings.BenchLog
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel


class SearchChannel(activity: MainActivity) : FeatureChannel(activity) {

    private val embeddingEngine: EmbeddingEngine get() = ScanEngineHolder.embeddingEngine(this)
    private val faces by lazy { FaceServices.get(applicationContext) }
    private val picker get() = (activity as MainActivity).picker

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {

            "pickImage" -> picker.pick(SafPickerActivity.MODE_IMAGE, result)

            "encodeText" -> {
                val tokens = call.argument<List<Int>>("tokens")
                if (tokens == null || tokens.size != 77) {
                    result.error("INVALID_TOKENS", "Expected 77 tokens", null)
                    return true
                }
                // The first call loads both CLIP models from disk (hundreds of MB). On the main thread this froze
                // the UI badly enough to get the app killed.
                searchExecutor.execute {
                    try {
                        val embedding = embeddingEngine.encodeText(tokens.toIntArray())
                        runOnUiThread { result.success(embedding.toList()) }
                    } catch (e: ModelsNotReadyException) {
                        runOnUiThread { result.error("MODELS_NOT_READY", e.message, null) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("ENCODE_FAILED", e.message, null) }
                    }
                }
            }

            "searchByText" -> {
                val tokens = call.argument<List<Int>>("tokens")
                val topK   = call.argument<Int>("topK") ?: 20
                val contentMode = call.argument<String>("contentMode") ?: "both"
                val personIds = (call.argument<List<*>>("personIds"))
                    ?.mapNotNull { (it as? Number)?.toLong() }
                    ?: emptyList()

                if (tokens == null || tokens.size != 77) {
                    result.error("INVALID_TOKENS", "Expected 77 tokens", null)
                    return true
                }

                searchExecutor.execute {
                    try {
                        val pathFilter = if (personIds.isEmpty()) null else
                            faces.store.peopleMedia(personIds, "together").map { it.uri }.toSet()
                        val startedNs = System.nanoTime()
                        val textEmbedding = embeddingEngine.encodeText(tokens.toIntArray())
                        val encodedNs = System.nanoTime()
                        val results = embeddingEngine.searchByText(textEmbedding, topK, contentMode, pathFilter)
                        val rankedNs = System.nanoTime()
                        // Only numbers are logged, nothing searched for and no file names, since logs can end up
                        // in a shared bug report.
                        BenchLog.log(applicationContext) {
                            "search: encode text ${(encodedNs - startedNs) / 1_000_000}ms, rank ${(rankedNs - encodedNs) / 1_000_000}ms, " +
                                "${results.size} results | top scores ${results.take(5).map { "%.3f".format(it.score) }}"
                        }

                        val mapped = results.map {
                            mapOf(
                                "path"        to it.imagePath,
                                "score"       to it.score,
                                "isVideo"     to (it.videoUri != null),
                                "videoUri"    to (it.videoUri ?: ""),
                                "timestampMs" to it.timestampMs
                            )
                        }

                        runOnUiThread { result.success(mapped) }
                    } catch (e: ModelsNotReadyException) {
                        runOnUiThread { result.error("MODELS_NOT_READY", e.message, null) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("SEARCH_FAILED", e.message, null)
                        }
                    }
                }
            }

            "searchByImage" -> {
                val uriString = call.argument<String>("uri")
                val topK      = call.argument<Int>("topK") ?: 20
                val contentMode = call.argument<String>("contentMode") ?: "both"

                if (uriString == null) {
                    result.error("NO_URI", "URI missing", null)
                    return true
                }

                searchExecutor.execute {
                    try {
                        val embedding = embeddingEngine.encodeImageFromUri(uriString)
                        val results   = embeddingEngine.searchByImageEmbedding(embedding, topK, contentMode)

                        val mapped = results.map {
                            mapOf(
                                "path"        to it.imagePath,
                                "score"       to it.score,
                                "isVideo"     to (it.videoUri != null),
                                "videoUri"    to (it.videoUri ?: ""),
                                "timestampMs" to it.timestampMs
                            )
                        }

                        runOnUiThread { result.success(mapped) }
                    } catch (e: ModelsNotReadyException) {
                        runOnUiThread { result.error("MODELS_NOT_READY", e.message, null) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("SEARCH_FAILED", e.message, null)
                        }
                    }
                }
            }

            "encodeImage" -> {
                val uriString = call.argument<String>("uri")
                val timestampMs = (call.argument<Number>("timestampMs"))?.toLong()

                if (uriString == null) {
                    result.error("NO_URI", "URI missing", null)
                    return true
                }

                searchExecutor.execute {
                    try {
                        val embedding = if (timestampMs == null) {
                            embeddingEngine.encodeImageFromUri(uriString)
                        } else {
                            val uri = android.net.Uri.parse(uriString)
                            synchronized(VideoFrameExtractor.decodeLock) {
                                val retriever = MediaMetadataRetriever()
                                try {
                                    retriever.setDataSource(this, uri)
                                    val frame = retriever.getFrameAtTime(
                                        timestampMs * 1000L,
                                        MediaMetadataRetriever.OPTION_CLOSEST
                                    ) ?: throw Exception("Frame extraction failed")
                                    try {
                                        embeddingEngine.encodeBitmap(frame)
                                    } finally {
                                        frame.recycle()
                                    }
                                } finally {
                                    try { retriever.release() } catch (_: Exception) {}
                                }
                            }
                        }
                        runOnUiThread { result.success(embedding.toList()) }
                    } catch (e: ModelsNotReadyException) {
                        runOnUiThread { result.error("MODELS_NOT_READY", e.message, null) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("ENCODE_FAILED", e.message, null) }
                    }
                }
            }

            // OPTION_CLOSEST, not the CLOSEST_SYNC of the thumbnail loader: a search must embed the frame on
            // screen, not the nearest keyframe.
            "searchByVideoFrame" -> {
                val uriString = call.argument<String>("uri")
                val timestampMs = (call.argument<Number>("timestampMs") ?: 0).toLong()
                val topK = call.argument<Int>("topK") ?: 20
                val contentMode = call.argument<String>("contentMode") ?: "both"

                if (uriString == null) {
                    result.error("NO_URI", "URI missing", null)
                    return true
                }

                searchExecutor.execute {
                    try {
                        val uri = android.net.Uri.parse(uriString)

                        val embedding = synchronized(VideoFrameExtractor.decodeLock) {
                            val retriever = MediaMetadataRetriever()
                            try {
                                retriever.setDataSource(this, uri)
                                val frame = retriever.getFrameAtTime(
                                    timestampMs * 1000L,
                                    MediaMetadataRetriever.OPTION_CLOSEST
                                ) ?: throw Exception("Frame extraction failed")
                                try {
                                    embeddingEngine.encodeBitmap(frame)
                                } finally {
                                    frame.recycle()
                                }
                            } finally {
                                try { retriever.release() } catch (_: Exception) {}
                            }
                        }

                        val results = embeddingEngine.searchByImageEmbedding(embedding, topK, contentMode)
                        val mapped = results.map {
                            mapOf(
                                "path"        to it.imagePath,
                                "score"       to it.score,
                                "isVideo"     to (it.videoUri != null),
                                "videoUri"    to (it.videoUri ?: ""),
                                "timestampMs" to it.timestampMs
                            )
                        }
                        runOnUiThread { result.success(mapped) }
                    } catch (e: ModelsNotReadyException) {
                        runOnUiThread { result.error("MODELS_NOT_READY", e.message, null) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("SEARCH_FAILED", e.message, null) }
                    }
                }
            }

            else -> return false
        }
        return true
    }
}
