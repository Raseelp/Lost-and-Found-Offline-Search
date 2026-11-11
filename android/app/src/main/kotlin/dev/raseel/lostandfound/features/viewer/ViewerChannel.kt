package dev.raseel.lostandfound.features.viewer

import android.content.ContentValues
import android.content.Intent
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.exifinterface.media.ExifInterface
import dev.raseel.lostandfound.MainActivity
import dev.raseel.lostandfound.core.native.FeatureChannel
import dev.raseel.lostandfound.features.library.ScanEngineHolder
import dev.raseel.lostandfound.features.search.EmbeddingEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel


class ViewerChannel(activity: MainActivity) : FeatureChannel(activity) {

    /**
     * The bounds+EXIF half of loadMetadataByUri, split out so the handler
     * can pick this or loadVideoMetadata below by isVideo instead of one
     * branchy function trying to do both.
     */
    private fun loadImageMetadata(
        uri: android.net.Uri,
        fileName: String,
        fileSize: Long,
        mimeType: String
    ): HashMap<String, Any?> {
        var width = 0
        var height = 0

        contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFileDescriptor(pfd.fileDescriptor, null, options)
            width = options.outWidth
            height = options.outHeight
        }

        val exif = try {
            contentResolver.openFileDescriptor(uri, "r")?.use { pfd -> ExifInterface(pfd.fileDescriptor) }
        } catch (e: Exception) {
            null
        }

        return hashMapOf<String, Any?>(
            "fileName" to fileName,
            "fileSize" to fileSize,
            "mimeType" to mimeType,
            "width" to width,
            "height" to height,
            "durationMs" to 0L,
            "orientation" to (exif?.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            ) ?: 0),
            "dateTime" to (exif?.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)
                ?: exif?.getAttribute(ExifInterface.TAG_DATETIME) ?: ""),
            "cameraMake" to (exif?.getAttribute(ExifInterface.TAG_MAKE) ?: ""),
            "cameraModel" to (exif?.getAttribute(ExifInterface.TAG_MODEL) ?: ""),
            "latitude" to exif?.latLong?.getOrNull(0),
            "longitude" to exif?.latLong?.getOrNull(1)
        )
    }
    /**
     * Metadata for a video, read with MediaMetadataRetriever because a video has no EXIF or BitmapFactory bounds. The
     * camera, GPS and orientation fields are left out, since the metadata sheet hides them when empty. A corrupt or
     * unusual video shows zeros instead of failing the sheet.
     */
    private fun loadVideoMetadata(
        uri: android.net.Uri,
        fileName: String,
        fileSize: Long,
        mimeType: String
    ): HashMap<String, Any?> {
        var width = 0
        var height = 0
        var durationMs = 0L

        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(this, uri)
            width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0
            durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
        } catch (e: Exception) {
        } finally {
            try { retriever.release() } catch (e: Exception) {}
        }

        return hashMapOf<String, Any?>(
            "fileName" to fileName,
            "fileSize" to fileSize,
            "mimeType" to mimeType,
            "width" to width,
            "height" to height,
            "durationMs" to durationMs,
            "orientation" to 0,
            "dateTime" to "",
            "cameraMake" to "",
            "cameraModel" to "",
            "latitude" to null,
            "longitude" to null
        )
    }
    /**
     * Copies the source content straight into a MediaStore entry instead of writing to a raw file path, the only way
     * that works on every supported Android version without WRITE_EXTERNAL_STORAGE on scoped-storage phones.
     * IS_PENDING brackets the copy on API 29 and up, so the gallery never sees a half-written file.
     */
    private fun saveCopyToGallery(uri: android.net.Uri, isVideo: Boolean) {
        val mimeType = contentResolver.getType(uri) ?: if (isVideo) "video/mp4" else "image/jpeg"
        val extension = if (isVideo) "mp4" else "jpg"
        val fileName = "LostFound_${System.currentTimeMillis()}.$extension"

        val collection = if (isVideo) {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }

        val destUri = contentResolver.insert(collection, values)
            ?: throw Exception("Could not create a destination entry in the gallery")

        contentResolver.openInputStream(uri)?.use { input ->
            contentResolver.openOutputStream(destUri)?.use { output ->
                input.copyTo(output)
            } ?: throw Exception("Could not open the destination for writing")
        } ?: throw Exception("Could not open the source file")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            contentResolver.update(
                destUri,
                ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                null,
                null
            )
        }
    }
    private val embeddingEngine: EmbeddingEngine get() = ScanEngineHolder.embeddingEngine(this)

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {

            "explainMatch" -> {
                val path = call.argument<String>("path")
                val isVideo = call.argument<Boolean>("isVideo") ?: false
                val timestampMs = (call.argument<Number>("timestampMs") ?: 0).toLong()
                @Suppress("UNCHECKED_CAST")
                val wordsArg = call.argument<List<Map<String, Any>>>("words")

                if (path == null || wordsArg == null) {
                    result.error("INVALID_ARGS", "path/words missing", null)
                    return true
                }

                searchExecutor.execute {
                    try {
                        val itemEmbedding = embeddingEngine.findEmbedding(
                            imagePath = path,
                            videoUri = if (isVideo) path else null,
                            timestampMs = timestampMs
                        )
                        if (itemEmbedding == null) {
                            runOnUiThread { result.success(emptyList<Map<String, Any>>()) }
                            return@execute
                        }

                        val words = wordsArg.mapNotNull { entry ->
                            val word = entry["word"] as? String ?: return@mapNotNull null
                            @Suppress("UNCHECKED_CAST")
                            val tokens = (entry["tokens"] as? List<Int>)?.toIntArray()
                                ?: return@mapNotNull null
                            if (tokens.size != 77) return@mapNotNull null
                            word to tokens
                        }

                        val scored = embeddingEngine.scoreWordsAgainstItem(itemEmbedding, words)
                        val mapped = scored.map { (word, score) ->
                            mapOf("word" to word, "score" to score)
                        }

                        runOnUiThread { result.success(mapped) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("EXPLAIN_FAILED", e.message, null) }
                    }
                }
            }

            "loadMetadataByUri" -> {
                val uriString = call.argument<String>("uri")
                val isVideo = call.argument<Boolean>("isVideo") ?: false

                if (uriString == null) {
                    result.error("NO_URI", "URI missing", null)
                    return true
                }

                searchExecutor.execute {
                    try {
                        val uri = android.net.Uri.parse(uriString)

                        var fileName = ""
                        var fileSize = 0L

                        contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                            if (cursor.moveToFirst()) {
                                val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                                val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                                if (nameIndex >= 0) fileName = cursor.getString(nameIndex) ?: ""
                                if (sizeIndex >= 0) fileSize = cursor.getLong(sizeIndex)
                            }
                        }

                        val mimeType = contentResolver.getType(uri) ?: ""

                        val metadata = if (isVideo) {
                            loadVideoMetadata(uri, fileName, fileSize, mimeType)
                        } else {
                            loadImageMetadata(uri, fileName, fileSize, mimeType)
                        }
                        // Both keys hold the same string: "uri" identifies the file to other native calls, and
                        // "imagePath" is what ImageMetadata.fromMap reads for the "File path" row.
                        metadata["uri"] = uriString
                        metadata["imagePath"] = uriString

                        runOnUiThread { result.success(metadata) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("LOAD_METADATA_FAILED", e.message ?: "Invalid URI", null)
                        }
                    }
                }
            }

            "shareFile" -> {
                val uriString = call.argument<String>("uri")
                val isVideo = call.argument<Boolean>("isVideo") ?: false
                if (uriString == null) {
                    result.error("NO_URI", "URI missing", null)
                    return true
                }
                try {
                    val uri = android.net.Uri.parse(uriString)
                    val mimeType = contentResolver.getType(uri) ?: if (isVideo) "video/*" else "image/*"
                    val shareIntent = Intent(Intent.ACTION_SEND).apply {
                        type = mimeType
                        putExtra(Intent.EXTRA_STREAM, uri)
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(Intent.createChooser(shareIntent, null).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    })
                    result.success(true)
                } catch (e: Exception) {
                    result.error("SHARE_FAILED", e.message, null)
                }
            }

            "saveCopyToGallery" -> {
                val uriString = call.argument<String>("uri")
                val isVideo = call.argument<Boolean>("isVideo") ?: false
                if (uriString == null) {
                    result.error("NO_URI", "URI missing", null)
                    return true
                }
                searchExecutor.execute {
                    try {
                        saveCopyToGallery(android.net.Uri.parse(uriString), isVideo)
                        runOnUiThread { result.success(true) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("SAVE_FAILED", e.message, null) }
                    }
                }
            }

            "setAsWallpaper" -> {
                val uriString = call.argument<String>("uri")
                if (uriString == null) {
                    result.error("NO_URI", "URI missing", null)
                    return true
                }
                searchExecutor.execute {
                    try {
                        val uri = android.net.Uri.parse(uriString)
                        contentResolver.openInputStream(uri)?.use { input ->
                            android.app.WallpaperManager.getInstance(applicationContext)
                                .setStream(input)
                        } ?: throw Exception("Cannot open image")
                        runOnUiThread { result.success(true) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("WALLPAPER_FAILED", e.message, null) }
                    }
                }
            }

            "copyImageToClipboard" -> {
                val uriString = call.argument<String>("uri")
                if (uriString == null) {
                    result.error("NO_URI", "URI missing", null)
                    return true
                }
                try {
                    val uri = android.net.Uri.parse(uriString)
                    val clipboard = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
                    clipboard.setPrimaryClip(
                        android.content.ClipData.newUri(contentResolver, "Image", uri)
                    )
                    result.success(true)
                } catch (e: Exception) {
                    result.error("CLIPBOARD_FAILED", e.message, null)
                }
            }

            else -> return false
        }
        return true
    }
}
