package dev.raseel.lostandfound.features.model_download

import dev.raseel.lostandfound.core.log.AppLog
import android.content.Context
import android.os.StatFs
import dev.raseel.lostandfound.BuildConfig
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest

/**
 * Downloads, verifies and deletes the on-device search model files. They live in context.filesDir, which is private,
 * needs no permission and is cleaned up on uninstall.
 */
class ModelManager(private val context: Context) {

    @Volatile
    private var isCancelled = false

    /** Set when one of the downloads running side by side failed for good, so the others stop instead of carrying on. */
    @Volatile
    private var aborted = false

    private val running = mutableSetOf<ResumableDownload>()

    private val prefs = context.getSharedPreferences("model_manager", Context.MODE_PRIVATE)

    init {
        cleanupLegacyPyTorchModels()
        cleanupLegacyFaceModels()
    }

    /**
     * Removes the face model files that older app versions downloaded (the accurate model of 170 MB and the downloaded
     * copy of the small one) and forgets that they were verified, because the face model is bundled in the app (see
     * FaceModelStore). A model put in the external folder by hand is the person's own, so only the accurate model's
     * files are removed from there.
     */
    private fun cleanupLegacyFaceModels() {
        val old = listOf("w600k_r50.onnx", "w600k_r50.onnx.part", "w600k_r50.json")
        val downloadedCopyOfBundled = listOf("w600k_mbf.onnx", "w600k_mbf.onnx.part")
        File(context.filesDir, "face_models").let { dir -> (old + downloadedCopyOfBundled).forEach { File(dir, it).delete() } }
        context.getExternalFilesDir("face_models")?.let { dir -> old.forEach { File(dir, it).delete() } }
        val stale = prefs.all.keys.filter { it.startsWith("verified_face_recognition") }
        if (stale.isNotEmpty()) prefs.edit().apply { stale.forEach { remove(it) } }.apply()
    }

    /**
     * Removes the TorchScript (.pt) CLIP models that older app versions downloaded. The ONNX models have other file
     * names and RemoteModel's catalog does not point at these, so they would sit in context.filesDir orphaned. It is
     * harmless on every launch: once the files are gone, File.delete() does nothing.
     */
    private fun cleanupLegacyPyTorchModels() {
        for (name in listOf("clip_vision_ts.pt", "clip_text_ts.pt")) {
            File(context.filesDir, name).delete()
            File(context.filesDir, "$name.part").delete()
        }
    }

    companion object {
        private const val BUFFER_SIZE = 64 * 1024
        private const val FREE_SPACE_MULTIPLIER = 1.3
        private const val REPLACED_REMOVED_KEY = "old_clip_models_removed_v2"
    }

    fun localFile(model: RemoteModel): File = File(context.filesDir, model.fileName)

    private fun partFile(model: RemoteModel): File = File(context.filesDir, "${model.fileName}.part")

    private fun verifiedKey(model: RemoteModel) = "verified_${model.id}_${model.sha256}"

    /**
     * Whether [model] is downloaded in full and verified. A file of the right size that is not flagged verified, such
     * as one copied into place directly, is hashed once and the result cached. The hash can be slow on a big file, so
     * call this from a background thread.
     */
    fun isModelVerified(model: RemoteModel): Boolean {
        seedFromDebugAssetsIfPresent(model)

        val file = localFile(model)
        if (!file.exists() || file.length() != model.sizeBytes) return false

        if (prefs.getBoolean(verifiedKey(model), false)) return true

        val matches = sha256Of(file).equals(model.sha256, ignoreCase = true)
        if (matches) {
            prefs.edit().putBoolean(verifiedKey(model), true).apply()
        }
        return matches
    }

    /**
     * Whether the search models are in place. Search and indexing need only these, and the face model is optional and
     * never holds them back.
     */
    fun areModelsReady(): Boolean {
        val ready = ModelCatalog.MODELS.all { isModelVerified(it) }
        if (ready) removeReplacedSearchModels()
        return ready
    }

    /**
     * Removes the replaced search models: OpenAI's CLIP ViT-B/32 (about 600 MB, two files under other names) and
     * MobileCLIP-S2. It runs once and only after the current models are in place, so a failed download does not leave
     * the person with no models at all.
     */
    private fun removeReplacedSearchModels() {
        if (prefs.getBoolean(REPLACED_REMOVED_KEY, false)) return
        for (name in listOf("clip_vision.onnx", "clip_text.onnx", "mobileclip_s2_vision.onnx", "mobileclip_s2_text.onnx")) {
            File(context.filesDir, name).delete()
            File(context.filesDir, "$name.part").delete()
        }
        val stale = prefs.all.keys.filter { it.startsWith("verified_vision_") || it.startsWith("verified_text_") }
            .filter { key -> ModelCatalog.MODELS.none { verifiedKey(it) == key } }
        prefs.edit().apply {
            stale.forEach { remove(it) }
            putBoolean(REPLACED_REMOVED_KEY, true)
        }.apply()
    }

    fun getModelStatuses(): List<ModelStatus> = ModelCatalog.ALL.map { m ->
        val f = localFile(m)
        ModelStatus(
            id = m.id,
            fileName = m.fileName,
            sizeBytes = m.sizeBytes,
            downloaded = f.exists() && f.length() == m.sizeBytes,
            verified = isModelVerified(m),
            group = m.group
        )
    }

    fun bytesNeededToDownload(models: List<RemoteModel> = ModelCatalog.MODELS): Long =
        models.filterNot { isModelVerified(it) }.sumOf { it.sizeBytes }

    fun hasEnoughFreeSpace(models: List<RemoteModel> = ModelCatalog.MODELS): Boolean {
        val stat = StatFs(context.filesDir.path)
        val free = stat.availableBytes
        val needed = bytesNeededToDownload(models)
        if (needed == 0L) return true
        return free > (needed * FREE_SPACE_MULTIPLIER).toLong()
    }

    /** Stops the download at once, also while it is still connecting or waiting between two tries. */
    fun cancelDownload() {
        isCancelled = true
        stopRunning()
    }

    private fun stopRunning() {
        val jobs = synchronized(running) { running.toList() }
        jobs.forEach { it.stop() }
    }

    private fun shouldStop() = isCancelled || aborted

    /** Deletes the search models (search and indexing stop until they are downloaded again). */
    fun deleteModels() = delete(ModelCatalog.MODELS)

    private fun delete(models: List<RemoteModel>) {
        for (m in models) {
            localFile(m).delete()
            partFile(m).delete()
            prefs.edit().remove(verifiedKey(m)).apply()
        }
    }

    /**
     * Downloads every not-yet-verified model of [models], all at the same time, so the waiting to connect overlaps and
     * the files use more than one stream. Safe to call again after a cancel or failure: verified models are skipped and
     * partial downloads resume. When one fails for good the others are stopped, their partial files are kept, and the
     * error is thrown.
     */
    fun download(models: List<RemoteModel>, onProgress: (ModelDownloadProgress) -> Unit) {
        isCancelled = false
        aborted = false

        val pending = models.filterNot { isModelVerified(it) }
        if (pending.isEmpty()) return
        val progress = DownloadProgressTracker(models, pending, onProgress)

        if (pending.size == 1) {
            downloadOne(pending.first(), progress)
            return
        }

        val failure = java.util.concurrent.atomic.AtomicReference<Throwable?>(null)
        val threads = pending.map { model ->
            Thread {
                try {
                    downloadOne(model, progress)
                } catch (t: Throwable) {
                    failure.compareAndSet(null, t)
                    aborted = true
                    stopRunning()
                }
            }.apply {
                name = "model-download-${model.id}"
                start()
            }
        }
        threads.forEach { it.join() }
        failure.get()?.let { throw it }
    }

    /**
     * Downloads one model, resuming a partial file when the server honours the Range request, and discards a stale
     * file of the wrong size to start clean. When every byte is here it reports that before the size and checksum
     * check, which takes seconds on a big file, so the app shows "checking" and not a bar frozen near the end.
     */
    private fun downloadOne(model: RemoteModel, progress: DownloadProgressTracker) {
        val target = localFile(model)
        val part = partFile(model)

        if (target.exists() && target.length() != model.sizeBytes) target.delete()

        val job = ResumableDownload(model.url, part, model.sizeBytes) { written -> progress.received(model, written) }
        synchronized(running) { running.add(job) }
        val complete = try {
            if (shouldStop()) false else job.run()
        } finally {
            synchronized(running) { running.remove(job) }
        }
        if (!complete || isCancelled) return

        progress.allBytesReceived(model)

        if (part.length() != model.sizeBytes) {
            throw IOException(
                "Downloaded size mismatch for ${model.fileName}: " +
                    "expected ${model.sizeBytes}, got ${part.length()}"
            )
        }

        val actualHash = sha256Of(part)
        if (!actualHash.equals(model.sha256, ignoreCase = true)) {
            part.delete()
            throw IOException("Checksum mismatch for ${model.fileName} - download was corrupted")
        }

        if (target.exists()) target.delete()
        if (!part.renameTo(target)) {
            throw IOException("Could not finalize ${model.fileName}")
        }

        prefs.edit().putBoolean(verifiedKey(model), true).apply()

        progress.finished(model)
    }

    /**
     * Debug convenience: copies a model file found in android/app/src/debug/assets/ into place so the app skips the
     * download screen. That source set is debug only, so a release APK never includes it. It does nothing when no file
     * is there, which is the normal case.
     */
    private fun seedFromDebugAssetsIfPresent(model: RemoteModel) {
        if (!BuildConfig.DEBUG) return

        val target = localFile(model)
        if (target.exists() && target.length() == model.sizeBytes) return

        try {
            context.assets.open(model.fileName).use { input ->
                FileOutputStream(target).use { output ->
                    input.copyTo(output, BUFFER_SIZE)
                }
            }
            AppLog.d("ModelManager", "Seeded ${model.fileName} from debug assets")
        } catch (e: IOException) {
            // Not bundled for this build, which is the normal case.
        }
    }

    private fun sha256Of(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(BUFFER_SIZE)
            var read: Int
            while (input.read(buffer).also { read = it } != -1) {
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
