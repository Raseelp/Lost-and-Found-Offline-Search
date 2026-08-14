package dev.twentyonevision.app.embedder

import android.content.Context
import android.net.Uri
import org.pytorch.IValue
import org.pytorch.Module
import org.pytorch.Tensor
import com.facebook.soloader.SoLoader
import dev.twentyonevision.app.embedder.models.ModelCatalog
import dev.twentyonevision.app.embedder.models.ModelManager
import dev.twentyonevision.app.embedder.models.ModelsNotReadyException
import dev.twentyonevision.app.embedder.storage.EmbeddingRecord
import dev.twentyonevision.app.embedder.storage.EmbeddingStore
import dev.twentyonevision.app.embedder.storage.HashUtils
import androidx.documentfile.provider.DocumentFile
import android.provider.DocumentsContract
import android.util.Log


class EmbeddingEngine(
    private val context: Context,
    private val modelManager: ModelManager
) {

    // Loaded lazily - always go through ensureModelsLoaded() first.
    private var visionModule: Module? = null
    private var textModule: Module? = null
    private val store: EmbeddingStore

    private var lastEmit: Long = 0L
    private var startTimeMs: Long = 0L

    @Volatile
    private var isCancelled = false

    companion object {
        private const val TAG = "EmbeddingEngine"
        private const val PROGRESS_INTERVAL_MS = 500L
    }

    init {
        SoLoader.init(context, false)
        store = EmbeddingStore(context)
    }

    // Throws ModelsNotReadyException if the download hasn't finished yet -
    // Dart checks areModelsReady() up front, this is just the backstop.
    @Synchronized
    private fun ensureModelsLoaded() {
        if (visionModule != null && textModule != null) return

        if (!modelManager.areModelsReady()) {
            throw ModelsNotReadyException("CLIP models are not downloaded yet")
        }

        if (visionModule == null) {
            val visionModel = ModelCatalog.MODELS.first { it.id == "vision" }
            visionModule = Module.load(modelManager.localFile(visionModel).absolutePath)
        }
        if (textModule == null) {
            val textModel = ModelCatalog.MODELS.first { it.id == "text" }
            textModule = Module.load(modelManager.localFile(textModel).absolutePath)
        }
    }

    fun cancelEmbedding() {
        isCancelled = true
    }

    fun encodeText(tokens: IntArray): FloatArray {
        require(tokens.size == 77) { "Expected 77 tokens, got ${tokens.size}" }

        ensureModelsLoaded()
        val text = textModule!!

        val longs = LongArray(77) { tokens[it].toLong() }
        val tensor = Tensor.fromBlob(longs, longArrayOf(1, 77))

        return text
            .forward(IValue.from(tensor))
            .toTensor()
            .dataAsFloatArray
    }

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
        Log.d(TAG, "embedImages: start — mode=$mode contentMode=$contentMode")

        ensureModelsLoaded()
        val vision = visionModule!!

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

            // Surface progress during the (possibly slow) SAF traversal so
            // the UI doesn't just sit on "Preparing..." looking hung.
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
                            path = "$label0 — found $foundSoFar files so far"
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

        // Enumeration itself can be cancelled - bail out before the scan loops.
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

        val batchSize = 10
        val batch = mutableListOf<EmbeddingRecord>()

        for (img in imageFiles) {

            if (isCancelled) {
                if (batch.isNotEmpty()) { store.appendBatch(batch); batch.clear() }
                break
            }

            try {
                val hash = HashUtils.identityHash(img.size, img.lastModified, img.name)

                if (existingHashes.contains(hash)) {
                    skipped++
                } else {
                    val tensor = ImagePreprocessor.loadAsTensor(context, img.uri)
                    if (tensor == null) {
                        skipped++
                    } else {
                        val embedding = vision
                            .forward(IValue.from(tensor))
                            .toTensor()
                            .dataAsFloatArray

                        batch.add(
                            EmbeddingRecord(
                                imagePath = img.uri.toString(),
                                hash = hash,
                                embedding = embedding,
                                folderId = folderId
                            )
                        )

                        existingHashes.add(hash)
                        embedded++

                        if (batch.size >= batchSize) {
                            store.appendBatch(batch)
                            batch.clear()
                        }
                    }
                }
            } catch (e: Exception) {
                skipped++
            }

            processed++
            emitProgressIfNeeded(total, processed, embedded, skipped, label, onProgress)
        }

        if (!isCancelled) {
            for (video in videoFiles) {

                if (isCancelled) {
                    if (batch.isNotEmpty()) { store.appendBatch(batch); batch.clear() }
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
                        } else {
                            batch.addAll(frameRecords)
                            existingHashes.add(hash)
                            embedded += frameRecords.size

                            if (batch.size >= batchSize) {
                                store.appendBatch(batch)
                                batch.clear()
                            }
                        }
                    }
                } catch (e: Exception) {
                    skipped++
                }

                processed++
                emitProgressIfNeeded(total, processed, embedded, skipped, label, onProgress)
            }
        }

        if (batch.isNotEmpty()) store.appendBatch(batch)

        val elapsed = System.currentTimeMillis() - startTimeMs

        onProgress(
            ScanProgress(
                total = total,
                processed = processed,
                embedded = embedded,
                skipped = skipped,
                elapsedMs = elapsed,
                done = true,
                path = label
            )
        )

        return ScanResult(total, embedded, skipped)
    }

    private fun embedVideoFile(
        video: VideoSource,
        hash: Long,
        folderId: String,
        vision: Module
    ): List<EmbeddingRecord> {

        val videoUriString = video.uri.toString()

        val frames = VideoFrameExtractor.extractFrames(
            context = context,
            uri = video.uri
        )

        if (frames.isEmpty()) return emptyList()

        val records = mutableListOf<EmbeddingRecord>()

        for ((timestampMs, bitmap) in frames) {
            try {
                val tensor = ImagePreprocessor.bitmapToTensor(bitmap)

                val embedding = vision
                    .forward(IValue.from(tensor))
                    .toTensor()
                    .dataAsFloatArray

                records.add(
                    EmbeddingRecord(
                        imagePath   = videoUriString,
                        hash        = hash,
                        embedding   = embedding,
                        folderId    = folderId,
                        videoUri    = videoUriString,
                        timestampMs = timestampMs
                    )
                )
            } catch (e: Exception) {
                // one bad frame doesn't kill the whole video
            } finally {
                bitmap.recycle()
            }
        }

        return records
    }


    private fun getFolderImages(
        folderUri: Uri,
        onFileFound: () -> Unit = {}
    ): List<ImageSource> {
        return SafUtils.listImageFiles(
            context, folderUri,
            isCancelled = { isCancelled },
            onFileFound = onFileFound
        ).map {
            ImageSource(
                uri = it.uri,
                size = it.length(),
                lastModified = it.lastModified(),
                name = it.name ?: ""
            )
        }
    }

    private fun getFolderVideos(
        folderUri: Uri,
        onFileFound: () -> Unit = {}
    ): List<VideoSource> {
        return SafUtils.listVideoFiles(
            context, folderUri,
            isCancelled = { isCancelled },
            onFileFound = onFileFound
        ).map {
            VideoSource(
                uri = it.uri,
                size = it.length(),
                lastModified = it.lastModified(),
                name = it.name ?: ""
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
        val tensor = ImagePreprocessor.loadAsTensor(context, uri)
            ?: throw Exception("Failed to load image")

        return visionModule!!
            .forward(IValue.from(tensor))
            .toTensor()
            .dataAsFloatArray
    }
    fun searchByText(
        textEmbedding: FloatArray,
        topK: Int = 20
    ): List<SearchResult> {
        if (topK <= 0) return emptyList()

        val bestPerKey = mutableMapOf<String, SearchResult>()

        for (record in store.readAll()) {
            val score = EmbeddingMath.dot(textEmbedding, record.embedding)

            val result = SearchResult(
                imagePath   = record.imagePath,
                score       = score,
                videoUri    = record.videoUri,
                timestampMs = record.timestampMs
            )

            // Collapse all frames of the same video into its best-scoring one.
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
        topK: Int = 20
    ): List<SearchResult> {
        if (topK <= 0) return emptyList()

        val bestPerKey = mutableMapOf<String, SearchResult>()

        for (record in store.readAll()) {
            val score = EmbeddingMath.dot(imageEmbedding, record.embedding)

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

    private fun emitProgressIfNeeded(
        total: Int,
        processed: Int,
        embedded: Int,
        skipped: Int,
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
                    done      = false,
                    path      = path
                )
            )
            lastEmit = now
        }
    }

    // Turns a SAF tree URI into "Internal Storage/DCIM/Camera" instead of
    // just "Camera" - uses getTreeDocumentId, not getDocumentId (that's for
    // /document/ URIs, not the /tree/ URIs we get here).
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

    fun getStoredCountForFolder(folderId: String): Int = store.countForFolder(folderId)

    fun clearAll() = store.clear()
}