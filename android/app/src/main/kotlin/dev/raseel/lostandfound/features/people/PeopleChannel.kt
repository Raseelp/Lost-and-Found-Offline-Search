package dev.raseel.lostandfound.features.people

import dev.raseel.lostandfound.core.log.AppLog
import androidx.work.WorkManager
import dev.raseel.lostandfound.MainActivity
import dev.raseel.lostandfound.core.native.FeatureChannel
import dev.raseel.lostandfound.features.library.ScanEngineHolder
import dev.raseel.lostandfound.features.library.ScanForegroundService
import dev.raseel.lostandfound.features.memories.MemoryDays
import dev.raseel.lostandfound.features.memories.MemoryEvergreen
import dev.raseel.lostandfound.features.memories.memoryTask
import dev.raseel.lostandfound.features.people.thennow.ThenNow
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream


class PeopleChannel(activity: MainActivity) : FeatureChannel(activity) {

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
    /**
     * Viewers that were closed before their photo's turn came (one photo is scanned at a time),
     * by the token each viewer sent: those requests are skipped instead of scanned for nobody.
     */
    private val cancelledPhotoScans: MutableSet<Long> = java.util.concurrent.ConcurrentHashMap.newKeySet()
    private val faces by lazy { FaceServices.get(applicationContext) }

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {

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
                        AppLog.w("MainActivity", "scanning video $uri failed: ${e.message}")
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
                        AppLog.w("MainActivity", "scanning $uri failed: ${e.message}")
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

            "loadUprightPhoto" -> {
                val uriString = call.argument<String>("uri")
                val maxSide = (call.argument<Number>("maxSide") ?: 360).toInt().coerceAtLeast(64)
                if (uriString == null) {
                    result.error("NO_URI", "URI missing", null)
                    return true
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

            else -> return false
        }
        return true
    }

    override fun registerStreams(messenger: BinaryMessenger) {
        EventChannel(messenger, "lostandfound/faceProgress").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                FaceScanHub.sink = events
            }

            override fun onCancel(arguments: Any?) {
                FaceScanHub.sink = null
            }
        })
    }
}

/** Runs [block] on the face thread and hands its value (or its error) to Flutter. */
internal fun FeatureChannel.faceTask(result: MethodChannel.Result, block: () -> Any?) {
    faceExecutor.execute {
        try {
            val value = block()
            runOnUiThread { result.success(value) }
        } catch (e: Throwable) {
            runOnUiThread { result.error("FACE_FAILED", e.message ?: e.toString(), null) }
        }
    }
}
