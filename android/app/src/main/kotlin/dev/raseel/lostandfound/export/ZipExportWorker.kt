package dev.raseel.lostandfound.export

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.MediaStore
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.documentfile.provider.DocumentFile
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import dev.raseel.lostandfound.MainActivity
import java.io.BufferedOutputStream
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject

/**
 * Makes the zip (or zips) of a [ZipJob] as background work with a notification, so it carries on
 * when the app is left. Nothing is compressed and nothing is changed or removed on the phone: the
 * files are only read. If it is cancelled, or fails, whatever it had made is deleted again.
 *
 * Every album gets a folder of its name in the zip, with an Images and a Videos folder in it
 * (only the ones that have something in them), and each zip has a list.json describing what is in
 * it (when the job asked for one). The zips of a job are planned before the first is written, so
 * their names can say how many there are, and no file is ever cut across two of them.
 */
class ZipExportWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    private class Cancelled : RuntimeException()

    // One file to go in, and where.
    private class Planned(
        val album: ZipAlbum,
        val item: ZipItem,
        val info: ExportItems.Info,
        val folder: String,
        val name: String,
    ) {
        val path: String get() = "$folder/$name"
    }

    private class Output(
        val stream: OutputStream,
        val uri: Uri,
        val shownName: String,
        val finish: () -> Unit,
        val delete: () -> Unit,
    )

    // What the list.json says about one file.
    private class Listed(val planned: Planned, val size: Long, val incomplete: Boolean)

    // A stream that reports a failed read as the end of the file, so a file that goes bad half
    // way still makes a valid (if short) entry, and the zip is not left half written.
    private class ForgivingStream(private val inner: InputStream) : InputStream() {
        var failed = false
        override fun read(): Int = try {
            inner.read()
        } catch (_: IOException) {
            failed = true
            -1
        }

        override fun read(b: ByteArray, off: Int, len: Int): Int = try {
            inner.read(b, off, len)
        } catch (_: IOException) {
            failed = true
            -1
        }

        override fun close() = inner.close()
    }

    private val state = ZipExportState
    private val created = ArrayList<Output>()
    private var lastNotified = 0L

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) { run() }

    private suspend fun run(): Result {
        val context = applicationContext
        try {
            setForeground(foregroundInfo("Getting your zip ready", 0, true))
        } catch (e: Exception) {
            Log.w(TAG, "setForeground failed, going on anyway: ${e.message}")
        }
        val wake = (context.getSystemService(Context.POWER_SERVICE) as? PowerManager)
            ?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "lostandfound:zipExport")
            ?.apply { acquire(WAKE_LOCK_MS) }
        val jobFile = File(context.filesDir, ZipExport.JOB_FILE)
        try {
            val job = ZipJob.fromJson(jobFile.readText())
            state.phase = ZipExportState.PREPARING
            val parts = plan(job)
            val total = parts.sumOf { it.size }
            if (total == 0) throw IOException("None of those files could be read.")
            state.filesTotal = total
            state.filesDone = 0
            state.bytesTotal = parts.sumOf { part -> part.sumOf { it.info.size.coerceAtLeast(0) } }
            state.bytesDone = 0
            state.partsTotal = parts.size
            state.phase = ZipExportState.WRITING

            val results = ArrayList<ZipResult>()
            for ((index, part) in parts.withIndex()) {
                state.part = index + 1
                results += writePart(job, part, index, parts.size)
            }
            state.results = results
            state.phase = ZipExportState.DONE
            postDone(results)
            return Result.success()
        } catch (e: Cancelled) {
            discard()
            state.phase = ZipExportState.CANCELLED
            return Result.success()
        } catch (e: Throwable) {
            Log.e(TAG, "the zip could not be made: ${e.message}", e)
            discard()
            state.error = friendly(e)
            state.phase = ZipExportState.FAILED
            postFailed(state.error)
            return Result.failure()
        } finally {
            try {
                if (wake?.isHeld == true) wake.release()
            } catch (_: Exception) {
            }
            jobFile.delete()
        }
    }

    // ---- the plan ----

    private fun checkCancel() {
        if (state.cancelRequested || isStopped) throw Cancelled()
    }

    // The files in the order they go in, cut into zips that each stay within the job's limit.
    private fun plan(job: ZipJob): List<List<Planned>> {
        val context = applicationContext
        val albumFolders = HashSet<String>()
        val planned = ArrayList<Planned>()
        state.filesTotal = job.albums.sumOf { it.items.size }
        state.filesDone = 0
        for (album in job.albums) {
            val folder = unique(safeName(album.name, "Album"), albumFolders)
            val names = HashSet<String>()
            val seen = HashSet<String>()
            // Images first, then videos, each in its own folder.
            for (videos in listOf(false, true)) {
                for (item in album.items) {
                    if (item.isVideo != videos || !seen.add(item.uri)) continue
                    checkCancel()
                    val info = ExportItems.resolve(context, item.uri)
                    state.filesDone++
                    if (!info.readable) {
                        state.skipped++
                        continue
                    }
                    val subfolder = "$folder/${if (videos) "Videos" else "Images"}"
                    val name = unique(safeName(info.name, "file"), names, subfolder, keepExtension = true)
                    planned += Planned(album, item, info, subfolder, name)
                }
            }
        }

        val limit = if (job.partLimitBytes > 0) job.partLimitBytes - RESERVE_BYTES else 0L
        val parts = ArrayList<MutableList<Planned>>()
        var current = ArrayList<Planned>()
        var bytes = 0L
        for (p in planned) {
            val cost = cost(p, job.includeList)
            if (limit > 0 && current.isNotEmpty() && bytes + cost > limit) {
                parts += current
                current = ArrayList()
                bytes = 0
            }
            current += p
            bytes += cost
        }
        if (current.isNotEmpty()) parts += current
        return parts
    }

    private fun cost(p: Planned, withList: Boolean): Long {
        val size = p.info.size.coerceAtLeast(0)
        return size + 5 * (size / 65535 + 1) + p.path.length * 2L + 200 + (if (withList) 300 else 0)
    }

    // ---- one zip ----

    private fun writePart(job: ZipJob, part: List<Planned>, index: Int, parts: Int): ZipResult {
        val context = applicationContext
        val planned = part.sumOf { cost(it, job.includeList) }
        val zip64 = planned > ZIP64_ABOVE_BYTES || part.size > ZIP64_ABOVE_FILES
        val fileName = zipFileName(job, index, parts)
        val output = openOutput(job.destination, fileName)
        created += output
        val writer = ZipPartWriter(BufferedOutputStream(output.stream, 256 * 1024), zip64)
        val listed = ArrayList<Listed>()
        try {
            for (p in part) {
                checkCancel()
                state.currentName = p.info.name
                val input = try {
                    context.contentResolver.openInputStream(Uri.parse(p.item.uri))
                } catch (_: Exception) {
                    null
                }
                if (input == null) {
                    state.skipped++
                    state.filesDone++
                    continue
                }
                val forgiving = ForgivingStream(input)
                val size = forgiving.use { stream ->
                    writer.addFile(p.path, p.info.dateMs, stream) { n ->
                        state.bytesDone += n
                        checkCancel()
                        notifyProgress()
                    }
                }
                if (forgiving.failed) state.skipped++
                listed += Listed(p, size, forgiving.failed)
                state.filesDone++
            }
            if (job.includeList) {
                writer.addBytes("list.json", System.currentTimeMillis(), listJson(listed, index + 1, parts).toByteArray(Charsets.UTF_8))
            }
            writer.close()
        } catch (e: Throwable) {
            try {
                writer.close()
            } catch (_: Exception) {
            }
            throw e
        }
        output.finish()
        // Stays in [created]: if a later zip fails or the job is cancelled, this one goes too.
        return ZipResult(output.shownName, output.uri.toString(), writer.bytesWritten)
    }

    private fun zipFileName(job: ZipJob, index: Int, parts: Int): String {
        val base = safeName(job.zipName, "Lost & Found export").take(120)
        return if (parts == 1) "$base.zip" else "$base - part ${index + 1} of $parts.zip"
    }

    private fun listJson(listed: List<Listed>, part: Int, parts: Int): String {
        val iso = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply { timeZone = TimeZone.getTimeZone("UTC") }
        fun date(ms: Long): Any = if (ms > 0) iso.format(Date(ms)) else JSONObject.NULL
        val albums = JSONArray()
        for (album in listed.map { it.planned.album }.distinct()) {
            val files = JSONArray()
            for (l in listed.filter { it.planned.album === album }) {
                files.put(
                    JSONObject()
                        .put("path", l.planned.path)
                        .put("name", l.planned.info.name)
                        .put("type", if (l.planned.item.isVideo) "video" else "image")
                        .put("dateTaken", date(l.planned.info.takenMs))
                        .put("modified", date(l.planned.info.modifiedMs))
                        .put("size", l.size)
                        .apply { if (l.incomplete) put("incomplete", true) },
                )
            }
            albums.put(JSONObject().put("name", album.name).put("type", album.kind).put("files", files))
        }
        return JSONObject()
            .put("app", "Lost & Found")
            .put("created", iso.format(Date()))
            .put("part", part)
            .put("parts", parts)
            .put("albums", albums)
            .toString(2)
    }

    // ---- where it goes ----

    private fun openOutput(destination: ZipDestination, fileName: String): Output {
        val context = applicationContext
        val resolver = context.contentResolver
        val tree = destination.treeUri
        if (tree == null) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                throw IOException("Choose a folder to save the zip in.")
            }
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/zip")
                put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/Lost & Found")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IOException("Could not create the file in Downloads.")
            val stream = resolver.openOutputStream(uri) ?: throw IOException("Could not write to Downloads.")
            var shown = fileName
            try {
                resolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use {
                    if (it.moveToFirst()) shown = it.getString(0) ?: fileName
                }
            } catch (_: Exception) {
            }
            return Output(
                stream,
                uri,
                shown,
                finish = {
                    resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
                },
                delete = {
                    try {
                        resolver.delete(uri, null, null)
                    } catch (_: Exception) {
                    }
                },
            )
        }
        val directory = DocumentFile.fromTreeUri(context, Uri.parse(tree))
            ?: throw IOException("The folder could not be opened.")
        val file = directory.createFile("application/zip", fileName)
            ?: throw IOException("Could not create the file in that folder.")
        val stream = resolver.openOutputStream(file.uri, "w") ?: throw IOException("Could not write to that folder.")
        return Output(
            stream,
            file.uri,
            file.name ?: fileName,
            finish = {},
            delete = {
                try {
                    file.delete()
                } catch (_: Exception) {
                }
            },
        )
    }

    // What was made so far is removed again.
    private fun discard() {
        for (output in created) {
            try {
                output.stream.close()
            } catch (_: Exception) {
            }
            output.delete()
        }
        created.clear()
    }

    private fun friendly(e: Throwable): String {
        val message = e.message ?: ""
        return when {
            message.contains("ENOSPC", true) || message.contains("No space", true) ->
                "There is not enough space for the zip."
            e is SecurityException -> "The app is not allowed to write to that folder. Choose another one."
            message.isNotBlank() -> message
            else -> "The zip could not be made."
        }
    }

    // ---- names ----

    private fun safeName(text: String, fallback: String): String {
        val cleaned = text.map { c -> if (c in "\\/:*?\"<>|" || c.code < 32) '_' else c }
            .joinToString("")
            .trim()
            .trim('.')
            .take(100)
            .trim()
        return cleaned.ifEmpty { fallback }
    }

    // [name] if it is not taken yet in [taken] (compared without regard to case), else with a
    // number in front of the extension.
    private fun unique(name: String, taken: MutableSet<String>, folder: String = "", keepExtension: Boolean = false): String {
        fun key(n: String) = "$folder/$n".lowercase(Locale.ROOT)
        if (taken.add(key(name))) return name
        val dot = if (keepExtension) name.lastIndexOf('.') else -1
        val stem = if (dot > 0) name.substring(0, dot) else name
        val extension = if (dot > 0) name.substring(dot) else ""
        var n = 2
        while (true) {
            val candidate = "$stem ($n)$extension"
            if (taken.add(key(candidate))) return candidate
            n++
        }
    }

    // ---- the notification ----

    private fun notifyProgress() {
        val now = System.currentTimeMillis()
        if (now - lastNotified < 700) return
        lastNotified = now
        val percent = if (state.bytesTotal > 0) (state.bytesDone * 100 / state.bytesTotal).toInt().coerceIn(0, 100) else 0
        val parts = if (state.partsTotal > 1) " · zip ${state.part} of ${state.partsTotal}" else ""
        val text = "${state.filesDone} of ${state.filesTotal} files$parts"
        try {
            NotificationManagerCompat.from(applicationContext).notify(NOTIFICATION_ID, notification("Making your zip", text, percent, false))
        } catch (_: SecurityException) {
        }
    }

    private fun foregroundInfo(text: String, percent: Int, indeterminate: Boolean): ForegroundInfo {
        val notification = notification("Making your zip", text, percent, indeterminate)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ForegroundInfo(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            ForegroundInfo(NOTIFICATION_ID, notification)
        }
    }

    private fun postDone(results: List<ZipResult>) {
        val text = if (results.size == 1) results[0].name else "${results.size} zip files"
        try {
            NotificationManagerCompat.from(applicationContext).notify(
                NOTIFICATION_DONE_ID,
                NotificationCompat.Builder(applicationContext, CHANNEL_ID)
                    .setContentTitle("Your zip is ready")
                    .setContentText(text)
                    .setSmallIcon(android.R.drawable.stat_sys_download_done)
                    .setColor(Color.parseColor("#165E59"))
                    .setAutoCancel(true)
                    .setContentIntent(contentIntent())
                    .build(),
            )
        } catch (_: SecurityException) {
        }
    }

    // Someone who left the app should hear that it did not work out.
    private fun postFailed(message: String) {
        try {
            createChannel()
            NotificationManagerCompat.from(applicationContext).notify(
                NOTIFICATION_DONE_ID,
                NotificationCompat.Builder(applicationContext, CHANNEL_ID)
                    .setContentTitle("Your zip could not be made")
                    .setContentText(message)
                    .setStyle(NotificationCompat.BigTextStyle().bigText(message))
                    .setSmallIcon(android.R.drawable.stat_notify_error)
                    .setColor(Color.parseColor("#165E59"))
                    .setAutoCancel(true)
                    .setContentIntent(contentIntent())
                    .build(),
            )
        } catch (_: SecurityException) {
        }
    }

    private fun notification(title: String, text: String, percent: Int, indeterminate: Boolean): Notification {
        createChannel()
        return NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_upload)
            .setColor(Color.parseColor("#165E59"))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setProgress(100, percent, indeterminate)
            .setContentIntent(contentIntent())
            .build()
    }

    private fun contentIntent(): PendingIntent {
        val intent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(applicationContext, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = applicationContext.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Zip export", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shows progress while Lost & Found makes a zip of your albums."
                setShowBadge(false)
            },
        )
    }

    companion object {
        private const val TAG = "ZipExportWorker"
        private const val CHANNEL_ID = "zip_export"
        // Not 4202: that is the face scan's, and the two can run at the same time.
        private const val NOTIFICATION_ID = 4204
        private const val NOTIFICATION_DONE_ID = 4203
        private const val WAKE_LOCK_MS = 3 * 60 * 60 * 1000L

        // Left free in each zip for the list and the index.
        private const val RESERVE_BYTES = 256 * 1024L

        // A zip that is expected to be bigger than this, or to hold more files than this, uses
        // the 64-bit zip format (plain zip is used otherwise, as every tool reads it).
        private const val ZIP64_ABOVE_BYTES = 3_000_000_000L
        private const val ZIP64_ABOVE_FILES = 60_000
    }
}
