package dev.raseel.lostandfound.embedder.memories

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import dev.raseel.lostandfound.embedder.ScanEngineHolder
import java.util.Calendar
import java.util.TimeZone

/** How much of the phone's photos and videos the search index covers: the numbers behind [IndexNudge]. */
class IndexShare(
    val onPhone: Int,
    val indexed: Int,
    /** How many of the photos and how many of the videos are not indexed (null: not told apart). */
    val missingPhotos: Int? = null,
    val missingVideos: Int? = null,
) {
    val missing: Int get() = (onPhone - indexed).coerceAtLeast(0)

    /** Whole percent found, rounded down, so 89.9% never reads as 90. */
    val percent: Int get() = if (onPhone <= 0) 100 else (indexed.toLong() * 100 / onPhone).toInt().coerceIn(0, 100)

    /** Nine tenths of the phone or more is in the index (or there is nothing to index). */
    val finished: Boolean get() = onPhone <= 0 || indexed.toLong() * 10 >= onPhone.toLong() * 9
}

/** Counts what is on the phone and what is in the index. Call off the main thread. */
object IndexGap {
    private const val YEARS_BACK = 20
    private const val DAY_MS = 86_400_000L

    /** Null when it cannot be told: the app may not read the phone's photos, or the index could not be read. */
    fun measure(context: Context): IndexShare? {
        val app = context.applicationContext
        if (!canReadMedia(app)) return null
        return try {
            val photos = count(app, images = true)
            val videos = count(app, images = false)
            val dates = LibraryDates.get(app)
            val indexed = dates.sync(ScanEngineHolder.embeddingEngine(app))
            val (indexedPhotos, indexedVideos) = dates.kindCounts()
            IndexShare(
                photos + videos, indexed,
                missingPhotos = (photos - indexedPhotos).coerceAtLeast(0),
                missingVideos = (videos - indexedVideos).coerceAtLeast(0),
            )
        } catch (_: Exception) {
            null
        }
    }

    /**
     * About how many photos and videos taken on today's date in earlier years are not in the index. Screenshots are left
     * out, as they are from the memories. Null when the dates of the index are not all known yet (the number would be
     * too high).
     */
    fun missingOnThisDay(context: Context, now: Long = System.currentTimeMillis()): Int? {
        val app = context.applicationContext
        if (!canReadMedia(app)) return null
        return try {
            val dates = LibraryDates.get(app)
            if (dates.progress().second > 0) return null
            var missing = 0
            for ((from, to) in sameDayInEarlierYears(now)) {
                val onPhone = count(app, images = true, takenFrom = from, takenTo = to) +
                    count(app, images = false, takenFrom = from, takenTo = to)
                missing += (onPhone - dates.count(from, to)).coerceAtLeast(0)
            }
            missing
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Today's date in each of the [yearsBack] years before, as the moments it starts and ends. A 29 February is only in the
     * leap years, and a day with a clock change is as long as it really was.
     */
    internal fun sameDayInEarlierYears(now: Long, zone: TimeZone = TimeZone.getDefault(), yearsBack: Int = YEARS_BACK): List<Pair<Long, Long>> {
        val today = Calendar.getInstance(zone).apply { timeInMillis = now }
        val year = today.get(Calendar.YEAR)
        val month = today.get(Calendar.MONTH)
        val day = today.get(Calendar.DAY_OF_MONTH)
        val out = ArrayList<Pair<Long, Long>>()
        for (y in year - 1 downTo year - yearsBack) {
            val start = Calendar.getInstance(zone).apply { clear(); set(y, month, day, 0, 0, 0) }
            // A 29 February that is not in that year would have been moved to 1 March.
            if (start.get(Calendar.DAY_OF_MONTH) != day) continue
            val end = (start.clone() as Calendar).apply { add(Calendar.DAY_OF_MONTH, 1) }
            out += start.timeInMillis to end.timeInMillis
        }
        return out
    }

    private fun canReadMedia(context: Context): Boolean {
        val permission = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.READ_MEDIA_IMAGES else Manifest.permission.READ_EXTERNAL_STORAGE
        return context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    }

    private fun collection(images: Boolean): Uri =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            if (images) MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
            else MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL)
        } else {
            if (images) MediaStore.Images.Media.EXTERNAL_CONTENT_URI else MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        }

    // The rows of the gallery, all of them or those taken from [takenFrom] up to [takenTo] (screenshots left out).
    private fun count(context: Context, images: Boolean, takenFrom: Long = 0L, takenTo: Long = 0L): Int {
        val taken = if (images) MediaStore.Images.Media.DATE_TAKEN else MediaStore.Video.Media.DATE_TAKEN
        val name = if (images) MediaStore.Images.Media.DISPLAY_NAME else MediaStore.Video.Media.DISPLAY_NAME
        val ranged = takenTo > 0L
        val selection = if (ranged) "$taken >= ? AND $taken < ? AND $name NOT LIKE 'Screenshot%'" else null
        val args = if (ranged) arrayOf(takenFrom.toString(), takenTo.toString()) else null
        val id = if (images) MediaStore.Images.Media._ID else MediaStore.Video.Media._ID
        return context.contentResolver.query(collection(images), arrayOf(id), selection, args, null)?.use { it.count } ?: 0
    }
}
