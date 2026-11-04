package dev.raseel.lostandfound.embedder.faces

import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import org.json.JSONObject
import java.io.File

enum class FaceModelKind { DETECTOR, EMBEDDER }

/**
 * Everything the pipeline needs to know about one face model, so the code never hard-codes a network. A model is an
 * `.onnx` file, and a `<name>.json` next to it overrides the defaults with "kind", "inputSize", "mean", "std", "rgb"
 * and "name". Without one, a file name containing "det", "scrfd", "retina" or "yunet" is a detector (SCRFD defaults)
 * and anything else is an ArcFace style embedder.
 */
data class FaceModelSpec(
    val id: String,
    val kind: FaceModelKind,
    val displayName: String,
    val inputSize: Int,
    val mean: Float,
    val std: Float,
    val rgb: Boolean,
)

/** Friendly names for the models the app knows by id. Others show their file name, or the name from their JSON file. */
private val KNOWN_NAMES = mapOf("w600k_mbf" to "MobileFaceNet")

/** A model file found somewhere on the device, with its resolved settings. A model is either [file] on disk, dropped in or downloaded, or bundled in the APK as [assetName]. */
data class LocatedFaceModel(
    val spec: FaceModelSpec,
    val file: File?,
    val assetName: String?,
    val sizeBytes: Long,
) {
    val source get() = if (file != null) "device" else "bundled"
}

/**
 * Finds face models and opens them. Nothing else in the face code knows where a model lives, so swapping one means
 * putting an `.onnx` in [modelsDir] and choosing it, with no rebuild. For the same id the app's external files folder
 * (reachable over adb or a file manager) is searched first, then its private files folder, then the APK's assets.
 */
class FaceModelStore(private val context: Context) {

    private val prefs = context.getSharedPreferences("face_models", Context.MODE_PRIVATE)
    private val env: OrtEnvironment = OrtEnvironment.getEnvironment()

    /** Where to drop model files (created on first use). */
    val modelsDir: File
        get() = (context.getExternalFilesDir("face_models") ?: File(context.filesDir, "face_models"))
            .also { it.mkdirs() }

    private val privateDir get() = File(context.filesDir, "face_models").also { it.mkdirs() }

    fun available(kind: FaceModelKind): List<LocatedFaceModel> = all().filter { it.spec.kind == kind }

    /** The model in use for [kind]: the one chosen last, else the first found. */
    fun selected(kind: FaceModelKind): LocatedFaceModel? {
        val models = available(kind)
        val chosen = prefs.getString(prefKey(kind), null)
        return models.firstOrNull { it.spec.id == chosen } ?: models.firstOrNull()
    }

    fun select(kind: FaceModelKind, id: String) {
        prefs.edit().putString(prefKey(kind), id).apply()
    }

    private fun prefKey(kind: FaceModelKind) = "selected_${kind.name.lowercase()}"

    /** Opens a session for [model] with the settings tuned for this phone. The caller closes it. */
    fun openSession(model: LocatedFaceModel): OrtSession =
        openSession(model, FaceTuner.configFor(context, model.spec))

    /**
     * Opens a session with explicit settings, used by the tuner's benchmark. The session gets one thread because
     * XNNPACK has a thread pool of its own and a second pool would compete for the cores. The model is loaded from a
     * path, not a byte array, because a 170 MB model would sit in memory twice while loading.
     */
    fun openSession(model: LocatedFaceModel, config: RunConfig): OrtSession {
        val options = OrtSession.SessionOptions().apply {
            setIntraOpNumThreads(if (config.provider == "xnnpack") 1 else config.threads)
            setInterOpNumThreads(1)
            config.affinity?.let { addConfigEntry("session.intra_op_thread_affinities", it) }
            when (config.provider) {
                "xnnpack" -> addXnnpack(mapOf("intra_op_num_threads" to config.threads.toString()))
                "nnapi" -> addNnapi(java.util.EnumSet.of(ai.onnxruntime.providers.NNAPIFlags.USE_FP16))
            }
        }
        val file = model.file ?: copyAssetToCache(model.assetName!!)
        return env.createSession(file.absolutePath, options)
    }

    /**
     * Unpacks a bundled model to the cache, because ONNX Runtime opens files by path. It is copied again after an app
     * update, since the bundled file may have changed. The asset's size is found by reading it through, because assets
     * are compressed in the APK and openFd() refuses those.
     */
    private fun copyAssetToCache(assetName: String): File {
        val target = File(privateDir, ".bundled_$assetName")
        val stamp = File(privateDir, ".bundled_$assetName.stamp")
        val version = installStamp()
        if (!target.exists() || !stamp.exists() || stamp.readText() != version) {
            context.assets.open(assetName).use { input ->
                target.outputStream().use { input.copyTo(it) }
            }
            stamp.writeText(version)
        }
        return target
    }

    private fun installStamp(): String = try {
        context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime.toString()
    } catch (_: Exception) {
        "0"
    }

    /** The size of each asset, counted once by reading it through. It is a few MB at most. */
    private val assetSizes = HashMap<String, Long>()

    private fun assetSize(name: String): Long = assetSizes.getOrPut(name) {
        try {
            context.assets.open(name).use { input ->
                val buffer = ByteArray(64 * 1024)
                var total = 0L
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    total += n
                }
                total
            }
        } catch (_: Exception) {
            0L
        }
    }

    private fun all(): List<LocatedFaceModel> {
        val found = LinkedHashMap<String, LocatedFaceModel>()

        for (dir in listOf(modelsDir, privateDir)) {
            dir.listFiles { f -> f.isFile && !f.name.startsWith(".") && f.extension.equals("onnx", true) }
                ?.sortedBy { it.name }
                ?.forEach { file ->
                    val id = file.nameWithoutExtension
                    if (id !in found) {
                        val sidecar = File(dir, "$id.json").takeIf { it.exists() }?.readText()
                        found[id] = LocatedFaceModel(specFor(id, sidecar), file, null, file.length())
                    }
                }
        }

        val assets = context.assets.list("")?.filter { it.endsWith(".onnx", true) }?.sorted().orEmpty()
        for (name in assets) {
            val id = name.removeSuffix(".onnx")
            if (id in found) continue
            val sidecar = try {
                context.assets.open("$id.json").use { it.readBytes().toString(Charsets.UTF_8) }
            } catch (_: Exception) {
                null
            }
            found[id] = LocatedFaceModel(specFor(id, sidecar), null, name, assetSize(name))
        }
        return found.values.toList()
    }

    private fun specFor(id: String, sidecarJson: String?): FaceModelSpec {
        val lower = id.lowercase()
        val looksLikeDetector = listOf("det", "scrfd", "retina", "yunet").any { it in lower }
        val json = try { sidecarJson?.let { JSONObject(it) } } catch (_: Exception) { null }

        val kind = when (json?.optString("kind")?.lowercase()) {
            "detector" -> FaceModelKind.DETECTOR
            "embedder" -> FaceModelKind.EMBEDDER
            else -> if (looksLikeDetector) FaceModelKind.DETECTOR else FaceModelKind.EMBEDDER
        }
        val detector = kind == FaceModelKind.DETECTOR

        return FaceModelSpec(
            id = id,
            kind = kind,
            displayName = json?.optString("name")?.takeIf { it.isNotBlank() } ?: KNOWN_NAMES[id] ?: id,
            inputSize = json?.optInt("inputSize", 0)?.takeIf { it > 0 } ?: if (detector) 640 else 112,
            mean = json?.optDouble("mean", Double.NaN)?.takeIf { !it.isNaN() }?.toFloat() ?: 127.5f,
            std = json?.optDouble("std", Double.NaN)?.takeIf { !it.isNaN() }?.toFloat()
                ?: if (detector) 128f else 127.5f,
            rgb = json?.optBoolean("rgb", true) ?: true,
        )
    }
}
