package dev.raseel.lostandfound.features.library

import android.net.Uri

data class VideoSource(
    val uri: Uri,
    val size: Long,
    val lastModified: Long,
    val name: String
)