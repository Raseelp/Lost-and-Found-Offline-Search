package dev.raseel.lostandfound.features.people

import dev.raseel.lostandfound.core.log.AppLog
import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import dev.raseel.lostandfound.features.library.IndexedVideo
import dev.raseel.lostandfound.features.library.ScanEngineHolder
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * Finds and recognises the people in videos. Every sampled frame is searched for faces (the cheap step), faces in
 * neighbouring frames are linked into tracks, and only the best one or two faces of each track are recognised (the
 * expensive step). Motion blur makes the standard higher than for photos. Each kept face's picture is saved when it is
 * found, because a video frame cannot be cut out again cheaply.
 */
class VideoFaceScanner(private val context: Context, private val services: FaceServices) {

    /** A face found in one frame, waiting to be tracked and (maybe) recognised. */
    private class Det(
        val frame: Int,
        val tsMs: Long,
        val box: DetectedFace,
        val frameW: Int,
        val frameH: Int,
        val sizePx: Int,
        val yaw: Float,
        val sharpness: Float,
        val rank: Float,
        var aligned: Bitmap?,
        val crop: ByteArray?,
    ) {
        var track = -1
        var embedding: FloatArray? = null
        var recognised = false
        var faceId = 0L
        val cx get() = (box.left + box.right) / 2f
        val cy get() = (box.top + box.bottom) / 2f
        val size get() = max(box.width, box.height)
    }

    /**
     * Scans one video and stores what was found. Returns how many faces were kept, [FAILED] if the video could not be
     * opened or read (it is tried again on a later run), [STOPPED] if [shouldStop] said to give up, or [BUSY] if
     * another scan of the same video is running. Only one runs at a time, so the background scan and the viewer never
     * place the same faces twice. [gate] is asked before each frame and returns false to stop.
     */
    fun scan(
        video: IndexedVideo,
        shouldStop: () -> Boolean,
        gate: () -> Boolean,
        background: Boolean = true,
        relax: Int = -1,
    ): Int {
        if (!active.add(video.hash)) return BUSY
        val progress = PhotoScanProgress().also { it.video = true }
        val key = "video:${video.uri}"
        services.scanner.photoProgress[key] = progress
        try {
            return scanInner(video, shouldStop, gate, progress, background, if (relax >= 0) relax else relaxOf(video.hash))
        } finally {
            services.scanner.photoProgress.remove(key)
            active.remove(video.hash)
        }
    }

    /** Blocks until nobody is scanning [hash] (or [maxMs] passes). */
    fun waitUntilFree(hash: Long, maxMs: Long) {
        var waited = 0L
        while (hash in active && waited < maxMs) {
            Thread.sleep(300)
            waited += 300
        }
    }

    /**
     * How loose the search for faces is for one video (0 standard, 1 looser, 2 loosest). It is remembered per video,
     * because a video where the standard search found nothing keeps needing the looser one, and it never changes the
     * app-wide settings or any other video.
     */
    fun relaxOf(hash: Long): Int = (services.store.getMeta("video_relax_$hash")?.toIntOrNull() ?: 0).coerceIn(0, MAX_RELAX)

    /** What each search level accepts. Looser means smaller and blurrier faces, turned heads, less certain detections, bigger frames and more of them. */
    private class Relax(val level: Int) {
        val minSize = when (level) { 0 -> FaceQuality.VIDEO_MIN_SIZE_PX; 1 -> 36; else -> 28 }
        val minScore = when (level) { 0 -> FaceQuality.VIDEO_MIN_SCORE; 1 -> 0.4f; else -> 0.3f }
        val maxYaw = when (level) { 0 -> FaceQuality.VIDEO_MAX_YAW; 1 -> 0.85f; else -> 1.5f }
        val minSharpness = when (level) { 0 -> FaceQuality.VIDEO_MIN_SHARPNESS; 1 -> 6f; else -> 0f }
        val detectScore = when (level) { 0 -> FaceDetector.DEFAULT_SCORE_THRESHOLD; 1 -> 0.35f; else -> 0.25f }
        val maxSide = when (level) { 0 -> VideoFrameReader.MAX_SIDE; 1 -> 1920; else -> 2560 }

        fun good(sizePx: Int, score: Float, sharpness: Float, yaw: Float) =
            sizePx >= minSize && score >= minScore && yaw <= maxYaw && sharpness >= minSharpness
    }

    /**
     * Scans the sampled frames of one video at search level [level]. A scan the user asked for looks harder: small
     * faces in a group too, and at least the balanced number of frames. The exact frame at a time is read, not the
     * nearest keyframe, so face positions line up with the picture the player shows. A video that opened but gave no
     * frame may just have a busy decoder, so it is given up on only after [MAX_READ_FAILURES] failures.
     */
    private fun scanInner(
        video: IndexedVideo,
        shouldStop: () -> Boolean,
        gate: () -> Boolean,
        progress: PhotoScanProgress,
        background: Boolean,
        level: Int,
    ): Int {
        val relax = Relax(level)
        progress.relax = level
        val reader = VideoFrameReader.open(context, Uri.parse(video.uri), relax.maxSide) ?: return FAILED
        val tiled = !background || FaceSettings.thorough(context)
        val dets = ArrayList<Det>()
        val frameDims = HashMap<Int, Pair<Int, Int>>()
        var decoded = 0

        try {
            val times = sampleTimes(reader.durationMs, atLeastBalanced = !background, level = level)
            progress.steps = times.size
            var lastSignature = Long.MIN_VALUE
            for ((index, ts) in times.withIndex()) {
                if (shouldStop() || !gate()) {
                    free(dets)
                    return STOPPED
                }
                progress.step = index + 1
                progress.faces = dets.size
                progress.stage = "detecting"
                val frame = reader.frameAt(ts, exact = true) ?: continue
                try {
                    decoded++
                    val signature = signatureOf(frame)
                    if (signature == lastSignature) continue
                    lastSignature = signature

                    frameDims[index] = frame.width to frame.height
                    findFaces(frame, index, ts, dets, tiled, relax)
                    trim(dets)
                } finally {
                    frame.recycle()
                }
            }
        } catch (e: Exception) {
            AppLog.w(TAG, "video ${video.uri}: reading frames failed: ${e.message}")
            free(dets)
            return FAILED
        } finally {
            reader.close()
        }

        if (decoded == 0 && dets.isEmpty()) {
            if (!background) return FAILED
            val key = "video_fail_${video.hash}"
            val failures = (services.store.getMeta(key)?.toIntOrNull() ?: 0) + 1
            if (failures < MAX_READ_FAILURES) {
                services.store.setMeta(key, failures.toString())
                return FAILED
            }
            services.store.insertVideo(video.hash, video.uri, emptyList())
            return 0
        }

        return try {
            finish(video, dets, frameDims, progress).also { kept ->
                if (!background && kept >= 0) services.store.setMeta("video_relax_${video.hash}", level.toString())
            }
        } catch (e: Exception) {
            AppLog.w(TAG, "video ${video.uri}: recognising failed: ${e.message}", e)
            FAILED
        } finally {
            free(dets)
        }
    }

    /** Finds the faces of one frame and adds the good ones to [out]. Only the clearest [MAX_FACES_PER_FRAME] of a frame are kept, which is plenty in a crowd. */
    private fun findFaces(frame: Bitmap, index: Int, tsMs: Long, out: MutableList<Det>, tiled: Boolean, relax: Relax) {
        val engine = services.engine
        val found = engine.detect(frame, tiled, relax.detectScore)
        val kept = ArrayList<Det>()
        for (box in found) {
            val size = min(box.width, box.height).toInt()
            if (size < relax.minSize) continue
            val aligned = engine.align(frame, box.landmarks)
            val yaw = FaceQuality.yaw(box.landmarks)
            if (!relax.good(size, box.score, aligned.sharpness, yaw)) {
                aligned.bitmap.recycle()
                continue
            }
            val crop = services.crops.render(
                frame,
                (box.left / frame.width).coerceIn(0f, 1f), (box.top / frame.height).coerceIn(0f, 1f),
                (box.right / frame.width).coerceIn(0f, 1f), (box.bottom / frame.height).coerceIn(0f, 1f),
            )
            kept += Det(
                index, tsMs, box, frame.width, frame.height, size, yaw, aligned.sharpness,
                FaceQuality.rank(size, box.score, yaw), aligned.bitmap, crop,
            )
        }
        kept.sortByDescending { it.rank }
        for ((i, d) in kept.withIndex()) {
            if (i < MAX_FACES_PER_FRAME) out += d else {
                d.aligned?.recycle()
                d.aligned = null
            }
        }
    }

    /** A cheap fingerprint of a frame (a few dozen pixels), to notice identical frames. */
    private fun signatureOf(frame: Bitmap): Long {
        var h = 1125899906842597L
        val w = frame.width
        val ht = frame.height
        for (yi in 1..6) {
            for (xi in 1..6) {
                h = 31 * h + frame.getPixel(w * xi / 7, ht * yi / 7)
            }
        }
        return h
    }

    /**
     * Links the faces in [dets] into tracks, recognises the best faces of each track, then stores and places them.
     * Extra faces of a track carry the fingerprint of its best face, because they were not recognised themselves.
     * Progress counts tracks, not sightings. If nothing is kept, a second look must not wipe what an earlier scan
     * found. A video scanned before has its old faces replaced, and people only in them are removed.
     */
    private fun finish(video: IndexedVideo, dets: List<Det>, frameDims: Map<Int, Pair<Int, Int>>, progress: PhotoScanProgress): Int {
        val engine = services.engine
        val store = services.store
        val clusterer = services.clusterer

        val byFrame = dets.groupBy { it.frame }
        var previous: List<Det> = emptyList()
        var nextTrack = 0
        for (frame in byFrame.keys.sorted()) {
            val current = byFrame.getValue(frame).sortedByDescending { it.rank }
            val used = HashSet<Det>()
            for (d in current) {
                var best: Det? = null
                var bestDistance = Float.MAX_VALUE
                for (p in previous) {
                    if (p in used) continue
                    val distance = hypot(d.cx - p.cx, d.cy - p.cy) / max(d.size, p.size)
                    val ratio = d.size / p.size
                    if (distance < TRACK_DISTANCE && ratio in TRACK_RATIO_LOW..TRACK_RATIO_HIGH && distance < bestDistance) {
                        best = p
                        bestDistance = distance
                    }
                }
                if (best != null) {
                    d.track = best.track
                    used += best
                } else {
                    d.track = nextTrack++
                }
            }
            previous = current
        }

        val tracks = dets.groupBy { it.track }
        val toRecognise = ArrayList<Det>()
        val extras = HashMap<Int, List<Det>>()
        for ((track, list) in tracks) {
            val sorted = list.sortedByDescending { it.rank }
            val first = sorted[0]
            toRecognise += first
            val second = sorted.drop(1).firstOrNull { abs(it.frame - first.frame) >= 2 } ?: sorted.getOrNull(1)
            if (second != null) toRecognise += second
            val rest = sorted.filter { it !== first && it !== second }
            extras[track] = when {
                rest.size <= 2 -> rest
                else -> listOf(rest.first(), rest.last())
            }
        }
        val limited = toRecognise.sortedByDescending { it.rank }.take(MAX_RECOGNISED_PER_VIDEO)
        progress.faces = dets.size
        progress.total = tracks.size
        progress.stage = if (limited.isEmpty()) "placing" else "recognising"
        if (limited.isNotEmpty()) {
            val vectors = engine.embedAligned(limited.map { it.aligned!! })
            limited.forEachIndexed { i, d ->
                d.embedding = vectors[i]
                d.recognised = true
            }
        }

        val stored = ArrayList<Det>()
        for ((track, list) in tracks) {
            val best = list.filter { it.recognised }.maxByOrNull { it.rank } ?: continue
            for (d in list) {
                if (d.recognised) {
                    stored += d
                } else if (d in (extras[track] ?: emptyList())) {
                    d.embedding = best.embedding
                    stored += d
                }
            }
        }
        if (stored.isEmpty()) {
            val before = store.videoFaceCount(video.hash)
            if (before != null && before > 0) return before
            if (store.videoHasFrames(video.hash)) {
                store.markVideoScanned(video.hash, video.uri)
            } else {
                store.insertVideo(video.hash, video.uri, emptyList())
            }
            return 0
        }

        progress.stage = "placing"

        val frames = stored.groupBy { it.frame }.toSortedMap().map { (frame, list) ->
            val (w, h) = frameDims[frame] ?: (list[0].frameW to list[0].frameH)
            list to FaceStore.FrameFaces(
                list[0].tsMs, w, h,
                list.map { d ->
                    FaceRow(
                        boxL = d.box.left / w, boxT = d.box.top / h, boxR = d.box.right / w, boxB = d.box.bottom / h,
                        landmarks = FloatArray(10) { k -> d.box.landmarks[k] / (if (k % 2 == 0) w else h) },
                        score = d.box.score, sizePx = d.sizePx, sharpness = d.sharpness, yaw = d.yaw,
                        good = d.recognised, rank = d.rank, embedding = d.embedding!!,
                    )
                },
            )
        }
        val hadBefore = store.videoHasFrames(video.hash)
        val ids = store.insertVideo(video.hash, video.uri, frames.map { it.second })
        if (hadBefore) clusterer.invalidate()
        frames.forEachIndexed { fi, (list, _) ->
            list.forEachIndexed { k, d ->
                d.faceId = ids[fi][k]
                d.crop?.let { store.saveCropBytes(d.faceId, it) }
            }
        }

        val trackPerson = HashMap<Int, Long>()
        for (d in stored.filter { it.recognised }.sortedByDescending { it.rank }) {
            val person = clusterer.assignVideoFace(
                d.faceId, store.frameHash(video.hash, d.tsMs), video.hash, d.embedding!!, good = true, rank = d.rank,
            )
            if (person != null && d.track !in trackPerson) trackPerson[d.track] = person
        }
        for (d in stored.filter { !it.recognised }) {
            val person = trackPerson[d.track] ?: continue
            clusterer.attachTracked(d.faceId, store.frameHash(video.hash, d.tsMs), video.hash, person)
        }
        if (hadBefore) store.pruneEmptyPeople()
        return stored.size
    }

    /** Keeps only the clearest [MAX_KEPT_FACES] of [dets]. A long, crowded video could keep a thousand faces, each with a small picture. */
    private fun trim(dets: MutableList<Det>) {
        if (dets.size <= MAX_KEPT_FACES) return
        dets.sortByDescending { it.rank }
        while (dets.size > MAX_KEPT_FACES) {
            val worst = dets.removeAt(dets.size - 1)
            worst.aligned?.recycle()
            worst.aligned = null
        }
    }

    private fun free(dets: List<Det>) {
        for (d in dets) {
            d.aligned?.recycle()
            d.aligned = null
        }
    }

    /**
     * Picks the moments of a video to look at: 3 up to a cap, about one per step (see [FaceSettings.videoDensity]).
     * A looser search also looks at more moments.
     */
    private fun sampleTimes(durationMs: Long, atLeastBalanced: Boolean, level: Int): List<Long> {
        var mode = FaceSettings.videoDensity(context)
        if (atLeastBalanced && mode == FaceSettings.DENSITY_FAST) mode = FaceSettings.DENSITY_BALANCED
        var (step, cap) = when (mode) {
            FaceSettings.DENSITY_FAST -> 3000L to 12
            FaceSettings.DENSITY_THOROUGH -> 1000L to 60
            else -> 2000L to 30
        }
        if (level >= 1) {
            step = 1000L
            cap = if (level >= 2) 90 else 60
        }
        val count = (durationMs / step).toInt().coerceIn(3, cap)
        return (0 until count).map { i -> durationMs * (2 * i + 1) / (2 * count) }
    }

    /** A face in one frame and who it is (0..1 fractions of the upright frame). */
    class FrameIdentity(
        val left: Float,
        val top: Float,
        val right: Float,
        val bottom: Float,
        val frameW: Int,
        val frameH: Int,
        val personId: Long,
        /** What is needed to store this face as part of the video, from here down (see [storeLooked]). */
        val landmarks: FloatArray,
        val score: Float,
        val sizePx: Int,
        val sharpness: Float,
        val yaw: Float,
        val rank: Float,
        val embedding: FloatArray,
        val crop: ByteArray?,
    )

    /**
     * Who is in the frame of [uri] at [positionMs], looked up on the spot. Nothing is stored and nobody's fingerprint
     * changes: it only names faces that match people already known. Null if the frame could not be read. It uses the
     * search level this video needed (a video the standard search missed faces in). The clearest faces come first, so
     * a crowd is recognised best-first.
     */
    fun identifyFrame(uri: String, positionMs: Long, progress: PhotoScanProgress): List<FrameIdentity>? {
        val engine = services.engine
        if (!engine.isReady()) return null
        val hash = ScanEngineHolder.embeddingEngine(context).indexedVideos().firstOrNull { it.uri == uri }?.hash
        val relax = Relax(if (hash != null) relaxOf(hash) else 0)
        val reader = VideoFrameReader.open(context, Uri.parse(uri), relax.maxSide) ?: return null
        val frame = try {
            reader.frameAt(positionMs, exact = true)
        } finally {
            reader.close()
        } ?: return null

        val aligned = ArrayList<Pair<DetectedFace, AlignedFace>>()
        try {
            progress.stage = "detecting"
            val w = frame.width
            val h = frame.height
            val found = engine.detect(frame, true, relax.detectScore)
            for (box in found) {
                val size = min(box.width, box.height).toInt()
                if (size < min(FaceQuality.MIN_EMBED_PX, relax.minSize)) continue
                aligned += box to engine.align(frame, box.landmarks)
            }
            aligned.sortByDescending { (box, a) ->
                FaceQuality.rank(min(box.width, box.height).toInt(), box.score, FaceQuality.yaw(box.landmarks)) + a.sharpness * 0.001f
            }
            progress.faces = aligned.size
            progress.total = aligned.size
            progress.stage = if (aligned.isEmpty()) "placing" else "recognising"
            if (aligned.isEmpty()) return emptyList()

            val vectors = engine.embedAligned(aligned.map { it.second.bitmap })
            progress.stage = "placing"
            val taken = HashSet<Long>()
            val out = ArrayList<FrameIdentity>()
            aligned.forEachIndexed { i, (box, a) ->
                val person = services.clusterer.identify(vectors[i], taken) ?: return@forEachIndexed
                taken += person
                val l = (box.left / w).coerceIn(0f, 1f)
                val t = (box.top / h).coerceIn(0f, 1f)
                val r = (box.right / w).coerceIn(0f, 1f)
                val b = (box.bottom / h).coerceIn(0f, 1f)
                val size = min(box.width, box.height).toInt()
                val yaw = FaceQuality.yaw(box.landmarks)
                out += FrameIdentity(
                    l, t, r, b, w, h, person,
                    landmarks = FloatArray(10) { k -> box.landmarks[k] / (if (k % 2 == 0) w else h) },
                    score = box.score, sizePx = size, sharpness = a.sharpness, yaw = yaw,
                    rank = FaceQuality.rank(size, box.score, yaw), embedding = vectors[i],
                    crop = services.crops.render(frame, l, t, r, b),
                )
            }
            return out
        } finally {
            aligned.forEach { it.second.bitmap.recycle() }
            frame.recycle()
        }
    }

    /**
     * Keeps what a look at one frame found. The faces that matched people are stored as that frame of the video, with
     * their pictures, and put with those people exactly as a scan would, so a person found this way has a real
     * position for that moment. They don't shape anyone (like the weaker faces of a scan). Skipped if a scan of the
     * video is running, which stores its own, or that moment is already stored.
     */
    fun storeLooked(uri: String, positionMs: Long, identities: List<FrameIdentity>) {
        if (identities.isEmpty()) return
        val hash = ScanEngineHolder.embeddingEngine(context).indexedVideos().firstOrNull { it.uri == uri }?.hash ?: return
        if (hash in active) return
        val store = services.store
        if (store.hasFrame(hash, positionMs)) return

        val rows = identities.map { f ->
            FaceRow(
                boxL = f.left, boxT = f.top, boxR = f.right, boxB = f.bottom,
                landmarks = f.landmarks, score = f.score, sizePx = f.sizePx, sharpness = f.sharpness, yaw = f.yaw,
                good = false, rank = f.rank, embedding = f.embedding,
            )
        }
        val first = identities[0]
        val ids = store.storeLookedFrame(hash, uri, positionMs, first.frameW, first.frameH, rows)
        val frame = store.frameHash(hash, positionMs)
        identities.forEachIndexed { i, f ->
            f.crop?.let { store.saveCropBytes(ids[i], it) }
            services.clusterer.attachTracked(ids[i], frame, hash, f.personId)
        }
    }

    companion object {
        private const val TAG = "VideoFaceScanner"
        const val FAILED = -1
        const val STOPPED = -2
        /** Someone else is scanning this video at the moment. */
        const val BUSY = -3

        /** The loosest search level (0 standard, 1 looser, 2 loosest). */
        const val MAX_RELAX = 2

        /** The hashes of the videos being scanned at the moment, by the background scan or a viewer. */
        private val active: MutableSet<Long> = java.util.concurrent.ConcurrentHashMap.newKeySet()

        private const val MAX_FACES_PER_FRAME = 12
        private const val MAX_RECOGNISED_PER_VIDEO = 60

        /** Faces held in memory while one video is scanned. */
        private const val MAX_KEPT_FACES = 300

        /** Background runs that find no readable frame before a video is given up on. */
        private const val MAX_READ_FAILURES = 3

        /** Same person from one sampled frame to the next: how far it may move (in face sizes) and change size. */
        private const val TRACK_DISTANCE = 1.0f
        private const val TRACK_RATIO_LOW = 0.55f
        private const val TRACK_RATIO_HIGH = 1.8f
    }
}
