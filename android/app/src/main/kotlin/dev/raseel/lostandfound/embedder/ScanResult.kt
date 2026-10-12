package dev.raseel.lostandfound.embedder


data class ScanResult(
    val totalImages: Int,
    val embedded: Int,
    val skipped: Int
)
