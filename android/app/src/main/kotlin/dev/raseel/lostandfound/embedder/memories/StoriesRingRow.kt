package dev.raseel.lostandfound.embedder.memories

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.SweepGradient
import android.graphics.Typeface
import android.net.Uri
import dev.raseel.lostandfound.embedder.faces.FaceServices
import org.json.JSONArray

/** One ring of the "your stories have refreshed" note: who or what it is, and the picture inside its ring. */
class StoryPreview(
    /** The name (a person who has none has an empty one: the ring is still shown, but nothing is said of it). */
    val title: String,
    /** The face of a person (0: none). */
    val faceId: Long = 0L,
    /** The cover of a collection (empty: none). */
    val coverUri: String = "",
    val coverIsVideo: Boolean = false,
) {
    companion object {
        /** The rings the app sent, at most [limit] (a bad or empty list is an empty one). */
        fun parse(json: String?, limit: Int = 8): List<StoryPreview> {
            if (json.isNullOrBlank()) return emptyList()
            return try {
                val array = JSONArray(json)
                (0 until minOf(array.length(), limit)).mapNotNull { i ->
                    val o = array.optJSONObject(i) ?: return@mapNotNull null
                    val title = o.optString("title").trim()
                    val preview = StoryPreview(title, o.optLong("faceId", 0L), o.optString("cover", ""), o.optBoolean("video", false))
                    // A ring needs a name or a picture to be one.
                    if (title.isEmpty() && preview.faceId <= 0L && preview.coverUri.isEmpty()) null else preview
                }
            } catch (_: Exception) {
                emptyList()
            }
        }

        /**
         * What the note says of [rings]: the names there are (three at most), and the rest as a number, so a person who
         * has no name is never read out as one. "Maya is ready to watch." "Maya and 2 more are ready to watch."
         * "Maya, Beach, Sam and 3 more are ready to watch." With no names at all: "5 stories are ready to watch."
         */
        fun sentence(rings: List<StoryPreview>): String {
            val total = rings.size
            if (total == 0) return "New photos and memories are waiting. Come explore."
            val named = rings.map { it.title }.filter { it.isNotBlank() }.take(3)
            if (named.isEmpty()) return if (total == 1) "A new story is ready to watch." else "$total stories are ready to watch."
            val more = total - named.size
            val names = when {
                more > 0 -> named.joinToString(", ") + " and $more more"
                named.size == 1 -> named[0]
                else -> named.dropLast(1).joinToString(", ") + " and " + named.last()
            }
            return if (total == 1) "$names is ready to watch." else "$names are ready to watch."
        }
    }
}

/**
 * The picture of the note: a row of rings, each with the picture of a person or collection inside a ring in the
 * app's colours (the same as a lit ring on the Search tab), and a grey ring with "+3" when there are more than fit.
 * The picture is transparent, so it sits on whatever colour the notification has (light or dark).
 */
object StoriesRingRow {
    private const val CIRCLE = 132f // across, ring included
    private const val RING = 6f
    private const val GAP_IN = 6f // between the ring and the picture
    private const val SPACE = 24f // between circles
    private const val MAX = 5

    private val colours = intArrayOf(
        Color.rgb(0x16, 0x5E, 0x59), Color.rgb(0x7F, 0xD6, 0xCC), Color.rgb(0xF2, 0xB8, 0x4B),
        Color.rgb(0xE8, 0x73, 0x5A), Color.rgb(0x16, 0x5E, 0x59),
    )

    /** The row for [rings] (five at most are drawn, the rest become "+n"), or null when no picture could be read. */
    fun render(context: Context, rings: List<StoryPreview>, total: Int = rings.size): Bitmap? {
        val shown = rings.take(MAX)
        val pictures = shown.map { picture(context, it) }
        if (pictures.all { it == null }) return null
        val more = total - shown.size
        val count = shown.size + if (more > 0) 1 else 0
        val width = (count * CIRCLE + (count - 1) * SPACE).toInt()
        val out = Bitmap.createBitmap(width, CIRCLE.toInt(), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        shown.forEachIndexed { i, _ ->
            val left = i * (CIRCLE + SPACE)
            drawRing(canvas, paint, left, pictures[i])
        }
        if (more > 0) {
            val left = shown.size * (CIRCLE + SPACE)
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = RING
            paint.shader = null
            paint.color = Color.rgb(0xB5, 0xBA, 0xB7)
            canvas.drawCircle(left + CIRCLE / 2, CIRCLE / 2, (CIRCLE - RING) / 2, paint)
            paint.style = Paint.Style.FILL
            paint.textSize = 40f
            paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            paint.textAlign = Paint.Align.CENTER
            paint.color = Color.rgb(0x8A, 0x90, 0x8D)
            canvas.drawText("+$more", left + CIRCLE / 2, CIRCLE / 2 + 14f, paint)
        }
        pictures.forEach { it?.recycle() }
        return out
    }

    private fun drawRing(canvas: Canvas, paint: Paint, left: Float, picture: Bitmap?) {
        val cx = left + CIRCLE / 2
        val cy = CIRCLE / 2
        // The picture, round, inside the ring and its gap.
        val inner = CIRCLE / 2 - RING - GAP_IN
        if (picture != null) {
            val clip = Path().apply { addCircle(cx, cy, inner, Path.Direction.CW) }
            canvas.save()
            canvas.clipPath(clip)
            canvas.drawBitmap(picture, null, RectF(cx - inner, cy - inner, cx + inner, cy + inner), paint)
            canvas.restore()
        } else {
            paint.style = Paint.Style.FILL
            paint.shader = null
            paint.color = Color.rgb(0xE3, 0xF1, 0xEF)
            canvas.drawCircle(cx, cy, inner, paint)
        }
        // The ring: a sweep of the app's colours, turned so the gold sits at the lower right.
        val sweep = SweepGradient(cx, cy, colours, floatArrayOf(0f, 0.4f, 0.75f, 0.9f, 1f))
        sweep.setLocalMatrix(Matrix().apply { postRotate(100f, cx, cy) })
        paint.shader = sweep
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = RING
        canvas.drawCircle(cx, cy, (CIRCLE - RING) / 2, paint)
        paint.shader = null
        paint.style = Paint.Style.FILL
    }

    // A square picture of the ring's subject: a person's face, or the middle of a collection's cover.
    private fun picture(context: Context, ring: StoryPreview): Bitmap? {
        return try {
            val side = 220
            val raw: Bitmap? = if (ring.faceId > 0) {
                FaceServices.get(context).crops.crop(ring.faceId, side)?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
            } else if (ring.coverUri.isNotEmpty()) {
                MemoryPictures.thumbnail(context, Uri.parse(ring.coverUri), ring.coverIsVideo, side * 2)
            } else {
                null
            }
            raw?.let { squareOf(it, side) }
        } catch (_: Exception) {
            null
        }
    }

    private fun squareOf(photo: Bitmap, side: Int): Bitmap {
        val short = minOf(photo.width, photo.height)
        val cut = Bitmap.createBitmap(photo, (photo.width - short) / 2, (photo.height - short) / 2, short, short)
        val scaled = Bitmap.createScaledBitmap(cut, side, side, true)
        if (cut !== photo && cut !== scaled) cut.recycle()
        if (photo !== scaled && photo !== cut) photo.recycle()
        return scaled
    }
}
