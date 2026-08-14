package dev.twentyonevision.app.embedder

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import org.pytorch.Tensor
import org.pytorch.torchvision.TensorImageUtils

object ImagePreprocessor {

    private const val IMAGE_SIZE = 224

    private val MEAN = floatArrayOf(
        0.48145466f,
        0.4578275f,
        0.40821073f
    )

    private val STD = floatArrayOf(
        0.26862954f,
        0.26130258f,
        0.27577711f
    )

    fun loadAsTensor(
        context: Context,
        uri: Uri
    ): Tensor? {
        return try {
            val bitmap = loadAndResizeBitmap(context, uri) ?: return null
            val tensor = bitmapToTensor(bitmap)
            bitmap.recycle()
            tensor
        } catch (e: Exception) {
            null
        }
    }

    fun bitmapToTensor(bitmap: Bitmap): Tensor {
        val scaled = if (bitmap.width == IMAGE_SIZE && bitmap.height == IMAGE_SIZE) {
            bitmap
        } else {
            Bitmap.createScaledBitmap(bitmap, IMAGE_SIZE, IMAGE_SIZE, true)
        }

        val tensor = TensorImageUtils.bitmapToFloat32Tensor(
            scaled,
            MEAN,
            STD
        )

        // Only recycle the scaled copy, never the original passed in
        if (scaled !== bitmap) {
            scaled.recycle()
        }

        return tensor
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

                val finalBitmap = Bitmap.createScaledBitmap(
                    sampledBitmap,
                    IMAGE_SIZE,
                    IMAGE_SIZE,
                    true
                )

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