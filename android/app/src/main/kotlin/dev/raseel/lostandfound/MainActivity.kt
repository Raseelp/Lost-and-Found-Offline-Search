package dev.raseel.lostandfound

import android.content.ContentValues
import android.graphics.Color
import android.os.Bundle
import androidx.core.view.WindowCompat
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.media.MediaMetadataRetriever
import dev.raseel.lostandfound.features.people.FaceImageLoader
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel

import androidx.exifinterface.media.ExifInterface
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.workDataOf

import dev.raseel.lostandfound.features.search.EmbeddingEngine
import dev.raseel.lostandfound.features.library.ScanEngineHolder
import dev.raseel.lostandfound.features.library.ScanForegroundService
import dev.raseel.lostandfound.features.library.ScanWorker
import dev.raseel.lostandfound.features.library.VideoFrameExtractor
import dev.raseel.lostandfound.features.settings.BenchLog
import dev.raseel.lostandfound.features.settings.LogDump
import dev.raseel.lostandfound.features.people.FaceClusterConfig
import dev.raseel.lostandfound.features.people.FaceFollower
import dev.raseel.lostandfound.features.people.FaceModelKind
import dev.raseel.lostandfound.features.people.FaceScanHub
import dev.raseel.lostandfound.features.people.FaceScanWorker
import dev.raseel.lostandfound.features.people.FaceServices
import dev.raseel.lostandfound.features.people.PhotoScanProgress
import dev.raseel.lostandfound.features.people.FaceTuner
import dev.raseel.lostandfound.features.people.FaceSettings
import dev.raseel.lostandfound.features.settings.IndexNudge
import dev.raseel.lostandfound.features.memories.LibraryDates
import dev.raseel.lostandfound.features.memories.MemoryDay
import dev.raseel.lostandfound.features.memories.MemoryDays
import dev.raseel.lostandfound.features.memories.MemoryEvergreen
import dev.raseel.lostandfound.features.memories.MemoryNotifier
import dev.raseel.lostandfound.features.memories.MemoryPlanner
import dev.raseel.lostandfound.features.memories.MemoryPrefs
import dev.raseel.lostandfound.features.memories.MemoryScheduler
import dev.raseel.lostandfound.features.people.thennow.ThenNow
import dev.raseel.lostandfound.features.memories.DayYear
import dev.raseel.lostandfound.features.memories.Plan
import dev.raseel.lostandfound.features.memories.PlanPhoto
import dev.raseel.lostandfound.features.memories.stories.StoriesReminder
import dev.raseel.lostandfound.features.model_download.ModelCatalog
import dev.raseel.lostandfound.features.model_download.ModelManager
import dev.raseel.lostandfound.features.model_download.ModelsNotReadyException
import dev.raseel.lostandfound.features.library.SafPickerActivity

class MainActivity : FlutterActivity() {

    companion object {
        /** What a tap on the scan's notification (indexing or faces) opens with: the Library tab, where the scan is. */
        const val ACTION_OPEN_LIBRARY = "dev.raseel.lostandfound.OPEN_LIBRARY"

        /** What a tap on the stories note opens with: the Search tab, where the rings are. */
        const val ACTION_OPEN_STORIES = "dev.raseel.lostandfound.OPEN_STORIES"

        /** The home tabs a notification can open (as the app numbers them). */
        private const val TAB_SEARCH = 0
        private const val TAB_LIBRARY = 2
    }

    /** The home tab a tapped notification wants shown, not yet taken by the app (takeOpenTab); -1: none. */
    @Volatile
    private var openTab = -1

    /** The "Index now" button of the note was pressed. takeIndexNow gives it to the app once. */
    @Volatile
    private var indexNow = false

    private val CHANNEL = "lostandfound/native"
    private val PROGRESS_CHANNEL = "lostandfound/progress"
    private val FACE_PROGRESS_CHANNEL = "lostandfound/faceProgress"
    private val MODEL_DOWNLOAD_CHANNEL = "lostandfound/modelDownload"
    private val PICK_REQUEST = 2001

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

    private var pendingPickResult: MethodChannel.Result? = null
    /**
     * Both process-wide (ScanEngineHolder), not per-Activity instances -
     * see its doc for why a lateinit var here was the actual bug behind
     * "cancelEmbedding does nothing after the app is reopened from
     * Recents". These properties keep every existing call site unchanged.
     */
    private val modelManager: ModelManager get() = ScanEngineHolder.modelManager(this)
    private val embeddingEngine: EmbeddingEngine get() = ScanEngineHolder.embeddingEngine(this)
    /**
     * The sink of the model download progress. A model download is not kept alive by a foreground service, so unlike
     * the scan progress sink on ScanForegroundService it cannot outlive this Activity.
     */
    private var modelDownloadSink: EventChannel.EventSink? = null
    /**
     * Deliberately not process-wide, unlike modelManager above. Sharing this thread between a running scan and quick
     * queries like areModelsReady made those queries hang behind the scan (see ScanEngineHolder).
     */
    private val executor = Executors.newSingleThreadExecutor()
    /**
     * Downloads get their own thread so a long-running download never blocks
     * unrelated calls (e.g. loading an already-cached thumbnail) sitting
     * behind it on the shared executor.
     */
    private val downloadExecutor = Executors.newSingleThreadExecutor()
    /**
     * Search gets its own thread so it does not queue behind a scan that can run for an hour or more. EmbeddingEngine
     * and EmbeddingStore allow this with locks around the shared vision module and the on-disk store.
     */
    private val searchExecutor = Executors.newSingleThreadExecutor()
    /**
     * Grid thumbnails only: a few in parallel so a collection's tiles fill in
     * together, and off searchExecutor so they never queue behind a search.
     */
    private val thumbnailExecutor = Executors.newFixedThreadPool(3)
    /**
     * Face pictures get their own threads: a grid of photo thumbnails filling in
     * (or a search) must never make an avatar wait, and the other way round.
     */
    private val faceCropExecutor = Executors.newFixedThreadPool(3)

    /** Work for the zip export that is quick but not instant (reading file sizes and dates). */
    private val exportExecutor = Executors.newSingleThreadExecutor()
    /**
     * Face detection has its own thread and detector, with its own ONNX session, so it never waits behind or holds up
     * search or a scan.
     */
    private val faceExecutor = Executors.newSingleThreadExecutor()
    /**
     * The memories (dates of everything indexed, "on this day", "then and now") have their own thread,
     * so reading dates never holds up the face calls or a search.
     */
    private val memoryExecutor = Executors.newSingleThreadExecutor()
    private val logExecutor = Executors.newSingleThreadExecutor()
    /**
     * A photo opened in the viewer that the face scan hasn't reached yet is analysed on
     * its own thread, so it doesn't queue behind the other face calls.
     */
    private val photoFacesExecutor = Executors.newSingleThreadExecutor()
    /**
     * A whole video is scanned on its own thread too: it can take a while, and must not hold up
     * the quick look-ups (a photo's faces, the paused frame of a video).
     */
    private val videoScanExecutor = Executors.newSingleThreadExecutor()
    /**
     * Viewers that were closed before their photo's turn came (one photo is scanned at a time),
     * by the token each viewer sent: those requests are skipped instead of scanned for nobody.
     */
    private val cancelledPhotoScans: MutableSet<Long> = java.util.concurrent.ConcurrentHashMap.newKeySet()
    private val faces by lazy { FaceServices.get(applicationContext) }

    /** A photo or video standing for a moment of several people, as the timeline wants it. */
    private fun groupMap(g: dev.raseel.lostandfound.features.people.FaceStore.GroupMedia) = mapOf(
        "key" to g.key,
        "takenMs" to g.ms,
        "people" to g.people,
        "gapDays" to g.gapDays,
        "uri" to g.uri,
        "isVideo" to g.isVideo,
        "tsMs" to g.tsMs,
    )

    /** Runs [block] on the face thread and hands its value (or its error) to Flutter. */
    private fun faceTask(result: MethodChannel.Result, block: () -> Any?) {
        faceExecutor.execute {
            try {
                val value = block()
                runOnUiThread { result.success(value) }
            } catch (e: Throwable) {
                runOnUiThread { result.error("FACE_FAILED", e.message ?: e.toString(), null) }
            }
        }
    }

    /**
     * Notes the tap that started the Activity, but not when it is only recreated, because that tap was already shown.
     * Draws behind the system bars with the navigation bar in the app background colour, because some OEM skins (a
     * vivo/iQOO was tested) keep an opaque black bar unless the window opts in natively. Keeps the daily memory
     * scheduled.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        noteMemoryTap(intent)
        if (savedInstanceState == null) noteTabTap(intent)
        try { MemoryScheduler.apply(applicationContext) } catch (_: Exception) {}

        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.WHITE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        noteMemoryTap(intent)
        noteTabTap(intent)
    }

    /**
     * The app is left: the "finish indexing" note is set for a few days after, and comes only if the library is not
     * all indexed then.
     */
    override fun onStop() {
        super.onStop()
        try { IndexNudge.arm(applicationContext) } catch (_: Exception) {}
    }

    /** The app is in use: unanswered stories notes stop counting. */
    override fun onResume() {
        super.onResume()
        try { StoriesReminder.noteOpened(applicationContext) } catch (_: Exception) {}
    }

    private fun noteTabTap(intent: Intent?) {
        when (intent?.action) {
            ACTION_OPEN_LIBRARY -> openTab = TAB_LIBRARY
            ACTION_OPEN_STORIES -> openTab = TAB_SEARCH
            IndexNudge.ACTION_INDEX_NOW -> {
                openTab = TAB_LIBRARY
                indexNow = true
            }
        }
    }

    /**
     * A tap on the daily memory's notification: remembered, and the app picks it up (takeLaunchMemory) to open the memory.
     */
    private fun noteMemoryTap(intent: Intent?) {
        if (intent?.action != MemoryNotifier.ACTION_OPEN) return
        MemoryPrefs(applicationContext).setLaunch(
            intent.getStringExtra(MemoryNotifier.EXTRA_KIND),
            intent.getIntExtra(MemoryNotifier.EXTRA_YEAR, 0),
            intent.getLongExtra(MemoryNotifier.EXTRA_PERSON, 0L),
        )
    }

    private fun planPhotoMap(p: PlanPhoto) = mapOf(
        "key" to p.key,
        "uri" to p.uri,
        "isVideo" to p.video,
        "tsMs" to p.tsMs,
        "takenMs" to p.takenMs,
        "names" to p.names,
    )

    private fun dayYearMap(y: DayYear) = mapOf(
        "year" to y.year,
        "yearsAgo" to y.yearsAgo,
        "total" to y.total,
        "photos" to y.photos.map { planPhotoMap(it) },
        "names" to y.names,
        "strength" to y.strength.toDouble(),
    )

    private fun planMap(plan: Plan) = mapOf(
        "month" to plan.month,
        "day" to plan.day,
        "year" to plan.year,
        "exact" to plan.exact.map { dayYearMap(it) },
        "week" to plan.week.map { dayYearMap(it) },
        "anniversaries" to plan.anniversaries.map { a ->
            mapOf(
                "yearsAgo" to a.yearsAgo,
                "ids" to a.ids,
                "names" to a.names,
                "firstMs" to a.firstMs,
                "photo" to a.photo?.let { planPhotoMap(it) },
            )
        },
    )

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

    private fun memorySettingsMap(): Map<String, Any> {
        val prefs = MemoryPrefs(applicationContext)
        return mapOf(
            "enabled" to prefs.enabled,
            "allowed" to MemoryNotifier.allowed(applicationContext),
        )
    }

    private fun memoryTask(result: MethodChannel.Result, block: () -> Any?) {
        memoryExecutor.execute {
            try {
                val value = block()
                runOnUiThread { result.success(value) }
            } catch (e: Throwable) {
                android.util.Log.w("MainActivity", "memory call failed: ${e.message}", e)
                runOnUiThread { result.error("MEMORY_FAILED", e.message, null) }
            }
        }
    }

    /**
     * Registers the method channel handlers. Anything that can block (hashing a model, reading the whole store,
     * SQLite) runs on a dedicated executor, never on the platform thread. Starting a scan replaces any queued one,
     * because Dart calls it only when nothing is scanning, and its result comes when the work is enqueued, not
     * finished.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "pickFolder" -> {
                    if (pendingPickResult != null) {
                        result.error("BUSY", "Picker already open", null)
                        return@setMethodCallHandler
                    }
                    pendingPickResult = result
                    launchSafPicker(SafPickerActivity.MODE_FOLDER)
                }

                "pickImage" -> {
                    if (pendingPickResult != null) {
                        result.error("BUSY", "Picker already open", null)
                        return@setMethodCallHandler
                    }
                    pendingPickResult = result
                    launchSafPicker(SafPickerActivity.MODE_IMAGE)
                }


                "scanImagesAndOrVideos" -> {
                    val mode        = call.argument<String>("mode") ?: "folder"
                    val uri         = call.argument<String>("uri")
                    val folderId    = call.argument<String>("folderId") ?: "default"
                    val contentMode = call.argument<String>("contentMode") ?: "both"

                    executor.execute {
                        if (!modelManager.areModelsReady()) {
                            runOnUiThread {
                                result.error(
                                    "MODELS_NOT_READY",
                                    "CLIP models are not downloaded yet",
                                    null
                                )
                            }
                            return@execute
                        }

                        val request = OneTimeWorkRequestBuilder<ScanWorker>()
                            .setInputData(
                                workDataOf(
                                    ScanWorker.KEY_MODE to mode,
                                    ScanWorker.KEY_URI to (uri ?: ""),
                                    ScanWorker.KEY_FOLDER_ID to folderId,
                                    ScanWorker.KEY_CONTENT_MODE to contentMode
                                )
                            )
                            .build()

                        WorkManager.getInstance(applicationContext).enqueueUniqueWork(
                            ScanWorker.UNIQUE_WORK_NAME,
                            ExistingWorkPolicy.REPLACE,
                            request
                        )

                        runOnUiThread { result.success(true) }
                    }
                }

                "areModelsReady" -> {
                    executor.execute {
                        val ready = modelManager.areModelsReady()
                        runOnUiThread { result.success(ready) }
                    }
                }

                "getModelInfo" -> {
                    executor.execute {
                        val statuses = modelManager.getModelStatuses().map {
                            mapOf(
                                "id"         to it.id,
                                "fileName"   to it.fileName,
                                "sizeBytes"  to it.sizeBytes,
                                "downloaded" to it.downloaded,
                                "verified"   to it.verified,
                                "group"      to it.group
                            )
                        }
                        runOnUiThread { result.success(statuses) }
                    }
                }

                "downloadModels" -> {
                    val requested = ModelCatalog.MODELS
                    executor.execute {
                        if (requested.all { modelManager.isModelVerified(it) }) {
                            runOnUiThread { result.success(true) }
                            return@execute
                        }
                        if (!modelManager.hasEnoughFreeSpace(requested)) {
                            runOnUiThread {
                                result.error(
                                    "INSUFFICIENT_STORAGE",
                                    "Not enough free space to download the models",
                                    null
                                )
                            }
                            return@execute
                        }

                        downloadExecutor.execute {
                            try {
                                modelManager.download(requested) { progress ->
                                    runOnUiThread {
                                        modelDownloadSink?.success(
                                            mapOf(
                                                "modelId"                to progress.modelId,
                                                "modelFileName"          to progress.modelFileName,
                                                "bytesForModel"          to progress.bytesForModel,
                                                "totalBytesForModel"     to progress.totalBytesForModel,
                                                "overallBytesDownloaded" to progress.overallBytesDownloaded,
                                                "overallTotalBytes"      to progress.overallTotalBytes,
                                                "done"                   to progress.done
                                            )
                                        )
                                    }
                                }
                                runOnUiThread {
                                    result.success(requested.all { modelManager.isModelVerified(it) })
                                }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    result.error("DOWNLOAD_FAILED", e.message, null)
                                }
                            }
                        }
                    }
                }

                "cancelModelDownload" -> {
                    modelManager.cancelDownload()
                    result.success(true)
                }

                "deleteModels" -> faceTask(result) {
                    modelManager.deleteModels()
                    true
                }

                "getEmbeddingCount" -> {
                    result.success(embeddingEngine.getStoredCount())
                }

                "getEmbeddingCountForFolder" -> {
                    val folderId = call.argument<String>("folderId")
                    if (folderId == null) {
                        result.error("NO_FOLDERID", "folderId missing", null)
                        return@setMethodCallHandler
                    }
                    result.success(embeddingEngine.getStoredCountForFolder(folderId))
                }

                "getLibraryStats" -> {
                    searchExecutor.execute {
                        val stats = embeddingEngine.getLibraryStats()
                        runOnUiThread {
                            result.success(
                                mapOf(
                                    "totalEmbeddings" to stats.totalEmbeddings,
                                    "images" to stats.images,
                                    "videos" to stats.videos,
                                    "sizeBytes" to stats.sizeBytes,
                                    "modelResetFrom" to stats.modelResetFrom
                                )
                            )
                        }
                    }
                }

                "clearEmbeddings" -> {
                    embeddingEngine.clearAll()
                    result.success(true)
                }

                "acknowledgeModelReset" -> {
                    embeddingEngine.clearModelReset()
                    result.success(true)
                }

                "getBenchLogs" -> result.success(BenchLog.enabled(applicationContext))

                "setBenchLogs" -> {
                    BenchLog.setEnabled(applicationContext, call.argument<Boolean>("enabled") ?: true)
                    result.success(true)
                }

                "appLogs" -> logExecutor.execute {
                    try {
                        val text = LogDump.collect(applicationContext)
                        runOnUiThread { result.success(text) }
                    } catch (e: Throwable) {
                        runOnUiThread { result.error("LOGS_FAILED", e.message, null) }
                    }
                }

                "encodeText" -> {
                    val tokens = call.argument<List<Int>>("tokens")
                    if (tokens == null || tokens.size != 77) {
                        result.error("INVALID_TOKENS", "Expected 77 tokens", null)
                        return@setMethodCallHandler
                    }
                    // The first call loads both CLIP models from disk (hundreds of MB). On the main thread this froze
                    // the UI badly enough to get the app killed.
                    searchExecutor.execute {
                        try {
                            val embedding = embeddingEngine.encodeText(tokens.toIntArray())
                            runOnUiThread { result.success(embedding.toList()) }
                        } catch (e: ModelsNotReadyException) {
                            runOnUiThread { result.error("MODELS_NOT_READY", e.message, null) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("ENCODE_FAILED", e.message, null) }
                        }
                    }
                }

                "searchByText" -> {
                    val tokens = call.argument<List<Int>>("tokens")
                    val topK   = call.argument<Int>("topK") ?: 20
                    val contentMode = call.argument<String>("contentMode") ?: "both"
                    val personIds = (call.argument<List<*>>("personIds"))
                        ?.mapNotNull { (it as? Number)?.toLong() }
                        ?: emptyList()

                    if (tokens == null || tokens.size != 77) {
                        result.error("INVALID_TOKENS", "Expected 77 tokens", null)
                        return@setMethodCallHandler
                    }

                    searchExecutor.execute {
                        try {
                            val pathFilter = if (personIds.isEmpty()) null else
                                faces.store.peopleMedia(personIds, "together").map { it.uri }.toSet()
                            val startedNs = System.nanoTime()
                            val textEmbedding = embeddingEngine.encodeText(tokens.toIntArray())
                            val encodedNs = System.nanoTime()
                            val results = embeddingEngine.searchByText(textEmbedding, topK, contentMode, pathFilter)
                            val rankedNs = System.nanoTime()
                            // Only numbers are logged, nothing searched for and no file names, since logs can end up
                            // in a shared bug report.
                            BenchLog.log(applicationContext) {
                                "search: encode text ${(encodedNs - startedNs) / 1_000_000}ms, rank ${(rankedNs - encodedNs) / 1_000_000}ms, " +
                                    "${results.size} results | top scores ${results.take(5).map { "%.3f".format(it.score) }}"
                            }

                            val mapped = results.map {
                                mapOf(
                                    "path"        to it.imagePath,
                                    "score"       to it.score,
                                    "isVideo"     to (it.videoUri != null),
                                    "videoUri"    to (it.videoUri ?: ""),
                                    "timestampMs" to it.timestampMs
                                )
                            }

                            runOnUiThread { result.success(mapped) }
                        } catch (e: ModelsNotReadyException) {
                            runOnUiThread { result.error("MODELS_NOT_READY", e.message, null) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("SEARCH_FAILED", e.message, null)
                            }
                        }
                    }
                }

                "searchByImage" -> {
                    val uriString = call.argument<String>("uri")
                    val topK      = call.argument<Int>("topK") ?: 20
                    val contentMode = call.argument<String>("contentMode") ?: "both"

                    if (uriString == null) {
                        result.error("NO_URI", "URI missing", null)
                        return@setMethodCallHandler
                    }

                    searchExecutor.execute {
                        try {
                            val embedding = embeddingEngine.encodeImageFromUri(uriString)
                            val results   = embeddingEngine.searchByImageEmbedding(embedding, topK, contentMode)

                            val mapped = results.map {
                                mapOf(
                                    "path"        to it.imagePath,
                                    "score"       to it.score,
                                    "isVideo"     to (it.videoUri != null),
                                    "videoUri"    to (it.videoUri ?: ""),
                                    "timestampMs" to it.timestampMs
                                )
                            }

                            runOnUiThread { result.success(mapped) }
                        } catch (e: ModelsNotReadyException) {
                            runOnUiThread { result.error("MODELS_NOT_READY", e.message, null) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("SEARCH_FAILED", e.message, null)
                            }
                        }
                    }
                }

                "scoreCollections" -> {
                    val specs = parseCollectionSpecs(call)
                    if (specs == null) {
                        result.error("INVALID_ARGS", "collections missing", null)
                        return@setMethodCallHandler
                    }
                    searchExecutor.execute {
                        try {
                            val scores = embeddingEngine.scoreCollections(resolvePathFilters(specs)).map { s ->
                                mapOf(
                                    "id" to s.id,
                                    "count" to s.count,
                                    "covers" to s.covers.map {
                                        mapOf(
                                            "path" to it.imagePath,
                                            "isVideo" to (it.videoUri != null),
                                            "timestampMs" to it.timestampMs
                                        )
                                    }
                                )
                            }
                            runOnUiThread { result.success(scores) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("COLLECTIONS_FAILED", e.message, null) }
                        }
                    }
                }

                "collectionMembers" -> {
                    val spec = parseCollectionSpecs(call)?.firstOrNull()
                    val limit = call.argument<Int>("limit") ?: 200
                    if (spec == null) {
                        result.error("INVALID_ARGS", "collection missing", null)
                        return@setMethodCallHandler
                    }
                    searchExecutor.execute {
                        try {
                            val resolvedSpec = resolvePathFilters(listOf(spec)).first()
                            val mapped = embeddingEngine.collectionMembers(resolvedSpec, limit).map {
                                mapOf(
                                    "path"        to it.imagePath,
                                    "score"       to it.score,
                                    "isVideo"     to (it.videoUri != null),
                                    "videoUri"    to (it.videoUri ?: ""),
                                    "timestampMs" to it.timestampMs
                                )
                            }
                            runOnUiThread { result.success(mapped) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("COLLECTIONS_FAILED", e.message, null) }
                        }
                    }
                }

                "encodeImage" -> {
                    val uriString = call.argument<String>("uri")
                    val timestampMs = (call.argument<Number>("timestampMs"))?.toLong()

                    if (uriString == null) {
                        result.error("NO_URI", "URI missing", null)
                        return@setMethodCallHandler
                    }

                    searchExecutor.execute {
                        try {
                            val embedding = if (timestampMs == null) {
                                embeddingEngine.encodeImageFromUri(uriString)
                            } else {
                                val uri = android.net.Uri.parse(uriString)
                                synchronized(VideoFrameExtractor.decodeLock) {
                                    val retriever = MediaMetadataRetriever()
                                    try {
                                        retriever.setDataSource(this, uri)
                                        val frame = retriever.getFrameAtTime(
                                            timestampMs * 1000L,
                                            MediaMetadataRetriever.OPTION_CLOSEST
                                        ) ?: throw Exception("Frame extraction failed")
                                        try {
                                            embeddingEngine.encodeBitmap(frame)
                                        } finally {
                                            frame.recycle()
                                        }
                                    } finally {
                                        try { retriever.release() } catch (_: Exception) {}
                                    }
                                }
                            }
                            runOnUiThread { result.success(embedding.toList()) }
                        } catch (e: ModelsNotReadyException) {
                            runOnUiThread { result.error("MODELS_NOT_READY", e.message, null) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("ENCODE_FAILED", e.message, null) }
                        }
                    }
                }

                // OPTION_CLOSEST, not the CLOSEST_SYNC of the thumbnail loader: a search must embed the frame on
                // screen, not the nearest keyframe.
                "searchByVideoFrame" -> {
                    val uriString = call.argument<String>("uri")
                    val timestampMs = (call.argument<Number>("timestampMs") ?: 0).toLong()
                    val topK = call.argument<Int>("topK") ?: 20
                    val contentMode = call.argument<String>("contentMode") ?: "both"

                    if (uriString == null) {
                        result.error("NO_URI", "URI missing", null)
                        return@setMethodCallHandler
                    }

                    searchExecutor.execute {
                        try {
                            val uri = android.net.Uri.parse(uriString)

                            val embedding = synchronized(VideoFrameExtractor.decodeLock) {
                                val retriever = MediaMetadataRetriever()
                                try {
                                    retriever.setDataSource(this, uri)
                                    val frame = retriever.getFrameAtTime(
                                        timestampMs * 1000L,
                                        MediaMetadataRetriever.OPTION_CLOSEST
                                    ) ?: throw Exception("Frame extraction failed")
                                    try {
                                        embeddingEngine.encodeBitmap(frame)
                                    } finally {
                                        frame.recycle()
                                    }
                                } finally {
                                    try { retriever.release() } catch (_: Exception) {}
                                }
                            }

                            val results = embeddingEngine.searchByImageEmbedding(embedding, topK, contentMode)
                            val mapped = results.map {
                                mapOf(
                                    "path"        to it.imagePath,
                                    "score"       to it.score,
                                    "isVideo"     to (it.videoUri != null),
                                    "videoUri"    to (it.videoUri ?: ""),
                                    "timestampMs" to it.timestampMs
                                )
                            }
                            runOnUiThread { result.success(mapped) }
                        } catch (e: ModelsNotReadyException) {
                            runOnUiThread { result.error("MODELS_NOT_READY", e.message, null) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SEARCH_FAILED", e.message, null) }
                        }
                    }
                }

                "explainMatch" -> {
                    val path = call.argument<String>("path")
                    val isVideo = call.argument<Boolean>("isVideo") ?: false
                    val timestampMs = (call.argument<Number>("timestampMs") ?: 0).toLong()
                    @Suppress("UNCHECKED_CAST")
                    val wordsArg = call.argument<List<Map<String, Any>>>("words")

                    if (path == null || wordsArg == null) {
                        result.error("INVALID_ARGS", "path/words missing", null)
                        return@setMethodCallHandler
                    }

                    searchExecutor.execute {
                        try {
                            val itemEmbedding = embeddingEngine.findEmbedding(
                                imagePath = path,
                                videoUri = if (isVideo) path else null,
                                timestampMs = timestampMs
                            )
                            if (itemEmbedding == null) {
                                runOnUiThread { result.success(emptyList<Map<String, Any>>()) }
                                return@execute
                            }

                            val words = wordsArg.mapNotNull { entry ->
                                val word = entry["word"] as? String ?: return@mapNotNull null
                                @Suppress("UNCHECKED_CAST")
                                val tokens = (entry["tokens"] as? List<Int>)?.toIntArray()
                                    ?: return@mapNotNull null
                                if (tokens.size != 77) return@mapNotNull null
                                word to tokens
                            }

                            val scored = embeddingEngine.scoreWordsAgainstItem(itemEmbedding, words)
                            val mapped = scored.map { (word, score) ->
                                mapOf("word" to word, "score" to score)
                            }

                            runOnUiThread { result.success(mapped) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("EXPLAIN_FAILED", e.message, null) }
                        }
                    }
                }

                "loadImageBytes" -> {
                    val uriString    = call.argument<String>("uri")
                    val shouldCompress = call.argument<Boolean>("compress") ?: true
                    val maxDimension = ((call.argument<Number>("maxDimension"))?.toInt()
                        ?: MAX_COMPRESSED_DIMENSION).coerceAtLeast(1)

                    if (uriString == null) {
                        result.error("NO_URI", "URI missing", null)
                        return@setMethodCallHandler
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

                "startFaceScan" -> faceTask(result) {
                    // Faces follow indexing. Starting it here covers it not being set up, such as when the model was
                    // downloaded mid-scan.
                    if (ScanForegroundService.isScanActive) FaceFollower.start(applicationContext)
                    else FaceScanWorker.enqueueIfNeeded(applicationContext)
                }

                "faceStatus" -> faceTask(result) {
                    val (photos, faceCount, people) = faces.store.stats()
                    val hub = FaceScanHub.last
                    mapOf(
                        "photos" to photos,
                        "faces" to faceCount,
                        "people" to people,
                        "running" to (FaceScanHub.running || FaceFollower.isArmed()),
                        "paused" to (hub?.get("paused") == true && FaceScanHub.running),
                        "following" to FaceFollower.isArmed(),
                        "batch" to (hub?.get("batch") == true && FaceScanHub.running),
                        "userPaused" to FaceSettings.paused(applicationContext),
                        "processed" to photos,
                        "total" to ScanEngineHolder.embeddingEngine(applicationContext).indexedImages().size,
                        "failed" to (hub?.get("failed") ?: 0),
                        "runProcessed" to (hub?.get("runProcessed") ?: 0),
                        "elapsedMs" to (hub?.get("elapsedMs") ?: 0L),
                        "error" to hub?.get("error"),
                        "ready" to faces.engine.isReady(),
                        "thorough" to FaceSettings.thorough(applicationContext),
                        "refine" to FaceSettings.refine(applicationContext),
                        "deferredPhotos" to faces.store.deferredPhotoCount(),
                        "scanVideos" to FaceSettings.scanVideos(applicationContext),
                        "videoDensity" to FaceSettings.videoDensity(applicationContext),
                        "videos" to faces.store.videoCount(),
                        "videosTotal" to ScanEngineHolder.embeddingEngine(applicationContext).indexedVideos().size,
                        "tuning" to FaceTuner.summary(applicationContext, faces.engine.store),
                        "strictness" to faces.clusterer.strictness(),
                        "modelsDir" to faces.engine.store.modelsDir.absolutePath,
                    )
                }

                "pauseFaceScan" -> faceTask(result) {
                    FaceSettings.setPaused(applicationContext, true)
                    FaceFollower.stop()
                    WorkManager.getInstance(applicationContext).cancelUniqueWork(FaceScanWorker.UNIQUE_WORK_NAME)
                    true
                }

                "resumeFaceScan" -> faceTask(result) {
                    FaceSettings.setPaused(applicationContext, false)
                    if (ScanForegroundService.isScanActive) FaceFollower.start(applicationContext)
                    else FaceScanWorker.enqueueIfNeeded(applicationContext)
                }

                "retuneFaces" -> faceTask(result) {
                    WorkManager.getInstance(applicationContext).cancelUniqueWork(FaceScanWorker.UNIQUE_WORK_NAME)
                    FaceTuner.reset(applicationContext)
                    FaceScanWorker.enqueueIfNeeded(applicationContext)
                }

                "listPeople" -> faceTask(result) {
                    val hidden = call.argument<Boolean>("hidden") ?: false
                    faces.store.listPeople(hidden).map { p ->
                        mapOf(
                            "id" to p.id,
                            "name" to p.name,
                            "hidden" to p.hidden,
                            "faceCount" to p.faceCount,
                            "photoCount" to p.photoCount,
                            "coverFaceId" to p.coverFaceId,
                            "stackFaceIds" to p.stackFaceIds,
                        )
                    }
                }

                "personSummary" -> faceTask(result) {
                    val id = (call.argument<Number>("personId") ?: 0).toLong()
                    faces.store.personSummary(id)?.let { p ->
                        mapOf(
                            "id" to p.id,
                            "name" to p.name,
                            "hidden" to p.hidden,
                            "faceCount" to p.faceCount,
                            "photoCount" to p.photoCount,
                            "coverFaceId" to p.coverFaceId,
                            "stackFaceIds" to p.stackFaceIds,
                        )
                    }
                }

                "personPhotos" -> faceTask(result) {
                    val id = (call.argument<Number>("personId") ?: 0).toLong()
                    faces.store.personMedia(id).map { m ->
                        mapOf(
                            "path" to m.uri,
                            "score" to 1.0,
                            "isVideo" to m.isVideo,
                            "videoUri" to (if (m.isVideo) m.uri else ""),
                            "timestampMs" to m.tsMs,
                        )
                    }
                }

                "peoplePhotos" -> faceTask(result) {
                    val ids = (call.argument<List<Number>>("personIds") ?: emptyList()).map { it.toLong() }
                    val mode = call.argument<String>("mode") ?: "together"
                    faces.store.peopleMedia(ids, mode).map { m ->
                        mapOf(
                            "path" to m.uri,
                            "score" to 1.0,
                            "isVideo" to m.isVideo,
                            "videoUri" to (if (m.isVideo) m.uri else ""),
                            "timestampMs" to m.tsMs,
                        )
                    }
                }

                "peopleCounts" -> faceTask(result) {
                    val ids = (call.argument<List<Number>>("personIds") ?: emptyList()).map { it.toLong() }
                    faces.store.peopleCounts(ids)
                }

                "peopleIn" -> faceTask(result) {
                    val uris = call.argument<List<String>>("uris") ?: emptyList()
                    faces.store.peopleIn(uris).map { (id, count) -> mapOf("personId" to id, "count" to count) }
                }

                "peopleTimeline" -> faceTask(result) {
                    val budget = (call.argument<Number>("budgetMs") ?: 800).toLong()
                    val now = System.currentTimeMillis()
                    val deadline = android.os.SystemClock.elapsedRealtime() + budget
                    while (android.os.SystemClock.elapsedRealtime() < deadline) {
                        val batch = faces.store.mediaMissingDates(300)
                        if (batch.isEmpty()) break
                        val found = dev.raseel.lostandfound.features.people.timeline.MediaDates.resolve(applicationContext, batch, now, deadline)
                        if (found.isEmpty()) break
                        faces.store.putDates(found)
                    }
                    val (total, pending) = faces.store.dateProgress()
                    val timeline = faces.store.peopleTimeline(full = pending == 0)
                    mapOf(
                        "total" to total,
                        "pending" to pending,
                        "people" to timeline.rows.map { r ->
                            mapOf(
                                "id" to r.personId,
                                "dated" to r.dated,
                                "undated" to r.undated,
                                "months" to r.months.toList(),
                            )
                        },
                        "together" to timeline.together.map { c ->
                            mapOf(
                                "id" to c.personId,
                                "withId" to c.withId,
                                "count" to c.count,
                                "firstMs" to c.firstMs,
                                "first" to timeline.togetherFirst[c.personId]?.let { g -> groupMap(g) },
                            )
                        },
                        "crowds" to timeline.crowds.map { g -> groupMap(g) },
                        "reunions" to timeline.reunions.map { g -> groupMap(g) },
                    )
                }

                "timelinePicks" -> faceTask(result) {
                    faces.store.timelinePicks(perMonth = 6, burstMs = 120_000L).map { m ->
                        mapOf(
                            "key" to m.key,
                            "uri" to m.uri,
                            "isVideo" to m.isVideo,
                            "tsMs" to m.tsMs,
                            "takenMs" to m.takenMs,
                        )
                    }
                }

                "timelineMonthPhotos" -> faceTask(result) {
                    val start = (call.argument<Number>("startMs") ?: 0).toLong()
                    val end = (call.argument<Number>("endMs") ?: 0).toLong()
                    val ids = (call.argument<List<Number>>("personIds") ?: emptyList()).map { it.toLong() }
                    faces.store.personPhotosBetween(start, end, ids).map { m ->
                        mapOf(
                            "personId" to m.personId,
                            "key" to m.key,
                            "uri" to m.uri,
                            "isVideo" to m.isVideo,
                            "tsMs" to m.tsMs,
                            "takenMs" to m.takenMs,
                        )
                    }
                }

                "timelineMonthMedia" -> faceTask(result) {
                    val start = (call.argument<Number>("startMs") ?: 0).toLong()
                    val end = (call.argument<Number>("endMs") ?: 0).toLong()
                    val limit = (call.argument<Number>("limit") ?: 9).toInt()
                    val burst = (call.argument<Number>("burstMs") ?: 20_000).toLong()
                    val media = faces.store.monthMedia(start, end, limit, burstMs = burst)
                    mapOf(
                        "total" to media.total,
                        "items" to media.items.map { m ->
                            mapOf(
                                "key" to m.key,
                                "uri" to m.uri,
                                "isVideo" to m.isVideo,
                                "tsMs" to m.tsMs,
                                "takenMs" to m.takenMs,
                            )
                        },
                    )
                }

                "memoryPrepare" -> memoryTask(result) {
                    val budget = (call.argument<Number>("budgetMs") ?: 600).toLong()
                    val dates = LibraryDates.get(applicationContext)
                    val faceStore = faces.store
                    dates.sync(embeddingEngine)
                    val pending = dates.resolve(applicationContext, faceStore, budget)
                    mapOf("total" to dates.progress().first, "pending" to pending)
                }

                "mediaDates" -> memoryTask(result) {
                    val uris = call.argument<List<String>>("uris") ?: emptyList()
                    val dates = LibraryDates.get(applicationContext)
                    try {
                        dates.sync(embeddingEngine)
                        dates.resolve(applicationContext, faces.store, 150L)
                    } catch (e: Exception) {
                        android.util.Log.w("MainActivity", "dates for stories failed: ${e.message}")
                    }
                    dates.datesFor(uris).map { mapOf("uri" to it.uri, "takenMs" to it.takenMs, "junk" to it.junk) }
                }

                "storiesReminder" -> {
                    call.argument<Boolean>("enabled")?.let { StoriesReminder.setEnabled(applicationContext, it) }
                    if (call.hasArgument("ringsJson")) StoriesReminder.setRings(applicationContext, call.argument<String>("ringsJson"))
                    if (call.argument<Boolean>("cancel") == true) StoriesReminder.cancel(applicationContext)
                    call.argument<Number>("atMs")?.let { StoriesReminder.schedule(applicationContext, it.toLong()) }
                    result.success(
                        mapOf(
                            "enabled" to StoriesReminder.enabled(applicationContext),
                            "allowed" to MemoryNotifier.allowed(applicationContext),
                        )
                    )
                }

                "storiesReminderTest" -> memoryTask(result) {
                    StoriesReminder.post(applicationContext, call.argument<String>("ringsJson"), test = true)
                }

                "onThisDay" -> memoryTask(result) {
                    val planner = MemoryPlanner(LibraryDates.get(applicationContext), faces.store)
                    planMap(planner.plan(System.currentTimeMillis(), withWeek = true, withAnniversaries = true))
                }

                "thenAndNow" -> memoryTask(result) {
                    val personId = (call.argument<Number>("personId") ?: 0).toLong()
                    val found = faces.store.personDatedFaces(personId)
                    val seed = MemoryDays.dayNumber(System.currentTimeMillis()) * 31L + personId
                    val r = ThenNow.choose(found.map { MemoryEvergreen.cand(it) }, seed = seed)
                    if (r == null) {
                        null
                    } else {
                        val names = faces.store.namesOf((r.allThen + r.allNow).mapNotNull { it.partner }.toSet())
                        fun side(c: ThenNow.Cand): Map<String, Any?> {
                            val withId = c.partner?.takeIf { names[it] != null }
                            val box = c.box(withId)
                            val pair = withId != null && c.others.any { it.personId == withId }
                            return mapOf(
                                "key" to c.key,
                                "uri" to c.uri,
                                "faceId" to c.faceId,
                                "takenMs" to c.takenMs,
                                "boxL" to box[0].toDouble(), "boxT" to box[1].toDouble(),
                                "boxR" to box[2].toDouble(), "boxB" to box[3].toDouble(),
                                "photoW" to c.photoW, "photoH" to c.photoH,
                                "margin" to (if (pair) MemoryEvergreen.DUO_MARGIN else 3.1f).toDouble(),
                                "lift" to (if (pair) 0.0 else 0.55),
                                "faces" to c.faces,
                                "kind" to c.kind.code,
                                "withName" to withId?.let { names[it] },
                            )
                        }
                        val startThen = r.allThen.indexOf(r.then[r.startThen]).coerceAtLeast(0)
                        val startNow = r.allNow.indexOf(r.now[r.startNow]).coerceAtLeast(0)
                        mapOf(
                            "then" to r.allThen.map { side(it) },
                            "now" to r.allNow.map { side(it) },
                            "startThen" to startThen,
                            "startNow" to startNow,
                            "spanMonths" to r.spanMonths,
                            "lastMonth" to r.lastMonth,
                        )
                    }
                }

                "portraitCrop" -> faceCropExecutor.execute {
                    try {
                        val bytes = faces.crops.portrait(
                            call.argument<String>("uri") ?: "",
                            (call.argument<Number>("boxL") ?: 0).toFloat(),
                            (call.argument<Number>("boxT") ?: 0).toFloat(),
                            (call.argument<Number>("boxR") ?: 0).toFloat(),
                            (call.argument<Number>("boxB") ?: 0).toFloat(),
                            (call.argument<Number>("photoW") ?: 0).toInt(),
                            (call.argument<Number>("photoH") ?: 0).toInt(),
                            (call.argument<Number>("size") ?: 640).toInt(),
                            (call.argument<Number>("margin") ?: 3.1).toFloat(),
                            (call.argument<Number>("lift") ?: 0.55).toFloat(),
                        )
                        runOnUiThread { result.success(bytes) }
                    } catch (e: Throwable) {
                        runOnUiThread { result.error("PORTRAIT_FAILED", e.message, null) }
                    }
                }

                "memoryDay" -> memoryTask(result) {
                    val start = (call.argument<Number>("startMs") ?: 0).toLong()
                    val end = (call.argument<Number>("endMs") ?: 0).toLong()
                    val limit = (call.argument<Number>("limit") ?: 2000).toInt()
                    val dates = LibraryDates.get(applicationContext)
                    mapOf(
                        "total" to dates.count(start, end),
                        "items" to dates.photos(start, end, limit).map { m ->
                            mapOf(
                                "key" to m.key,
                                "uri" to m.uri,
                                "isVideo" to m.video,
                                "tsMs" to (if (m.video) 1000L else 0L),
                                "takenMs" to m.takenMs,
                            )
                        },
                    )
                }

                "memorySettings" -> result.success(memorySettingsMap())

                "videoEnv" -> result.success(videoEnvMap())

                "setMemorySettings" -> {
                    val prefs = MemoryPrefs(applicationContext)
                    call.argument<Boolean>("enabled")?.let { prefs.enabled = it }
                    MemoryScheduler.apply(applicationContext, replace = true)
                    result.success(memorySettingsMap())
                }

                "memoryTest" -> memoryTask(result) {
                    val outcome = MemoryDay.run(applicationContext, test = true, budgetMs = 4_000L)
                    mapOf("sent" to outcome.sent?.code, "message" to outcome.message)
                }

                "androidSdk" -> result.success(Build.VERSION.SDK_INT)

                "takeOpenTab" -> {
                    result.success(openTab)
                    openTab = -1
                }

                "getIndexNudge" -> result.success(IndexNudge.enabled(applicationContext))

                "setIndexNudge" -> {
                    IndexNudge.setEnabled(applicationContext, call.argument<Boolean>("enabled") ?: true)
                    result.success(true)
                }

                "takeIndexNow" -> {
                    result.success(indexNow)
                    indexNow = false
                }

                "takeLaunchMemory" -> {
                    val launch = MemoryPrefs(applicationContext).takeLaunch()
                    result.success(launch?.let { mapOf("kind" to it.kind, "year" to it.year, "personId" to it.personId) })
                }

                "personFaces" -> faceTask(result) {
                    val id = (call.argument<Number>("personId") ?: 0).toLong()
                    faces.store.personFaces(id).map { f ->
                        mapOf("faceId" to f.faceId, "good" to f.good, "photoUri" to f.photoUri, "isVideo" to f.isVideo)
                    }
                }

                "videoFaces" -> photoFacesExecutor.execute {
                    try {
                        val uri = call.argument<String>("uri") ?: ""
                        val positionMs = (call.argument<Number>("positionMs") ?: 0).toLong()
                        val token = call.argument<Number>("token")?.toLong()
                        if (token != null && cancelledPhotoScans.remove(token)) {
                            runOnUiThread { result.success(emptyList<Any>()) }
                            return@execute
                        }
                        val key = "$uri#$positionMs"
                        val progress = PhotoScanProgress()
                        faces.scanner.photoProgress[key] = progress
                        val identities = try {
                            faces.videoScanner.identifyFrame(uri, positionMs, progress)
                        } finally {
                            faces.scanner.photoProgress.remove(key)
                        } ?: emptyList()
                        try {
                            faces.store.recordVideoSeen(uri, positionMs, identities.map { it.personId }.toSet())
                            faces.videoScanner.storeLooked(uri, positionMs, identities)
                        } catch (_: Throwable) {
                        }
                        val out = identities.mapIndexedNotNull { i, f ->
                            val p = faces.store.personSummary(f.personId)
                            if (p == null || p.hidden) {
                                null
                            } else {
                                mapOf(
                                    // Not a stored face: a made-up id, only to tell them apart on screen.
                                    "faceId" to -(i + 1).toLong(),
                                    "left" to f.left, "top" to f.top, "right" to f.right, "bottom" to f.bottom,
                                    "photoW" to f.frameW, "photoH" to f.frameH,
                                    "person" to mapOf(
                                        "id" to p.id,
                                        "name" to p.name,
                                        "hidden" to p.hidden,
                                        "faceCount" to p.faceCount,
                                        "photoCount" to p.photoCount,
                                        "coverFaceId" to p.coverFaceId,
                                    ),
                                )
                            }
                        }
                        runOnUiThread { result.success(out) }
                    } catch (e: Throwable) {
                        runOnUiThread { result.error("VIDEO_FACES_FAILED", e.message ?: e.toString(), null) }
                    }
                }

                "videoFrameFaces" -> faceTask(result) {
                    val uri = call.argument<String>("uri") ?: ""
                    val tsMs = (call.argument<Number>("tsMs") ?: 0).toLong()
                    val (exact, stored) = faces.store.videoFrameFaces(uri, tsMs)
                    val summaries = HashMap<Long, dev.raseel.lostandfound.features.people.PersonSummary?>()
                    val list = stored.mapNotNull { f ->
                        val p = summaries.getOrPut(f.personId) { faces.store.personSummary(f.personId) }
                        if (p == null || p.hidden) {
                            null
                        } else {
                            mapOf(
                                "faceId" to f.faceId,
                                "left" to f.boxL, "top" to f.boxT, "right" to f.boxR, "bottom" to f.boxB,
                                "photoW" to f.photoW, "photoH" to f.photoH,
                                "person" to mapOf(
                                    "id" to p.id,
                                    "name" to p.name,
                                    "hidden" to p.hidden,
                                    "faceCount" to p.faceCount,
                                    "photoCount" to p.photoCount,
                                    "coverFaceId" to p.coverFaceId,
                                ),
                            )
                        }
                    }
                    mapOf("exact" to exact, "faces" to list)
                }

                "videoPeople" -> faceTask(result) {
                    val uri = call.argument<String>("uri") ?: ""
                    val times = LinkedHashMap<Long, MutableList<Long>>()
                    val stored = HashMap<Long, MutableList<Long>>()
                    for ((personId, ts) in faces.store.videoSightings(uri)) {
                        times.getOrPut(personId) { ArrayList() }.add(ts)
                        stored.getOrPut(personId) { ArrayList() }.add(ts)
                    }
                    val looked = HashSet<Long>()
                    for ((personId, ts) in faces.store.videoSeen(uri)) {
                        times.getOrPut(personId) { ArrayList() }.add(ts)
                        looked += personId
                    }
                    times.mapNotNull { (personId, list) ->
                        val p = faces.store.personSummary(personId)
                        // Someone known elsewhere, or seen in at least two moments of this video: one stray frame is
                        // more likely a bystander.
                        val enough = p != null &&
                            (p.photoCount >= dev.raseel.lostandfound.features.people.FaceStore.MIN_PHOTOS_TO_SHOW ||
                                list.distinct().size >= 2 || personId in looked)
                        if (p == null || p.hidden || !enough) {
                            null
                        } else {
                            mapOf(
                                "person" to mapOf(
                                    "id" to p.id,
                                    "name" to p.name,
                                    "hidden" to p.hidden,
                                    "faceCount" to p.faceCount,
                                    "photoCount" to p.photoCount,
                                    "coverFaceId" to p.coverFaceId,
                                ),
                                "times" to list.distinct().sorted(),
                                "stored" to (stored[personId] ?: emptyList<Long>()).distinct().sorted(),
                            )
                        }
                    }
                }

                "videoScanState" -> faceTask(result) {
                    val plan = faces.scanner.videoScanPlan(call.argument<String>("uri") ?: "")
                    mapOf("state" to plan.state, "level" to plan.level, "lastFaces" to plan.lastFaces)
                }

                "scanVideoFaces" -> videoScanExecutor.execute {
                    try {
                        val uri = call.argument<String>("uri") ?: ""
                        val token = call.argument<Number>("token")?.toLong()
                        if (token != null && cancelledPhotoScans.remove(token)) {
                            runOnUiThread { result.success(mapOf("scanned" to false, "level" to 0, "faces" to 0)) }
                            return@execute
                        }
                        val scanned = try {
                            faces.scanner.scanVideoNow(uri)
                        } catch (e: Throwable) {
                            android.util.Log.w("MainActivity", "scanning video $uri failed: ${e.message}")
                            dev.raseel.lostandfound.features.people.FaceScanner.VideoScanResult(false, 0, 0)
                        }
                        runOnUiThread {
                            result.success(mapOf("scanned" to scanned.scanned, "level" to scanned.level, "faces" to scanned.faces))
                        }
                    } catch (e: Throwable) {
                        runOnUiThread { result.error("SCAN_VIDEO_FAILED", e.message ?: e.toString(), null) }
                    }
                }

                "cancelPhotoFaces" -> {
                    (call.argument<Number>("token"))?.let {
                        if (cancelledPhotoScans.size > 200) cancelledPhotoScans.clear()
                        cancelledPhotoScans.add(it.toLong())
                    }
                    result.success(true)
                }

                "photoFaces" -> photoFacesExecutor.execute {
                    try {
                        val uri = call.argument<String>("uri") ?: ""
                        val token = call.argument<Number>("token")?.toLong()
                        if (token != null && cancelledPhotoScans.remove(token)) {
                            runOnUiThread { result.success(emptyList<Any>()) }
                            return@execute
                        }
                        try {
                            faces.scanner.scanOne(uri)
                        } catch (e: Throwable) {
                            android.util.Log.w("MainActivity", "scanning $uri failed: ${e.message}")
                        }
                        val summaries = HashMap<Long, dev.raseel.lostandfound.features.people.PersonSummary?>()
                        val found = faces.store.photoFaces(uri).mapNotNull { f ->
                            val p = summaries.getOrPut(f.personId) { faces.store.personSummary(f.personId) }
                            if (p == null || p.hidden) {
                                null
                            } else {
                                mapOf(
                                    "faceId" to f.faceId,
                                    "left" to f.boxL, "top" to f.boxT, "right" to f.boxR, "bottom" to f.boxB,
                                    "photoW" to f.photoW, "photoH" to f.photoH,
                                    "person" to mapOf(
                                        "id" to p.id,
                                        "name" to p.name,
                                        "hidden" to p.hidden,
                                        "faceCount" to p.faceCount,
                                        "photoCount" to p.photoCount,
                                        "coverFaceId" to p.coverFaceId,
                                    ),
                                )
                            }
                        }
                        runOnUiThread { result.success(found) }
                    } catch (e: Throwable) {
                        runOnUiThread { result.error("PHOTO_FACES_FAILED", e.message ?: e.toString(), null) }
                    }
                }

                "photoScanStatus" -> faceTask(result) {
                    faces.scanner.photoProgress[call.argument<String>("uri") ?: ""]?.let { p ->
                        mapOf(
                            "stage" to p.stage, "faces" to p.faces, "total" to p.total, "more" to p.more,
                            "video" to p.video, "step" to p.step, "steps" to p.steps, "relax" to p.relax,
                        )
                    }
                }

                "buildInfo" -> result.success(
                    mapOf(
                        "version" to BuildConfig.VERSION_NAME,
                        "build" to BuildConfig.VERSION_CODE,
                        "commit" to BuildConfig.GIT_COMMIT,
                        "commitDate" to BuildConfig.GIT_COMMIT_DATE,
                        "debug" to BuildConfig.DEBUG,
                    ),
                )

                "deviceChip" -> {
                    val soc = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
                    val cores = Runtime.getRuntime().availableProcessors()
                    var maxKhz = 0L
                    for (i in 0 until cores) {
                        try {
                            val khz = java.io.File("/sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq")
                                .readText().trim().toLong()
                            if (khz > maxKhz) maxKhz = khz
                        } catch (_: Exception) {
                        }
                    }
                    val memory = android.app.ActivityManager.MemoryInfo()
                    (getSystemService(android.content.Context.ACTIVITY_SERVICE) as android.app.ActivityManager)
                        .getMemoryInfo(memory)
                    result.success(
                        mapOf(
                            "maker" to (if (soc) Build.SOC_MANUFACTURER else ""),
                            "model" to (if (soc) Build.SOC_MODEL else ""),
                            "hardware" to Build.HARDWARE,
                            "cores" to cores,
                            "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
                            "maxMhz" to (maxKhz / 1000).toInt(),
                            "ramMb" to (memory.totalMem / (1024 * 1024)).toInt(),
                            "release" to Build.VERSION.RELEASE,
                        )
                    )
                }

                "loadUprightPhoto" -> {
                    val uriString = call.argument<String>("uri")
                    val maxSide = (call.argument<Number>("maxSide") ?: 360).toInt().coerceAtLeast(64)
                    if (uriString == null) {
                        result.error("NO_URI", "URI missing", null)
                        return@setMethodCallHandler
                    }
                    faceCropExecutor.execute {
                        try {
                            val bitmap = FaceImageLoader.load(applicationContext, android.net.Uri.parse(uriString), maxSide)
                                ?: throw Exception("Cannot decode image")
                            val output = ByteArrayOutputStream()
                            bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 88, output)
                            bitmap.recycle()
                            runOnUiThread { result.success(output.toByteArray()) }
                        } catch (e: Throwable) {
                            runOnUiThread { result.error("LOAD_FAILED", e.message ?: e.toString(), null) }
                        }
                    }
                }

                "faceCrop" -> {
                    val faceId = (call.argument<Number>("faceId") ?: 0).toLong()
                    val size = (call.argument<Number>("size") ?: 256).toInt()
                    faceCropExecutor.execute {
                        try {
                            val bytes = faces.crops.crop(faceId, size)
                            runOnUiThread {
                                if (bytes == null) result.error("NO_CROP", "Face not found", null)
                                else result.success(bytes)
                            }
                        } catch (e: Throwable) {
                            runOnUiThread { result.error("CROP_FAILED", e.message ?: e.toString(), null) }
                        }
                    }
                }

                "renamePerson" -> faceTask(result) {
                    faces.clusterer.rename(
                        (call.argument<Number>("personId") ?: 0).toLong(),
                        call.argument<String>("name"),
                    )
                    true
                }

                "hidePerson" -> faceTask(result) {
                    faces.clusterer.setHidden(
                        (call.argument<Number>("personId") ?: 0).toLong(),
                        call.argument<Boolean>("hidden") ?: true,
                    )
                    true
                }

                "mergePeople" -> faceTask(result) {
                    faces.clusterer.merge(
                        (call.argument<Number>("keepId") ?: 0).toLong(),
                        (call.argument<Number>("otherId") ?: 0).toLong(),
                    )
                }

                "mergeHistory" -> faceTask(result) {
                    faces.store.mergeHistory().map { r ->
                        mapOf(
                            "id" to r.id,
                            "keptId" to r.keptId,
                            "keptName" to r.keptName,
                            "keptCover" to r.keptCover,
                            "removedName" to r.removedName,
                            "removedCover" to r.removedCover,
                            "faceCount" to r.faceIds.size,
                            "createdAt" to r.createdAt,
                        )
                    }
                }

                "previewSplit" -> faceTask(result) {
                    faces.clusterer.previewSplit((call.argument<Number>("personId") ?: 0).toLong())?.let { p ->
                        mapOf(
                            "first" to p.first,
                            "second" to p.second,
                            "firstCovers" to p.firstCovers,
                            "secondCovers" to p.secondCovers,
                        )
                    }
                }

                "splitPerson" -> faceTask(result) {
                    val ids = (call.argument<List<Number>>("faceIds") ?: emptyList()).map { it.toLong() }
                    faces.clusterer.splitPerson((call.argument<Number>("personId") ?: 0).toLong(), ids)
                }

                "undoMerge" -> faceTask(result) {
                    faces.clusterer.undoMerge((call.argument<Number>("id") ?: 0).toLong())
                }

                "suggestMerges" -> faceTask(result) {
                    val limit = (call.argument<Number>("limit") ?: 20).toInt()
                    faces.clusterer.suggestMerges(limit).map {
                        mapOf("a" to it.aId, "b" to it.bId, "score" to it.score.toDouble())
                    }
                }

                "rejectMerge" -> faceTask(result) {
                    faces.clusterer.rejectMerge(
                        (call.argument<Number>("a") ?: 0).toLong(),
                        (call.argument<Number>("b") ?: 0).toLong(),
                    )
                    true
                }

                "removeFace" -> faceTask(result) {
                    faces.clusterer.removeFace((call.argument<Number>("faceId") ?: 0).toLong())
                    true
                }

                "regroupFaces" -> faceTask(result) {
                    faces.clusterer.regroup()
                    true
                }

                "resetFaces" -> faceTask(result) {
                    // Stop a running scan first so it does not write into the fresh start.
                    FaceFollower.stop()
                    WorkManager.getInstance(applicationContext).cancelUniqueWork(FaceScanWorker.UNIQUE_WORK_NAME)
                    FaceSettings.setPaused(applicationContext, false)
                    faces.store.wipeAll()
                    faces.clusterer.invalidate()
                    true
                }

                "setFaceSettings" -> faceTask(result) {
                    call.argument<Boolean>("thorough")?.let { FaceSettings.setThorough(applicationContext, it) }
                    call.argument<Boolean>("refine")?.let {
                        FaceSettings.setRefine(applicationContext, it)
                    }
                    call.argument<String>("strictness")?.let {
                        if (it in listOf(FaceClusterConfig.STRICT, FaceClusterConfig.BALANCED, FaceClusterConfig.LOOSE)) {
                            faces.clusterer.setStrictness(it)
                        }
                    }
                    call.argument<String>("videoDensity")?.let { FaceSettings.setVideoDensity(applicationContext, it) }
                    call.argument<Boolean>("scanVideos")?.let {
                        FaceSettings.setScanVideos(applicationContext, it)
                    }
                    true
                }

                "faceModels" -> faceTask(result) {
                    val store = faces.engine.store
                    val models = FaceModelKind.values().flatMap { kind ->
                        val chosen = store.selected(kind)?.spec?.id
                        store.available(kind).map { m ->
                            mapOf(
                                "kind" to kind.name.lowercase(),
                                "id" to m.spec.id,
                                "name" to m.spec.displayName,
                                "sizeBytes" to m.sizeBytes,
                                "source" to m.source,
                                "selected" to (m.spec.id == chosen),
                            )
                        }
                    }
                    mapOf("dir" to store.modelsDir.absolutePath, "models" to models)
                }

                "selectFaceModel" -> faceTask(result) {
                    val kind = call.argument<String>("kind") ?: throw IllegalArgumentException("kind required")
                    val id = call.argument<String>("id") ?: throw IllegalArgumentException("id required")
                    // A running scan must not carry on with the other model.
                    FaceFollower.stop()
                    WorkManager.getInstance(applicationContext).cancelUniqueWork(FaceScanWorker.UNIQUE_WORK_NAME)
                    FaceSettings.setPaused(applicationContext, false)
                    faces.engine.store.select(FaceModelKind.valueOf(kind.uppercase()), id)
                    true
                }

                "loadThumbnail" -> {
                    val uriString   = call.argument<String>("uri")
                    val isVideo     = call.argument<Boolean>("isVideo") ?: false
                    val timestampMs = (call.argument<Number>("timestampMs") ?: 0).toLong()
                    val size        = (call.argument<Number>("size") ?: 400).toInt()

                    if (uriString == null) {
                        result.error("NO_URI", "URI missing", null)
                        return@setMethodCallHandler
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
                        return@setMethodCallHandler
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

                "loadMetadataByUri" -> {
                    val uriString = call.argument<String>("uri")
                    val isVideo = call.argument<Boolean>("isVideo") ?: false

                    if (uriString == null) {
                        result.error("NO_URI", "URI missing", null)
                        return@setMethodCallHandler
                    }

                    searchExecutor.execute {
                        try {
                            val uri = android.net.Uri.parse(uriString)

                            var fileName = ""
                            var fileSize = 0L

                            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                                if (cursor.moveToFirst()) {
                                    val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                                    val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                                    if (nameIndex >= 0) fileName = cursor.getString(nameIndex) ?: ""
                                    if (sizeIndex >= 0) fileSize = cursor.getLong(sizeIndex)
                                }
                            }

                            val mimeType = contentResolver.getType(uri) ?: ""

                            val metadata = if (isVideo) {
                                loadVideoMetadata(uri, fileName, fileSize, mimeType)
                            } else {
                                loadImageMetadata(uri, fileName, fileSize, mimeType)
                            }
                            // Both keys hold the same string: "uri" identifies the file to other native calls, and
                            // "imagePath" is what ImageMetadata.fromMap reads for the "File path" row.
                            metadata["uri"] = uriString
                            metadata["imagePath"] = uriString

                            runOnUiThread { result.success(metadata) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("LOAD_METADATA_FAILED", e.message ?: "Invalid URI", null)
                            }
                        }
                    }
                }

                "shareFile" -> {
                    val uriString = call.argument<String>("uri")
                    val isVideo = call.argument<Boolean>("isVideo") ?: false
                    if (uriString == null) {
                        result.error("NO_URI", "URI missing", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = android.net.Uri.parse(uriString)
                        val mimeType = contentResolver.getType(uri) ?: if (isVideo) "video/*" else "image/*"
                        val shareIntent = Intent(Intent.ACTION_SEND).apply {
                            type = mimeType
                            putExtra(Intent.EXTRA_STREAM, uri)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        startActivity(Intent.createChooser(shareIntent, null).apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        })
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SHARE_FAILED", e.message, null)
                    }
                }

                "saveCopyToGallery" -> {
                    val uriString = call.argument<String>("uri")
                    val isVideo = call.argument<Boolean>("isVideo") ?: false
                    if (uriString == null) {
                        result.error("NO_URI", "URI missing", null)
                        return@setMethodCallHandler
                    }
                    searchExecutor.execute {
                        try {
                            saveCopyToGallery(android.net.Uri.parse(uriString), isVideo)
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("SAVE_FAILED", e.message, null) }
                        }
                    }
                }

                "setAsWallpaper" -> {
                    val uriString = call.argument<String>("uri")
                    if (uriString == null) {
                        result.error("NO_URI", "URI missing", null)
                        return@setMethodCallHandler
                    }
                    searchExecutor.execute {
                        try {
                            val uri = android.net.Uri.parse(uriString)
                            contentResolver.openInputStream(uri)?.use { input ->
                                android.app.WallpaperManager.getInstance(applicationContext)
                                    .setStream(input)
                            } ?: throw Exception("Cannot open image")
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("WALLPAPER_FAILED", e.message, null) }
                        }
                    }
                }

                "copyImageToClipboard" -> {
                    val uriString = call.argument<String>("uri")
                    if (uriString == null) {
                        result.error("NO_URI", "URI missing", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val uri = android.net.Uri.parse(uriString)
                        val clipboard = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
                        clipboard.setPrimaryClip(
                            android.content.ClipData.newUri(contentResolver, "Image", uri)
                        )
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CLIPBOARD_FAILED", e.message, null)
                    }
                }

                "deleteEmbeddingsByFolderId" -> {
                    val folderId = call.argument<String>("folderId")

                    if (folderId == null) {
                        result.error("NO_FOLDERID", "folderId missing", null)
                        return@setMethodCallHandler
                    }

                    executor.execute {
                        try {
                            embeddingEngine.deleteEmbeddingsForFolder(folderId)
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            runOnUiThread {
                                result.error("DELETION_FAILED", e.message, null)
                            }
                        }
                    }
                }

                "cancelEmbedding" -> {
                    embeddingEngine.cancelEmbedding()
                    result.success(true)
                }

                "pickExportFolder" -> {
                    if (pendingPickResult != null) {
                        result.error("BUSY", "Picker already open", null)
                        return@setMethodCallHandler
                    }
                    pendingPickResult = result
                    launchSafPicker(SafPickerActivity.MODE_EXPORT_FOLDER)
                }

                "exportItemInfo" -> {
                    val uris = (call.argument<List<String>>("uris") ?: emptyList())
                    exportExecutor.execute {
                        try {
                            val infos = uris.map {
                                val info = dev.raseel.lostandfound.features.export.ExportItems.resolve(applicationContext, it)
                                mapOf(
                                    "name" to info.name,
                                    "size" to info.size,
                                    "takenMs" to info.takenMs,
                                    "modifiedMs" to info.modifiedMs,
                                )
                            }
                            runOnUiThread { result.success(infos) }
                        } catch (e: Throwable) {
                            runOnUiThread { result.error("EXPORT_INFO_FAILED", e.message, null) }
                        }
                    }
                }

                "exportFreeSpace" -> {
                    result.success(
                        try {
                            android.os.StatFs(android.os.Environment.getExternalStorageDirectory().path).availableBytes
                        } catch (e: Exception) {
                            -1L
                        }
                    )
                }

                "exportDownloadsAvailable" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)

                "startZipExport" -> {
                    val job = call.argument<String>("job")
                    if (job == null) {
                        result.error("NO_JOB", "Job missing", null)
                        return@setMethodCallHandler
                    }
                    exportExecutor.execute {
                        val started = try {
                            dev.raseel.lostandfound.features.export.ZipExport.start(applicationContext, job)
                        } catch (e: Throwable) {
                            null
                        }
                        runOnUiThread {
                            if (started == null) result.error("EXPORT_FAILED", "Could not start", null)
                            else result.success(started)
                        }
                    }
                }

                "zipExportStatus" -> result.success(dev.raseel.lostandfound.features.export.ZipExportState.toMap())

                "cancelZipExport" -> {
                    dev.raseel.lostandfound.features.export.ZipExport.cancel()
                    result.success(true)
                }

                "shareZips" -> {
                    val uris = (call.argument<List<String>>("uris") ?: emptyList()).map { android.net.Uri.parse(it) }
                    if (uris.isEmpty()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val send = Intent(if (uris.size == 1) Intent.ACTION_SEND else Intent.ACTION_SEND_MULTIPLE).apply {
                        type = "application/zip"
                        if (uris.size == 1) putExtra(Intent.EXTRA_STREAM, uris[0])
                        else putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    }
                    startActivity(Intent.createChooser(send, "Send the zip").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    result.success(true)
                }

                "openDownloads" -> {
                    try {
                        startActivity(Intent(android.app.DownloadManager.ACTION_VIEW_DOWNLOADS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }

                "takeLatestScan" -> {
                    faceCropExecutor.execute {
                        val items = try {
                            dev.raseel.lostandfound.features.library.LatestScan.take(applicationContext)
                        } catch (e: Throwable) {
                            emptyList()
                        }
                        runOnUiThread { result.success(items) }
                    }
                }

                // No battery-optimization exemption is requested: Play policy allows it only for a short list of core
                // uses, and WorkManager restarts a killed scan.
                "getActiveScanProgress" -> {
                    // A running scan that has not reported yet (WorkManager restarts one after a kill) shows as
                    // starting. "stopping" is read live: no tick comes after Stop.
                    result.success(
                        ScanForegroundService.activeProgress()
                            ?.plus("stopping" to embeddingEngine.wasCancelled())
                            ?: if (ScanForegroundService.isScanActive) mapOf(
                                "id" to "",
                                "total" to 0,
                                "processed" to 0,
                                "embedded" to 0,
                                "elapsedMs" to 0L,
                                "skipped" to 0,
                                "done" to false,
                                "path" to "",
                                "recentItems" to emptyList<Map<String, Any>>(),
                            ) else null
                    )
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PROGRESS_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                ScanForegroundService.setProgressSink(events)
            }
            override fun onCancel(arguments: Any?) {
                ScanForegroundService.setProgressSink(null)
            }
        })

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FACE_PROGRESS_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                FaceScanHub.sink = events
            }
            override fun onCancel(arguments: Any?) {
                FaceScanHub.sink = null
            }
        })

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MODEL_DOWNLOAD_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                modelDownloadSink = events
            }
            override fun onCancel(arguments: Any?) {
                modelDownloadSink = null
            }
        })
    }

    private fun parseCollectionSpecs(
        call: io.flutter.plugin.common.MethodCall
    ): List<EmbeddingEngine.CollectionSpec>? {
        val raw = call.argument<List<Map<String, Any>>>("collections") ?: return null
        return raw.mapNotNull { entry ->
            val id = entry["id"] as? String ?: return@mapNotNull null
            val embedding = (entry["embedding"] as? List<*>)
                ?.map { (it as Number).toFloat() }
                ?.toFloatArray() ?: return@mapNotNull null
            val personIds = (entry["personIds"] as? List<*>)
                ?.mapNotNull { (it as? Number)?.toLong() }
                ?: emptyList()
            EmbeddingEngine.CollectionSpec(
                id = id,
                embedding = embedding,
                contentMode = entry["contentMode"] as? String ?: "both",
                k = (entry["k"] as? Number)?.toDouble() ?: 3.0,
                personIds = personIds
            )
        }
    }

    /**
     * Resolves each spec's personIds (from an "@name" search) to a pathFilter via FaceStore, with the same "together"
     * reading of several people as searchByText. Call it inside a searchExecutor.execute block: peopleMedia is a real
     * SQLite read, and parseCollectionSpecs runs synchronously on the thread the channel call arrives on.
     */
    private fun resolvePathFilters(
        specs: List<EmbeddingEngine.CollectionSpec>
    ): List<EmbeddingEngine.CollectionSpec> = specs.map { spec ->
        if (spec.personIds.isEmpty()) spec else spec.copy(
            pathFilter = faces.store.peopleMedia(spec.personIds, "together").map { it.uri }.toSet()
        )
    }

    /**
     * The bounds+EXIF half of loadMetadataByUri, split out so the handler
     * can pick this or loadVideoMetadata below by isVideo instead of one
     * branchy function trying to do both.
     */
    private fun loadImageMetadata(
        uri: android.net.Uri,
        fileName: String,
        fileSize: Long,
        mimeType: String
    ): HashMap<String, Any?> {
        var width = 0
        var height = 0

        contentResolver.openFileDescriptor(uri, "r")?.use { pfd ->
            val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFileDescriptor(pfd.fileDescriptor, null, options)
            width = options.outWidth
            height = options.outHeight
        }

        val exif = try {
            contentResolver.openFileDescriptor(uri, "r")?.use { pfd -> ExifInterface(pfd.fileDescriptor) }
        } catch (e: Exception) {
            null
        }

        return hashMapOf<String, Any?>(
            "fileName" to fileName,
            "fileSize" to fileSize,
            "mimeType" to mimeType,
            "width" to width,
            "height" to height,
            "durationMs" to 0L,
            "orientation" to (exif?.getAttributeInt(
                ExifInterface.TAG_ORIENTATION,
                ExifInterface.ORIENTATION_NORMAL
            ) ?: 0),
            "dateTime" to (exif?.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL)
                ?: exif?.getAttribute(ExifInterface.TAG_DATETIME) ?: ""),
            "cameraMake" to (exif?.getAttribute(ExifInterface.TAG_MAKE) ?: ""),
            "cameraModel" to (exif?.getAttribute(ExifInterface.TAG_MODEL) ?: ""),
            "latitude" to exif?.latLong?.getOrNull(0),
            "longitude" to exif?.latLong?.getOrNull(1)
        )
    }

    /**
     * Metadata for a video, read with MediaMetadataRetriever because a video has no EXIF or BitmapFactory bounds. The
     * camera, GPS and orientation fields are left out, since the metadata sheet hides them when empty. A corrupt or
     * unusual video shows zeros instead of failing the sheet.
     */
    private fun loadVideoMetadata(
        uri: android.net.Uri,
        fileName: String,
        fileSize: Long,
        mimeType: String
    ): HashMap<String, Any?> {
        var width = 0
        var height = 0
        var durationMs = 0L

        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(this, uri)
            width = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
                ?.toIntOrNull() ?: 0
            height = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
                ?.toIntOrNull() ?: 0
            durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 0L
        } catch (e: Exception) {
        } finally {
            try { retriever.release() } catch (e: Exception) {}
        }

        return hashMapOf<String, Any?>(
            "fileName" to fileName,
            "fileSize" to fileSize,
            "mimeType" to mimeType,
            "width" to width,
            "height" to height,
            "durationMs" to durationMs,
            "orientation" to 0,
            "dateTime" to "",
            "cameraMake" to "",
            "cameraModel" to "",
            "latitude" to null,
            "longitude" to null
        )
    }

    /**
     * Copies the source content straight into a MediaStore entry instead of writing to a raw file path, the only way
     * that works on every supported Android version without WRITE_EXTERNAL_STORAGE on scoped-storage phones.
     * IS_PENDING brackets the copy on API 29 and up, so the gallery never sees a half-written file.
     */
    private fun saveCopyToGallery(uri: android.net.Uri, isVideo: Boolean) {
        val mimeType = contentResolver.getType(uri) ?: if (isVideo) "video/mp4" else "image/jpeg"
        val extension = if (isVideo) "mp4" else "jpg"
        val fileName = "LostFound_${System.currentTimeMillis()}.$extension"

        val collection = if (isVideo) {
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }

        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    if (isVideo) Environment.DIRECTORY_MOVIES else Environment.DIRECTORY_PICTURES
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }

        val destUri = contentResolver.insert(collection, values)
            ?: throw Exception("Could not create a destination entry in the gallery")

        contentResolver.openInputStream(uri)?.use { input ->
            contentResolver.openOutputStream(destUri)?.use { output ->
                input.copyTo(output)
            } ?: throw Exception("Could not open the destination for writing")
        } ?: throw Exception("Could not open the source file")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            contentResolver.update(
                destUri,
                ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) },
                null,
                null
            )
        }
    }

    /**
     * Loads a bitmap sampled down to [maxDimension]. It reads the dimensions first (inJustDecodeBounds), picks a
     * power-of-two sample size, then decodes at the reduced size. That costs one extra stream open but never allocates
     * a full-resolution bitmap just to shrink it, which matters for a photo of thousands of pixels shown in a small
     * tile.
     */
    private fun decodeSampledBitmap(uri: android.net.Uri, maxDimension: Int): android.graphics.Bitmap? {
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
    private fun capBitmapDimension(
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

    private fun launchSafPicker(mode: String) {
        val intent = Intent(this, SafPickerActivity::class.java).apply {
            putExtra(SafPickerActivity.EXTRA_MODE, mode)
        }
        startActivityForResult(intent, PICK_REQUEST)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != PICK_REQUEST) return

        val result = pendingPickResult
        pendingPickResult = null
        if (result == null) return

        if (resultCode != RESULT_OK || data == null) {
            result.error("CANCELLED", "Picking cancelled", null)
            return
        }

        val uri = data.getStringExtra(SafPickerActivity.EXTRA_URI)
        if (uri == null) {
            result.error("NO_URI", "No URI returned", null)
            return
        }

        result.success(uri)
    }
}