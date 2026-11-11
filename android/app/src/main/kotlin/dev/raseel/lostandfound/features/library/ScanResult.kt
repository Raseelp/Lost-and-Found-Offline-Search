package dev.raseel.lostandfound.features.library


data class ScanResult(
    val totalImages: Int,
    val embedded: Int,
    val skipped: Int
)
