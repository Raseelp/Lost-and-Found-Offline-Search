package dev.raseel.lostandfound.embedder.memories

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.net.Uri
import android.os.Build
import android.util.Size
import dev.raseel.lostandfound.embedder.faces.FaceImageLoader
import dev.raseel.lostandfound.embedder.faces.FaceServices

/** What a notification shows: the whole picture, and a small rounded one for when it is folded. */
class Rendered(val card: Bitmap, val thumb: Bitmap)

/** How the photos of a notification are laid out. */
enum class PictureStyle {
    /** Two photos filling the card, a slanted white seam between them: then and now. */
    SPLIT,

    /** One photo, edge to edge. */
    HERO,

    /** Two or three photos side by side, full height, with a thin white gap: a few days, a few years. */
    STRIP,

    /** A big photo with a small one tucked into its corner: the two of them now and the first one. */
    INSET;

    companion object {
        /** The layout that suits a kind. */
        fun of(kind: MemoryKind): PictureStyle = when (kind) {
            MemoryKind.THEN_NOW, MemoryKind.PAIR_THEN_NOW -> SPLIT
            MemoryKind.TOGETHER_SINCE -> INSET
            MemoryKind.TRIP, MemoryKind.SAME_DAY -> STRIP
            else -> HERO
        }
    }
}

/**
 * The picture of a notification. The photos fill the card - no frames, no empty space - and the card has
 * rounded corners. Small pills carry what is not in the words: the year or day on each photo, and - for then
 * and now - the time between, on the seam.
 */
object MemoryPictures {
    // The card is designed on this canvas and drawn scaled down: the numbers below are in these units.
    private const val DESIGN_W = 1080f
    private const val DESIGN_H = 520f
    private const val OUT_W = 960
    private const val OUT_H = 462
    private const val CORNER = 36f
    private const val GAP = 8f

    // The seam of a split: from the top edge down to the bottom, slanting left.
    private const val SEAM_TOP = 590f
    private const val SEAM_BOTTOM = 490f

    private fun rect(l: Float, t: Float, r: Float, b: Float) = RectF(l, t, r, b)

    /** Where each photo goes, in design units. */
    private fun layout(style: PictureStyle, n: Int): List<RectF> = when (style) {
        PictureStyle.HERO -> listOf(rect(0f, 0f, DESIGN_W, DESIGN_H))
        // Each reaches past the seam, so the one on top has room to be cut along it.
        PictureStyle.SPLIT -> listOf(rect(0f, 0f, 600f, DESIGN_H), rect(480f, 0f, DESIGN_W, DESIGN_H))
        PictureStyle.STRIP -> {
            val w = (DESIGN_W - GAP * (n - 1)) / n
            List(n) { i -> rect(i * (w + GAP), 0f, i * (w + GAP) + w, DESIGN_H) }
        }
        PictureStyle.INSET -> listOf(rect(0f, 0f, DESIGN_W, DESIGN_H), rect(826f, 26f, 1054f, 254f))
    }

    /**
     * The picture for [pics] (the first three) laid out as [style]; [connector] is written on the seam of a
     * split, or on the big photo of an inset. Null when none of the photos could be read.
     */
    fun render(context: Context, pics: List<Pic>, style: PictureStyle, connector: String? = null): Rendered? {
        if (pics.isEmpty()) return null
        val n = pics.size.coerceAtMost(3)
        // A layout that needs several photos is not used with one.
        val used = when {
            n < 2 -> PictureStyle.HERO
            style == PictureStyle.SPLIT -> PictureStyle.SPLIT
            style == PictureStyle.INSET -> PictureStyle.INSET
            style == PictureStyle.STRIP -> PictureStyle.STRIP
            else -> PictureStyle.HERO
        }
        val count = when (used) {
            PictureStyle.HERO -> 1
            PictureStyle.SPLIT, PictureStyle.INSET -> 2
            PictureStyle.STRIP -> n
        }
        val spots = layout(used, count)
        val scale = OUT_W / DESIGN_W
        val tiles = spots.mapIndexed { i, spot ->
            tile(context, pics[i], (spot.width() * scale).toInt().coerceAtLeast(120), (spot.height() * scale).toInt().coerceAtLeast(120))
        }
        if (tiles.all { it == null }) return null

        val layer = Bitmap.createBitmap(OUT_W, OUT_H, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(layer)
        canvas.scale(OUT_W / DESIGN_W, OUT_H / DESIGN_H)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        canvas.drawColor(Color.rgb(228, 230, 227))

        when (used) {
            PictureStyle.HERO -> {
                draw(canvas, paint, tiles[0], spots[0])
                pics[0].label?.let {
                    shade(canvas, paint)
                    pill(canvas, it, 28f, DESIGN_H - 80f)
                }
            }
            PictureStyle.SPLIT -> {
                draw(canvas, paint, tiles[1], spots[1])
                canvas.save()
                canvas.clipPath(Path().apply {
                    moveTo(0f, 0f); lineTo(SEAM_TOP, 0f); lineTo(SEAM_BOTTOM, DESIGN_H); lineTo(0f, DESIGN_H); close()
                })
                draw(canvas, paint, tiles[0], spots[0])
                canvas.restore()
                // The seam (it also hides the rough edge of the cut).
                paint.color = Color.WHITE
                paint.style = Paint.Style.STROKE
                paint.strokeWidth = 8f
                canvas.drawLine(SEAM_TOP, 0f, SEAM_BOTTOM, DESIGN_H, paint)
                paint.style = Paint.Style.FILL
                pics[0].label?.let { pill(canvas, it, 28f, DESIGN_H - 80f) }
                pics[1].label?.let { pill(canvas, it, DESIGN_W - 28f, DESIGN_H - 80f, alignRight = true) }
                connector?.let { pill(canvas, it, (SEAM_TOP + SEAM_BOTTOM) / 2f, DESIGN_H / 2f - 30f, centred = true, light = true) }
            }
            PictureStyle.STRIP -> {
                for (i in spots.indices) {
                    draw(canvas, paint, tiles[i], spots[i])
                    pics[i].label?.let { pill(canvas, it, spots[i].left + 20f, DESIGN_H - 80f) }
                }
                // The gaps are white.
                paint.color = Color.WHITE
                for (i in 1 until spots.size) canvas.drawRect(spots[i].left - GAP, 0f, spots[i].left, DESIGN_H, paint)
            }
            PictureStyle.INSET -> {
                draw(canvas, paint, tiles[0], spots[0])
                // The small one, with a white edge round it.
                val inset = spots[1]
                paint.color = Color.WHITE
                paint.setShadowLayer(18f, 0f, 6f, Color.argb(90, 0, 0, 0))
                canvas.drawRoundRect(RectF(inset.left - 7f, inset.top - 7f, inset.right + 7f, inset.bottom + 7f), 34f, 34f, paint)
                paint.clearShadowLayer()
                canvas.save()
                canvas.clipPath(Path().apply { addRoundRect(inset, 28f, 28f, Path.Direction.CW) })
                draw(canvas, paint, tiles[1], inset)
                canvas.restore()
                connector?.let { pill(canvas, it, 28f, DESIGN_H - 80f, light = true) }
            }
        }

        val thumbSource = tiles.lastOrNull { it != null && used == PictureStyle.SPLIT } ?: tiles.first { it != null }!!
        val thumb = thumbnail(thumbSource)
        tiles.forEach { it?.recycle() }
        return Rendered(rounded(layer, CORNER * OUT_W / DESIGN_W), thumb)
    }

    // ---- the pieces ----

    private fun draw(canvas: Canvas, paint: Paint, tile: Bitmap?, into: RectF) {
        if (tile == null) return
        canvas.drawBitmap(tile, null, into, paint)
    }

    // A soft dark shade along the bottom, so a pill on a bright photo can be read.
    private fun shade(canvas: Canvas, paint: Paint) {
        paint.shader = LinearGradient(0f, DESIGN_H - 170f, 0f, DESIGN_H, Color.argb(0, 0, 0, 0), Color.argb(120, 0, 0, 0), Shader.TileMode.CLAMP)
        canvas.drawRect(0f, DESIGN_H - 170f, DESIGN_W, DESIGN_H, paint)
        paint.shader = null
    }

    // A small pill of writing: dark with white letters (a year, a day), or white with dark ones (the time between).
    private fun pill(
        canvas: Canvas, text: String, x: Float, y: Float,
        alignRight: Boolean = false, centred: Boolean = false, light: Boolean = false,
    ) {
        val write = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = if (light) Color.rgb(36, 56, 54) else Color.WHITE
            textSize = if (light) 34f else 32f
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        val w = write.measureText(text) + 44f
        val left = when {
            centred -> x - w / 2f
            alignRight -> x - w
            else -> x
        }
        val back = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = if (light) Color.argb(240, 255, 255, 255) else Color.argb(135, 0, 0, 0)
            if (light) setShadowLayer(12f, 0f, 4f, Color.argb(70, 0, 0, 0))
        }
        canvas.drawRoundRect(RectF(left, y, left + w, y + 58f), 29f, 29f, back)
        canvas.drawText(text, left + 22f, y + 40f, write)
    }

    // [layer] with rounded corners (edges smooth, what is outside the corners clear).
    private fun rounded(layer: Bitmap, radius: Float): Bitmap {
        val out = Bitmap.createBitmap(layer.width, layer.height, Bitmap.Config.ARGB_8888)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { shader = BitmapShader(layer, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP) }
        Canvas(out).drawRoundRect(RectF(0f, 0f, layer.width.toFloat(), layer.height.toFloat()), radius, radius, paint)
        layer.recycle()
        return out
    }

    // A small rounded square of a photo, for the folded notification.
    private fun thumbnail(photo: Bitmap): Bitmap {
        val side = 240
        val short = minOf(photo.width, photo.height)
        val cut = Bitmap.createBitmap(photo, (photo.width - short) / 2, (photo.height - short) / 2, short, short)
        val square = Bitmap.createScaledBitmap(cut, side, side, true)
        if (cut !== photo && cut !== square) cut.recycle()
        return rounded(square, 44f)
    }

    // ---- reading the photos ----

    // One picture [w] x [h]: the framed face(s), or the middle of the photo.
    private fun tile(context: Context, pic: Pic, w: Int, h: Int): Bitmap? {
        return try {
            val box = pic.box
            if (box != null) {
                val bytes = FaceServices.get(context).crops.portrait(
                    pic.uri, box[0], box[1], box[2], box[3], pic.photoW, pic.photoH, w, pic.margin, pic.lift, w.toFloat() / h,
                ) ?: return null
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            } else {
                val photo = thumbnail(context, Uri.parse(pic.uri), pic.video, (maxOf(w, h) * 1.35f).toInt()) ?: return null
                val cut = centreCrop(photo, w, h)
                if (cut !== photo) photo.recycle()
                cut
            }
        } catch (_: Exception) {
            null
        }
    }

    /**
     * A picture of the photo or video, about [side] across at its longest (upright). A photo is read from the
     * photo itself: the system's thumbnail of it is a small cached one that goes soft once it is stretched over
     * a notification's picture. A video has no such picture to read, so it gets the system's.
     */
    fun thumbnail(context: Context, uri: Uri, video: Boolean, side: Int): Bitmap? {
        if (!video) FaceImageLoader.load(context, uri, side)?.let { return it }
        if (Build.VERSION.SDK_INT >= 29) {
            try {
                return context.contentResolver.loadThumbnail(uri, Size(side, side), null)
            } catch (_: Exception) {
            }
        }
        if (video) return null
        return FaceImageLoader.load(context, uri, side)
    }

    // The middle of [photo] cut to the shape [w] x [h] and made that size.
    private fun centreCrop(photo: Bitmap, w: Int, h: Int): Bitmap {
        val want = w.toFloat() / h
        val have = photo.width.toFloat() / photo.height
        val cw = if (have > want) (photo.height * want).toInt() else photo.width
        val ch = if (have > want) photo.height else (photo.width / want).toInt()
        val cut = Bitmap.createBitmap(photo, (photo.width - cw) / 2, (photo.height - ch) / 2, cw.coerceAtLeast(1), ch.coerceAtLeast(1))
        val scaled = Bitmap.createScaledBitmap(cut, w, h, true)
        if (cut !== photo && cut !== scaled) cut.recycle()
        return scaled
    }
}
