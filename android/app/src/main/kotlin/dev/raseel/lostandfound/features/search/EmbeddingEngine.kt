package dev.raseel.lostandfound.features.search

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.net.Uri
import dev.raseel.lostandfound.features.model_download.ModelCatalog
import dev.raseel.lostandfound.features.model_download.ModelManager
import dev.raseel.lostandfound.features.model_download.ModelsNotReadyException
import dev.raseel.lostandfound.core.storage.EmbeddingRecord
import dev.raseel.lostandfound.core.storage.EmbeddingStore
import dev.raseel.lostandfound.core.storage.HashUtils
import androidx.documentfile.provider.DocumentFile
import android.provider.DocumentsContract
import android.util.Log
import java.nio.FloatBuffer
import java.nio.LongBuffer
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.Future
import dev.raseel.lostandfound.features.library.FolderMediaStoreScan
import dev.raseel.lostandfound.features.library.ImageSource
import dev.raseel.lostandfound.features.library.IndexedImage
import dev.raseel.lostandfound.features.library.IndexedVideo
import dev.raseel.lostandfound.features.library.LatestScan
import dev.raseel.lostandfound.features.library.RecentEmbeddedItem
import dev.raseel.lostandfound.features.library.SafUtils
import dev.raseel.lostandfound.features.library.ScanHandoff
import dev.raseel.lostandfound.features.library.ScanProgress
import dev.raseel.lostandfound.features.library.ScanResult
import dev.raseel.lostandfound.features.library.VideoFrameExtractor
import dev.raseel.lostandfound.features.library.VideoSource
import dev.raseel.lostandfound.features.settings.BenchLog


class EmbeddingEngine(
    private val context: Context,
    private val modelManager: ModelManager
) {

    private val ortEnv: OrtEnvironment = OrtEnvironment.getEnvironment()

    /** The model sessions load lazily. Call [ensureModelsLoaded] before using them. */
    private var visionSession: OrtSession? = null
    private var textSession: OrtSession? = null
    /** What the image model runs on ("xnnpack x6", or "cpu" after a fallback). Only the performance logs use it. */
    private var visionBackend = "not loaded"
    private val store: EmbeddingStore

    /**
     * Serializes every run() on the vision session, which is not safe to call from two threads at once. Search runs
     * alongside a scan and image search shares the session with scanning. Only the call itself is locked, so a wait is
     * at most one batch of inference.
     */
    private val visionLock = Any()
    private val textLock = Any()

    private var lastEmit: Long = 0L
    private var startTimeMs: Long = 0L

    /**
     * The photos and videos of the current scan, and how many videos were already indexed. The photos are done before
     * the videos and everything already indexed counts as done from the start, so how far each has got follows from
     * these and the number processed (see [kindsDone]).
     */
    private var kindPhotos = 0
    private var kindVideos = 0
    private var kindVideosKnown = 0

    /** How many photos and how many videos of this scan are done, when [processed] items are. */
    private fun kindsDone(processed: Int): Pair<Int, Int> {
        val photos = (processed - kindVideosKnown).coerceIn(0, kindPhotos)
        val videos = (processed - photos).coerceIn(0, kindVideos)
        return photos to videos
    }

    /** How long this scan has spent waiting for the photos it handed over (see [handOver]). */
    @Volatile
    private var pausedMs: Long = 0L

    /**
     * Where indexing's time goes, for the performance logs (see [BenchLog]). Each report prints what has gathered
     * since the last one and starts over.
     */
    private class ClipTiming {
        /** Written by the decode threads, several at once. */
        val decodeNs = AtomicLong()
        val decoded = AtomicInteger()

        /** Written by the scan thread. */
        var waitDecodeNs = 0L
        var inferNs = 0L
        var writeNs = 0L
        var images = 0
        var chunks = 0
        var startedAt = System.currentTimeMillis()
        var pausedAtStart = 0L
    }

    @Volatile
    private var clipTiming = ClipTiming()

    private fun reportClip(reason: String) {
        val t = clipTiming
        clipTiming = ClipTiming().also { it.pausedAtStart = pausedMs }
        if (t.images == 0) return
        BenchLog.log(context) {
            val wallMs = System.currentTimeMillis() - t.startedAt
            val facesMs = pausedMs - t.pausedAtStart
            val activeMs = (wallMs - facesMs).coerceAtLeast(1L)
            fun ms(ns: Long, per: Int) = if (per <= 0) 0 else (ns / 1_000_000 / per).toInt()
            val waiting = if (facesMs > 0) " (+${"%.1f".format(facesMs / 1000.0)}s waiting for faces)" else ""
            "clip [$reason]: ${t.images} images in ${"%.1f".format(activeMs / 1000.0)}s = " +
                "${"%.1f".format(t.images * 1000.0 / activeMs)}/s$waiting | per image: " +
                "decode ${ms(t.decodeNs.get(), t.decoded.get())}ms (on $PREP_THREAD_COUNT threads), " +
                "infer ${ms(t.inferNs, t.images)}ms, waited-on-decode ${ms(t.waitDecodeNs, t.images)}ms, " +
                "index-write ${ms(t.writeNs, t.images)}ms | ${t.chunks} chunks of $INFERENCE_BATCH_SIZE | " +
                BenchLog.device(context)
        }
    }

    @Volatile
    private var isCancelled = false

    /**
     * The most recently embedded files, newest first, for the recently indexed strip. Only the scan's own thread
     * touches it, so it needs no lock.
     */
    private val recentItems = ArrayDeque<RecentEmbeddedItem>()

    private fun recordRecent(item: RecentEmbeddedItem) {
        recentItems.addFirst(item)
        while (recentItems.size > RECENT_WINDOW_SIZE) recentItems.removeLast()
    }

    companion object {
        private const val TAG = "EmbeddingEngine"
        private const val PROGRESS_INTERVAL_MS = 500L

        /**
         * How many images go into one forward() call, and how many decode threads prepare tensors ahead of the
         * inference thread. Not measured on real devices yet, so they may need tuning.
         */
        private const val INFERENCE_BATCH_SIZE = 4
        private const val PREP_THREAD_COUNT = 2

        private const val RECENT_WINDOW_SIZE = 10

        /**
         * Performance logs (see [BenchLog]) print a CLIP line every this many images, and a hand-over to the face scan
         * gets its own line only if it took this long.
         */
        private const val BENCH_REPORT_EVERY_IMAGES = 40
        private const val BENCH_BATCH_MIN_MS = 1000L

        /** Named on the timing lines of the performance logs, so numbers from different models are not mixed up. */
        private const val MODEL_LABEL = "mobileclip-s0(vision fp32, text int8)"

        private const val ENGINE_PREFS = "embedding_engine"

        /** Set while the image model is being set up on XNNPACK and cleared when that worked. See [createVisionSession]. */
        private const val KEY_XNNPACK_TRYING = "xnnpack_trying"

        /**
         * The most threads the image model uses. On a phone with 2 fast and 6 slow cores, a scan took 303 ms per photo
         * with 6 threads, against 327 with 8 and 374 with 4, while photos decoded on 2 other threads.
         */
        private const val VISION_THREADS_MAX = 6

        /** Side of the square input. Every image array is exactly 3x256x256 (see [ImagePreprocessor]), so batching does not check lengths. */
        private const val VISION_INPUT_SIZE = 256
    }

    init {
        store = EmbeddingStore(context)
    }

    /**
     * Loads the image and text sessions if they are not loaded yet. Throws [ModelsNotReadyException] when the download
     * has not finished. Dart checks areModelsReady() first, so this is only the backstop.
     */
    @Synchronized
    private fun ensureModelsLoaded() {
        if (visionSession != null && textSession != null) return

        if (!modelManager.areModelsReady()) {
            throw ModelsNotReadyException("CLIP models are not downloaded yet")
        }

        if (visionSession == null) {
            val visionModel = ModelCatalog.MODELS.first { it.id == "vision" }
            val startedNs = System.nanoTime()
            visionSession = createVisionSession(modelManager.localFile(visionModel).absolutePath)
            BenchLog.log(context) {
                "model loaded: $MODEL_LABEL vision (${visionModel.sizeBytes / 1_000_000} MB, on $visionBackend) in " +
                    "${(System.nanoTime() - startedNs) / 1_000_000}ms"
            }
        }
        if (textSession == null) {
            val textModel = ModelCatalog.MODELS.first { it.id == "text" }
            val startedNs = System.nanoTime()
            textSession = ortEnv.createSession(
                modelManager.localFile(textModel).absolutePath,
                OrtSession.SessionOptions()
            )
            BenchLog.log(context) {
                "model loaded: $MODEL_LABEL text (${textModel.sizeBytes / 1_000_000} MB) in " +
                    "${(System.nanoTime() - startedNs) / 1_000_000}ms"
            }
        }
    }

    /**
     * Creates the image model session on XNNPACK, ONNX Runtime's fast CPU kernels, with a plain CPU fallback. The
     * runtime can abort the whole process during XNNPACK setup, which cannot be caught, so a marker is written before
     * the try and cleared after it. A marker still there means the last try never came back and is not repeated.
     */
    private fun createVisionSession(path: String): OrtSession {
        val prefs = context.getSharedPreferences(ENGINE_PREFS, Context.MODE_PRIVATE)
        if (prefs.getBoolean(KEY_XNNPACK_TRYING, false)) {
            Log.w(TAG, "the last try at XNNPACK never came back, using the plain CPU path")
        } else {
            val threads = Runtime.getRuntime().availableProcessors().coerceIn(2, VISION_THREADS_MAX)
            prefs.edit().putBoolean(KEY_XNNPACK_TRYING, true).commit()
            try {
                val session = OrtSession.SessionOptions().use { options ->
                    options.setIntraOpNumThreads(1)
                    options.addXnnpack(mapOf("intra_op_num_threads" to threads.toString()))
                    ortEnv.createSession(path, options)
                }
                visionBackend = "xnnpack x$threads"
                prefs.edit().putBoolean(KEY_XNNPACK_TRYING, false).apply()
                return session
            } catch (e: Exception) {
                Log.w(TAG, "XNNPACK is not available (${e.message}), using the plain CPU path", e)
                prefs.edit().putBoolean(KEY_XNNPACK_TRYING, false).apply()
            }
        }
        visionBackend = "cpu"
        return OrtSession.SessionOptions().use { ortEnv.createSession(path, it) }
    }

    /** True if the last scan was stopped by the user rather than running to its end. */
    fun wasCancelled(): Boolean = isCancelled

    fun cancelEmbedding() {
        isCancelled = true
    }

    /**
     * Encodes 77 tokens into a text embedding. It runs under [textLock] because a session is not safe to run from two
     * threads, and text encoding happens off the main thread, so calls can overlap.
     */
    fun encodeText(tokens: IntArray): FloatArray {
        require(tokens.size == 77) { "Expected 77 tokens, got ${tokens.size}" }

        ensureModelsLoaded()
        val text = textSession!!

        val longs = LongArray(77) { tokens[it].toLong() }

        return synchronized(textLock) {
            OnnxTensor.createTensor(ortEnv, LongBuffer.wrap(longs), longArrayOf(1, 77)).use { tensor ->
                text.run(mapOf(text.inputNames.first() to tensor)).use { result ->
                    val buffer = (result[0] as OnnxTensor).floatBuffer
                    val out = FloatArray(buffer.remaining())
                    buffer.get(out)
                    check(EmbeddingMath.isFinite(out)) { "The text model gave NaN or infinite numbers" }
                    out
                }
            }
        }
    }

    /**
     * Embeds the photos and videos of the device or of one folder that are not in the store yet, and reports progress.
     * Files already in the store are filtered out first, so a resumed scan jumps to the done count. The rest is
     * shuffled, because an interrupted scan would otherwise leave search with only the slice embedded first.
     */
    fun embedImages(
        mode: String,
        folderUriString: String?,
        folderId: String,
        contentMode: String = "both",
        onProgress: (ScanProgress) -> Unit
    ): ScanResult {

        isCancelled = false
        startTimeMs = System.currentTimeMillis()
        lastEmit = startTimeMs
        pausedMs = 0L
        kindPhotos = 0
        kindVideos = 0
        kindVideosKnown = 0
        clipTiming = ClipTiming()
        recentItems.clear()
        BenchLog.log(context) {
            "scan start: mode=$mode contentMode=$contentMode cpus=${Runtime.getRuntime().availableProcessors()} " +
                "clip=$MODEL_LABEL chunk=$INFERENCE_BATCH_SIZE decodeThreads=$PREP_THREAD_COUNT | " +
                BenchLog.device(context)
        }
        Log.d(TAG, "embedImages: start — mode=$mode contentMode=$contentMode")

        ensureModelsLoaded()
        val vision = visionSession!!

        onProgress(
            ScanProgress(
                total = 0, processed = 0, embedded = 0,
                skipped = 0, elapsedMs = 0, done = false,
                path = "Preparing..."
            )
        )

        val scanImages = contentMode == "images" || contentMode == "both"
        val scanVideos = contentMode == "videos" || contentMode == "both"

        val imageFiles: List<ImageSource>
        val videoFiles: List<VideoSource>
        val label: String

        val runtime = Runtime.getRuntime()

        if (mode == "device") {

            Log.d(TAG, "embedImages: loading device images (scanImages=$scanImages)...")
            imageFiles = if (scanImages) {
                getAllDeviceImages().also {
                    Log.d(TAG, "embedImages: got ${it.size} images, mem=${
                        (runtime.totalMemory() - runtime.freeMemory()) / 1_048_576}MB")
                }
            } else emptyList()

            Log.d(TAG, "embedImages: loading device videos (scanVideos=$scanVideos)...")
            videoFiles = if (scanVideos) {
                getAllDeviceVideos().also {
                    Log.d(TAG, "embedImages: got ${it.size} videos, mem=${
                        (runtime.totalMemory() - runtime.freeMemory()) / 1_048_576}MB")
                }
            } else emptyList()

            label = "Full device scan"

        } else {
            val folderUri = Uri.parse(folderUriString!!)
            val label0 = getDisplayPath(folderUriString)

            var foundSoFar = 0
            val onFileFound: () -> Unit = {
                foundSoFar++
                val now = System.currentTimeMillis()
                if (now - lastEmit > PROGRESS_INTERVAL_MS) {
                    onProgress(
                        ScanProgress(
                            total = 0, processed = 0, embedded = 0, skipped = 0,
                            elapsedMs = now - startTimeMs,
                            done = false,
                            path = "Found $foundSoFar files so far"
                        )
                    )
                    lastEmit = now
                }
            }

            imageFiles = if (scanImages) getFolderImages(folderUri, onFileFound) else emptyList()
            videoFiles = if (scanVideos && !isCancelled) {
                getFolderVideos(folderUri, onFileFound)
            } else emptyList()
            label = label0
        }

        if (isCancelled) {
            onProgress(
                ScanProgress(
                    total = 0, processed = 0, embedded = 0, skipped = 0,
                    elapsedMs = System.currentTimeMillis() - startTimeMs,
                    done = true, path = label
                )
            )
            return ScanResult(0, 0, 0)
        }

        val total = imageFiles.size + videoFiles.size
        Log.d(TAG, "embedImages: total files to process = $total (${imageFiles.size} images + ${videoFiles.size} videos)")

        Log.d(TAG, "embedImages: reading existing hashes from store...")
        val existingHashes = try {
            store.readAll().map { it.hash }.toHashSet().also {
                Log.d(TAG, "embedImages: loaded ${it.size} existing hashes, mem=${
                    (runtime.totalMemory() - runtime.freeMemory()) / 1_048_576}MB")
            }
        } catch (e: Exception) {
            Log.e(TAG, "embedImages: FAILED reading existing hashes — ${e.message}", e)
            hashSetOf()
        }

        var processed = 0
        var embedded = 0
        var skipped = 0
        var failed = 0

        val newImages = mutableListOf<ImageSource>()
        for (img in imageFiles) {
            try {
                val hash = HashUtils.identityHash(img.size, img.lastModified, img.name)
                if (existingHashes.contains(hash)) skipped++ else newImages.add(img)
            } catch (e: Exception) {
                skipped++
                failed++
            }
        }
        val newVideos = mutableListOf<VideoSource>()
        for (video in videoFiles) {
            try {
                val hash = HashUtils.identityHash(video.size, video.lastModified, video.name)
                if (existingHashes.contains(hash)) skipped++ else newVideos.add(video)
            } catch (e: Exception) {
                skipped++
                failed++
            }
        }
        kindPhotos = imageFiles.size
        kindVideos = videoFiles.size
        kindVideosKnown = videoFiles.size - newVideos.size
        processed += skipped
        if (skipped > 0) {
            lastEmit = 0L
            emitProgressIfNeeded(total, processed, embedded, skipped, failed, label, onProgress)
        }

        val batchSize = 10
        val batch = mutableListOf<EmbeddingRecord>()

        val prepPool = Executors.newFixedThreadPool(PREP_THREAD_COUNT)
        try {
            data class PendingChunk(
                val toEmbed: List<Pair<ImageSource, Long>>,
                val futures: List<Future<FloatArray?>>
            )

            fun submitChunk(chunk: List<ImageSource>): PendingChunk {
                val toEmbed = mutableListOf<Pair<ImageSource, Long>>()
                for (img in chunk) {
                    try {
                        val hash = HashUtils.identityHash(img.size, img.lastModified, img.name)
                        if (existingHashes.contains(hash)) {
                            skipped++
                        } else {
                            // Claimed here, not after the embed: two chunks decoding at once must never embed the same
                            // hash.
                            existingHashes.add(hash)
                            toEmbed.add(img to hash)
                        }
                    } catch (e: Exception) {
                        skipped++
                failed++
                    }
                }
                val futures = toEmbed.map { (img, _) ->
                    prepPool.submit(Callable {
                        val decodeStartedNs = System.nanoTime()
                        val prepared = try { ImagePreprocessor.loadAsFloatArray(context, img.uri) } catch (e: Exception) { null }
                        clipTiming.decodeNs.addAndGet(System.nanoTime() - decodeStartedNs)
                        clipTiming.decoded.incrementAndGet()
                        prepared
                    })
                }
                return PendingChunk(toEmbed, futures)
            }

            val chunks = newImages.shuffled().chunked(INFERENCE_BATCH_SIZE)
            var prefetched: PendingChunk? = null

            for (chunkIndex in chunks.indices) {
                if (isCancelled) break

                val chunk = chunks[chunkIndex]
                val current = prefetched ?: submitChunk(chunk)
                prefetched = if (chunkIndex + 1 < chunks.size && !isCancelled) {
                    submitChunk(chunks[chunkIndex + 1])
                } else null

                val tensors = mutableListOf<FloatArray>()
                val meta = mutableListOf<Pair<ImageSource, Long>>()
                val waitStartedNs = System.nanoTime()
                for ((idx, pair) in current.toEmbed.withIndex()) {
                    val tensor = try { current.futures[idx].get() } catch (e: Exception) { null }
                    if (tensor == null) {
                        skipped++
                failed++
                    } else {
                        tensors.add(tensor)
                        meta.add(pair)
                    }
                }

                clipTiming.waitDecodeNs += System.nanoTime() - waitStartedNs

                if (tensors.isNotEmpty()) {
                    val inferStartedNs = System.nanoTime()
                    val embeddings = runBatchedInference(vision, tensors)
                    clipTiming.inferNs += System.nanoTime() - inferStartedNs
                    clipTiming.images += tensors.size
                    clipTiming.chunks++
                    if (clipTiming.images >= BENCH_REPORT_EVERY_IMAGES) reportClip("periodic")
                    for ((idx, pair) in meta.withIndex()) {
                        val embedding = embeddings[idx]
                        if (embedding == null) {
                            skipped++
                failed++
                        } else {
                            val (img, hash) = pair
                            batch.add(
                                EmbeddingRecord(
                                    imagePath = img.uri.toString(),
                                    hash = hash,
                                    embedding = embedding,
                                    folderId = folderId
                                )
                            )
                            embedded++
                            recordRecent(
                                RecentEmbeddedItem(
                                    uri = img.uri.toString(),
                                    isVideo = false,
                                    timestampMs = 0L
                                )
                            )
                            if (batch.size >= batchSize) {
                                commitBatch(batch)
                            }
                        }
                    }
                }

                processed += chunk.size
                emitProgressIfNeeded(total, processed, embedded, skipped, failed, label, onProgress)
            }

            if (isCancelled && batch.isNotEmpty()) {
                commitBatch(batch)
            }
        } finally {
            prepPool.shutdownNow()
        }

        if (!isCancelled) {
            for (video in newVideos.shuffled()) {

                if (isCancelled) {
                    if (batch.isNotEmpty()) commitBatch(batch)
                    break
                }

                try {
                    val hash = HashUtils.identityHash(video.size, video.lastModified, video.name)

                    if (existingHashes.contains(hash)) {
                        skipped++
                    } else {
                        val frameRecords = embedVideoFile(
                            video = video,
                            hash = hash,
                            folderId = folderId,
                            vision = vision
                        )

                        if (frameRecords.isEmpty()) {
                            skipped++
                failed++
                        } else {
                            batch.addAll(frameRecords)
                            existingHashes.add(hash)
                            embedded += frameRecords.size
                            recordRecent(
                                RecentEmbeddedItem(
                                    uri = video.uri.toString(),
                                    isVideo = true,
                                    timestampMs = frameRecords.first().timestampMs,
                                    frames = frameRecords.size
                                )
                            )

                            if (batch.size >= batchSize) {
                                commitBatch(batch)
                            }
                        }
                    }
                } catch (e: Exception) {
                    skipped++
                failed++
                }

                processed++
                emitProgressIfNeeded(total, processed, embedded, skipped, failed, label, onProgress)
            }
        }

        if (batch.isNotEmpty()) commitBatch(batch)

        val elapsed = System.currentTimeMillis() - startTimeMs
        reportClip("scan end")
        BenchLog.log(context) {
            "scan end: $embedded embedded, $skipped skipped in ${"%.1f".format(elapsed / 1000.0)}s " +
                "(${"%.1f".format(pausedMs / 1000.0)}s of it waiting for faces) | " +
                BenchLog.device(context)
        }

        onProgress(
            ScanProgress(
                total = total,
                processed = processed,
                embedded = embedded,
                skipped = skipped,
                elapsedMs = elapsed,
                activeMs = elapsed - pausedMs,
                done = true,
                path = label,
                recentItems = recentItems.toList(),
                failed = failed,
                photos = kindPhotos,
                videos = kindVideos,
                photosDone = kindsDone(processed).first,
                videosDone = kindsDone(processed).second,
            )
        )

        return ScanResult(total, embedded, skipped)
    }

    /**
     * Writes a batch to the index and clears it, then offers the photos in it to whoever works alongside this scan
     * (the face scan; videos are left out, it does those in its own later pass). The items are added to [LatestScan],
     * and a video's frames all share its uri.
     */
    private fun commitBatch(batch: MutableList<EmbeddingRecord>) {
        val writeStartedNs = System.nanoTime()
        store.appendBatch(batch)
        clipTiming.writeNs += System.nanoTime() - writeStartedNs
        val photos = batch.filter { it.videoUri == null }.map { IndexedImage(it.hash, it.imagePath) }
        LatestScan.add(batch.map { it.imagePath })
        batch.clear()
        handOver(photos)
    }

    /**
     * Offers photos to the consumer of [ScanHandoff]. The consumer may take a good while (finding the faces in a
     * batch), and this scan simply waits, so the two do not compete. That time is counted so the speed shown for
     * indexing is indexing's own (see [ScanProgress.activeMs]), and a failure over there never becomes this scan's.
     * After a long wait, [reportClip] prints what indexing did since the last line, ending right before the wait.
     */
    private fun handOver(photos: List<IndexedImage>) {
        val consumer = ScanHandoff.consumer ?: return
        if (photos.isEmpty()) return
        val startedAt = System.currentTimeMillis()
        try {
            consumer.onIndexed(photos) { isCancelled }
        } catch (e: Exception) {
            Log.w(TAG, "handOver: the consumer failed (${e.message})", e)
        } catch (e: OutOfMemoryError) {
            Log.w(TAG, "handOver: the consumer ran out of memory", e)
        }
        val tookMs = System.currentTimeMillis() - startedAt
        pausedMs += tookMs
        if (tookMs >= BENCH_BATCH_MIN_MS) {
            BenchLog.log(context) { "handoff: indexing waited ${tookMs}ms for the faces of a batch" }
            reportClip("before faces")
        }
    }

    /**
     * Embeds the frames of one video. All frames are extracted before this point, so one batched call covers them
     * and no pipelining is needed.
     */
    private fun embedVideoFile(
        video: VideoSource,
        hash: Long,
        folderId: String,
        vision: OrtSession
    ): List<EmbeddingRecord> {

        val videoUriString = video.uri.toString()

        val extractStartedNs = System.nanoTime()
        val frames = VideoFrameExtractor.extractFrames(
            context = context,
            uri = video.uri
        )
        val extractNs = System.nanoTime() - extractStartedNs

        if (frames.isEmpty()) return emptyList()

        val tensors = mutableListOf<FloatArray>()
        val timestamps = mutableListOf<Long>()
        val prepStartedNs = System.nanoTime()

        for ((timestampMs, bitmap) in frames) {
            try {
                tensors.add(ImagePreprocessor.bitmapToFloatArray(bitmap))
                timestamps.add(timestampMs)
            } catch (e: Exception) {
                // One bad frame does not fail the whole video.
            } finally {
                bitmap.recycle()
            }
        }

        if (tensors.isEmpty()) return emptyList()
        val prepNs = System.nanoTime() - prepStartedNs

        val inferStartedNs = System.nanoTime()
        val embeddings = runBatchedInference(vision, tensors)
        BenchLog.log(context) {
            "clip video: ${tensors.size} frames | extract ${extractNs / 1_000_000}ms, " +
                "preprocess ${prepNs / 1_000_000}ms, infer ${(System.nanoTime() - inferStartedNs) / 1_000_000}ms"
        }
        val records = mutableListOf<EmbeddingRecord>()

        for (i in tensors.indices) {
            val embedding = embeddings[i] ?: continue
            records.add(
                EmbeddingRecord(
                    imagePath   = videoUriString,
                    hash        = hash,
                    embedding   = embedding,
                    folderId    = folderId,
                    videoUri    = videoUriString,
                    timestampMs = timestamps[i]
                )
            )
        }

        return records
    }

    /**
     * One forward() call for the whole batch instead of one per tensor, to cut per-call overhead. If it fails for any
     * reason, it falls back to one tensor at a time, so it cannot crash a scan and at worst loses the speedup.
     *
     * A null in the returned list means that tensor failed and the caller skips it.
     */
    private fun runBatchedInference(vision: OrtSession, tensors: List<FloatArray>): List<FloatArray?> {
        if (tensors.isEmpty()) return emptyList()

        if (tensors.size == 1) {
            return listOf(
                try {
                    synchronized(visionLock) { runVision(vision, tensors[0], 1) }
                } catch (e: Exception) {
                    null
                }
            ).map { onlyIfFinite(it) }
        }

        val batched = try {
            val perItemFloats = 3 * VISION_INPUT_SIZE * VISION_INPUT_SIZE
            val batchedData = FloatArray(tensors.size * perItemFloats)
            for ((i, t) in tensors.withIndex()) {
                System.arraycopy(t, 0, batchedData, i * perItemFloats, perItemFloats)
            }
            val output = synchronized(visionLock) { runVision(vision, batchedData, tensors.size) }
            val embeddingDim = output.size / tensors.size
            (0 until tensors.size).map { i -> output.copyOfRange(i * embeddingDim, (i + 1) * embeddingDim) }
        } catch (e: Exception) {
            Log.w(TAG, "runBatchedInference: batched forward failed (${e.message}), falling back to one-by-one", e)
            null
        }

        if (batched != null) return batched.map { onlyIfFinite(it) }

        return tensors.map { t ->
            try {
                synchronized(visionLock) { runVision(vision, t, 1) }
            } catch (e: Exception) {
                null
            }
        }.map { onlyIfFinite(it) }
    }

    /**
     * Returns [embedding] unless it holds a NaN or infinite number, which would be stored and then rank every search
     * the same (an image model that overflowed on one phone did this). Such an image counts as failed: it is skipped
     * and tried again by the next scan.
     */
    private fun onlyIfFinite(embedding: FloatArray?): FloatArray? {
        if (embedding == null || EmbeddingMath.isFinite(embedding)) return embedding
        Log.w(TAG, "the image model gave NaN or infinite numbers; the image is skipped")
        return null
    }

    /**
     * Runs a batch of [n] items (1 for a single one) through the vision model and returns the flat output. It is the
     * one place that builds the input tensor, runs the session and reads the result.
     */
    private fun runVision(session: OrtSession, data: FloatArray, n: Int): FloatArray {
        val shape = longArrayOf(n.toLong(), 3L, VISION_INPUT_SIZE.toLong(), VISION_INPUT_SIZE.toLong())
        return OnnxTensor.createTensor(ortEnv, FloatBuffer.wrap(data), shape).use { tensor ->
            session.run(mapOf(session.inputNames.first() to tensor)).use { result ->
                val buffer = (result[0] as OnnxTensor).floatBuffer
                val out = FloatArray(buffer.remaining())
                buffer.get(out)
                out
            }
        }
    }


    /**
     * Lists the image files of a folder. When the folder is already in MediaStore's own index (see
     * [FolderMediaStoreScan] for when that holds), that is queried instead of walking SAF. A null or empty answer is
     * not trusted, because MediaStore can have nothing under the path of a real folder, so the verified SAF walk runs
     * instead. Checking a folder that is really empty is cheap.
     */
    private fun getFolderImages(
        folderUri: Uri,
        onFileFound: () -> Unit = {}
    ): List<ImageSource> {
        val relativePath = FolderMediaStoreScan.resolvePrimaryRelativePath(folderUri)
        if (relativePath != null) {
            val fast = FolderMediaStoreScan.queryImages(context, relativePath)
            if (!fast.isNullOrEmpty()) return fast
        }

        return SafUtils.listImageFiles(
            context, folderUri,
            isCancelled = { isCancelled },
            onFileFound = onFileFound
        ).map {
            ImageSource(
                uri = it.uri,
                size = it.size,
                lastModified = it.lastModified,
                name = it.name
            )
        }
    }

    private fun getFolderVideos(
        folderUri: Uri,
        onFileFound: () -> Unit = {}
    ): List<VideoSource> {
        val relativePath = FolderMediaStoreScan.resolvePrimaryRelativePath(folderUri)
        if (relativePath != null) {
            val fast = FolderMediaStoreScan.queryVideos(context, relativePath)
            if (!fast.isNullOrEmpty()) return fast
        }

        return SafUtils.listVideoFiles(
            context, folderUri,
            isCancelled = { isCancelled },
            onFileFound = onFileFound
        ).map {
            VideoSource(
                uri = it.uri,
                size = it.size,
                lastModified = it.lastModified,
                name = it.name
            )
        }
    }

    private fun getAllDeviceImages(): List<ImageSource> {
        val result = mutableListOf<ImageSource>()

        val collection =
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q)
                android.provider.MediaStore.Images.Media.getContentUri(
                    android.provider.MediaStore.VOLUME_EXTERNAL
                )
            else
                android.provider.MediaStore.Images.Media.EXTERNAL_CONTENT_URI

        val projection = arrayOf(
            android.provider.MediaStore.Images.Media._ID,
            android.provider.MediaStore.Images.Media.SIZE,
            android.provider.MediaStore.Images.Media.DATE_MODIFIED,
            android.provider.MediaStore.Images.Media.DISPLAY_NAME
        )

        context.contentResolver.query(
            collection, projection, null, null, null
        )?.use { cursor ->
            val idCol   = cursor.getColumnIndexOrThrow(android.provider.MediaStore.Images.Media._ID)
            val sizeCol = cursor.getColumnIndexOrThrow(android.provider.MediaStore.Images.Media.SIZE)
            val modCol  = cursor.getColumnIndexOrThrow(android.provider.MediaStore.Images.Media.DATE_MODIFIED)
            val nameCol = cursor.getColumnIndexOrThrow(android.provider.MediaStore.Images.Media.DISPLAY_NAME)

            while (cursor.moveToNext()) {
                val id  = cursor.getLong(idCol)
                val uri = android.content.ContentUris.withAppendedId(collection, id)
                result.add(
                    ImageSource(
                        uri          = uri,
                        size         = cursor.getLong(sizeCol),
                        lastModified = cursor.getLong(modCol),
                        name         = cursor.getString(nameCol) ?: ""
                    )
                )
            }
        }

        return result
    }

    private fun getAllDeviceVideos(): List<VideoSource> {
        Log.d(TAG, "getAllDeviceVideos: starting")

        val result = mutableListOf<VideoSource>()

        val collection =
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                Log.d(TAG, "getAllDeviceVideos: using VOLUME_EXTERNAL (API ${android.os.Build.VERSION.SDK_INT})")
                android.provider.MediaStore.Video.Media.getContentUri(
                    android.provider.MediaStore.VOLUME_EXTERNAL
                )
            } else {
                Log.d(TAG, "getAllDeviceVideos: using EXTERNAL_CONTENT_URI (legacy)")
                android.provider.MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            }

        val projection = arrayOf(
            android.provider.MediaStore.Video.Media._ID,
            android.provider.MediaStore.Video.Media.SIZE,
            android.provider.MediaStore.Video.Media.DATE_MODIFIED,
            android.provider.MediaStore.Video.Media.DISPLAY_NAME
        )

        Log.d(TAG, "getAllDeviceVideos: querying MediaStore...")

        val cursor = try {
            context.contentResolver.query(
                collection,
                projection,
                null,
                null,
                "${android.provider.MediaStore.Video.Media.DATE_MODIFIED} DESC"
            )
        } catch (e: Exception) {
            Log.e(TAG, "getAllDeviceVideos: query THREW EXCEPTION — ${e.javaClass.simpleName}: ${e.message}", e)
            return emptyList()
        }

        if (cursor == null) {
            Log.e(TAG, "getAllDeviceVideos: cursor is NULL — permission likely denied")
            return emptyList()
        }

        Log.d(TAG, "getAllDeviceVideos: cursor obtained, count = ${cursor.count}")

        val runtime = Runtime.getRuntime()
        val usedMemMb = (runtime.totalMemory() - runtime.freeMemory()) / 1_048_576
        val maxMemMb  = runtime.maxMemory() / 1_048_576
        Log.d(TAG, "getAllDeviceVideos: memory before list build — used=${usedMemMb}MB max=${maxMemMb}MB")

        try {
            cursor.use { c ->
                val idCol   = c.getColumnIndexOrThrow(android.provider.MediaStore.Video.Media._ID)
                val sizeCol = c.getColumnIndexOrThrow(android.provider.MediaStore.Video.Media.SIZE)
                val modCol  = c.getColumnIndexOrThrow(android.provider.MediaStore.Video.Media.DATE_MODIFIED)
                val nameCol = c.getColumnIndexOrThrow(android.provider.MediaStore.Video.Media.DISPLAY_NAME)

                var rowCount = 0

                while (c.moveToNext()) {
                    try {
                        val id  = c.getLong(idCol)
                        val uri = android.content.ContentUris.withAppendedId(collection, id)

                        result.add(
                            VideoSource(
                                uri          = uri,
                                size         = c.getLong(sizeCol),
                                lastModified = c.getLong(modCol),
                                name         = c.getString(nameCol) ?: ""
                            )
                        )

                        rowCount++

                        if (rowCount % 500 == 0) {
                            val usedNow = (runtime.totalMemory() - runtime.freeMemory()) / 1_048_576
                            Log.d(TAG, "getAllDeviceVideos: processed $rowCount rows, used=${usedNow}MB")
                        }

                    } catch (e: Exception) {
                        Log.w(TAG, "getAllDeviceVideos: skipped row $rowCount — ${e.message}")
                    }
                }

                Log.d(TAG, "getAllDeviceVideos: cursor loop complete, total rows = $rowCount")
            }
        } catch (e: Exception) {
            Log.e(TAG, "getAllDeviceVideos: CRASHED during cursor iteration at result.size=${result.size} — ${e.javaClass.simpleName}: ${e.message}", e)
            return result
        }

        val usedAfter = (runtime.totalMemory() - runtime.freeMemory()) / 1_048_576
        Log.d(TAG, "getAllDeviceVideos: done — ${result.size} videos, used=${usedAfter}MB")

        return result
    }

    fun encodeImageFromUri(uriString: String): FloatArray {
        ensureModelsLoaded()

        val uri = Uri.parse(uriString)
        val data = ImagePreprocessor.loadAsFloatArray(context, uri)
            ?: throw Exception("Failed to load image")

        return synchronized(visionLock) { runVision(visionSession!!, data, 1) }
    }

    /**
     * Same as [encodeImageFromUri], for a frame already decoded in memory (a paused video frame). It goes through the
     * same preprocessing and model call, so its embedding is comparable to every stored one. The caller keeps
     * ownership of the bitmap.
     */
    fun encodeBitmap(bitmap: android.graphics.Bitmap): FloatArray {
        ensureModelsLoaded()

        val data = ImagePreprocessor.bitmapToFloatArray(bitmap)

        return synchronized(visionLock) { runVision(visionSession!!, data, 1) }
    }

    /**
     * Ranks the stored items by their score against [textEmbedding]. A video's frames collapse to its best frame.
     * [pathFilter], when given, restricts the search to records whose path (a photo's uri, or a video frame's
     * videoUri) is in the set, for the person half of a "person + words" search. It is a plain path set, so this stays
     * a generic embedding search and does not need to know that people exist.
     */
    fun searchByText(
        textEmbedding: FloatArray,
        topK: Int = 20,
        contentFilter: String = "both",
        pathFilter: Set<String>? = null
    ): List<SearchResult> {
        if (topK <= 0) return emptyList()

        val bestPerKey = mutableMapOf<String, SearchResult>()

        for (record in store.readAll()) {
            if (!matchesContentFilter(record, contentFilter)) continue
            if (pathFilter != null && record.imagePath !in pathFilter) continue

            val score = EmbeddingMath.dot(textEmbedding, record.embedding)
            if (score.isNaN()) continue

            val result = SearchResult(
                imagePath   = record.imagePath,
                score       = score,
                videoUri    = record.videoUri,
                timestampMs = record.timestampMs
            )

            val dedupKey = record.videoUri ?: record.imagePath

            val existing = bestPerKey[dedupKey]
            if (existing == null || score > existing.score) {
                bestPerKey[dedupKey] = result
            }
        }

        return bestPerKey.values
            .sortedByDescending { it.score }
            .take(topK)
    }

    fun searchByImageEmbedding(
        imageEmbedding: FloatArray,
        topK: Int = 20,
        contentFilter: String = "both"
    ): List<SearchResult> {
        if (topK <= 0) return emptyList()

        val bestPerKey = mutableMapOf<String, SearchResult>()

        for (record in store.readAll()) {
            if (!matchesContentFilter(record, contentFilter)) continue

            val score = EmbeddingMath.dot(imageEmbedding, record.embedding)
            if (score.isNaN()) continue

            val result = SearchResult(
                imagePath   = record.imagePath,
                score       = score,
                videoUri    = record.videoUri,
                timestampMs = record.timestampMs
            )

            val dedupKey = record.videoUri ?: record.imagePath

            val existing = bestPerKey[dedupKey]
            if (existing == null || score > existing.score) {
                bestPerKey[dedupKey] = result
            }
        }

        return bestPerKey.values
            .sortedByDescending { it.score }
            .take(topK)
    }

    /**
     * What one collection needs to find its members.
     *
     * Members are not the top K, because raw CLIP similarity is not comparable across queries. Membership is a
     * per-query z-score: how far above the query's own average score across the library an item sits.
     */
    data class CollectionSpec(
        val id: String,
        val embedding: FloatArray,
        val contentMode: String,
        /** Standard deviations above the library-wide mean an item must reach. */
        val k: Double,
        /**
         * Ids from an "@name" search, as parsed off the channel call. MainActivity.resolvePathFilters turns them into
         * [pathFilter] off the UI thread, because that is a SQLite read.
         */
        val personIds: List<Long> = emptyList(),
        /**
         * Restricts membership to the photos and videos of those people. The mean and sigma are then computed over
         * that set only, because filtered-out records never enter the sum.
         */
        val pathFilter: Set<String>? = null
    )

    data class CollectionScore(
        val id: String,
        val count: Int,
        val covers: List<SearchResult>
    )

    /**
     * Every member of one collection, best match first. A video's frames collapse to its best frame. With a person
     * filter, the filter is the membership criterion and the score only orders the results, because the z-score test
     * rejects almost everything on a small, similar set.
     */
    private fun collectionMembers(
        records: List<EmbeddingRecord>,
        spec: CollectionSpec
    ): List<SearchResult> {
        val scores = FloatArray(records.size)
        var n = 0
        var sum = 0.0
        var sumSq = 0.0

        for ((i, record) in records.withIndex()) {
            if (!matchesContentFilter(record, spec.contentMode) ||
                record.embedding.size != spec.embedding.size ||
                (spec.pathFilter != null && record.imagePath !in spec.pathFilter)
            ) {
                scores[i] = Float.NaN
                continue
            }
            val score = EmbeddingMath.dot(spec.embedding, record.embedding)
            scores[i] = score
            n++
            sum += score
            sumSq += score.toDouble() * score
        }

        if (n == 0) return emptyList()

        val threshold = if (spec.pathFilter != null) {
            Double.NEGATIVE_INFINITY
        } else {
            if (n < 2) return emptyList()
            val mean = sum / n
            val variance = (sumSq / n) - mean * mean
            val sigma = kotlin.math.sqrt(kotlin.math.max(variance, 0.0))
            if (sigma < 1e-6) return emptyList()
            mean + spec.k * sigma
        }

        val bestPerKey = mutableMapOf<String, SearchResult>()

        for ((i, record) in records.withIndex()) {
            val score = scores[i]
            if (score.isNaN() || score < threshold) continue

            val key = record.videoUri ?: record.imagePath
            val existing = bestPerKey[key]
            if (existing == null || score > existing.score) {
                bestPerKey[key] = SearchResult(
                    imagePath = record.imagePath,
                    score = score,
                    videoUri = record.videoUri,
                    timestampMs = record.timestampMs
                )
            }
        }

        return bestPerKey.values.sortedByDescending { it.score }
    }

    /** Counts the members of each collection and picks a few cover items, in one read of the store. */
    fun scoreCollections(specs: List<CollectionSpec>): List<CollectionScore> {
        val records = store.readAll()
        return specs.map { spec ->
            val members = collectionMembers(records, spec)
            CollectionScore(spec.id, members.size, members.take(6))
        }
    }

    fun collectionMembers(spec: CollectionSpec, limit: Int): List<SearchResult> {
        return collectionMembers(store.readAll(), spec).take(limit)
    }

    /** True if [record] fits [contentFilter]. A record with a videoUri is a video frame, one without is a photo. Any other filter means both. */
    private fun matchesContentFilter(record: EmbeddingRecord, contentFilter: String): Boolean {
        return when (contentFilter) {
            "images" -> record.videoUri == null
            "videos" -> record.videoUri != null
            else -> true
        }
    }

    private fun emitProgressIfNeeded(
        total: Int,
        processed: Int,
        embedded: Int,
        skipped: Int,
        failed: Int,
        path: String,
        onProgress: (ScanProgress) -> Unit
    ) {
        val now = System.currentTimeMillis()
        if (now - lastEmit > PROGRESS_INTERVAL_MS) {
            onProgress(
                ScanProgress(
                    total     = total,
                    processed = processed,
                    embedded  = embedded,
                    skipped   = skipped,
                    elapsedMs = now - startTimeMs,
                    activeMs  = now - startTimeMs - pausedMs,
                    done      = false,
                    path      = path,
                    failed    = failed,
                    recentItems = recentItems.toList(),
                    photos    = kindPhotos,
                    videos    = kindVideos,
                    photosDone = kindsDone(processed).first,
                    videosDone = kindsDone(processed).second,
                )
            )
            lastEmit = now
        }
    }

    /**
     * Turns a SAF tree URI into a path like "Internal Storage/DCIM/Camera" instead of just "Camera". It uses
     * getTreeDocumentId because these are /tree/ URIs, not /document/ URIs.
     */
    fun getDisplayPath(uriString: String): String {
        val uri = Uri.parse(uriString)
        return try {
            val docId = DocumentsContract.getTreeDocumentId(uri)
            val parts = docId.split(":", limit = 2)
            val storageName = if (parts[0] == "primary") "Internal Storage" else parts[0]
            val relativePath = parts.getOrNull(1)
            if (relativePath.isNullOrEmpty()) storageName else "$storageName/$relativePath"
        } catch (e: Exception) {
            Log.w(TAG, "getDisplayPath: couldn't parse $uriString, falling back to leaf name", e)
            DocumentFile.fromTreeUri(context, uri)?.name ?: "Folder"
        }
    }

    fun deleteEmbeddingsForFolder(folderId: String) {
        store.deleteByFolderId(folderId)
    }

    fun getStoredCount(): Int = store.readAll().size

    /** Every indexed photo, not video, once each. Face grouping works through these. */
    fun indexedImages(): List<IndexedImage> {
        val seen = HashSet<Long>()
        val out = ArrayList<IndexedImage>()
        for (record in store.readAll()) {
            if (record.videoUri != null) continue
            if (seen.add(record.hash)) out += IndexedImage(record.hash, record.imagePath)
        }
        return out
    }

    /** Every indexed video, once each. Face grouping works through these after the photos. */
    fun indexedVideos(): List<IndexedVideo> {
        val seen = HashSet<Long>()
        val out = ArrayList<IndexedVideo>()
        for (record in store.readAll()) {
            val uri = record.videoUri ?: continue
            if (seen.add(record.hash)) out += IndexedVideo(record.hash, uri)
        }
        return out
    }

    fun getStoredCountForFolder(folderId: String): Int = store.countForFolder(folderId)

    /**
     * Looks up the stored embedding of one item by the identity a search result carries: imagePath for a photo, or
     * videoUri and timestampMs for the frame a video result stands for. Null if it was deleted or embedded again since.
     */
    fun findEmbedding(imagePath: String, videoUri: String?, timestampMs: Long): FloatArray? {
        val records = store.readAll()
        return if (videoUri != null) {
            records.firstOrNull { it.videoUri == videoUri && it.timestampMs == timestampMs }?.embedding
        } else {
            records.firstOrNull { it.videoUri == null && it.imagePath == imagePath }?.embedding
        }
    }

    /**
     * Approximates why an item matched: scores each query word's text embedding against the item's stored embedding, so
     * the caller can show which words pulled the most. It works per concept, not per region, which CLIP cannot give.
     */
    fun scoreWordsAgainstItem(
        itemEmbedding: FloatArray,
        words: List<Pair<String, IntArray>>
    ): List<Pair<String, Float>> {
        return words.mapNotNull { (word, tokens) ->
            try {
                val wordEmbedding = encodeText(tokens)
                word to EmbeddingMath.dot(wordEmbedding, itemEmbedding)
            } catch (e: Exception) {
                null
            }
        }
    }

    /**
     * Everything the Library tab's stats need, from one pass over the store. readAll() is not free for a large library
     * and the stats are refreshed on a timer during a scan (see NativeController).
     */
    data class LibraryStats(
        val totalEmbeddings: Int,
        val images: Int,
        val videos: Int,
        val sizeBytes: Long,
        /** The model that made an index this app had to drop, or 0 for none. See [EmbeddingStore.modelResetFrom]. */
        val modelResetFrom: Int
    )

    /**
     * Counts media items, not embedding rows. A video's frame records (see [embedVideoFile]) all share its videoUri, so
     * they count as one video. Images have no videoUri, so imagePath alone identifies them.
     */
    fun getLibraryStats(): LibraryStats {
        val records = store.readAll()

        val images = mutableSetOf<String>()
        val videos = mutableSetOf<String>()
        for (record in records) {
            val videoUri = record.videoUri
            if (videoUri != null) videos.add(videoUri) else images.add(record.imagePath)
        }

        return LibraryStats(
            totalEmbeddings = records.size,
            images = images.size,
            videos = videos.size,
            sizeBytes = store.sizeBytes(),
            modelResetFrom = store.modelResetFrom()
        )
    }

    fun clearAll() = store.clear()

    /** The person has been told that the index was dropped for a new model. */
    fun clearModelReset() = store.clearModelReset()

    /** See [EmbeddingStore.generation] and [EmbeddingStore.scanMeta]. */
    fun storeGeneration(): Long = store.generation()

    fun scanStoreMeta(from: Long, onRecord: (key: Long, uri: String, video: Boolean) -> Unit): Long =
        store.scanMeta(from, onRecord)
}