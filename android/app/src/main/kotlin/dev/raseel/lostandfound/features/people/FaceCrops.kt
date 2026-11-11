package dev.raseel.lostandfound.features.people

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.net.Uri
import java.io.ByteArrayOutputStream
import java.io.File
import kotlin.math.max

/**
 * Square face pictures for avatars and the review grid, cut from the photo on demand and
 * cached on disk. The system can clear the cache, and the pictures are then remade.
 */
class FaceCrops(private val context: Context, private val store: FaceStore) {

    private val dir: File get() = File(context.cacheDir, "face_crops").also { it.mkdirs() }
    /**
     * The picture of a face, from the cache or cut from its photo.
     *
     * A face found in a video is not cut again, because a video frame cannot be cut out again
     * cheaply. Its picture was kept when it was found.
     */

    fun crop(faceId: Long, size: Int = DEFAULT_SIZE): ByteArray? {
        val cached = File(dir, "${faceId}_$size.jpg")
        if (cached.exists()) return cached.readBytes()

        val location = store.faceLocation(faceId) ?: return null

        if (location.isVideo) {
            val kept = store.cropFile(faceId)
            return if (kept.exists()) kept.readBytes() else null
        }

        val photo = FaceImageLoader.load(context, Uri.parse(location.photoUri), decodeSideFor(location, size))
            ?: return null
        try {
            val bytes = render(photo, location.boxL, location.boxT, location.boxR, location.boxB, size) ?: return null
            try { cached.writeBytes(bytes) } catch (_: Exception) {}
            return bytes
        } finally {
            photo.recycle()
        }
    }

    /**
     * The picture of a face from [photo], with the box as 0..1 fractions of it, as JPEG, [size] across.
     * It is square, or shaped by [aspect] (width over height), with [margin] of room round the face and the middle a
     * little above it for hair and forehead, moved down by [lift]. With [fill] the area stays inside the photo.
     */
    fun render(
        photo: Bitmap, boxL: Float, boxT: Float, boxR: Float, boxB: Float, size: Int = DEFAULT_SIZE,
        margin: Float = MARGIN, lift: Float = -0.04f, aspect: Float = 1f, fill: Boolean = false,
    ): ByteArray? {
        val w = photo.width.toFloat()
        val h = photo.height.toFloat()
        val cx = (boxL + boxR) / 2f * w
        val cy = (boxT + boxB) / 2f * h + (boxB - boxT) * h * lift
        val base = max((boxR - boxL) * w, (boxB - boxT) * h) * margin
        var cropW = if (aspect >= 1f) base * aspect else base
        var cropH = if (aspect >= 1f) base else base / aspect
        var left = cx - cropW / 2f
        var top = cy - cropH / 2f
        if (fill) {
            val a = fillArea(cx, cy, cropW, cropH, w, h)
            left = a[0]; top = a[1]; cropW = a[2]; cropH = a[3]
        }

        val src = Rect(
            max(0f, left).toInt(), max(0f, top).toInt(),
            minOf(w, left + cropW).toInt(), minOf(h, top + cropH).toInt(),
        )
        if (src.width() <= 0 || src.height() <= 0) return null
        val scale = size / cropW
        val dst = Rect(
            ((src.left - left) * scale).toInt(), ((src.top - top) * scale).toInt(),
            ((src.right - left) * scale).toInt(), ((src.bottom - top) * scale).toInt(),
        )

        val out = Bitmap.createBitmap(size, max(1, (size / aspect).toInt()), Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        canvas.drawColor(Color.rgb(228, 230, 227))
        canvas.drawBitmap(photo, src, dst, Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG))

        val bytes = ByteArrayOutputStream().also { out.compress(Bitmap.CompressFormat.JPEG, 86, it) }.toByteArray()
        out.recycle()
        return bytes
    }

    /**
     * A head-and-shoulders picture of the person whose face is at the box (0..1 fractions) in the photo at [uri]. It
     * has the same framing for every photo, so two of them compare like for like. Kept on disk like the face pictures.
     * With [fill] the decode asks for enough pixels for the area to close in.
     */
    fun portrait(
        uri: String, boxL: Float, boxT: Float, boxR: Float, boxB: Float, photoW: Int, photoH: Int, size: Int = PORTRAIT_SIZE,
        margin: Float = PORTRAIT_MARGIN, lift: Float = PORTRAIT_LIFT, aspect: Float = 1f, fill: Boolean = false,
    ): ByteArray? {
        val key = "$uri|$boxL|$boxT|$boxR|$boxB|$size|$margin|$lift|$aspect" + if (fill) "|fill" else ""
        val cached = File(dir, "p_${key.hashCode()}.jpg")
        if (cached.exists()) return cached.readBytes()
        val faceSide = max((boxR - boxL) * photoW, (boxB - boxT) * photoH)
        val decodeSide = if (photoW <= 0 || photoH <= 0 || faceSide <= 0f) {
            FALLBACK_SIDE
        } else {
            val area = faceSide * margin * max(1f, aspect)
            val across = if (fill) minOf(area, photoW.toFloat(), photoH * aspect) else area
            (size * max(photoW, photoH) / across).toInt().coerceIn(MIN_SIDE, MAX_SIDE)
        }
        val photo = FaceImageLoader.load(context, Uri.parse(uri), decodeSide) ?: return null
        try {
            val bytes = render(photo, boxL, boxT, boxR, boxB, size, margin, lift, aspect, fill) ?: return null
            try { cached.writeBytes(bytes) } catch (_: Exception) {}
            return bytes
        } finally {
            photo.recycle()
        }
    }

    /**
     * How large to decode the photo so the crop comes out at [size]. A face is usually a small part of the photo, and
     * decoding only as large as needed is much cheaper.
     */
    private fun decodeSideFor(location: FaceLocation, size: Int): Int {
        if (location.photoW <= 0 || location.photoH <= 0) return FALLBACK_SIDE
        val cropRef = max(
            (location.boxR - location.boxL) * location.photoW,
            (location.boxB - location.boxT) * location.photoH,
        ) * MARGIN
        val refLong = max(location.photoW, location.photoH)
        val needed = (size * refLong / max(cropRef, 1f)).toInt()
        return needed.coerceIn(MIN_SIDE, MAX_SIDE)
    }

    companion object {
        const val DEFAULT_SIZE = 256

        /**
         * The area [cropW] by [cropH] round ([cx], [cy]) kept inside a [w] by [h] photo: closer in, in the same shape,
         * if it is bigger than the photo, and then moved inside. Returns left, top, width and height. Rounding can
         * leave the area a hair bigger than the photo, so no room to move means none, not less.
         */
        fun fillArea(cx: Float, cy: Float, cropW: Float, cropH: Float, w: Float, h: Float): FloatArray {
            val fit = minOf(1f, w / cropW, h / cropH)
            val cw = cropW * fit
            val ch = cropH * fit
            return floatArrayOf(
                (cx - cw / 2f).coerceIn(0f, maxOf(0f, w - cw)), (cy - ch / 2f).coerceIn(0f, maxOf(0f, h - ch)), cw, ch,
            )
        }

        private const val FALLBACK_SIDE = 1600
        private const val MIN_SIDE = 640
        private const val MAX_SIDE = 2560

        /** The crop side as a multiple of the box side: the face plus some surroundings. */
        private const val MARGIN = 1.7f

        /**
         * The roomier picture for the then and now view: the face is a third of its width, a little above the middle.
         */
        const val PORTRAIT_SIZE = 640
        const val PORTRAIT_MARGIN = 3.1f
        const val PORTRAIT_LIFT = 0.55f
    }
}
