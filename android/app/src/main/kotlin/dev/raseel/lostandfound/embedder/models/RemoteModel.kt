package dev.raseel.lostandfound.embedder.models

import dev.raseel.lostandfound.BuildConfig

// sha256 must be lowercase hex. Update it (and sizeBytes) if the hosted
// model file ever changes.
data class RemoteModel(
    val id: String,
    val fileName: String,
    val url: String,
    val sha256: String,
    val sizeBytes: Long,
    // What the model is for - see ModelGroup.
    val group: String = ModelGroup.SEARCH
)

object ModelGroup {
    /** The search models (Apple's MobileCLIP-S2): needed for searching and indexing. */
    const val SEARCH = "search"
}

object ModelCatalog {

    val MODELS: List<RemoteModel> = listOf(
        // Made by export_clip/export_mobileclip_s2.py from Apple's 2024 MobileCLIP-S2 checkpoint (where it came from
        // and under what licence: export_clip/MOBILECLIP_S2_SOURCE.md). Image tower fp16, text tower int8.
        RemoteModel(
            id = "vision",
            fileName = "mobileclip_s2_vision.onnx",
            url = "${BuildConfig.MODEL_BASE_URL}/mobileclip_s2_vision.onnx",
            sha256 = "faa31ef2a619b049bbd87a3c6a4e8d94894ed2a6fa93b7d18beb1ddcbb8c5d7b",
            sizeBytes = 71792146L
        ),
        RemoteModel(
            id = "text",
            fileName = "mobileclip_s2_text.onnx",
            url = "${BuildConfig.MODEL_BASE_URL}/mobileclip_s2_text.onnx",
            sha256 = "bfc216d9913df1c19b4b8929b2eeabf3b4475967b287e121074757a672039919",
            sizeBytes = 67475592L
        )
    )

    val ALL: List<RemoteModel> = MODELS

    fun forGroups(groups: Collection<String>): List<RemoteModel> = ALL.filter { it.group in groups }

    val totalBytes: Long get() = MODELS.sumOf { it.sizeBytes }
}
