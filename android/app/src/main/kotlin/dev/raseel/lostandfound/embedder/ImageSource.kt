package dev.raseel.lostandfound.embedder

import android.net.Uri

data class ImageSource(
    val uri: Uri,
    val size: Long,
    val lastModified: Long,
    val name: String
)
