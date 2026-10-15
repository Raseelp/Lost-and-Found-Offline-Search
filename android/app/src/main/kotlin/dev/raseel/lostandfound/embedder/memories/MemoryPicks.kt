package dev.raseel.lostandfound.embedder.memories

import dev.raseel.lostandfound.embedder.faces.TimelinePicks

/**
 * Which photos stand for a day of a past year.
 *
 * A day can hold anything from one photo to a thousand (a trip), so the choice is made from a bounded
 * list of candidates, never by looking at everything: first the photos with the clearest faces (a
 * group beats a close-up, see [TimelinePicks.score]), then - to give the day some variety - photos
 * with no people, spread evenly through the day rather than the first ones taken. Shots taken almost
 * together (a burst) count once. The result is in the order they were taken.
 */
object MemoryPicks {
    const val BURST_MS = 120_000L

    fun pick(candidates: List<TimelinePicks.Candidate>, n: Int, burstMs: Long = BURST_MS): List<TimelinePicks.Candidate> {
        if (candidates.isEmpty() || n <= 0) return emptyList()
        val chosen = ArrayList<TimelinePicks.Candidate>(n)
        fun free(c: TimelinePicks.Candidate) = chosen.none { Math.abs(it.takenMs - c.takenMs) < burstMs }

        val withPeople = candidates.filter { it.score > 0f }
            .sortedWith(compareByDescending<TimelinePicks.Candidate> { it.score }.thenBy { it.takenMs })
        for (c in withPeople) {
            if (chosen.size >= n) break
            if (free(c)) chosen += c
        }

        if (chosen.size < n) {
            val rest = candidates.filter { it.score <= 0f }.sortedBy { it.takenMs }
            val need = n - chosen.size
            if (rest.isNotEmpty()) {
                // Evenly spread: the middle of each of [need] equal parts of the day's list.
                val step = rest.size.toDouble() / need
                var next = 0
                for (i in 0 until need) {
                    var at = maxOf((i * step + step / 2).toInt(), next)
                    while (at < rest.size && !free(rest[at])) at++
                    if (at >= rest.size) break
                    chosen += rest[at]
                    next = at + 1
                }
            }
        }
        return chosen.sortedBy { it.takenMs }
    }

    /**
     * How well a past year stands for the day: how clear the best faces are, how much was going on
     * (the count counts for less and less), and a bonus for having people in it at all.
     */
    fun strength(count: Int, bestScore: Float): Float =
        minOf(bestScore, 300f) / 300f + 0.5f * minOf(1.0, Math.log(1.0 + count) / Math.log(21.0)).toFloat() +
            (if (bestScore > 0f) 0.3f else 0f)

    /**
     * Whether a year is worth a notification: a photo with people in it, or a day with a few photos.
     * One lone landscape from that date is not.
     */
    fun qualifies(count: Int, bestScore: Float): Boolean = bestScore > 0f || count >= 4
}
