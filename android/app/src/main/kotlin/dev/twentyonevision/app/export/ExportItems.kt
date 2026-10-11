package dev.twentyonevision.app.export

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns

/** What a zip needs to know about one photo or video before it is put in. */
object ExportItems {

    /**
     * [size] is -1 when the file cannot be read at all. [takenMs] is when it was taken (0 when
     * that is not known) and [modifiedMs] when it was last changed (0 when not known).
     */
    class Info(
        val name: String,
        val size: Long,
        val takenMs: Long,
        val modifiedMs: Long,
    ) {
        val readable: Boolean get() = size >= 0

        /** The date the file carries in the zip: when it was taken, else when it was changed. */
        val dateMs: Long get() = if (takenMs > 0) takenMs else modifiedMs
    }

    fun resolve(context: Context, uriString: String): Info {
        val uri = try {
            Uri.parse(uriString)
        } catch (_: Exception) {
            return Info("file", -1, 0, 0)
        }
        val resolver = context.contentResolver
        var name: String? = null
        var size = -1L
        var taken = 0L
        var modified = 0L

        val mediaStore = uri.authority == MediaStore.AUTHORITY
        val document = !mediaStore && DocumentsContract.isDocumentUri(context, uri)
        val basic = arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val projection = when {
            mediaStore -> arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE, "datetaken", "date_modified")
            document -> arrayOf(
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            )
            else -> basic
        }
        // A provider that lacks one of the date columns fails the whole query: it is then asked
        // again for just the name and the size, so a file never loses its name over a date.
        for (columns in if (projection === basic) listOf(basic) else listOf(projection, basic)) {
            try {
                resolver.query(uri, columns, null, null, null)?.use { c ->
                    if (c.moveToFirst()) {
                        name = c.getString(0)
                        if (!c.isNull(1)) size = c.getLong(1)
                        if (columns.size > 2) {
                            when {
                                mediaStore -> {
                                    if (!c.isNull(2)) taken = c.getLong(2)
                                    if (!c.isNull(3)) modified = c.getLong(3) * 1000L
                                }
                                document -> if (!c.isNull(2)) modified = c.getLong(2)
                            }
                        }
                    }
                }
                break
            } catch (_: Exception) {
            }
        }

        if (size < 0) {
            try {
                resolver.openAssetFileDescriptor(uri, "r")?.use { size = it.length }
            } catch (_: Exception) {
            }
        }
        if (size < 0) {
            // No size anywhere, but it may still open: it is then read for what it is.
            try {
                resolver.openInputStream(uri)?.use { size = 0 }
            } catch (_: Exception) {
            }
        }
        val shown = name?.takeIf { it.isNotBlank() } ?: uri.lastPathSegment?.substringAfterLast('/') ?: "file"
        return Info(shown, size, taken, modified)
    }
}
