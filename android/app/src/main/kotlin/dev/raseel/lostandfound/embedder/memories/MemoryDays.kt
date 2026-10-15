package dev.raseel.lostandfound.embedder.memories

import java.util.Calendar
import java.util.TimeZone

/**
 * Days on the calendar, for "this day in past years".
 *
 * A day is a local day: midnight to midnight in the phone's time zone, so a photo taken at 23:50 stays
 * on its own day. Each year gets its own range, so a day in a past year is found with one lookup on
 * the date index (a range scan), however many photos there are in all.
 */
object MemoryDays {

    /** The local days [month]/[day] of [year], widened by [spread] days either side, as [start, end) in ms; null for 29 February in a year without one. */
    fun range(year: Int, month: Int, day: Int, spread: Int = 0, tz: TimeZone = TimeZone.getDefault()): Pair<Long, Long>? {
        val cal = Calendar.getInstance(tz)
        cal.clear()
        cal.isLenient = false
        return try {
            cal.set(year, month - 1, day, 0, 0, 0)
            cal.timeInMillis // validates the date
            val centre = cal.timeInMillis
            cal.timeInMillis = centre
            cal.add(Calendar.DAY_OF_MONTH, -spread)
            val start = cal.timeInMillis
            cal.timeInMillis = centre
            cal.add(Calendar.DAY_OF_MONTH, spread + 1)
            start to cal.timeInMillis
        } catch (_: IllegalArgumentException) {
            null
        }
    }

    /** Year, month (1..12) and day of month of [ms] in [tz]. */
    fun ymd(ms: Long, tz: TimeZone = TimeZone.getDefault()): Triple<Int, Int, Int> {
        val cal = Calendar.getInstance(tz)
        cal.timeInMillis = ms
        return Triple(cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH))
    }

    /** A number for the day, counting up by one each day (for "how many days ago"). */
    fun dayNumber(ms: Long, tz: TimeZone = TimeZone.getDefault()): Int {
        val (y, m, d) = ymd(ms, tz)
        val cal = Calendar.getInstance(TimeZone.getTimeZone("UTC"))
        cal.clear()
        cal.set(y, m - 1, d, 0, 0, 0)
        return Math.floorDiv(cal.timeInMillis, 86_400_000L).toInt()
    }

    /** "Wednesday-free" label such as "May 3". */
    fun label(month: Int, day: Int): String = "${MONTHS[month - 1]} $day"

    val MONTHS = arrayOf(
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December",
    )
}
