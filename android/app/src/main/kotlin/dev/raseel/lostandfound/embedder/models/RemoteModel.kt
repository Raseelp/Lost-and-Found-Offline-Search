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
    /** The search models (Apple's MobileCLIP-S0): needed for searching and indexing. */
    const val SEARCH = "search"
}

object ModelCatalog {

    val MODELS: List<RemoteModel> = listOf(
        // Made by export_clip/export_mobileclip.py from Apple's 2024 MobileCLIP-S0 checkpoint (where it came from
        // and under what licence: export_clip/MOBILECLIP_SOURCE.md). Image tower fp32 (fp16 gave NaN on a real
        // phone), text tower int8.
        RemoteModel(
            id = "vision",
            fileName = "mobileclip_s0_vision.onnx",
            url = "${BuildConfig.MODEL_BASE_URL}/mobileclip_s0_vision.onnx",
            sha256 = "2404c7f922d3d64552eb9643ff5c6325dab0d3c8b0ab8b51531fc68bf62fdbdf",
            sizeBytes = 45575684L
        ),
        RemoteModel(
            id = "text",
            fileName = "mobileclip_s0_text.onnx",
            url = "${BuildConfig.MODEL_BASE_URL}/mobileclip_s0_text.onnx",
            sha256 = "6412755124a4125282cc4fc7b22ea9bdd4671ff07ca59494b1e7545b003327bd",
            sizeBytes = 58652554L
        )
    )

    val ALL: List<RemoteModel> = MODELS

    fun forGroups(groups: Collection<String>): List<RemoteModel> = ALL.filter { it.group in groups }

    val totalBytes: Long get() = MODELS.sumOf { it.sizeBytes }
}
