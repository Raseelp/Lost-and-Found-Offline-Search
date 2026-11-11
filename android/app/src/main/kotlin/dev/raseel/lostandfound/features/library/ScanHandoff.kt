package dev.raseel.lostandfound.features.library

/**
 * Where the indexing scan hands the photos it has just written to the face scan in [FaceFollower].
 *
 * The call is synchronous on purpose, so the two never compete for the CPU. What the consumer does not get to is found
 * later by the face worker.
 */
object ScanHandoff {

    fun interface Consumer {
        /** [shouldStop] turns true if the indexing scan is cancelled while this is working. */
        fun onIndexed(photos: List<IndexedImage>, shouldStop: () -> Boolean)
    }

    @Volatile
    var consumer: Consumer? = null
}
