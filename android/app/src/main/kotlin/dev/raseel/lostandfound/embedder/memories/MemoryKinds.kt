package dev.raseel.lostandfound.embedder.memories

/**
 * The small algorithms behind the kinds of memory that are not just "this date in past years". All pure:
 * they work on numbers and lists the planner hands them, so they are tested on their own.
 */

/** A few busy days in a row: a trip, a holiday, a long weekend. */
object Trips {
    class Run(val startDay: Int, val endDay: Int, val total: Int, val perDay: Map<Int, Int>) {
        val days: Int get() = endDay - startDay + 1
    }

    /**
     * [perDay] is the photos taken on each day (by day number). A trip is [minDays] or more days in a
     * row with at least [minPerDay] photos each and [minTotal] in all - one busy day is a party, a few
     * quiet days in a row are not worth a notification.
     */
    fun find(perDay: Map<Int, Int>, minDays: Int = 3, minPerDay: Int = 5, minTotal: Int = 24): List<Run> {
        val busy = perDay.filterValues { it >= minPerDay }.keys.sorted()
        val runs = ArrayList<Run>()
        var i = 0
        while (i < busy.size) {
            var j = i
            while (j + 1 < busy.size && busy[j + 1] == busy[j] + 1) j++
            val days = busy.subList(i, j + 1)
            val total = days.sumOf { perDay[it] ?: 0 }
            if (days.size >= minDays && total >= minTotal) {
                runs += Run(days.first(), days.last(), total, days.associateWith { perDay[it] ?: 0 })
            }
            i = j + 1
        }
        return runs
    }

    /** The biggest trip that takes in the day [centreDay] or the [spread] days round it. */
    fun near(runs: List<Run>, centreDay: Int, spread: Int): Run? =
        runs.filter { it.endDay >= centreDay - spread && it.startDay <= centreDay + spread }.maxByOrNull { it.total }
}

/** Round numbers of photos of a person. */
object Milestones {
    val STEPS = intArrayOf(50, 100, 250, 500, 1000, 2000, 5000, 10000)

    /** The biggest step [count] has reached (0 before the first). */
    fun reached(count: Int): Int = STEPS.lastOrNull { it <= count } ?: 0

    /** The step [count] has newly passed, given the biggest one already told about; null if none. */
    fun crossed(count: Int, announced: Int): Int? = reached(count).takeIf { it > announced }
}

/** Someone's first day in the photos, told once a year on its date. */
object FirstAppearance {
    private const val DAY_MS = 86_400_000L

    /**
     * Whether [firstMs] is a real beginning and not one photo with a wrong date: at least [need] photos
     * in the [windowDays] days from it ([takenMs] are all the dates there are).
     */
    fun real(takenMs: List<Long>, firstMs: Long, windowDays: Int = 90, need: Int = 3): Boolean =
        takenMs.count { it in firstMs..(firstMs + windowDays * DAY_MS) } >= need
}

/** Choices that are the same all day but different from one day to the next, so the same thing is not picked every time. */
object DayChoice {
    /** [list] turned round to start at a place that depends on [day]. */
    fun <T> rotated(list: List<T>, day: Int): List<T> {
        if (list.size < 2) return list
        val start = Math.floorMod(day.toLong() * 2_654_435_761L, list.size.toLong()).toInt()
        return list.drop(start) + list.take(start)
    }

    /** One of [options] for [day]. */
    fun <T> pick(day: Int, vararg options: T): T = options[Math.floorMod(day, options.size)]
}
