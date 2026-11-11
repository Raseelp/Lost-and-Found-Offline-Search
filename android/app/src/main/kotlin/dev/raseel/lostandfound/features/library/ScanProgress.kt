package dev.raseel.lostandfound.features.library

/** One file that just finished embedding. It feeds the recently indexed strip in the UI. */
data class RecentEmbeddedItem(
    val uri: String,
    val isVideo: Boolean,
    val timestampMs: Long,
    /** For a video, how many frames were read from it. 0 for a photo. */
    val frames: Int = 0
)

data class ScanProgress(
    val total: Int,
    val processed: Int,
    val embedded: Int,
    val skipped: Int,
    val elapsedMs: Long,
    /**
     * [elapsedMs] without the time spent waiting for the face scan to work through a batch just indexed (see
     * ScanHandoff). Indexing's own speed is measured over this, and the time left is worked out from [elapsedMs].
     */
    val activeMs: Long = elapsedMs,
    val done: Boolean,
    val path: String,
    val recentItems: List<RecentEmbeddedItem> = emptyList(),
    /**
     * The part of [skipped] that was not already indexed: files that could not be decoded or embedded at all, such as
     * corrupt or unsupported files and videos with no readable frames. They are retried on every rescan, so a finished
     * library can still show a few of them.
     */
    val failed: Int = 0,
    /** Of [total], how many are photos and how many videos, and how many of each are done. Photos are indexed first, then videos. 0 when not known. */
    val photos: Int = 0,
    val videos: Int = 0,
    val photosDone: Int = 0,
    val videosDone: Int = 0
)
