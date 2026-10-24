package dev.raseel.lostandfound.embedder

// One file that just finished embedding - purely cosmetic, feeds the
// "recently indexed" strip in the UI.
data class RecentEmbeddedItem(
    val uri: String,
    val isVideo: Boolean,
    val timestampMs: Long,
    // For a video, how many frames were read from it (0 for a photo).
    val frames: Int = 0
)

data class ScanProgress(
    val total: Int,
    val processed: Int,
    val embedded: Int,
    val skipped: Int,
    val elapsedMs: Long,
    // elapsedMs without the time spent waiting for the face scan to work through a
    // batch of photos just indexed (see ScanHandoff) - what indexing's own speed is
    // measured over; elapsedMs (the real time) is what the time left is worked out from.
    val activeMs: Long = elapsedMs,
    val done: Boolean,
    val path: String,
    val recentItems: List<RecentEmbeddedItem> = emptyList(),
    // The subset of skipped that wasn't "already indexed" - files that
    // couldn't be decoded/embedded at all (corrupt, unsupported format, a
    // video with no readable frames). They're retried on every rescan,
    // which is why a finished library can still show a few "new" files.
    val failed: Int = 0,
    // Of [total], how many are photos and how many videos, and how many of each are done (photos are indexed
    // first, then videos). 0 when not known.
    val photos: Int = 0,
    val videos: Int = 0,
    val photosDone: Int = 0,
    val videosDone: Int = 0
)
