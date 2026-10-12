package dev.raseel.lostandfound.embedder

/** One photo in the search index: its content hash and where to read it. */
data class IndexedImage(val hash: Long, val uri: String)

/** One video in the search index: its content hash and where to read it. */
data class IndexedVideo(val hash: Long, val uri: String)
