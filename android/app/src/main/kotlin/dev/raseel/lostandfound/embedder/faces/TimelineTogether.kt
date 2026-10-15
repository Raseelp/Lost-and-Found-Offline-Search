package dev.raseel.lostandfound.embedder.faces

/**
 * Who each person is photographed with most, and when they first were - for the timeline's
 * "first photo together" moment.
 */
object TimelineTogether {
    /**
     * [withId] is the person [personId] shares the most photos with; they have [count] together, the
     * first at [firstMs] (the photo or video [firstKey]).
     */
    class Companion(val personId: Long, val withId: Long, val count: Int, val firstMs: Long, val firstKey: Long)

    private class Pair(var count: Int, var firstMs: Long, var firstKey: Long)

    /**
     * [media] is every dated photo or video (when it was taken, who is in it). A person's
     * companion is the one they are in the most photos with (the earlier first photo wins a tie).
     * Very big groups are left out: a photo of twenty people says little about two of them.
     */
    fun companions(media: List<Item>, maxGroup: Int = 12): List<Companion> {
        val pairs = HashMap<kotlin.Pair<Long, Long>, Pair>()
        for (m in media) {
            if (m.people.size < 2 || m.people.size > maxGroup) continue
            val sorted = m.people.distinct().sorted()
            for (i in sorted.indices) {
                for (j in i + 1 until sorted.size) {
                    val key = sorted[i] to sorted[j]
                    val p = pairs.getOrPut(key) { Pair(0, m.ms, m.key) }
                    p.count++
                    if (m.ms < p.firstMs || (m.ms == p.firstMs && m.key < p.firstKey)) {
                        p.firstMs = m.ms
                        p.firstKey = m.key
                    }
                }
            }
        }
        val best = HashMap<Long, Companion>()
        fun offer(person: Long, other: Long, p: Pair) {
            val current = best[person]
            if (current == null || p.count > current.count || (p.count == current.count && p.firstMs < current.firstMs)) {
                best[person] = Companion(person, other, p.count, p.firstMs, p.firstKey)
            }
        }
        for ((key, p) in pairs) {
            offer(key.first, key.second, p)
            offer(key.second, key.first, p)
        }
        return best.values.toList()
    }

    /** A photo or video with many known people in it. */
    class Crowd(val key: Long, val ms: Long, val people: List<Long>)

    /** A photo or video that brought together people who had not been photographed together for a long time. */
    class Reunion(val key: Long, val ms: Long, val people: List<Long>, val gapDays: Int)

    /** One dated photo or video: its key, when it was taken, who is in it. */
    class Item(val key: Long, val ms: Long, val people: List<Long>)

    /**
     * For each year, the [perYear] photos or videos with the most different people in them (at least
     * [minPeople]; the earlier one wins a tie). The caller decides which of those people are known.
     */
    fun crowds(media: List<Item>, yearOf: (Long) -> Int, minPeople: Int = 4, perYear: Int = 3): List<Crowd> {
        val byYear = HashMap<Int, ArrayList<Crowd>>()
        for (m in media) {
            val people = m.people.distinct()
            if (people.size < minPeople) continue
            byYear.getOrPut(yearOf(m.ms)) { ArrayList() } += Crowd(m.key, m.ms, people)
        }
        val out = ArrayList<Crowd>()
        for ((_, list) in byYear) {
            list.sortWith(compareByDescending<Crowd> { it.people.size }.thenBy { it.ms })
            out += list.take(perYear)
        }
        return out.sortedBy { it.ms }
    }

    private const val DAY_MS = 86_400_000L

    /**
     * A reunion: a photo of [minPeople] to [maxPeople] people where none of the pairs among them has been
     * photographed together for [gapDays] days, and at least two of the pairs were together before that
     * (so it is people coming back together, not people meeting). At most one a [spacingDays] stretch,
     * the one with the most people (then the longest time apart) winning.
     */
    fun reunions(
        media: List<Item>,
        minPeople: Int = 3,
        maxPeople: Int = 12,
        gapDays: Int = 365,
        spacingDays: Int = 180,
    ): List<Reunion> {
        val last = HashMap<kotlin.Pair<Long, Long>, Long>()
        val found = ArrayList<Reunion>()
        // What a day's photos add to [last] waits until the day is over: all the photos of a get-together
        // are measured against the time before it, so its best photo can win, not only its first.
        val today = ArrayList<kotlin.Pair<kotlin.Pair<Long, Long>, Long>>()
        var day = Long.MIN_VALUE
        for (m in media.sortedBy { it.ms }) {
            val thisDay = Math.floorDiv(m.ms, DAY_MS)
            if (thisDay != day) {
                for ((key, ms) in today) last[key] = ms
                today.clear()
                day = thisDay
            }
            val people = m.people.distinct().sorted()
            if (people.size < 2) continue
            var recent = false
            var returning = 0
            var shortest = Long.MAX_VALUE
            val pairs = ArrayList<kotlin.Pair<Long, Long>>()
            for (i in people.indices) {
                for (j in i + 1 until people.size) {
                    val key = people[i] to people[j]
                    pairs += key
                    val before = last[key] ?: continue
                    val apart = m.ms - before
                    if (apart < gapDays * DAY_MS) {
                        recent = true
                    } else {
                        returning++
                        if (apart < shortest) shortest = apart
                    }
                }
            }
            if (people.size in minPeople..maxPeople && !recent && returning >= 2) {
                found += Reunion(m.key, m.ms, people, (shortest / DAY_MS).toInt())
            }
            for (key in pairs) today += key to m.ms
        }
        // The best of each stretch.
        val chosen = ArrayList<Reunion>()
        for (r in found.sortedWith(compareByDescending<Reunion> { it.people.size }.thenByDescending { it.gapDays })) {
            if (chosen.none { Math.abs(it.ms - r.ms) < spacingDays * DAY_MS }) chosen += r
        }
        return chosen.sortedBy { it.ms }
    }
}
