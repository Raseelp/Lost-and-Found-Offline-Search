package dev.raseel.lostandfound.features.library

import dev.raseel.lostandfound.core.log.AppLog
import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore

/**
 * Lists the media in a picked folder from MediaStore instead of walking the folder. Every function returns null when
 * anything is uncertain, such as another volume, a folder under Android/, an API level below 29 or a failed query, and
 * [EmbeddingEngine] then walks the directory, so it never gets fewer files than exist.
 */
object FolderMediaStoreScan {

    private const val TAG = "FolderMediaStoreScan"

    /** RELATIVE_PATH and the per-volume queries need API 29. Older phones use the directory walk. */
    private val SUPPORTED = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    /**
     * The path of [folderUri] on the primary storage as RELATIVE_PATH writes it, such as "Pictures/Camera/". An empty
     * string means the volume root. Null when the folder is not surely on the primary storage, and for Android/data,
     * obb and media, which MediaStore lists differently across versions.
     */
    fun resolvePrimaryRelativePath(folderUri: Uri): String? {
        if (!SUPPORTED) return null
        if (folderUri.authority != "com.android.externalstorage.documents") return null

        val docId = try {
            DocumentsContract.getTreeDocumentId(folderUri)
        } catch (e: Exception) {
            AppLog.w(TAG, "resolvePrimaryRelativePath: couldn't read tree document id: ${e.message}")
            return null
        }

        val colonIndex = docId.indexOf(':')
        if (colonIndex < 0) return null
        val volumeId = docId.substring(0, colonIndex)
        if (volumeId != "primary") return null

        val relativePath = docId.substring(colonIndex + 1).trim('/')

        if (relativePath == "Android" || relativePath.startsWith("Android/")) return null

        return if (relativePath.isEmpty()) "" else "$relativePath/"
    }

    /**
     * The images under [relativePath] from [resolvePrimaryRelativePath], or null to fall back.
     *
     * It filters by the same extensions as the directory walk, so both paths find the same files. It checks the API
     * level itself so that Android Lint sees the guard next to the calls that need it.
     */
    fun queryImages(context: Context, relativePath: String): List<ImageSource>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return try {
            val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val projection = arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.SIZE,
                MediaStore.Images.Media.DATE_MODIFIED,
                MediaStore.Images.Media.DISPLAY_NAME
            )
            val (selection, args) = relativePathSelection(relativePath)

            val result = mutableListOf<ImageSource>()
            context.contentResolver.query(collection, projection, selection, args, null)?.use { c ->
                val idCol = c.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
                val sizeCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE)
                val modCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_MODIFIED)
                val nameCol = c.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)

                while (c.moveToNext()) {
                    val name = c.getString(nameCol) ?: ""
                    if (!isImageName(name)) continue
                    val id = c.getLong(idCol)
                    result.add(
                        ImageSource(
                            uri = ContentUris.withAppendedId(collection, id),
                            size = c.getLong(sizeCol),
                            lastModified = c.getLong(modCol) * 1000L,
                            name = name
                        )
                    )
                }
            }
            result
        } catch (e: Exception) {
            AppLog.w(TAG, "queryImages: failed, caller will fall back: ${e.message}")
            null
        }
    }

    /**
     * The videos under [relativePath], or null to fall back.
     *
     * Like [queryImages]. MediaStore stores the modified time in seconds, so it is converted to milliseconds, which
     * makes [HashUtils.identityHash] give a file the same hash as the directory walk does.
     */
    fun queryVideos(context: Context, relativePath: String): List<VideoSource>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return null
        return try {
            val collection = MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val projection = arrayOf(
                MediaStore.Video.Media._ID,
                MediaStore.Video.Media.SIZE,
                MediaStore.Video.Media.DATE_MODIFIED,
                MediaStore.Video.Media.DISPLAY_NAME,
                MediaStore.Video.Media.MIME_TYPE
            )
            val (selection, args) = relativePathSelection(relativePath)

            val result = mutableListOf<VideoSource>()
            context.contentResolver.query(collection, projection, selection, args, null)?.use { c ->
                val idCol = c.getColumnIndexOrThrow(MediaStore.Video.Media._ID)
                val sizeCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.SIZE)
                val modCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DATE_MODIFIED)
                val nameCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.DISPLAY_NAME)
                val mimeCol = c.getColumnIndexOrThrow(MediaStore.Video.Media.MIME_TYPE)

                while (c.moveToNext()) {
                    val mimeType = c.getString(mimeCol) ?: ""
                    if (!mimeType.startsWith("video/")) continue
                    val id = c.getLong(idCol)
                    result.add(
                        VideoSource(
                            uri = ContentUris.withAppendedId(collection, id),
                            size = c.getLong(sizeCol),
                            lastModified = c.getLong(modCol) * 1000L,
                            name = c.getString(nameCol) ?: ""
                        )
                    )
                }
            }
            result
        } catch (e: Exception) {
            AppLog.w(TAG, "queryVideos: failed, caller will fall back: ${e.message}")
            null
        }
    }

    private fun isImageName(name: String): Boolean {
        val lower = name.lowercase()
        return lower.endsWith(".jpg") || lower.endsWith(".jpeg") ||
            lower.endsWith(".png") || lower.endsWith(".webp")
    }

    /**
     * The SQL selection and arguments that match the folder and everything under it.
     *
     * It matches RELATIVE_PATH or the legacy DATA column, because RELATIVE_PATH is often NULL for older entries and a
     * LIKE on NULL matches nothing. Without a known storage root, only RELATIVE_PATH is used.
     */
    private fun relativePathSelection(relativePath: String): Pair<String?, Array<String>?> {
        if (relativePath.isEmpty()) return null to null

        val storageRoot = Environment.getExternalStorageDirectory()?.absolutePath
        val dataPrefix = if (storageRoot != null) "$storageRoot/$relativePath" else null

        return if (dataPrefix != null) {
            "(${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ? OR ${MediaStore.MediaColumns.DATA} LIKE ?)" to
                arrayOf("$relativePath%", "$dataPrefix%")
        } else {
            "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?" to arrayOf("$relativePath%")
        }
    }
}
