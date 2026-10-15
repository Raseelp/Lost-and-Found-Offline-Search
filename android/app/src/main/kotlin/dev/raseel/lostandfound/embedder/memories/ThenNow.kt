package dev.raseel.lostandfound.embedder.memories

import java.util.Calendar
import java.util.Random
import java.util.TimeZone

/**
 * "Then and now" for one person: good photos of them from about the start of their time in the photos and
 * from about now.
 *
 * "About" is meant: not the first and last photo there is, but the best of the first couple of months and
 * of the latest couple (the window widens a step at a time - 2, 4, 8, 12 months - only if those months
 * have too little to choose from). Works only from clear faces in still photos with a trustworthy date
 * (the caller filters), and from a bounded list - one person's dated faces - so it costs the same however
 * big the library is. Lone photos far from the rest (most likely a wrong date) never count as the first or
 * last time, the same rule the people timeline uses.
 *
 * Each end offers a few photos that differ in kind - on their own, with one other person, in a small
 * group - because a person is more than the pictures of their face, and the comparison can mix them. Which
 * of the options are shown first is random (the seed says how, so it can be the same all day).
 */
object ThenNow {
    /** Another clear face in the photo: who (a listed person) and where it is. */
    class Other(val personId: Long, val boxL: Float, val boxT: Float, val boxR: Float, val boxB: Float)

    class Cand(
        val faceId: Long,
        val key: Long,
        val uri: String,
        val takenMs: Long,
        /** How good a picture of the person it is (see FaceQuality.rank). */
        val rank: Float,
        val boxL: Float, val boxT: Float, val boxR: Float, val boxB: Float,
        val photoW: Int, val photoH: Int,
        /** How many clear faces there are in the photo, the person's own included. */
        val faces: Int = 1,
        /** The listed people among the other clear faces. */
        val others: List<Other> = emptyList(),
        /** For a picture of two people: the other one, always framed together with the first. */
        val pair: Long? = null,
    ) {
        /** Who is framed with the person: the pair's other, or the one other person when it is just the two of them. */
        val partner: Long?
            get() = pair ?: if (faces == 2 && others.size == 1) others[0].personId else null

        val kind: Kind
            get() = when {
                partner != null -> Kind.DUO
                faces <= 1 -> Kind.SOLO
                faces <= MAX_GROUP -> Kind.GROUP
                else -> Kind.CROWD
            }

        /** The box to frame: the person's own, or - with [withId] in the photo too - the two of them. */
        fun box(withId: Long?): FloatArray {
            val o = if (withId == null) null else others.firstOrNull { it.personId == withId }
            return if (o == null) floatArrayOf(boxL, boxT, boxR, boxB) else floatArrayOf(
                minOf(boxL, o.boxL), minOf(boxT, o.boxT), maxOf(boxR, o.boxR), maxOf(boxB, o.boxB),
            )
        }
    }

    enum class Kind(val code: String) { SOLO("solo"), DUO("duo"), GROUP("group"), CROWD("crowd") }

    class Result(
        /** Up to three photos from about the start, best first; the same for about now in [now]. */
        val then: List<Cand>,
        val now: List<Cand>,
        /** Which of the options are shown first (random, by the seed). */
        val startThen: Int,
        val startNow: Int,
        val spanMonths: Int,
        val firstMonth: Int,
        val lastMonth: Int,
    )

    // The windows tried, in months from each end; the later ones only when the earlier have too little.
    private val WINDOWS = intArrayOf(2, 4, 8, 12, 18, 24)
    private const val MIN_SPAN_MONTHS = 6
    private const val MIN_PHOTOS = 4
    private const val LONE_GAP_MONTHS = 18
    private const val PER_SIDE = 3
    private const val APART_MS = 14L * 24 * 3_600_000
    private const val MAX_GROUP = 5

    fun monthOf(ms: Long, tz: TimeZone): Int {
        val cal = Calendar.getInstance(tz)
        cal.timeInMillis = ms
        return cal.get(Calendar.YEAR) * 12 + cal.get(Calendar.MONTH)
    }

    /** The photos to show, or null when there is not enough to compare (too little time between, too few photos). */
    fun choose(cands: List<Cand>, tz: TimeZone = TimeZone.getDefault(), perSide: Int = PER_SIDE, seed: Long = 0L): Result? {
        if (cands.size < MIN_PHOTOS) return null

        // Photos per month (a photo counts once however many faces it has).
        val perMonth = java.util.TreeMap<Int, MutableSet<Long>>()
        val monthOfCand = HashMap<Cand, Int>(cands.size * 2)
        for (c in cands) {
            val m = monthOf(c.takenMs, tz)
            monthOfCand[c] = m
            perMonth.getOrPut(m) { HashSet() } += c.key
        }
        val months = perMonth.keys.toList()
        var lo = 0
        var hi = months.size - 1
        while (lo < hi && perMonth[months[lo]]!!.size == 1 && months[lo + 1] - months[lo] > LONE_GAP_MONTHS) lo++
        while (hi > lo && perMonth[months[hi]]!!.size == 1 && months[hi] - months[hi - 1] > LONE_GAP_MONTHS) hi--
        val first = months[lo]
        val last = months[hi]
        val span = last - first
        if (span < MIN_SPAN_MONTHS) return null

        // About the start and about now: the first couple of months and the latest couple, widening only
        // while either has too little to choose from. The two never meet.
        val reach = (span + 1) / 2
        var thenPool = emptyList<Cand>()
        var nowPool = emptyList<Cand>()
        for ((i, w) in WINDOWS.withIndex()) {
            val width = minOf(w, reach)
            thenPool = cands.filter { monthOfCand[it]!! in first..(first + width - 1) }
            nowPool = cands.filter { monthOfCand[it]!! in (last - width + 1)..last }
            // Enough for three options at each end (three different photos that can be told apart).
            val enough = options(thenPool, perSide).size >= perSide && options(nowPool, perSide).size >= perSide
            if (enough || i == WINDOWS.lastIndex || width == reach) break
        }

        val then = options(thenPool, perSide)
        val now = options(nowPool, perSide)
        if (then.isEmpty() || now.isEmpty()) return null

        // Which are shown first: random, the same for the same seed.
        val random = Random(seed)
        val startThen = random.nextInt(then.size)
        var startNow = random.nextInt(now.size)
        fun same() = then[startThen].key == now[startNow].key || then[startThen].uri == now[startNow].uri
        if (same()) {
            startNow = (startNow + 1) % now.size
            if (same()) return null
        }
        return Result(then, now, startThen, startNow, span, first, last)
    }

    // How good a picture it is of the person, a crowd counting for less (two in the picture costs nothing).
    private fun score(c: Cand): Float = c.rank / (1f + 0.3f * (c.faces - 2).coerceAtLeast(0))

    /**
     * Up to [n] of [pool], all different photos, and as different in kind as there is: the best on their own,
     * the best with one other person, the best in a small group, then the best of what is left. They are
     * taken a fortnight or more from each other if the photos allow it; if that leaves fewer than [n], a few
     * days apart, and then simply different photos - so there are three whenever there are three. Best first.
     */
    fun options(pool: List<Cand>, n: Int): List<Cand> {
        val chosen = ArrayList<Cand>(n)
        val ranked = pool.sortedWith(compareByDescending<Cand> { score(it) }.thenBy { it.takenMs })
        fun free(c: Cand, apart: Long) = chosen.none { it.key == c.key || it.uri == c.uri || Math.abs(it.takenMs - c.takenMs) < apart }
        for (kind in listOf(Kind.SOLO, Kind.DUO, Kind.GROUP)) {
            if (chosen.size >= n) break
            ranked.firstOrNull { it.kind == kind && free(it, APART_MS) }?.let { chosen += it }
        }
        for (apart in longArrayOf(APART_MS, 3L * 24 * 3_600_000, 1L)) {
            for (c in ranked) {
                if (chosen.size >= n) break
                if (free(c, apart)) chosen += c
            }
        }
        return chosen.sortedWith(compareByDescending<Cand> { score(it) }.thenBy { it.takenMs })
    }
}
