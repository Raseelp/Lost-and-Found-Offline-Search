package dev.twentyonevision.app.embedder

data class SearchResult(
    val imagePath: String,
    val score: Float,
    val videoUri: String? = null,
    val timestampMs: Long = 0L
)