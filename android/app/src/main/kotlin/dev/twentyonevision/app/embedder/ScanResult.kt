package dev.twentyonevision.app.embedder


data class ScanResult(
    val totalImages: Int,
    val embedded: Int,
    val skipped: Int
)
