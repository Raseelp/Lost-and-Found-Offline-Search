package dev.twentyonevision.app.export

import android.content.Context
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.io.File
import org.json.JSONObject

/** Where the zips go. [treeUri] is a folder the user picked; null means the Downloads folder. */
class ZipDestination(val treeUri: String?)

/** One photo or video to put in a zip. */
class ZipItem(val uri: String, val isVideo: Boolean)

/** One album: its items go in a folder of its name, images and videos in their own subfolders. */
class ZipAlbum(val name: String, val kind: String, val items: List<ZipItem>)

/** What the app asks for. */
class ZipJob(
    val zipName: String,
    /** Largest size of one zip file in bytes; 0 for one file whatever its size. */
    val partLimitBytes: Long,
    val includeList: Boolean,
    val destination: ZipDestination,
    val albums: List<ZipAlbum>,
) {
    companion object {
        fun fromJson(text: String): ZipJob {
            val json = JSONObject(text)
            val albums = json.getJSONArray("albums")
            val destination = json.optJSONObject("destination")
            return ZipJob(
                zipName = json.optString("zipName", "Vector export"),
                partLimitBytes = json.optLong("partLimitBytes", 0L),
                includeList = json.optBoolean("includeList", true),
                destination = ZipDestination(destination?.optString("treeUri")?.takeIf { it.isNotEmpty() }),
                albums = List(albums.length()) { i ->
                    val album = albums.getJSONObject(i)
                    val items = album.getJSONArray("items")
                    ZipAlbum(
                        name = album.optString("name", "Album"),
                        kind = album.optString("kind", "collection"),
                        items = List(items.length()) { k ->
                            val item = items.getJSONObject(k)
                            ZipItem(item.getString("uri"), item.optBoolean("isVideo", false))
                        },
                    )
                },
            )
        }
    }
}

/** A zip file that has been made. */
class ZipResult(val name: String, val uri: String, val bytes: Long)

/**
 * What the export is doing, for the app to look at (it asks every so often; a freshly started app
 * asks too, so it finds an export that carried on without it).
 */
object ZipExportState {
    const val IDLE = "idle"
    const val PREPARING = "preparing"
    const val WRITING = "writing"
    const val DONE = "done"
    const val FAILED = "failed"
    const val CANCELLED = "cancelled"

    @Volatile var phase = IDLE
    @Volatile var filesTotal = 0
    @Volatile var filesDone = 0
    @Volatile var bytesTotal = 0L
    @Volatile var bytesDone = 0L
    @Volatile var partsTotal = 0
    @Volatile var part = 0
    @Volatile var skipped = 0
    @Volatile var currentName = ""
    @Volatile var error = ""
    @Volatile var results: List<ZipResult> = emptyList()
    @Volatile var cancelRequested = false

    /** A unique number for this export, so the app can tell one from the next. */
    @Volatile var id = 0

    fun reset() {
        phase = PREPARING
        filesTotal = 0
        filesDone = 0
        bytesTotal = 0L
        bytesDone = 0L
        partsTotal = 0
        part = 0
        skipped = 0
        currentName = ""
        error = ""
        results = emptyList()
        cancelRequested = false
        id++
    }

    val running: Boolean get() = phase == PREPARING || phase == WRITING

    fun toMap(): Map<String, Any?> = mapOf(
        "id" to id,
        "phase" to phase,
        "filesTotal" to filesTotal,
        "filesDone" to filesDone,
        "bytesTotal" to bytesTotal,
        "bytesDone" to bytesDone,
        "partsTotal" to partsTotal,
        "part" to part,
        "skipped" to skipped,
        "currentName" to currentName,
        "error" to error,
        "results" to results.map { mapOf("name" to it.name, "uri" to it.uri, "bytes" to it.bytes) },
    )
}

object ZipExport {
    const val JOB_FILE = "zip_export_job.json"
    const val UNIQUE_WORK_NAME = "zip_export"

    /** Starts making the zip described by [jobJson]; false when one is already being made. */
    @Synchronized
    fun start(context: Context, jobJson: String): Boolean {
        if (ZipExportState.running) return false
        File(context.filesDir, JOB_FILE).writeText(jobJson)
        ZipExportState.reset()
        val request = OneTimeWorkRequestBuilder<ZipExportWorker>().build()
        WorkManager.getInstance(context.applicationContext)
            .enqueueUniqueWork(UNIQUE_WORK_NAME, ExistingWorkPolicy.REPLACE, request)
        return true
    }

    fun cancel() {
        if (ZipExportState.running) ZipExportState.cancelRequested = true
    }
}
