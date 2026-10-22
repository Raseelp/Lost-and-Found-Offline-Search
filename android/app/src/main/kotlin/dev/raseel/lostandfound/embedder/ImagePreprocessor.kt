package dev.raseel.lostandfound.embedder

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import kotlin.math.ceil

// Prepares a photo for MobileCLIP-S2, the way Apple's own preprocessing does: the shorter side to 256 (bilinear),
// the middle 256 x 256, each pixel scaled to 0..1 - and nothing more. Unlike the OpenAI CLIP models this one was
// trained without the mean/std normalisation, so adding it would only damage the result.
object ImagePreprocessor {

    private const val IMAGE_SIZE = 256

    fun loadAsFloatArray(
        context: Context,
        uri: Uri
    ): FloatArray? {
        return try {
            val bitmap = loadAndResizeBitmap(context, uri) ?: return null
            val data = bitmapToFloatArray(bitmap)
            bitmap.recycle()
            data
        } catch (e: Exception) {
            null
        }
    }

    // CHW, RGB, each channel's 0..255 pixel value scaled to 0..1. getPixels
    // always returns standard 32-bit ARGB regardless of the Bitmap's own
    // Config (RGB_565 included), so this doesn't care how the bitmap was
    // decoded.
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

        // Only recycle the cropped copy, never the original passed in
        if (cropped !== bitmap) {
            cropped.recycle()
        }

        return data
    }

    // The model's own preprocessing resizes the shorter side to 256 and
    // center-crops the rest, so a photo keeps its real proportions - only the
    // excess on the long side gets trimmed. Stretching straight to a
    // 256x256 square would warp every non-square photo, which is most of them.
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
                    inPreferredConfig = Bitmap.Config.RGB_565
                    inSampleSize = sampleSize
                    inMutable = false
                }

                val sampledBitmap = BitmapFactory.decodeStream(stream2, null, decodeOptions)
                    ?: return null

                val finalBitmap = resizeAndCenterCrop(sampledBitmap)

                if (finalBitmap !== sampledBitmap) {
                    sampledBitmap.recycle()
                }

                finalBitmap
            }
        }
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
