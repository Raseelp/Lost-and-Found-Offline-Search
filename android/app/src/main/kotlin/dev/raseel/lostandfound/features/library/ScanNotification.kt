package dev.raseel.lostandfound.features.library

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.drawable.Icon
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import dev.raseel.lostandfound.R
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.roundToInt

/**
 * The progress notification of a scan, shared by indexing ([ScanForegroundService]) and the face scan on its own
 * ([FaceScanWorker]). Indexing is one bar in two parts, photos then videos, each as long as its share of the scan.
 * Faces are a violet bar while they are found, with indexing dimmed under it. On Android 16 and later it is the
 * system's progress notification, promoted to a live update, which a custom layout never is.
 */
object ScanNotification {

    /** Indexing: how many photos and videos the scan has, how many of each are done, and the time left. */
    data class Indexing(
        val photos: Int,
        val videos: Int,
        val photosDone: Int,
        val videosDone: Int,
        val timeLeft: String?,
        val speed: String? = null,
    ) {
        val total get() = photos + videos
        val done get() = photosDone + videosDone
        val percent get() = if (total > 0) (done.toLong() * 100 / total).toInt() else 0

        /** Photos are indexed first, so the scan is on the videos once the photos are all done. */
        val onVideos get() = videos > 0 && photosDone >= photos
        val ready get() = total > 0
    }

    /**
     * Finding faces: [done] of [total] photos, [title] for the folded line, [context] for the
     * line under the bar and [header] next to the app's name. [waiting] is true when how far
     * it is cannot be told yet. [speed] goes under the line, once it can be told.
     */
    data class Faces(
        val done: Int,
        val total: Int,
        val title: String,
        val context: String,
        val header: String?,
        val waiting: Boolean,
        val speed: String? = null,
    )

    /**
     * How fast something is counting up, over the last [windowMs], so it is steady but follows a change in pace.
     * [add] takes each count with the time it was reached. A count lower than the last one means the counting started
     * again.
     */
    class Rate(private val windowMs: Long = 10_000) {
        private val samples = ArrayDeque<Pair<Long, Int>>()

        /** Adds [count] at [atMs] and returns how many a second, or null until a second or more has gone by. */
        fun add(atMs: Long, count: Int): Double? {
            if (samples.isNotEmpty() && count < samples.last().second) samples.clear()
            samples.addLast(atMs to count)
            while (samples.size > 2 && atMs - samples[1].first >= windowMs) samples.removeFirst()
            val (fromMs, from) = samples.first()
            val ms = atMs - fromMs
            if (ms < 1_000 || count <= from) return null
            return (count - from) * 1000.0 / ms
        }

        fun reset() = samples.clear()
    }

    const val MAX = 1000

    /** Teal for photos, a lighter teal for videos, violet for faces and the app's green, matching the bars in lane_bar_*.xml. */
    private const val PHOTOS = 0xFF1FA393.toInt()
    private const val VIDEOS = 0xFF8EDBD0.toInt()
    private const val FACES = 0xFF6C63B5.toInt()
    private const val APP = 0xFF165E59.toInt()

    /** The empty part of a bar, and of the videos' part, matching the tracks in lane_bar_faces.xml. */
    private const val TRACK = 0x40888888
    private const val VIDEOS_TRACK = 0x2E8EDBD0

    /** The alpha of indexing while it waits below the faces. */
    private const val DIMMED = 0.45f

    /** What Android 16 looks for in a notification's extras to promote it. AndroidX sets it in setRequestPromotedOngoing. */
    private const val EXTRA_REQUEST_PROMOTED_ONGOING = "android.requestPromotedOngoing"

    private const val ON_THIS_PHONE = "Making them searchable, on this phone only"

    /** "11,376" in the phone's own way of writing numbers. */
    fun count(n: Int): String = NumberFormat.getIntegerInstance().format(n)

    /** "844 / 9,876". */
    fun fraction(done: Int, total: Int): String = "${count(done)} / ${count(total)}"

    /** How long, to the minute, such as "1 h 20 min" or "8 min". It is never less than "1 min". */
    fun duration(ms: Long): String {
        val totalMinutes = ((ms + 59_999) / 60_000).coerceAtLeast(1)
        val h = totalMinutes / 60
        val m = totalMinutes % 60
        return when {
            h > 0 && m > 0 -> "$h h $m min"
            h > 0 -> "$h h"
            else -> "$m min"
        }
    }

    /**
     * A speed in words, such as "6.2 photos a second" or "1 video every 4 s". [one] and [many] name what is counted.
     * From about one a second it uses "a second", so it never says "1 photo every 1 s".
     */
    fun speed(perSecond: Double?, one: String, many: String): String? {
        if (perSecond == null || perSecond <= 0.0) return null
        return when {
            perSecond >= 9.95 -> "${perSecond.roundToInt()} $many a second"
            perSecond >= 0.6 -> "${String.format(Locale.getDefault(), "%.1f", perSecond)} $many a second"
            else -> {
                val seconds = (1 / perSecond).roundToInt()
                if (seconds < 90) "1 $one every $seconds s" else "1 $one every ${(seconds + 30) / 60} min"
            }
        }
    }

    /** [done] of [total] as a bar's progress. */
    fun progress(done: Int, total: Int): Int =
        if (total <= 0) 0 else (done.toLong() * MAX / total).toInt().coerceIn(0, MAX)

    /** The folded line of indexing, such as "Indexing photos" with the percent after it. */
    fun indexingTitle(indexing: Indexing): String = when {
        !indexing.ready -> "Getting ready to index"
        indexing.onVideos || indexing.photos == 0 -> "Indexing videos  ·  ${indexing.percent}%"
        else -> "Indexing photos  ·  ${indexing.percent}%"
    }

    /** The count of the part being indexed: "844 / 9,876". */
    fun indexingCount(indexing: Indexing): String = when {
        !indexing.ready -> ""
        indexing.onVideos || indexing.photos == 0 -> fraction(indexing.videosDone, indexing.videos)
        else -> fraction(indexing.photosDone, indexing.photos)
    }

    /**
     * The line under the bar while indexing. It is null with both photos and videos, because
     * the two parts are named under the bar instead.
     */
    fun indexingContext(indexing: Indexing): String? = when {
        !indexing.ready -> "Looking for photos and videos"
        indexing.photos == 0 || indexing.videos == 0 -> ON_THIS_PHONE
        else -> null
    }

    /**
     * The notification for indexing, with [faces] while the faces of a batch are found, or for the face scan alone
     * when [indexing] is null. Before Android 16 it uses folded and unfolded custom layouts sharing the bar from
     * [splitBar]. The content title and text are set too, for screen readers and phones without custom layouts. It is
     * public on the lock screen because it holds only counts and speed.
     */
    fun build(
        context: Context,
        channelId: String,
        indexing: Indexing?,
        faces: Faces?,
        contentIntent: PendingIntent,
        deleteIntent: PendingIntent,
    ): Notification {
        val app = context.applicationContext
        if (Build.VERSION.SDK_INT >= 36) return buildLive(app, channelId, indexing, faces, contentIntent, deleteIntent)

        val folded = RemoteViews(app.packageName, R.layout.notification_scan_lane)
        val unfolded = RemoteViews(app.packageName, R.layout.notification_scan_lanes)
        val title: String
        val text: String?
        val header: String?
        if (faces != null) {
            title = faces.title
            text = faces.context
            header = faces.header
            for (views in listOf(folded, unfolded)) showFaces(views, faces)
            folded.setTextViewText(R.id.lane_title, faces.title)
            unfolded.setTextViewText(R.id.lane_title, "Faces")
            unfolded.setViewVisibility(R.id.lane_legend, View.GONE)
            unfolded.setTextViewText(R.id.lane_context, faces.context)
            showSpeed(unfolded, faces.speed)
            if (indexing != null && indexing.ready) {
                val videos = indexing.onVideos || indexing.photos == 0
                unfolded.setViewVisibility(R.id.lane_next, View.VISIBLE)
                unfolded.setImageViewResource(R.id.lane_next_dot, if (videos) R.drawable.lane_dot_videos else R.drawable.lane_dot_photos)
                unfolded.setTextViewText(R.id.lane_next_label, if (videos) "Videos" else "Photos")
                unfolded.setTextViewText(R.id.lane_next_count, "${indexingCount(indexing)}  ·  next")
                unfolded.setFloat(R.id.lane_next, "setAlpha", DIMMED)
            }
        } else {
            val ix = indexing ?: Indexing(0, 0, 0, 0, null)
            title = indexingTitle(ix)
            text = indexingContext(ix)
            header = ix.timeLeft?.let { "about $it left" }
            val bar = if (ix.ready) splitBar(app, ix) else null
            for (views in listOf(folded, unfolded)) showIndexing(views, ix, bar)
            folded.setTextViewText(R.id.lane_title, title)
            unfolded.setTextViewText(
                R.id.lane_title,
                if (ix.ready && (ix.onVideos || ix.photos == 0)) "Videos" else if (ix.ready) "Photos" else title,
            )
            if (ix.photos > 0 && ix.videos > 0) {
                unfolded.setViewVisibility(R.id.lane_legend, View.VISIBLE)
                unfolded.setTextViewText(R.id.lane_legend_photos, "${count(ix.photos)} ${if (ix.photos == 1) "photo" else "photos"}")
                unfolded.setTextViewText(
                    R.id.lane_legend_videos,
                    "${count(ix.videos)} ${if (ix.videos == 1) "video" else "videos"}",
                )
            } else {
                unfolded.setViewVisibility(R.id.lane_legend, View.GONE)
            }
            unfolded.setTextViewText(R.id.lane_context, text)
            unfolded.setViewVisibility(R.id.lane_context, if (text == null) View.GONE else View.VISIBLE)
            showSpeed(unfolded, ix.speed)
        }

        return NotificationCompat.Builder(app, channelId)
            .setContentTitle(title)
            .setContentText(text ?: indexing?.let { indexingCount(it) })
            .setSubText(header)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(folded)
            .setCustomBigContentView(unfolded)
            .setSmallIcon(R.drawable.ic_stat_app)
            .setColor(APP)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(contentIntent)
            .setDeleteIntent(deleteIntent)
            .build()
    }

    /** Shows the quiet speed line under the rest, or hides it until [speed] is known. */
    private fun showSpeed(views: RemoteViews, speed: String?) {
        views.setTextViewText(R.id.lane_speed, speed ?: "")
        views.setViewVisibility(R.id.lane_speed, if (speed == null) View.GONE else View.VISIBLE)
    }

    /** Shows the lane of finding faces, in either layout: the violet dot, the count and the bar. */
    private fun showFaces(views: RemoteViews, faces: Faces) {
        views.setImageViewResource(R.id.lane_dot, R.drawable.lane_dot_faces)
        views.setTextViewText(R.id.lane_count, if (faces.waiting) "" else fraction(faces.done, faces.total))
        views.setViewVisibility(R.id.lane_split, View.GONE)
        views.setViewVisibility(R.id.lane_bar_faces, View.VISIBLE)
        views.setProgressBar(R.id.lane_bar_faces, MAX, progress(faces.done, faces.total), faces.waiting)
    }

    /** Shows the lane of indexing, in either layout: the dot of the part being indexed, its count and the two-part [bar]. */
    private fun showIndexing(views: RemoteViews, ix: Indexing, bar: Bitmap?) {
        val videos = ix.ready && (ix.onVideos || ix.photos == 0)
        views.setImageViewResource(R.id.lane_dot, if (videos) R.drawable.lane_dot_videos else R.drawable.lane_dot_photos)
        views.setTextViewText(R.id.lane_count, indexingCount(ix))
        views.setViewVisibility(R.id.lane_bar_faces, View.GONE)
        if (bar != null) {
            views.setViewVisibility(R.id.lane_split, View.VISIBLE)
            views.setImageViewBitmap(R.id.lane_split, bar)
        } else {
            views.setViewVisibility(R.id.lane_split, View.GONE)
        }
    }

    /**
     * Indexing's bar as a picture: photos then videos, each part as long as its share of the scan, with a small gap,
     * filled as far as it has got. A layout cannot be given such proportions, so the picture is drawn about as wide as
     * the notification shows it and stretched to fit. Each part is at least a dot wide, so a sliver of progress still
     * shows.
     */
    fun splitBar(context: Context, ix: Indexing): Bitmap {
        val metrics = context.resources.displayMetrics
        val dp = metrics.density
        val width = (metrics.widthPixels - 112 * dp).toInt().coerceAtLeast((160 * dp).toInt())
        val height = (6 * dp).toInt().coerceAtLeast(2)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val radius = height / 2f

        fun part(left: Float, right: Float, fraction: Float, track: Int, fill: Int) {
            if (right - left <= 0f) return
            paint.color = track
            canvas.drawRoundRect(RectF(left, 0f, right, height.toFloat()), radius, radius, paint)
            val filled = (right - left) * fraction.coerceIn(0f, 1f)
            if (filled <= 0f) return
            paint.color = fill
            canvas.drawRoundRect(RectF(left, 0f, left + filled.coerceAtLeast(height.toFloat()), height.toFloat()), radius, radius, paint)
        }

        val both = ix.photos > 0 && ix.videos > 0
        val gap = if (both) 3 * dp else 0f
        val usable = width - gap
        val photosWidth = when {
            ix.photos == 0 -> 0f
            ix.videos == 0 -> usable
            else -> (usable * ix.photos / ix.total).coerceIn(height.toFloat(), usable - height)
        }
        part(0f, photosWidth, ix.photosDone.toFloat() / ix.photos.coerceAtLeast(1), TRACK, PHOTOS)
        part(photosWidth + gap, width.toFloat(), ix.videosDone.toFloat() / ix.videos.coerceAtLeast(1), VIDEOS_TRACK, VIDEOS)
        return bitmap
    }

    /** The Android 16 version of [build], using the system's progress style. */
    @RequiresApi(36)
    private fun buildLive(
        app: Context,
        channelId: String,
        indexing: Indexing?,
        faces: Faces?,
        contentIntent: PendingIntent,
        deleteIntent: PendingIntent,
    ): Notification {
        val style = Notification.ProgressStyle()
        val title: String
        val text: String
        val header: String?
        val chip: String?
        if (faces != null) {
            style.setProgressSegments(listOf(Notification.ProgressStyle.Segment(MAX).setColor(FACES)))
                .setProgress(progress(faces.done, faces.total))
                .setProgressIndeterminate(faces.waiting)
                .setProgressTrackerIcon(Icon.createWithResource(app, R.drawable.ic_notif_face))
            title = if (faces.waiting) faces.title else "${faces.title}  ·  ${fraction(faces.done, faces.total)}"
            text = listOfNotNull(faces.context, faces.speed).joinToString("  ·  ")
            header = faces.header
            chip = "Faces"
        } else {
            val ix = indexing ?: Indexing(0, 0, 0, 0, null)
            val segments = buildList {
                if (ix.photos > 0) add(Notification.ProgressStyle.Segment(ix.photos).setColor(PHOTOS))
                if (ix.videos > 0) add(Notification.ProgressStyle.Segment(ix.videos).setColor(VIDEOS))
            }
            if (segments.isEmpty()) {
                style.setProgressSegments(listOf(Notification.ProgressStyle.Segment(MAX).setColor(PHOTOS)))
                    .setProgressIndeterminate(true)
            } else {
                style.setProgressSegments(segments).setProgress(ix.done)
            }
            style.setProgressTrackerIcon(Icon.createWithResource(app, R.drawable.ic_notif_search))
            title = indexingTitle(ix)
            text = listOfNotNull(indexingCount(ix).ifEmpty { null }, indexingContext(ix), ix.speed).joinToString("  ·  ")
            header = ix.timeLeft?.let { "about $it left" }
            chip = if (ix.ready) "${ix.percent}%" else null
        }
        val builder = Notification.Builder(app, channelId)
            .setContentTitle(title)
            .setContentText(text)
            .setSubText(header)
            .setStyle(style)
            .setSmallIcon(R.drawable.ic_stat_app)
            .setColor(APP)
            .setCategory(Notification.CATEGORY_PROGRESS)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(contentIntent)
            .setDeleteIntent(deleteIntent)
        chip?.let { builder.setShortCriticalText(it) }
        builder.extras.putBoolean(EXTRA_REQUEST_PROMOTED_ONGOING, true)
        return builder.build()
    }
}
