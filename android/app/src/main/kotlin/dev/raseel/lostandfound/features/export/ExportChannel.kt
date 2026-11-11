package dev.raseel.lostandfound.features.export

import android.content.Intent
import android.os.Build
import dev.raseel.lostandfound.MainActivity
import dev.raseel.lostandfound.core.native.FeatureChannel
import dev.raseel.lostandfound.features.library.SafPickerActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel


class ExportChannel(activity: MainActivity) : FeatureChannel(activity) {

    private val picker get() = (activity as MainActivity).picker

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {

            "pickExportFolder" -> picker.pick(SafPickerActivity.MODE_EXPORT_FOLDER, result)

            "exportItemInfo" -> {
                val uris = (call.argument<List<String>>("uris") ?: emptyList())
                exportExecutor.execute {
                    try {
                        val infos = uris.map {
                            val info = dev.raseel.lostandfound.features.export.ExportItems.resolve(applicationContext, it)
                            mapOf(
                                "name" to info.name,
                                "size" to info.size,
                                "takenMs" to info.takenMs,
                                "modifiedMs" to info.modifiedMs,
                            )
                        }
                        runOnUiThread { result.success(infos) }
                    } catch (e: Throwable) {
                        runOnUiThread { result.error("EXPORT_INFO_FAILED", e.message, null) }
                    }
                }
            }

            "exportFreeSpace" -> {
                result.success(
                    try {
                        android.os.StatFs(android.os.Environment.getExternalStorageDirectory().path).availableBytes
                    } catch (e: Exception) {
                        -1L
                    }
                )
            }

            "exportDownloadsAvailable" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)

            "startZipExport" -> {
                val job = call.argument<String>("job")
                if (job == null) {
                    result.error("NO_JOB", "Job missing", null)
                    return true
                }
                exportExecutor.execute {
                    val started = try {
                        dev.raseel.lostandfound.features.export.ZipExport.start(applicationContext, job)
                    } catch (e: Throwable) {
                        null
                    }
                    runOnUiThread {
                        if (started == null) result.error("EXPORT_FAILED", "Could not start", null)
                        else result.success(started)
                    }
                }
            }

            "zipExportStatus" -> result.success(dev.raseel.lostandfound.features.export.ZipExportState.toMap())

            "cancelZipExport" -> {
                dev.raseel.lostandfound.features.export.ZipExport.cancel()
                result.success(true)
            }

            "shareZips" -> {
                val uris = (call.argument<List<String>>("uris") ?: emptyList()).map { android.net.Uri.parse(it) }
                if (uris.isEmpty()) {
                    result.success(false)
                    return true
                }
                val send = Intent(if (uris.size == 1) Intent.ACTION_SEND else Intent.ACTION_SEND_MULTIPLE).apply {
                    type = "application/zip"
                    if (uris.size == 1) putExtra(Intent.EXTRA_STREAM, uris[0])
                    else putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                startActivity(Intent.createChooser(send, "Send the zip").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                result.success(true)
            }

            "openDownloads" -> {
                try {
                    startActivity(Intent(android.app.DownloadManager.ACTION_VIEW_DOWNLOADS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                } catch (e: Exception) {
                    result.success(false)
                }
            }

            else -> return false
        }
        return true
    }
}
