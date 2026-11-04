package dev.raseel.lostandfound.embedder

import android.content.Context
import dev.raseel.lostandfound.embedder.models.ModelManager

/**
 * Holds the one [EmbeddingEngine] and [ModelManager] of the process, not tied to any MainActivity.
 * Removing the app from Recents does not kill the process, and a scan keeps running on its engine. A call such as
 * cancelEmbedding has to reach that same instance. The scan's executor is not held here, because a quick query at
 * startup would queue behind a running scan and hang the loading spinner.
 */
object ScanEngineHolder {

    @Volatile
    private var modelManagerInstance: ModelManager? = null
    @Volatile
    private var embeddingEngineInstance: EmbeddingEngine? = null

    fun modelManager(context: Context): ModelManager =
        modelManagerInstance ?: synchronized(this) {
            modelManagerInstance ?: ModelManager(context.applicationContext).also {
                modelManagerInstance = it
            }
        }

    fun embeddingEngine(context: Context): EmbeddingEngine =
        embeddingEngineInstance ?: synchronized(this) {
            embeddingEngineInstance ?: EmbeddingEngine(
                context.applicationContext,
                modelManager(context)
            ).also { embeddingEngineInstance = it }
        }
}
