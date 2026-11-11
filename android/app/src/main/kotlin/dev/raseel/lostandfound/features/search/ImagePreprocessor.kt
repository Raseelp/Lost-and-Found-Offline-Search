package dev.raseel.lostandfound.features.search

import dev.raseel.lostandfound.core.log.AppLog
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import dev.raseel.lostandfound.features.people.FaceImageLoader
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.ceil

/**
 * Prepares a photo for MobileCLIP-S0 the way Apple's own preprocessing does: the shorter side to 256 (bilinear), the
 * middle 256 x 256, each pixel scaled to 0..1, and nothing more. This model was trained without the mean and std
 * normalisation of the OpenAI CLIP models, so adding it would damage the result.
 */
object ImagePreprocessor {

    private const val IMAGE_SIZE = 256
    private const val TAG = "ImagePreprocessor"

    /** Only the first few failures are logged, so a library of unreadable files does not fill the log. */
    private const val MAX_FAILURES_LOGGED = 5
    private val failuresLogged = AtomicInteger()

    fun loadAsFloatArray(
        context: Context,
        uri: Uri
    ): FloatArray? {
        return try {
            val bitmap = loadAndResizeBitmap(context, uri) ?: run {
                logFailure("the photo could not be decoded")
                return null
            }
            val data = bitmapToFloatArray(bitmap)
            bitmap.recycle()
            data
        } catch (e: Exception) {
            logFailure("${e.javaClass.simpleName}: ${e.message}")
            null
        }
    }

    private fun logFailure(reason: String) {
        if (failuresLogged.incrementAndGet() <= MAX_FAILURES_LOGGED) AppLog.w(TAG, "could not prepare a photo: $reason")
    }

    /**
     * Returns [bitmap] as CHW, RGB floats with each channel scaled from 0..255 to 0..1. The bitmap passed in is not
     * recycled. Any bitmap config works, because getPixels always returns 32-bit ARGB.
     */
    fun bitmapToFloatArray(bitmap: Bitmap): FloatArray {
        val cropped = resizeAndCenterCrop(bitmap)
        val size = IMAGE_SIZE
        val plane = size * size
        val pixels = IntArray(plane)
        cropped.getPixels(pixels, 0, size, 0, 0, size, size)

        val data = FloatArray(3 * plane)
        for (i in 0 until plane) {
            val p = pixels[i]
            data[i] = (p shr 16 and 0xFF) / 255f
            data[plane + i] = (p shr 8 and 0xFF) / 255f
            data[2 * plane + i] = (p and 0xFF) / 255f
        }

        if (cropped !== bitmap) {
            cropped.recycle()
        }

        return data
    }

    /**
     * Scales the shorter side to 256 and trims the longer side evenly, so a photo keeps its proportions. Stretching to
     * a square would warp most photos.
     */
    private fun resizeAndCenterCrop(bitmap: Bitmap): Bitmap {
        val width = bitmap.width
        val height = bitmap.height

        if (width == IMAGE_SIZE && height == IMAGE_SIZE) return bitmap

        val shorterSide = minOf(width, height)
        val scale = IMAGE_SIZE.toFloat() / shorterSide
        val scaledWidth = ceil(width * scale).toInt().coerceAtLeast(IMAGE_SIZE)
        val scaledHeight = ceil(height * scale).toInt().coerceAtLeast(IMAGE_SIZE)

        val resized = Bitmap.createScaledBitmap(bitmap, scaledWidth, scaledHeight, true)

        val cropLeft = ((scaledWidth - IMAGE_SIZE) / 2).coerceAtLeast(0)
        val cropTop = ((scaledHeight - IMAGE_SIZE) / 2).coerceAtLeast(0)
        val cropped = Bitmap.createBitmap(resized, cropLeft, cropTop, IMAGE_SIZE, IMAGE_SIZE)

        if (resized !== cropped) {
            resized.recycle()
        }

        return cropped
    }

    /**
     * Decodes the photo near 256 px and returns it upright and cropped.
     * The decode uses full colour, because RGB_565 moved the vectors of test photos further from Apple's own
     * preprocessing (cosine 0.994 on average, against 0.997). The photo is turned upright first, because a phone photo
     * is often stored sideways with a tag and the decoder does not turn it.
     */
    private fun loadAndResizeBitmap(
        context: Context,
        uri: Uri
    ): Bitmap? {
        return context.contentResolver.openInputStream(uri)?.use { stream ->

            val boundsOptions = BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeStream(stream, null, boundsOptions)
            stream.close()

            val sampleSize = calculateInSampleSize(
                boundsOptions.outWidth,
                boundsOptions.outHeight,
                IMAGE_SIZE
            )

            context.contentResolver.openInputStream(uri)?.use { stream2 ->
                val decodeOptions = BitmapFactory.Options().apply {
                    inPreferredConfig = Bitmap.Config.ARGB_8888
                    inSampleSize = sampleSize
                    inMutable = false
                }

                val decoded = BitmapFactory.decodeStream(stream2, null, decodeOptions)
                    ?: return null
                val sampledBitmap = FaceImageLoader.upright(decoded, orientationOf(context, uri))

                val finalBitmap = resizeAndCenterCrop(sampledBitmap)

                if (finalBitmap !== sampledBitmap) {
                    sampledBitmap.recycle()
                }

                finalBitmap
            }
        }
    }

    /** The EXIF orientation of the photo, or normal when it has none or cannot be read. */
    private fun orientationOf(context: Context, uri: Uri): Int = try {
        context.contentResolver.openInputStream(uri)?.use {
            ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        } ?: ExifInterface.ORIENTATION_NORMAL
    } catch (_: Exception) {
        ExifInterface.ORIENTATION_NORMAL
    }

    private fun calculateInSampleSize(
        width: Int,
        height: Int,
        targetSize: Int
    ): Int {
        var inSampleSize = 1

        while (width / (inSampleSize * 2) >= targetSize &&
            height / (inSampleSize * 2) >= targetSize
        ) {
            inSampleSize *= 2
        }

        return inSampleSize
    }
}
