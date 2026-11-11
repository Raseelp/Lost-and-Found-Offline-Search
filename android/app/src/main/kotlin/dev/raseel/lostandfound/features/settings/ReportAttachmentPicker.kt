package dev.raseel.lostandfound.features.settings

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.plugin.common.MethodChannel

/**
 * Opens the system picker for the screenshots and screen recordings of a problem report, and answers with what the
 * person chose. Only one pick can be open at a time. The activity forwards its onActivityResult to [onResult].
 */
class ReportAttachmentPicker(private val activity: Activity) {

    private var pending: MethodChannel.Result? = null

    fun pick(result: MethodChannel.Result) {
        if (pending != null) {
            result.error("BUSY", "Picker already open", null)
            return
        }
        pending = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("image/*", "video/*"))
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        activity.startActivityForResult(intent, REQUEST)
    }

    fun onResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST) return
        val result = pending ?: return
        pending = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(emptyList<Map<String, Any>>())
            return
        }

        val uris = ArrayList<Uri>()
        data.data?.let { uris += it }
        val clip = data.clipData
        if (clip != null) for (i in 0 until clip.itemCount) clip.getItemAt(i).uri?.let { uris += it }

        result.success(uris.distinct().map { describe(it) })
    }

    private fun describe(uri: Uri): Map<String, Any> {
        try {
            activity.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        } catch (_: Exception) {
        }
        var name = "attachment"
        var size = 0L
        activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)
            ?.use {
                if (it.moveToFirst()) {
                    it.getString(0)?.let { n -> name = n }
                    if (!it.isNull(1)) size = it.getLong(1)
                }
            }
        val type = activity.contentResolver.getType(uri).orEmpty()
        return mapOf("uri" to uri.toString(), "name" to name, "size" to size, "video" to type.startsWith("video/"))
    }

    private companion object {
        const val REQUEST = 2002
    }
}
