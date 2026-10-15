package dev.raseel.lostandfound.embedder.faces

/**
 * Which photos and videos stand for a month on the People timeline's filmstrip.
 *
 * Every month gets a few: the ones with the clearest faces, and the most people in them, so a group
 * photo beats a single close-up. Shots taken almost together (a burst) count once, so the strip
 * does not show the same moment four times.
 */
object TimelinePicks {
    class Candidate(
        val key: Long,
        val uri: String,
        val isVideo: Boolean,
        /** Where in a video the best face is (0 for a photo). */
        val tsMs: Long,
        /** When it was taken. */
        val takenMs: Long,
        /** Higher is better. */
        val score: Float,
    )

    /**
     * The best [perMonth] of every month, [candidates] being everything dated; shots less than
     * [burstMs] apart (in the same month) count as one. The result is in the order they were taken.
     */
    fun bestPerMonth(
        candidates: List<Candidate>,
        monthOf: (Long) -> Int,
        perMonth: Int,
        burstMs: Long,
    ): List<Candidate> {
        val byMonth = HashMap<Int, ArrayList<Candidate>>()
        for (c in candidates) byMonth.getOrPut(monthOf(c.takenMs)) { ArrayList() }.add(c)
        val out = ArrayList<Candidate>()
        for ((_, list) in byMonth) {
            list.sortWith(compareByDescending<Candidate> { it.score }.thenBy { it.takenMs })
            val chosen = ArrayList<Candidate>(perMonth)
            for (c in list) {
                if (chosen.size >= perMonth) break
                if (chosen.any { kotlin.math.abs(it.takenMs - c.takenMs) < burstMs }) continue
                chosen += c
            }
            out += chosen
        }
        out.sortBy { it.takenMs }
        return out
    }

    /** The score of a photo from the ranks of the faces in it: its three clearest count. */
    fun score(faceRanks: List<Float>): Float = faceRanks.sortedDescending().take(3).sum()
}
