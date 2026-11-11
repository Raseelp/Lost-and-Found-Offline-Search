package dev.raseel.lostandfound.core.native

import android.app.Activity
import android.content.ContextWrapper
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * One feature's share of the method channel. [handle] answers the calls the feature owns and returns false for any
 * other, so the activity can offer a call to each feature in turn. It is a Context (the activity's) so the code moved
 * out of the activity keeps using contentResolver, applicationContext and the rest unchanged.
 */
abstract class FeatureChannel(protected val activity: Activity) : ContextWrapper(activity) {

    abstract fun handle(call: MethodCall, result: MethodChannel.Result): Boolean

    /** Event channels the feature streams on. Called once, when the engine is set up. */
    open fun registerStreams(messenger: BinaryMessenger) {}

    internal fun runOnUiThread(block: () -> Unit) = activity.runOnUiThread(block)

    internal val executor get() = NativeExecutors.executor
    internal val downloadExecutor get() = NativeExecutors.downloadExecutor
    internal val searchExecutor get() = NativeExecutors.searchExecutor
    internal val thumbnailExecutor get() = NativeExecutors.thumbnailExecutor
    internal val faceCropExecutor get() = NativeExecutors.faceCropExecutor
    internal val exportExecutor get() = NativeExecutors.exportExecutor
    internal val faceExecutor get() = NativeExecutors.faceExecutor
    internal val memoryExecutor get() = NativeExecutors.memoryExecutor
    internal val logExecutor get() = NativeExecutors.logExecutor
    internal val photoFacesExecutor get() = NativeExecutors.photoFacesExecutor
    internal val videoScanExecutor get() = NativeExecutors.videoScanExecutor

    /**
     * Loads a bitmap sampled down to [maxDimension]. It reads the dimensions first (inJustDecodeBounds), picks a
     * power-of-two sample size, then decodes at the reduced size. That costs one extra stream open but never allocates
     * a full-resolution bitmap just to shrink it, which matters for a photo of thousands of pixels shown in a small
     * tile.
     */
    protected fun decodeSampledBitmap(uri: android.net.Uri, maxDimension: Int): android.graphics.Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        // Failure is judged by whether the stream opened, because a bounds-only decode always returns a null bitmap.
        val boundsStream = contentResolver.openInputStream(uri) ?: return null
        boundsStream.use { BitmapFactory.decodeStream(it, null, bounds) }

        var sampleSize = 1
        val longestSide = maxOf(bounds.outWidth, bounds.outHeight)
        if (longestSide > 0) {
            while (longestSide / sampleSize > maxDimension) {
                sampleSize *= 2
            }
        }

        val decodeOptions = BitmapFactory.Options().apply { inSampleSize = sampleSize }
        return contentResolver.openInputStream(uri)?.use {
            BitmapFactory.decodeStream(it, null, decodeOptions)
        }
    }

    /**
     * Scales down only if needed, otherwise returns the same bitmap. For where the decode itself cannot be sampled
     * down, a video frame from MediaMetadataRetriever, unlike decodeSampledBitmap, which avoids the full-size
     * allocation.
     */
    protected fun capBitmapDimension(
        bitmap: android.graphics.Bitmap,
        maxDimension: Int
    ): android.graphics.Bitmap {
        val longestSide = maxOf(bitmap.width, bitmap.height)
        if (longestSide <= maxDimension) return bitmap
        val scale = maxDimension.toFloat() / longestSide
        val targetWidth = (bitmap.width * scale).toInt().coerceAtLeast(1)
        val targetHeight = (bitmap.height * scale).toInt().coerceAtLeast(1)
        return android.graphics.Bitmap.createScaledBitmap(bitmap, targetWidth, targetHeight, true)
    }
}
