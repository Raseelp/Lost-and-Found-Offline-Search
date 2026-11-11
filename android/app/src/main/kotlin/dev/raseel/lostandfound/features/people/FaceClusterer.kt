package dev.raseel.lostandfound.features.people

import dev.raseel.lostandfound.core.log.AppLog
import android.content.Context
import kotlin.math.sqrt

/**
 * How strict grouping is. A face joins a person at [join] similarity to that person's average face. Two people merge
 * when their averages are [merge] similar, or when several faces of one match several of the other at [link] or
 * better. Weak faces need [weakJoin]. Stricter means fewer wrong merges but more people split in two.
 */
class FaceClusterConfig(
    val join: Float,
    val weakJoin: Float,
    val merge: Float,
    val link: Float,
) {
    companion object {
        const val STRICT = "strict"
        const val BALANCED = "balanced"
        const val LOOSE = "loose"

        /**
         * The thresholds for [name], or the balanced ones for any other name. They are set for the MobileFaceNet model
         * from how it scores people against strangers on about 4,400 LFW faces. The joining ones are lower than for
         * the previous model because this network scores the same person about 0.06 lower.
         */
        fun forStrictness(name: String?): FaceClusterConfig = when (name) {
            STRICT -> FaceClusterConfig(join = 0.445f, weakJoin = 0.48f, merge = 0.53f, link = 0.505f)
            LOOSE -> FaceClusterConfig(join = 0.305f, weakJoin = 0.34f, merge = 0.39f, link = 0.365f)
            else -> FaceClusterConfig(join = 0.365f, weakJoin = 0.40f, merge = 0.45f, link = 0.425f)
        }
    }
}

/**
 * Groups faces into people, and applies the user's corrections. A face joins the closest person if it is similar
 * enough and otherwise starts one. Two faces in one photo are never the same person, and a rejected face never goes
 * back. Anything the user named, merged or edited is pinned and regrouping leaves it alone.
 */
class FaceClusterer(private val context: Context, private val store: FaceStore) {

    /** One of a person's best faces, kept to compare people face to face. */
    private class Exemplar(val rank: Float, val vector: FloatArray)

    /**
     * One look of a person: a group of their faces that resemble each other, such as with and without glasses.
     *
     * A person is one or more looks, and a face belongs to them if it matches any look. Keeping both looks when two
     * groups merge makes a merge stick, because one average would sit between them and match neither.
     */
    private class Proto(first: FloatArray) {
        val sum = first.copyOf()
        val centroid = first.copyOf()
        var count = 1

        fun add(e: FloatArray) {
            for (i in sum.indices) sum[i] += e[i]
            count++
            refresh()
        }

        fun absorb(other: Proto) {
            for (i in sum.indices) sum[i] += other.sum[i]
            count += other.count
            refresh()
        }

        fun copy(): Proto {
            val c = Proto(centroid)
            for (i in sum.indices) c.sum[i] = sum[i]
            c.count = count
            c.refresh()
            return c
        }

        private fun refresh() {
            var norm = 0.0
            for (v in sum) norm += v * v
            val n = sqrt(norm).toFloat()
            for (i in sum.indices) centroid[i] = if (n > 0f) sum[i] / n else 0f
        }
    }

    /** The vector length is whatever the recognition model outputs, so the arrays are sized by the first face added. */
    private class PersonState(val id: Long, var pinned: Boolean, var named: Boolean) {
        var sum = FloatArray(0)
        var centroid = FloatArray(0)
        var count = 0

        /** Every photo or video frame they are in, which tells who appears together. */
        val photos = HashSet<Long>()

        /** The photos and videos they are in. A video counts once however many of its frames they are in. */
        val media = HashSet<Long>()
        val protos = ArrayList<Proto>()

        /**
         * The best few faces, from the second face on, because with just one the average is
         * that face. Two people who are really one, seen in different light or with and
         * without glasses, have averages that are far apart but still have individual faces
         * that match each other.
         */
        private val exemplars = ArrayList<Exemplar>()
        private var firstRank = 0f

        /** Adds a face to the look it resembles at [join] or more, and otherwise starts a look. */
        fun add(e: FloatArray, rank: Float = 0f, join: Float = 0.365f) {
            if (sum.isEmpty()) {
                sum = FloatArray(e.size)
                centroid = FloatArray(e.size)
            }
            if (e.size != sum.size) return
            if (count == 0) firstRank = rank
            else if (exemplars.isEmpty()) exemplars += Exemplar(firstRank, centroid.copyOf())
            for (i in sum.indices) sum[i] += e[i]
            count++
            refresh()
            keep(Exemplar(rank, e))

            var best = -1
            var bestSim = -2f
            for (i in protos.indices) {
                val sim = dotProduct(e, protos[i].centroid)
                if (sim > bestSim) {
                    bestSim = sim
                    best = i
                }
            }
            if (best >= 0 && bestSim >= join) protos[best].add(e) else protos += Proto(e)
            capProtos()
        }

        /** Takes in everything of [other] and keeps both people's looks. */
        fun absorb(other: PersonState) {
            photos.addAll(other.photos)
            media.addAll(other.media)
            if (other.count == 0) return
            if (sum.isEmpty()) {
                sum = FloatArray(other.sum.size)
                centroid = FloatArray(other.sum.size)
            }
            if (other.sum.size != sum.size) return
            if (count == 1 && exemplars.isEmpty()) exemplars += Exemplar(firstRank, centroid.copyOf())
            val theirs = other.faceVectors()
            for (i in sum.indices) sum[i] += other.sum[i]
            count += other.count
            refresh()
            for (x in theirs) keep(x)

            for (p in other.protos) protos += p.copy()
            capProtos()
        }

        /** How well [e] matches this person: its closest look. */
        fun bestSimTo(e: FloatArray): Float {
            var best = -1f
            for (p in protos) {
                if (p.centroid.size != e.size) continue
                val sim = dotProduct(e, p.centroid)
                if (sim > best) best = sim
            }
            return best
        }

        /** A handful of looks is plenty. Past [MAX_PROTOS] the two most alike become one. */
        private fun capProtos() {
            while (protos.size > MAX_PROTOS) {
                var bi = 0
                var bj = 1
                var bestSim = -2f
                for (i in protos.indices) {
                    for (j in i + 1 until protos.size) {
                        val sim = dotProduct(protos[i].centroid, protos[j].centroid)
                        if (sim > bestSim) {
                            bestSim = sim
                            bi = i
                            bj = j
                        }
                    }
                }
                protos[bi].absorb(protos[bj])
                protos.removeAt(bj)
            }
        }

        fun refresh() {
            var norm = 0.0
            for (v in sum) norm += v * v
            val n = sqrt(norm).toFloat()
            for (i in sum.indices) centroid[i] = if (n > 0f) sum[i] / n else 0f
        }

        /** The stored best faces, or the average when there is only one face. */
        fun faceVectors(): List<Exemplar> =
            if (exemplars.isNotEmpty()) exemplars else if (count > 0) listOf(Exemplar(firstRank, centroid.copyOf())) else emptyList()

        private fun keep(x: Exemplar) {
            if (count < 2) return
            exemplars += x
            exemplars.sortByDescending { it.rank }
            while (exemplars.size > EXEMPLARS) exemplars.removeAt(exemplars.size - 1)
        }
    }

    /** How two people compare: their closest looks, and their individual faces. */
    private class Link(val centroid: Float, val best: Float, val top3: Float, val pairs: Int)

    /** How alike two people's closest looks are. */
    private fun protoSim(a: PersonState, b: PersonState): Float {
        var best = -1f
        for (x in a.protos) {
            for (y in b.protos) {
                if (x.centroid.size != y.centroid.size) continue
                val sim = dotProduct(x.centroid, y.centroid)
                if (sim > best) best = sim
            }
        }
        return best
    }

    private fun link(a: PersonState, b: PersonState): Link? {
        if (a.count == 0 || b.count == 0 || a.centroid.size != b.centroid.size) return null
        val centroid = protoSim(a, b)
        val top = FloatArray(3) { -1f }
        var pairs = 0
        for (x in a.faceVectors()) {
            for (y in b.faceVectors()) {
                if (x.vector.size != y.vector.size) continue
                val sim = dotProduct(x.vector, y.vector)
                pairs++

                if (sim > top[0]) { top[2] = top[1]; top[1] = top[0]; top[0] = sim }
                else if (sim > top[1]) { top[2] = top[1]; top[1] = sim }
                else if (sim > top[2]) { top[2] = sim }
            }
        }
        val used = top.count { it > -1f }
        if (used == 0) return null
        return Link(centroid, top[0], top.filter { it > -1f }.sum() / used, pairs)
    }

    /**
     * How well two people's faces agree, face by face. Each face of one person takes its best match in the other, the
     * best three are averaged per side, and the lower side is the result. Null when either person has fewer than two
     * faces, because one face can match by luck.
     */
    private fun mutualMatch(a: PersonState, b: PersonState): Float? {
        fun side(from: PersonState, to: PersonState): Float? {
            val best = ArrayList<Float>()
            for (x in from.faceVectors()) {
                var top = -1f
                for (y in to.faceVectors()) {
                    if (x.vector.size != y.vector.size) continue
                    val sim = dotProduct(x.vector, y.vector)
                    if (sim > top) top = sim
                }
                if (top > -1f) best.add(top)
            }
            if (best.size < 2) return null
            best.sortDescending()
            val k = minOf(3, best.size)
            return best.take(k).sum() / k
        }
        val ab = side(a, b) ?: return null
        val ba = side(b, a) ?: return null
        return minOf(ab, ba)
    }

    private val lock = Any()
    private var people: HashMap<Long, PersonState>? = null

    /** Maps a photo to the people who already have a face in it, because a person cannot appear twice in one photo. */
    private val photoPeople = HashMap<Long, HashSet<Long>>()

    /** Maps a person and a video to how many faces from that video have shaped the person, so a long clip does not outweigh a lifetime of photos. */
    private val videoUses = HashMap<Pair<Long, Long>, Int>()

    private val config: FaceClusterConfig
        get() = FaceClusterConfig.forStrictness(store.getMeta(META_STRICTNESS))

    fun strictness(): String = store.getMeta(META_STRICTNESS) ?: FaceClusterConfig.BALANCED

    fun setStrictness(value: String) = store.setMeta(META_STRICTNESS, value)

    /** Drops the in-memory state; it is rebuilt from the database on next use. */
    fun invalidate() = synchronized(lock) {
        people = null
        photoPeople.clear()
        videoUses.clear()
    }

    private fun state(): HashMap<Long, PersonState> {
        people?.let { return it }
        val join = config.join
        val map = HashMap<Long, PersonState>()
        for (p in store.allPeople()) map[p.id] = PersonState(p.id, p.pinned, p.name != null)
        photoPeople.clear()
        store.forEachFace("person_id IS NOT NULL") { f ->
            val personId = f.personId ?: return@forEachFace
            val person = map[personId] ?: return@forEachFace
            person.photos.add(f.photoHash)
            person.media.add(f.mediaKey)
            photoPeople.getOrPut(f.photoHash) { HashSet() }.add(person.id)
            if (f.good) {
                person.add(f.embedding, f.rank, join)
                if (f.mediaKey != f.photoHash) videoUses[person.id to f.mediaKey] = (videoUses[person.id to f.mediaKey] ?: 0) + 1
            }
        }
        people = map
        return map
    }

    /** Who a face was placed with: [isNew] when it started that person, and [photos] for how many photos that person has. */
    class Placement(val personId: Long, val isNew: Boolean, val photos: Int)

    /**
     * Places the faces of one just-processed photo, best first, creating people as needed. Returns, for each of [ids],
     * who it was placed with (null if nobody).
     *
     * A face that is found but not recognised yet, with an empty vector, is skipped and placed later.
     */
    fun assignPhotoFaces(photoHash: Long, ids: List<Long>, rows: List<FaceRow>): List<Placement?> = synchronized(lock) {
        val state = state()
        val cfg = config
        val order = ids.indices.sortedByDescending { rows[it].rank }
        val placed = arrayOfNulls<Placement>(ids.size)

        for (i in order) {
            val row = rows[i]
            if (row.embedding.isEmpty()) continue
            val before = state.size
            val person = place(state, cfg, photoHash, ids[i], row.embedding, row.good, row.rank) ?: continue
            placed[i] = Placement(person, state.size > before, state[person]?.photos?.size ?: 1)
        }
        placed.toList()
    }

    /**
     * Places one face that was stored without a vector and has since been recognised in full, such as in a photo
     * opened in the viewer. It is placed like a face of a freshly scanned photo.
     */
    fun assignRecognised(
        faceId: Long,
        photoHash: Long,
        embedding: FloatArray,
        good: Boolean,
        rank: Float,
        mediaKey: Long = photoHash,
    ): Long? = synchronized(lock) { place(state(), config, photoHash, faceId, embedding, good, rank, mediaKey) }

    /**
     * Places a face found in a video frame (see [place]); returns who it joined or became,
     * or null. [photoHash] identifies the frame (two faces in one frame are two people),
     * [mediaKey] the video.
     */
    fun assignVideoFace(faceId: Long, frameHash: Long, videoHash: Long, embedding: FloatArray, good: Boolean, rank: Float): Long? =
        assignRecognised(faceId, frameHash, embedding, good, rank, videoHash)

    /** Puts a face with the person the face it was tracked from was placed with (no effect on who they are). */
    fun attachTracked(faceId: Long, frameHash: Long, videoHash: Long, personId: Long) = synchronized(lock) {
        val person = state()[personId] ?: return@synchronized
        val taken = photoPeople[frameHash]
        if (taken != null && personId in taken) return@synchronized
        store.setFacePerson(faceId, personId)
        person.photos.add(frameHash)
        person.media.add(videoHash)
        photoPeople.getOrPut(frameHash) { HashSet() }.add(personId)
    }

    /**
     * Who a face is, without changing anything: the closest listed person at the usual
     * threshold (skipping [exclude], e.g. people already found in the same frame), or null.
     */
    fun identify(embedding: FloatArray, exclude: Set<Long>): Long? = synchronized(lock) {
        var best: PersonState? = null
        var bestSim = config.join
        for (person in state().values) {
            if (person.count == 0 || person.id in exclude) continue
            val sim = person.bestSimTo(embedding)
            if (sim >= bestSim) {
                bestSim = sim
                best = person
            }
        }
        best?.id
    }

    /** Two faces per person and video may shape the person. The rest of that video's faces only join. */
    private fun videoSlot(personId: Long, mediaKey: Long): Boolean {
        val key = personId to mediaKey
        val used = videoUses[key] ?: 0
        if (used >= MAX_PER_VIDEO) return false
        videoUses[key] = used + 1
        return true
    }

    /** Places a face with the closest person, or starts a person if it is clear. A weak face nobody matches stays unassigned. */
    private fun place(
        state: HashMap<Long, PersonState>,
        cfg: FaceClusterConfig,
        photoHash: Long,
        faceId: Long,
        embedding: FloatArray,
        good: Boolean,
        rank: Float,
        mediaKey: Long = photoHash,
    ): Long? {
        val isVideo = mediaKey != photoHash
        val best = closest(listOf(state.values), embedding, photoHash, blocked = null, threshold = if (good) cfg.join else cfg.weakJoin)

        if (best != null) {
            store.setFacePerson(faceId, best.id)
            if (good && (!isVideo || videoSlot(best.id, mediaKey))) best.add(embedding, rank, cfg.join)
            best.photos.add(photoHash)
            best.media.add(mediaKey)
            photoPeople.getOrPut(photoHash) { HashSet() }.add(best.id)
            return best.id
        } else if (good) {
            val id = store.createPerson()
            val person = PersonState(id, pinned = false, named = false)
            person.add(embedding, rank, cfg.join)
            if (isVideo) videoSlot(id, mediaKey)
            person.photos.add(photoHash)
            person.media.add(mediaKey)
            state[id] = person
            store.setFacePerson(faceId, id)
            photoPeople.getOrPut(photoHash) { HashSet() }.add(id)
            return id
        }
        return null
    }

    /**
     * Places a face that was stored earlier without a vector and has just been
     * recognised: it joins a person if it is similar enough, but as a weak face
     * it never starts one or shifts anyone's average.
     */
    fun assignExisting(faceId: Long, photoHash: Long, embedding: FloatArray) = synchronized(lock) {
        val state = state()
        val best = closest(listOf(state.values), embedding, photoHash, blocked = null, threshold = config.weakJoin)
            ?: return@synchronized
        store.setFacePerson(faceId, best.id)
        best.photos.add(photoHash)
        photoPeople.getOrPut(photoHash) { HashSet() }.add(best.id)
    }

    /**
     * The most similar person at or above the threshold, skipping anyone who already has a
     * face in this photo and the one this face was rejected from.
     */
    private fun closest(
        pools: List<Collection<PersonState>>,
        embedding: FloatArray,
        photoHash: Long,
        blocked: Long?,
        threshold: Float,
    ): PersonState? {
        val taken = photoPeople[photoHash]
        var best: PersonState? = null
        var bestSim = threshold
        for (pool in pools) {
            for (person in pool) {
                if (person.count == 0) continue
                if (person.id == blocked || (taken != null && person.id in taken)) continue
                val sim = person.bestSimTo(embedding)
                if (sim >= bestSim) {
                    bestSim = sim
                    best = person
                }
            }
        }
        return best
    }

    /**
     * Joins people who are very likely one, the same person split by early greedy choices. It never merges a pair that
     * shares a photo, a pair the user said differ, or two named people, and the named or pinned person survives. It
     * stops at the first person with a single face, who was already compared on arrival.
     */
    fun mergeSimilar() = synchronized(lock) {
        val state = state()
        val cfg = config
        val rejected = store.rejectedPairs()
        val ordered = state.values.filter { it.count > 0 }.sortedByDescending { it.count }.toMutableList()
        val removed = HashSet<Long>()

        for (i in ordered.indices) {
            val a = ordered[i]
            if (a.id in removed) continue
            if (a.count <= 1) break
            for (j in i + 1 until ordered.size) {
                val b = ordered[j]
                if (b.id in removed) continue
                if (a.pinned && b.pinned) continue
                if (a.named && b.named) continue
                if (a.centroid.size != b.centroid.size) continue
                if ((minOf(a.id, b.id) to maxOf(a.id, b.id)) in rejected) continue

                val centroidSim = protoSim(a, b)
                if (centroidSim < PREFILTER) continue
                if (sharesPhoto(a, b)) continue

                val strong = centroidSim >= cfg.merge || run {
                    val l = link(a, b)
                    l != null && l.pairs >= 3 && l.top3 >= cfg.link
                }
                if (!strong) continue

                val (keep, drop) = if (b.named || (b.pinned && !a.named)) b to a else a to b
                AppLog.d(TAG, "merge person ${drop.id} into ${keep.id} (centroids $centroidSim)")
                store.mergeInto(drop.id, keep.id)
                keep.absorb(drop)
                for (photo in drop.photos) {
                    photoPeople[photo]?.let { it.remove(drop.id); it.add(keep.id) }
                }
                removed.add(drop.id)
                state.remove(drop.id)
                if (drop === a) break
            }
        }
    }

    class MergeSuggestion(val aId: Long, val bId: Long, val score: Float)

    /**
     * Pairs of listed people who may be the same person, most likely first, for the user to decide. Pairs said to
     * differ, hidden people and pairs sharing a photo are left out. The limits sit just under what automatic merging
     * needs (see [FaceClusterConfig.link]), and a lone lucky face pair is not enough because look-alikes and cartoons
     * produce them.
     */
    fun suggestMerges(limit: Int): List<MergeSuggestion> = synchronized(lock) {
        val state = state()
        val rejected = store.rejectedPairs()
        val hidden = store.allPeople().filter { it.hidden }.map { it.id }.toSet()
        val listed = state.values.filter {
            it.count > 0 && it.media.size >= FaceStore.MIN_PHOTOS_TO_SHOW && it.id !in hidden
        }

        val cfg = config
        val top3Min = cfg.link - SUGGEST_BELOW_LINK
        val bestMin = cfg.link - SUGGEST_BEST_BELOW_LINK
        val centroidMin = cfg.join - SUGGEST_CENTROID_BELOW_JOIN

        val out = ArrayList<MergeSuggestion>()
        for (i in listed.indices) {
            val a = listed[i]
            for (j in i + 1 until listed.size) {
                val b = listed[j]
                if (a.named && b.named) continue
                if (a.centroid.size != b.centroid.size) continue
                if ((minOf(a.id, b.id) to maxOf(a.id, b.id)) in rejected) continue
                if (protoSim(a, b) < PREFILTER) continue
                if (sharesPhoto(a, b)) continue

                val l = link(a, b) ?: continue
                if (l.best < bestMin || l.centroid < centroidMin) continue
                val mutual = mutualMatch(a, b) ?: continue
                if (mutual < top3Min) continue
                out += MergeSuggestion(a.id, b.id, mutual - cfg.link + SUGGEST_SCORE_AT_LINK)
            }
        }
        out.sortByDescending { it.score }
        out.take(limit)
    }

    /** "Not the same person": never suggested or merged automatically again. */
    fun rejectMerge(a: Long, b: Long) = synchronized(lock) {
        store.rejectMerge(a, b)
    }

    /**
     * Joins [otherId] into [keepId], and the name and pin carry over. Remembers what it moved
     * so the merge can be undone. Returns that record's id, or 0 if nothing was merged.
     */
    fun merge(keepId: Long, otherId: Long): Long = synchronized(lock) {
        if (keepId == otherId) return@synchronized 0L
        val keep = store.person(keepId) ?: return@synchronized 0L
        val other = store.person(otherId) ?: return@synchronized 0L

        val movedFaces = store.faceIdsOf(otherId)
        val recordId = store.logMerge(
            keptId = keepId, keptName = keep.name, keptCover = store.bestFaceOf(keepId),
            removedName = other.name, removedCover = store.bestFaceOf(otherId),
            removedPinned = other.pinned, removedHidden = other.hidden,
            faceIds = movedFaces,
        )

        store.mergeInto(otherId, keepId)
        if (keep.name == null && other.name != null) store.rename(keepId, other.name)
        store.setPinned(keepId)
        if (keep.hidden) store.setHidden(keepId, true)
        invalidate()
        recordId
    }

    class SplitPreview(
        val first: List<Long>,
        val second: List<Long>,
        val firstCovers: List<Long>,
        val secondCovers: List<Long>,
    )

    private class SplitFace(val id: Long, val e: FloatArray, val good: Boolean, val rank: Float)

    /**
     * Finds the two groups the faces of a person who is really two fall into, so the user can split them. Null when
     * there are too few clear faces. It tries several starting pairs, because a pair seeded from a stray face can end
     * with a group of one, and the bigger group comes first and stays with the person.
     */
    fun previewSplit(personId: Long): SplitPreview? = synchronized(lock) {
        val faces = ArrayList<SplitFace>()
        store.forEachFace("person_id = $personId") { faces += SplitFace(it.id, it.embedding, it.good, it.rank) }
        val clear = faces.filter { it.good }
        if (clear.size < 4) return@synchronized null

        fun farthest(from: FloatArray): FloatArray = clear.minByOrNull { dotProduct(it.e, from) }!!.e
        val top = clear.first().e
        val far1 = farthest(top)
        val far2 = farthest(far1)
        val seeds = listOf(top to far1, far1 to far2, far2 to farthest(far2))

        var a = FloatArray(0)
        var b = FloatArray(0)
        var bestScore = -1f
        for ((seedA, seedB) in seeds) {
            var ca = seedA.copyOf()
            var cb = seedB.copyOf()
            var countA = 0
            var countB = 0
            for (iteration in 0 until 15) {
                val sumA = FloatArray(ca.size)
                val sumB = FloatArray(ca.size)
                countA = 0
                countB = 0
                for (f in clear) {
                    val toA = dotProduct(f.e, ca) >= dotProduct(f.e, cb)
                    val target = if (toA) sumA else sumB
                    for (k in target.indices) target[k] += f.e[k]
                    if (toA) countA++ else countB++
                }
                if (countA == 0 || countB == 0) break
                val na = normalised(sumA)
                val nb = normalised(sumB)
                val moved = dotProduct(na, ca) < 0.9999f || dotProduct(nb, cb) < 0.9999f
                ca = na
                cb = nb
                if (!moved) break
            }
            if (countA == 0 || countB == 0) continue

            var fit = 0f
            for (f in clear) fit += maxOf(dotProduct(f.e, ca), dotProduct(f.e, cb))
            val share = minOf(countA, countB).toFloat() / clear.size
            val score = if (share >= SPLIT_MIN_SHARE) fit / clear.size + 1f else fit / clear.size
            if (score > bestScore) {
                bestScore = score
                a = ca
                b = cb
            }
        }
        if (a.isEmpty()) return@synchronized null

        val first = ArrayList<SplitFace>()
        val second = ArrayList<SplitFace>()
        for (f in faces) {
            if (f.e.size != a.size) continue
            if (dotProduct(f.e, a) >= dotProduct(f.e, b)) first += f else second += f
        }
        if (first.isEmpty() || second.isEmpty()) return@synchronized null

        val (big, small) = if (first.size >= second.size) first to second else second to first
        fun covers(list: List<SplitFace>) = list.sortedWith(compareByDescending<SplitFace> { it.good }.thenByDescending { it.rank })
            .take(SPLIT_SAMPLE).map { it.id }
        SplitPreview(big.map { it.id }, small.map { it.id }, covers(big), covers(small))
    }

    private fun normalised(v: FloatArray): FloatArray {
        var norm = 0.0
        for (x in v) norm += x * x
        val n = sqrt(norm).toFloat()
        return FloatArray(v.size) { if (n > 0f) v[it] / n else 0f }
    }

    /**
     * Moves [faceIds] out of [personId] into a separate person and returns its id. The two are marked as different
     * people so they are not suggested or merged again, and both are kept as the user's own.
     */
    fun splitPerson(personId: Long, faceIds: List<Long>): Long = synchronized(lock) {
        val newId = store.createPerson(pinned = true)
        store.moveFaces(faceIds, personId, newId)
        store.setPinned(personId)
        store.rejectMerge(newId, personId)
        store.pruneEmptyPeople()
        invalidate()
        newId
    }

    /**
     * Undoes a merge: the person it removed comes back with their name and the faces that were
     * theirs, and the two are marked "not the same person" so neither the suggestions nor
     * automatic merging join them again. If the kept person took the other one's name in the
     * merge, it is given back.
     */
    fun undoMerge(recordId: Long): Boolean = synchronized(lock) {
        val record = store.mergeRecord(recordId) ?: return@synchronized false
        val restored = store.restorePerson(record)

        val kept = store.person(record.keptId)
        if (kept != null) {
            store.rejectMerge(restored, record.keptId)
            if (record.keptName == null && kept.name != null && kept.name == record.removedName) {
                store.rename(record.keptId, null)
            }
        }
        store.deleteMergeRecord(recordId)
        store.pruneEmptyPeople()
        invalidate()
        true
    }

    private fun sharesPhoto(a: PersonState, b: PersonState): Boolean {
        val (small, big) = if (a.photos.size <= b.photos.size) a.photos to b.photos else b.photos to a.photos
        return small.any { it in big }
    }

    /**
     * Rebuilds the automatic groups from scratch with the current strictness. Good faces go first, best rank first,
     * and seed the people. Weak faces only join those people. Pinned people and hand-placed faces are left as they are
     * and can still take faces in.
     */
    fun regroup() = synchronized(lock) {
        store.dissolveUnpinnedPeople()
        invalidate()

        val cfg = config
        val state = state()
        val assignments = ArrayList<Pair<Long, Long>>()
        val provisional = HashMap<Long, PersonState>()
        var nextTemp = -1L

        store.forEachFace("person_id IS NULL AND locked = 0 AND good = 1") { f ->
            val best = closest(listOf(state.values, provisional.values), f.embedding, f.photoHash, f.blockedPerson, cfg.join)
            val target = best ?: PersonState(nextTemp--, pinned = false, named = false).also { provisional[it.id] = it }
            target.add(f.embedding, f.rank, cfg.join)
            target.photos.add(f.photoHash)
            target.media.add(f.mediaKey)
            photoPeople.getOrPut(f.photoHash) { HashSet() }.add(target.id)
            assignments += f.id to target.id
        }

        val realIds = HashMap<Long, Long>()
        for (temp in provisional.keys) realIds[temp] = store.createPerson()
        store.applyAssignments(assignments.map { (face, person) -> face to (realIds[person] ?: person) })
        invalidate()

        val weakState = state()
        val weak = ArrayList<Pair<Long, Long>>()
        store.forEachFace("person_id IS NULL AND locked = 0 AND good = 0") { f ->
            val best = closest(listOf(weakState.values), f.embedding, f.photoHash, f.blockedPerson, cfg.weakJoin)
            if (best != null) {
                weak += f.id to best.id
                photoPeople.getOrPut(f.photoHash) { HashSet() }.add(best.id)
            }
        }
        store.applyAssignments(weak)
        invalidate()

        mergeSimilar()
    }

    fun rename(personId: Long, name: String?) = synchronized(lock) {
        store.rename(personId, name)
        invalidate()
    }

    fun setHidden(personId: Long, hidden: Boolean) = synchronized(lock) {
        store.setHidden(personId, hidden)
        invalidate()
    }

    /**
     * "Not this person": takes a face out of its person for good. It goes to someone else if it clearly matches them
     * and is otherwise left unassigned. A person left empty is removed.
     */
    fun removeFace(faceId: Long) = synchronized(lock) {
        val face = store.face(faceId) ?: return@synchronized
        val from = face.personId
        store.lockFace(faceId, personId = null, blockedPerson = from)
        invalidate()

        val state = state()
        val other = closest(listOf(state.values), face.embedding, face.photoHash, blocked = from, threshold = config.join)
        if (other != null && face.good) {
            store.lockFace(faceId, personId = other.id, blockedPerson = null)
            store.setPinned(other.id)
        }
        invalidate()
        store.pruneEmptyPeople()
    }

    companion object {
        private const val TAG = "FaceClusterer"
        const val META_STRICTNESS = "strictness"

        /** Best faces kept per person for face-to-face comparison. */
        private const val EXEMPLARS = 10

        /** Averages this far apart or less are unrelated people, so the finer comparison is skipped. */
        private const val PREFILTER = 0.26f

        /**
         * A pair is suggested only when it is nearly what automatic merging would do: within [SUGGEST_BELOW_LINK] of
         * the link for the best three faces, [SUGGEST_BEST_BELOW_LINK] for the best pair and
         * [SUGGEST_CENTROID_BELOW_JOIN] for the looks. They are relative to the model's thresholds, because fixed
         * numbers fell below the joining threshold with the small model.
         */
        private const val SUGGEST_BELOW_LINK = 0.025f
        private const val SUGGEST_BEST_BELOW_LINK = 0.01f
        private const val SUGGEST_CENTROID_BELOW_JOIN = 0.03f

        /** What a pair exactly at the merge rule's link scores on the review screen's scale. */
        private const val SUGGEST_SCORE_AT_LINK = 0.41f

        /** Looks kept per person. */
        private const val MAX_PROTOS = 6

        /** Faces of one video that may shape a person. */
        private const val MAX_PER_VIDEO = 2

        /** Faces shown per group when previewing a split. */
        private const val SPLIT_SAMPLE = 8

        /**
         * The share of the clear faces that the smaller group should hold for a split to count as
         * real rather than one stray face against everyone else.
         */
        private const val SPLIT_MIN_SHARE = 0.1f
    }
}

private fun dotProduct(a: FloatArray, b: FloatArray): Float {
    var d = 0f
    for (i in a.indices) d += a[i] * b[i]
    return d
}
