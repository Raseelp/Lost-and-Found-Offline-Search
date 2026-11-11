package dev.raseel.lostandfound.features.library

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.MethodChannel

/**
 * Opens [SafPickerActivity] for a folder or a photo and hands what the person chose to the call that asked. Only one
 * pick can be open at a time. The activity that owns it forwards its onActivityResult to [onResult].
 */
class SafPicker(private val activity: Activity) {

    private var pending: MethodChannel.Result? = null

    fun pick(mode: String, result: MethodChannel.Result) {
        if (pending != null) {
            result.error("BUSY", "Picker already open", null)
            return
        }
        pending = result
        val intent = Intent(activity, SafPickerActivity::class.java).apply {
            putExtra(SafPickerActivity.EXTRA_MODE, mode)
        }
        activity.startActivityForResult(intent, REQUEST)
    }

    fun onResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQUEST) return

        val result = pending
        pending = null
        if (result == null) return

        if (resultCode != Activity.RESULT_OK || data == null) {
            result.error("CANCELLED", "Picking cancelled", null)
            return
        }

        val uri = data.getStringExtra(SafPickerActivity.EXTRA_URI)
        if (uri == null) {
            result.error("NO_URI", "No URI returned", null)
            return
        }

        result.success(uri)
    }

    private companion object {
        const val REQUEST = 2001
    }
}
