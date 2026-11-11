package dev.raseel.lostandfound.features.collections

import dev.raseel.lostandfound.MainActivity
import dev.raseel.lostandfound.core.native.FeatureChannel
import dev.raseel.lostandfound.features.library.ScanEngineHolder
import dev.raseel.lostandfound.features.people.FaceServices
import dev.raseel.lostandfound.features.search.EmbeddingEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel


class CollectionsChannel(activity: MainActivity) : FeatureChannel(activity) {

    private fun parseCollectionSpecs(
        call: io.flutter.plugin.common.MethodCall
    ): List<EmbeddingEngine.CollectionSpec>? {
        val raw = call.argument<List<Map<String, Any>>>("collections") ?: return null
        return raw.mapNotNull { entry ->
            val id = entry["id"] as? String ?: return@mapNotNull null
            val embedding = (entry["embedding"] as? List<*>)
                ?.map { (it as Number).toFloat() }
                ?.toFloatArray() ?: return@mapNotNull null
            val personIds = (entry["personIds"] as? List<*>)
                ?.mapNotNull { (it as? Number)?.toLong() }
                ?: emptyList()
            EmbeddingEngine.CollectionSpec(
                id = id,
                embedding = embedding,
                contentMode = entry["contentMode"] as? String ?: "both",
                k = (entry["k"] as? Number)?.toDouble() ?: 3.0,
                personIds = personIds
            )
        }
    }
    /**
     * Resolves each spec's personIds (from an "@name" search) to a pathFilter via FaceStore, with the same "together"
     * reading of several people as searchByText. Call it inside a searchExecutor.execute block: peopleMedia is a real
     * SQLite read, and parseCollectionSpecs runs synchronously on the thread the channel call arrives on.
     */
    private fun resolvePathFilters(
        specs: List<EmbeddingEngine.CollectionSpec>
    ): List<EmbeddingEngine.CollectionSpec> = specs.map { spec ->
        if (spec.personIds.isEmpty()) spec else spec.copy(
            pathFilter = faces.store.peopleMedia(spec.personIds, "together").map { it.uri }.toSet()
        )
    }
    private val embeddingEngine: EmbeddingEngine get() = ScanEngineHolder.embeddingEngine(this)
    private val faces by lazy { FaceServices.get(applicationContext) }

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {

            "scoreCollections" -> {
                val specs = parseCollectionSpecs(call)
                if (specs == null) {
                    result.error("INVALID_ARGS", "collections missing", null)
                    return true
                }
                searchExecutor.execute {
                    try {
                        val scores = embeddingEngine.scoreCollections(resolvePathFilters(specs)).map { s ->
                            mapOf(
                                "id" to s.id,
                                "count" to s.count,
                                "covers" to s.covers.map {
                                    mapOf(
                                        "path" to it.imagePath,
                                        "isVideo" to (it.videoUri != null),
                                        "timestampMs" to it.timestampMs
                                    )
                                }
                            )
                        }
                        runOnUiThread { result.success(scores) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("COLLECTIONS_FAILED", e.message, null) }
                    }
                }
            }

            "collectionMembers" -> {
                val spec = parseCollectionSpecs(call)?.firstOrNull()
                val limit = call.argument<Int>("limit") ?: 200
                if (spec == null) {
                    result.error("INVALID_ARGS", "collection missing", null)
                    return true
                }
                searchExecutor.execute {
                    try {
                        val resolvedSpec = resolvePathFilters(listOf(spec)).first()
                        val mapped = embeddingEngine.collectionMembers(resolvedSpec, limit).map {
                            mapOf(
                                "path"        to it.imagePath,
                                "score"       to it.score,
                                "isVideo"     to (it.videoUri != null),
                                "videoUri"    to (it.videoUri ?: ""),
                                "timestampMs" to it.timestampMs
                            )
                        }
                        runOnUiThread { result.success(mapped) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("COLLECTIONS_FAILED", e.message, null) }
                    }
                }
            }

            else -> return false
        }
        return true
    }
}
