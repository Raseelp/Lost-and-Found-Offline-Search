package dev.twentyonevision.app.embedder.models

import dev.twentyonevision.app.BuildConfig

// sha256 must be lowercase hex. Update it (and sizeBytes) if the hosted
// model file ever changes.
data class RemoteModel(
    val id: String,
    val fileName: String,
    val url: String,
    val sha256: String,
    val sizeBytes: Long
)

object ModelCatalog {

    val MODELS: List<RemoteModel> = listOf(
        RemoteModel(
            id = "vision",
            fileName = "clip_vision_ts.pt",
            url = "${BuildConfig.MODEL_BASE_URL}/clip_vision_ts.pt",
            sha256 = "2aa36306b7da2e6bb866a61863b1aa96a79f1dc6d22285f2098ac77c2be12178",
            sizeBytes = 351463461L
        ),
        RemoteModel(
            id = "text",
            fileName = "clip_text_ts.pt",
            url = "${BuildConfig.MODEL_BASE_URL}/clip_text_ts.pt",
            sha256 = "7d06dd86e914be7910063a1a9613e4591a1cf0d8fbfb5f6648d1bef4bb04b09b",
            sizeBytes = 253829539L
        )
    )

    val totalBytes: Long get() = MODELS.sumOf { it.sizeBytes }
}
