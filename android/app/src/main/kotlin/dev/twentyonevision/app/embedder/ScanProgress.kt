package dev.twentyonevision.app.embedder

data class ScanProgress(
    val total: Int,
    val processed: Int,
    val embedded: Int,
    val skipped: Int,
    val elapsedMs: Long,
    val done: Boolean,
    val path: String
)
