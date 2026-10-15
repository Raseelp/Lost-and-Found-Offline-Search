package dev.raseel.lostandfound.embedder.faces

import android.content.ContentUris
import android.content.Context
import android.net.Uri
import android.os.SystemClock
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.exifinterface.media.ExifInterface
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * When each photo or video was taken, for the People timeline.
 *
 * The date of a file is more than one thing: the gallery's own "taken" date is best; the picture's
 * EXIF date is next (folders picked by hand have no gallery date); then a date in the file's name
 * (IMG_20190812..., WhatsApp, screenshots); then when the file was last changed, and last when it
 * was added. A date before 1990 or in the future is a camera with no clock set, never a real one,
 * so it is skipped for the next kind.
 */
object MediaDates {
    const val SRC_NONE = 0
    const val SRC_TAKEN = 1
    const val SRC_EXIF = 2
    const val SRC_NAME = 3
    const val SRC_MODIFIED = 4
    const val SRC_ADDED = 5

    /** [junk]: a screenshot or screen recording, which is not a memory whatever its date. */
    class Found(val ms: Long, val src: Int, val junk: Boolean = false)

    // 1990-01-01. Cameras with no clock set write 1970 or 2000-01-01 (or the day they were made).
    private const val MIN_MS = 631152000000L
    private const val DAY_MS = 86_400_000L
    private const val CHUNK = 300

    private val nameDate = Regex("(?<!\\d)((?:19|20)\\d{2})[-_.]?(0[1-9]|1[0-2])[-_.]?(0[1-9]|[12]\\d|3[01])(?!\\d)")
    private val videoExt = setOf("mp4", "mov", "3gp", "3gpp", "mkv", "webm", "avi", "m4v", "mpg", "mpeg", "wmv", "flv")

    // A camera that has lost its clock starts at 2000-01-01 00:00 (in whatever time zone it is read).
    private const val CLOCK_RESET_START = 946684800000L - 14 * 3_600_000L
    private const val CLOCK_RESET_END = 946684800000L + DAY_MS + 14 * 3_600_000L

    fun valid(ms: Long, now: Long): Boolean =
        ms in MIN_MS..(now + DAY_MS) && ms !in CLOCK_RESET_START..CLOCK_RESET_END

    /** The best of the dates there are (0 for "not known"), in the order described above. */
    fun pick(taken: Long, exif: Long, named: Long, modified: Long, added: Long, now: Long): Found = when {
        valid(taken, now) -> Found(taken, SRC_TAKEN)
        valid(exif, now) -> Found(exif, SRC_EXIF)
        valid(named, now) -> Found(named, SRC_NAME)
        valid(modified, now) -> Found(modified, SRC_MODIFIED)
        valid(added, now) -> Found(added, SRC_ADDED)
        else -> Found(0, SRC_NONE)
    }

    /** A date written in a file name ("IMG_20190812_101500.jpg", "IMG-20190812-WA0001.jpg"), at noon; 0 if none. */
    fun dateFromName(name: String?): Long {
        if (name == null) return 0
        val m = nameDate.find(name) ?: return 0
        val cal = Calendar.getInstance()
        cal.clear()
        cal.set(m.groupValues[1].toInt(), m.groupValues[2].toInt() - 1, m.groupValues[3].toInt(), 12, 0, 0)
        return cal.timeInMillis
    }

    private class Meta(val name: String?, val taken: Long, val modified: Long, val added: Long)

    /**
     * The dates of [items] (key to uri), as many as there is time for before [deadline] (an
     * [SystemClock.elapsedRealtime] value). Anything not in the result was not decided and is asked
     * for again later - a file is never given a worse date only because time ran out.
     */
    fun resolve(context: Context, items: List<Pair<Long, String>>, now: Long, deadline: Long): Map<Long, Found> {
        val out = HashMap<Long, Found>()
        for (chunk in items.chunked(CHUNK)) {
            if (SystemClock.elapsedRealtime() >= deadline) break
            val metas = lookup(context, chunk)
            for ((key, uri) in chunk) {
                val meta = metas[key]
                var exif = 0L
                val needsExif = meta == null || !valid(meta.taken, now)
                if (needsExif && isImage(meta?.name ?: uri)) {
                    if (SystemClock.elapsedRealtime() >= deadline) continue
                    exif = exifDate(context, uri)
                }
                val picked = pick(
                    taken = meta?.taken ?: 0, exif = exif, named = dateFromName(meta?.name ?: uri.substringAfterLast('/')),
                    modified = meta?.modified ?: 0, added = meta?.added ?: 0, now = now,
                )
                out[key] = if (isScreenshot(meta?.name ?: uri.substringAfterLast('/'))) Found(picked.ms, picked.src, true) else picked
            }
        }
        return out
    }

    private val screenshotName = Regex("screen[-_ ]?(shot|record|cast)", RegexOption.IGNORE_CASE)

    /** A screenshot or screen recording, by its file name. */
    fun isScreenshot(name: String?): Boolean = name != null && screenshotName.containsMatchIn(name)

    private fun isImage(nameOrUri: String): Boolean {
        val ext = nameOrUri.substringAfterLast('.', "").substringBefore('?').lowercase(Locale.US)
        return ext !in videoExt
    }

    private fun lookup(context: Context, chunk: List<Pair<Long, String>>): Map<Long, Meta> {
        val out = HashMap<Long, Meta>()
        val byId = HashMap<Long, Long>() // gallery id -> key
        for ((key, uriString) in chunk) {
            val uri = try { Uri.parse(uriString) } catch (_: Exception) { continue }
            if (uri.authority == MediaStore.AUTHORITY) {
                try { byId[ContentUris.parseId(uri)] = key } catch (_: Exception) { }
            } else {
                out[key] = lookupOne(context, uri)
            }
        }
        if (byId.isNotEmpty()) {
            val files = MediaStore.Files.getContentUri("external")
            val selection = "_id IN (${byId.keys.joinToString(",")})"
            // A phone whose gallery lacks the "taken" column fails the whole query: it is asked
            // again without it, so the other dates still count.
            for (columns in listOf(
                arrayOf("_id", "_display_name", "datetaken", "date_modified", "date_added"),
                arrayOf("_id", "_display_name", "date_modified", "date_added"),
            )) {
                try {
                    context.contentResolver.query(files, columns, selection, null, null)?.use { c ->
                        val withTaken = columns.size == 5
                        while (c.moveToNext()) {
                            val key = byId[c.getLong(0)] ?: continue
                            val shift = if (withTaken) 1 else 0
                            out[key] = Meta(
                                name = c.getString(1),
                                taken = if (withTaken && !c.isNull(2)) c.getLong(2) else 0,
                                modified = if (!c.isNull(2 + shift)) c.getLong(2 + shift) * 1000L else 0,
                                added = if (!c.isNull(3 + shift)) c.getLong(3 + shift) * 1000L else 0,
                            )
                        }
                    }
                    break
                } catch (_: Exception) {
                }
            }
        }
        return out
    }

    // A file from a folder picked by hand: what the provider says about its name and its change date.
    private fun lookupOne(context: Context, uri: Uri): Meta {
        val document = DocumentsContract.isDocumentUri(context, uri)
        val columns = if (document) {
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_LAST_MODIFIED)
        } else {
            arrayOf(OpenableColumns.DISPLAY_NAME)
        }
        try {
            context.contentResolver.query(uri, columns, null, null, null)?.use { c ->
                if (c.moveToFirst()) {
                    return Meta(
                        name = c.getString(0),
                        taken = 0,
                        modified = if (document && !c.isNull(1)) c.getLong(1) else 0,
                        added = 0,
                    )
                }
            }
        } catch (_: Exception) {
        }
        return Meta(null, 0, 0, 0)
    }

    private fun exifDate(context: Context, uriString: String): Long {
        return try {
            context.contentResolver.openInputStream(Uri.parse(uriString))?.use { stream ->
                val exif = ExifInterface(stream)
                val text = exif.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)
                    ?: exif.getAttribute(ExifInterface.TAG_DATETIME_DIGITIZED)
                    ?: exif.getAttribute(ExifInterface.TAG_DATETIME)
                    ?: return 0L
                SimpleDateFormat("yyyy:MM:dd HH:mm:ss", Locale.US).parse(text.trim())?.time ?: 0L
            } ?: 0L
        } catch (_: Exception) {
            0L
        }
    }
}
