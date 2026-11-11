package dev.raseel.lostandfound.core.media

import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.os.Build
import dev.raseel.lostandfound.MainActivity
import dev.raseel.lostandfound.core.native.FeatureChannel
import dev.raseel.lostandfound.features.library.VideoFrameExtractor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream


class MediaChannel(activity: MainActivity) : FeatureChannel(activity) {

    /**
     * The cap on the longest side of a compressed load (loadImageBytes, loadVideoThumbnail), which backs only a grid
     * thumbnail or a phone-sized full-screen view. It is well above a normal tile so the picture stays sharp. The
     * bigger bento tiles ask for one of the caps below through the optional "maxDimension" argument.
     */
    private val MAX_COMPRESSED_DIMENSION = 1600
    /** The cap for the bento grid's 2-cell wide or tall filler tiles, a little bigger than a normal tile. */
    private val MAX_COMPRESSED_DIMENSION_WIDE = 1900
    /** The cap for the bento grid's 2x2 hero tile, bigger than a normal tile but far below the showcase cap. */
    private val MAX_COMPRESSED_DIMENSION_HERO = 2200
    /**
     * The cap for the bento grid's 8 and 16 slot showcase tiles (search_results.dart decides which). Only a handful of
     * these decode per screen, so the high cap costs little, unlike the default that every grid thumbnail shares.
     */
    private val MAX_COMPRESSED_DIMENSION_SHOWCASE = 3200
    private fun videoEnvMap(): Map<String, Any> {
        val powerSave = try {
            (getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager).isPowerSaveMode
        } catch (_: Exception) {
            false
        }
        return mapOf("powerSave" to powerSave, "maxDecoders" to hardwareVideoDecoders)
    }
    /**
     * How many H.264 hardware decoders can run at once, looked up once because it walks every codec of the phone.
     * Software decoders are left out because they claim to run dozens at once, which would make a weak phone look
     * strong.
     */
    private val hardwareVideoDecoders: Int by lazy {
        var decoders = 1
        try {
            for (info in android.media.MediaCodecList(android.media.MediaCodecList.REGULAR_CODECS).codecInfos) {
                if (info.isEncoder || !info.supportedTypes.any { it.equals("video/avc", ignoreCase = true) }) continue
                val software = if (Build.VERSION.SDK_INT >= 29) {
                    !info.isHardwareAccelerated || info.isSoftwareOnly
                } else {
                    info.name.startsWith("OMX.google.") || info.name.startsWith("c2.android.")
                }
                if (software) continue
                val n = info.getCapabilitiesForType("video/avc").maxSupportedInstances
                if (n > decoders) decoders = n
            }
        } catch (_: Exception) {
        }
        decoders
    }

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {

            "loadImageBytes" -> {
                val uriString    = call.argument<String>("uri")
                val shouldCompress = call.argument<Boolean>("compress") ?: true
                val maxDimension = ((call.argument<Number>("maxDimension"))?.toInt()
                    ?: MAX_COMPRESSED_DIMENSION).coerceAtLeast(1)

                if (uriString == null) {
                    result.error("NO_URI", "URI missing", null)
                    return true
                }

                thumbnailExecutor.execute {
                    try {
                        val uri = android.net.Uri.parse(uriString)

                        val bitmap = if (shouldCompress) {
                            decodeSampledBitmap(uri, maxDimension)
                        } else {
                            contentResolver.openInputStream(uri)?.use {
                                BitmapFactory.decodeStream(it)
                            }
                        } ?: throw Exception("Cannot decode image")

                        val output = ByteArrayOutputStream()
                        if (shouldCompress) {
                            bitmap.compress(
                                android.graphics.Bitmap.CompressFormat.JPEG, 85, output
                            )
                        } else {
                            bitmap.compress(
                                android.graphics.Bitmap.CompressFormat.PNG, 100, output
                            )
                        }
                        bitmap.recycle()

                        runOnUiThread { result.success(output.toByteArray()) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("LOAD_FAILED", e.message, null)
                        }
                    }
                }
            }

            "videoEnv" -> result.success(videoEnvMap())

            "loadThumbnail" -> {
                val uriString   = call.argument<String>("uri")
                val isVideo     = call.argument<Boolean>("isVideo") ?: false
                val timestampMs = (call.argument<Number>("timestampMs") ?: 0).toLong()
                val size        = (call.argument<Number>("size") ?: 400).toInt()

                if (uriString == null) {
                    result.error("NO_URI", "URI missing", null)
                    return true
                }

                thumbnailExecutor.execute {
                    try {
                        val uri = android.net.Uri.parse(uriString)
                        val bitmap: android.graphics.Bitmap = if (isVideo) {
                            synchronized(VideoFrameExtractor.decodeLock) {
                                val retriever = MediaMetadataRetriever()
                                try {
                                    retriever.setDataSource(this, uri)
                                    val maybeFrame: android.graphics.Bitmap? = if (android.os.Build.VERSION.SDK_INT >= 27) {
                                        // The target size is given per axis, so it is worked out from the video's
                                        // own shape after rotation to keep the frame undistorted.
                                        fun meta(key: Int) = retriever.extractMetadata(key)?.toIntOrNull() ?: 0
                                        var vw = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                                        var vh = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                                        val rotation = meta(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                                        if (rotation == 90 || rotation == 270) { val t = vw; vw = vh; vh = t }
                                        val longest = maxOf(vw, vh)
                                        if (longest > size) {
                                            val k = size.toFloat() / longest
                                            retriever.getScaledFrameAtTime(
                                                timestampMs * 1000L,
                                                MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                                                (vw * k).toInt().coerceAtLeast(1),
                                                (vh * k).toInt().coerceAtLeast(1)
                                            )
                                        } else {
                                            retriever.getFrameAtTime(
                                                timestampMs * 1000L,
                                                MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                                            )
                                        }
                                    } else {
                                        retriever.getFrameAtTime(
                                            timestampMs * 1000L,
                                            MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                                        )
                                    }
                                    val frame = maybeFrame ?: throw Exception("Frame extraction failed")
                                    val scaled = capBitmapDimension(frame, size)
                                    if (scaled !== frame) frame.recycle()
                                    scaled
                                } finally {
                                    try { retriever.release() } catch (_: Exception) {}
                                }
                            }
                        } else {
                            decodeSampledBitmap(uri, size)
                                ?: throw Exception("Cannot decode image")
                        }

                        val scaled = capBitmapDimension(bitmap, size)
                        val output = ByteArrayOutputStream()
                        scaled.compress(android.graphics.Bitmap.CompressFormat.JPEG, 82, output)
                        if (scaled !== bitmap) bitmap.recycle()
                        scaled.recycle()

                        runOnUiThread { result.success(output.toByteArray()) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("LOAD_FAILED", e.message, null) }
                    }
                }
            }

            "loadVideoThumbnail" -> {
                val uriString   = call.argument<String>("uri")
                val timestampMs = (call.argument<Number>("timestampMs") ?: 0).toLong()
                val maxDimension = ((call.argument<Number>("maxDimension"))?.toInt()
                    ?: MAX_COMPRESSED_DIMENSION).coerceAtLeast(1)

                if (uriString == null) {
                    result.error("NO_URI", "URI missing", null)
                    return true
                }

                searchExecutor.execute {
                    try {
                        val uri = android.net.Uri.parse(uriString)

                        // Takes the decode lock: a scan decoding another video at the same time can exhaust the
                        // few hardware decoder sessions, and one of the two then fails silently.
                        val bytes = synchronized(VideoFrameExtractor.decodeLock) {
                            val retriever = MediaMetadataRetriever()
                            try {
                                retriever.setDataSource(this, uri)

                                val bitmap = retriever.getFrameAtTime(
                                    timestampMs * 1000L,
                                    MediaMetadataRetriever.OPTION_CLOSEST_SYNC
                                ) ?: throw Exception("Frame extraction failed")
                                // A frame comes out at the video's own resolution, so it is capped after decoding.
                                // MediaMetadataRetriever has no sampling hint.
                                val scaled = capBitmapDimension(bitmap, maxDimension)

                                val output = ByteArrayOutputStream()
                                scaled.compress(
                                    android.graphics.Bitmap.CompressFormat.JPEG, 85, output
                                )
                                if (scaled !== bitmap) bitmap.recycle()
                                scaled.recycle()
                                output.toByteArray()
                            } finally {
                                try { retriever.release() } catch (_: Exception) {}
                            }
                        }

                        runOnUiThread { result.success(bytes) }
                    } catch (e: Exception) {
                        runOnUiThread {
                            result.error("THUMBNAIL_FAILED", e.message, null)
                        }
                    }
                }
            }

            else -> return false
        }
        return true
    }
}
