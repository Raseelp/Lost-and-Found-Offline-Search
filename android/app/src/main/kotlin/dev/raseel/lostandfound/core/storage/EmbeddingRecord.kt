package dev.raseel.lostandfound.core.storage

data class EmbeddingRecord(
    val imagePath: String,
    val hash: Long,
    val embedding: FloatArray,
    val folderId: String,
    val videoUri: String? = null,
    val timestampMs: Long = 0L
)