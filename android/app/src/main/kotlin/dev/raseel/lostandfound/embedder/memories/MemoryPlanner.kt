package dev.raseel.lostandfound.embedder.memories

import dev.raseel.lostandfound.embedder.faces.FaceStore
import dev.raseel.lostandfound.embedder.faces.TimelinePicks
import java.util.TimeZone

/** A photo or video of a memory, with who is in it. */
class PlanPhoto(
    val key: Long,
    val uri: String,
    val video: Boolean,
    val tsMs: Long,
    val takenMs: Long,
    val score: Float,
    val names: List<String>,
)

/** One past year's share of a day: how much there was, and the photos that stand for it. */
class DayYear(
    val year: Int,
    val yearsAgo: Int,
    val total: Int,
    val photos: List<PlanPhoto>,
    val strength: Float,
    val qualifies: Boolean,
) {
    /** The best photo of it (the one with the clearest people). */
    val best: PlanPhoto? get() = photos.maxWithOrNull(compareBy<PlanPhoto> { it.score }.thenBy { -it.takenMs })

    /** The named people in its photos, most often seen first. */
    val names: List<String>
        get() = photos.flatMap { it.names }.groupingBy { it }.eachCount().entries.sortedByDescending { it.value }.map { it.key }
}

/** Two people's first photo together, on its anniversary. */
class Anniversary(val yearsAgo: Int, val ids: List<Long>, val names: List<String>, val firstMs: Long, val photo: PlanPhoto?)

class Plan(
    val month: Int,
    val day: Int,
    val year: Int,
    /** The same date in past years, most recent first (only years that have something). */
    val exact: List<DayYear>,
    /** The week round it, for a day with nothing on the date itself. */
    val week: List<DayYear>,
    val anniversaries: List<Anniversary>,
)

/**
 * One picture of a notification: a whole photo, or - with a [box] (0..1 fractions of the photo) - the face
 * or faces framed head-and-shoulders. [label] is written on it (a year, a day).
 */
class Pic(
    val uri: String,
    val video: Boolean = false,
    val box: FloatArray? = null,
    val photoW: Int = 0,
    val photoH: Int = 0,
    val margin: Float = 3.1f,
    val lift: Float = 0.55f,
    val label: String? = null,
)

/**
 * What a notification says, and its picture: [pics] when it has them (one framed, or several side by
 * side), else the [photo]. [subject] is who it is about (not again for a while); [milestone] is the person
 * and round number it told about (remembered once it is sent).
 */
class Notice(
    val kind: MemoryKind,
    val title: String,
    val body: String,
    val photo: PlanPhoto?,
    val year: Int,
    val pics: List<Pic> = emptyList(),
    val subject: String? = null,
    val milestone: Pair<Long, Int>? = null,
    val personId: Long? = null,
    /** Written on the picture: the time between then and now, or since when. */
    val connector: String? = null,
)

/**
 * Works out what there is to remember for a date: [plan] looks the date up in every past year (one
 * range scan each, never more than a bounded list of candidates per year, so a library of a million
 * photos costs the same as one of a thousand), and [notices] turns that into the things a notification
 * could say today.
 */
class MemoryPlanner(private val dates: LibraryDates, private val faces: FaceStore) {

    /**
     * [exclude]: photos not to show (shown lately). With [withWeek], also looks at the week round the
     * date, but only when the date itself has nothing.
     */
    fun plan(
        now: Long,
        exclude: Set<Long> = emptySet(),
        withWeek: Boolean = false,
        withAnniversaries: Boolean = false,
        tz: TimeZone = TimeZone.getDefault(),
    ): Plan {
        val (year, month, day) = MemoryDays.ymd(now, tz)
        val bounds = dates.bounds()
        val firstYear = bounds?.let { MemoryDays.ymd(it.first, tz).first } ?: year
        val years = (year - 1 downTo maxOf(firstYear, year - MAX_YEARS)).toList()

        val exact = years.mapNotNull { y ->
            MemoryDays.range(y, month, day, 0, tz)?.let { dayYear(y, year, it, exclude) }
        }
        val week = if (withWeek && exact.isEmpty()) {
            years.mapNotNull { y ->
                MemoryDays.range(y, month, day, WEEK_SPREAD, tz)?.let { dayYear(y, year, it, exclude) }
            }
        } else {
            emptyList()
        }
        val anniversaries = if (withAnniversaries) anniversaries(now, exclude, tz) else emptyList()
        return Plan(month, day, year, exact, week, anniversaries)
    }

    private fun dayYear(year: Int, nowYear: Int, range: Pair<Long, Long>, exclude: Set<Long>): DayYear? {
        val total = dates.count(range.first, range.second)
        if (total == 0) return null
        val rows = dates.photos(range.first, range.second, MAX_CANDIDATES).filter { it.key !in exclude }
        if (rows.isEmpty()) return null
        val scores = faces.faceScores(rows.map { it.key })
        val cands = rows.map {
            TimelinePicks.Candidate(it.key, it.uri, it.video, if (it.video) VIDEO_FRAME_MS else 0L, it.takenMs, scores[it.key] ?: 0f)
        }
        val picked = MemoryPicks.pick(cands, PICKS)
        val names = faces.namesIn(picked.map { it.key })
        val best = cands.maxOf { it.score }
        return DayYear(
            year = year,
            yearsAgo = nowYear - year,
            total = total,
            photos = picked.map { PlanPhoto(it.key, it.uri, it.isVideo, it.tsMs, it.takenMs, it.score, names[it.key].orEmpty().map { n -> n.second }) },
            strength = MemoryPicks.strength(total, best),
            qualifies = MemoryPicks.qualifies(total, best),
        )
    }

    // The people timeline is a pass over every face: kept for a while (by the process, not by this planner,
    // which is made afresh for every look), not worked out each time.
    fun timeline(now: Long): FaceStore.TimelineResult {
        cachedTimeline?.let { if (now - it.first in 0 until TIMELINE_KEEP_MS) return it.second }
        return faces.peopleTimeline(full = true).also { cachedTimeline = now to it }
    }

    private fun anniversaries(now: Long, exclude: Set<Long>, tz: TimeZone): List<Anniversary> {
        val (year, month, day) = MemoryDays.ymd(now, tz)
        val tl = timeline(now)
        val seen = HashSet<Pair<Long, Long>>()
        val due = ArrayList<kotlin.Triple<dev.raseel.lostandfound.embedder.faces.TimelineTogether.Companion, Int, Pair<Long, Long>>>()
        for (c in tl.together) {
            if (c.count < MIN_TOGETHER) continue
            val (y, m, d) = MemoryDays.ymd(c.firstMs, tz)
            if (m != month || d != day || y >= year) continue
            val pair = minOf(c.personId, c.withId) to maxOf(c.personId, c.withId)
            if (seen.add(pair)) due += kotlin.Triple(c, y, pair)
        }
        if (due.isEmpty()) return emptyList()
        val names = faces.namesOf(due.flatMap { listOf(it.third.first, it.third.second) })
        val out = ArrayList<Anniversary>()
        for ((c, y, pair) in due) {
            // Both have to be named: "two people" is not much of a celebration.
            val a = names[pair.first] ?: continue
            val b = names[pair.second] ?: continue
            val g = tl.togetherFirst[c.personId]
            if (g != null && g.key in exclude) continue
            val photo = g?.let { PlanPhoto(it.key, it.uri, it.isVideo, 0L, it.ms, 0f, listOf(a, b)) }
            out += Anniversary(year - y, listOf(pair.first, pair.second), listOf(a, b), c.firstMs, photo)
        }
        return out
    }

    /** What a notification could be about today, by kind: the ones that have something good enough. */
    fun notices(plan: Plan): Map<MemoryKind, Notice> = MemoryNotices.build(plan)

    companion object {
        const val MAX_YEARS = 60
        const val MAX_CANDIDATES = 1500
        const val PICKS = 6
        const val WEEK_SPREAD = 3
        const val MIN_TOGETHER = 3
        const val TIMELINE_KEEP_MS = 6 * 60 * 60 * 1000L
        private const val VIDEO_FRAME_MS = 1000L

        @Volatile private var cachedTimeline: Pair<Long, FaceStore.TimelineResult>? = null
    }
}

/**
 * The words of the daily memory, from a [Plan]: which kinds there is something good enough for, and what each says. No
 * database in it, so it is tested on its own. The tone is always warm: what you have, never what is missing.
 */
object MemoryNotices {
    const val MIN_YEARS_ACROSS = 3

    // A day with this many photos was an occasion.
    const val BIG_DAY = 40

    /** What a notification could be about today, by kind: the ones that have something good enough. */
    fun build(plan: Plan): Map<MemoryKind, Notice> {
        val out = LinkedHashMap<MemoryKind, Notice>()
        plan.anniversaries.maxByOrNull { it.yearsAgo }?.let { a ->
            val who = join(a.names)
            out[MemoryKind.ANNIVERSARY] = Notice(
                MemoryKind.ANNIVERSARY,
                "$who · ${years(a.yearsAgo)} of photos together",
                "You first appeared in a photo together on this day in ${plan.year - a.yearsAgo}.",
                a.photo,
                plan.year - a.yearsAgo,
            )
        }

        val good = plan.exact.filter { it.qualifies }
        bestYear(good)?.let { y ->
            val day = plan.year * 372 + plan.month * 31 + plan.day // anything that differs from day to day
            val crowd = (y.best?.names?.size ?: 0) >= 3
            val big = y.total >= BIG_DAY
            val title = when {
                crowd -> DayChoice.pick(day, "Everyone together · ${ago(y.yearsAgo)}", "The whole gang · ${ago(y.yearsAgo)} today")
                big -> "A day to remember · ${ago(y.yearsAgo)}"
                else -> DayChoice.pick(day, "On this day · ${ago(y.yearsAgo)}", "${years(y.yearsAgo)} ago today", "Remember this day?")
            }
            val body = if (big) "${describe(plan, y, withCount = false)} · ${y.total} photos and videos" else describe(plan, y)
            out[MemoryKind.ON_THIS_DAY] = Notice(MemoryKind.ON_THIS_DAY, title, body, y.best, y.year)
        }
        if (good.size >= MIN_YEARS_ACROSS) {
            val y = bestYear(good)!!
            // The picture: the best photo of up to three of the years, side by side, each with its year.
            val strip = good.sortedByDescending { it.strength }.take(3).sortedBy { it.year }
                .mapNotNull { yr -> yr.best?.let { Pic(it.uri, it.video, label = yr.year.toString()) } }
            out[MemoryKind.SAME_DAY] = Notice(
                MemoryKind.SAME_DAY,
                "${MemoryDays.label(plan.month, plan.day)}, across the years",
                "Photos from ${good.size} different years are waiting for you.",
                y.best,
                y.year,
                pics = strip,
            )
        }
        bestYear(plan.week.filter { it.qualifies })?.let { y ->
            out[MemoryKind.THIS_WEEK] = Notice(
                MemoryKind.THIS_WEEK,
                "This week · ${ago(y.yearsAgo)}",
                describe(null, y),
                y.best,
                y.year,
            )
        }
        return out
    }

    // The year that stands for the date best; a tie goes to the longer ago (it has gone the longer unseen).
    private fun bestYear(years: List<DayYear>): DayYear? =
        years.maxWithOrNull(compareBy<DayYear> { it.strength }.thenBy { it.yearsAgo })

    // "Anna and Dev · May 3, 2022", or the date and how much there was.
    private fun describe(plan: Plan?, y: DayYear, withCount: Boolean = true): String {
        val date = y.best?.takenMs?.let { MemoryDays.ymd(it) }
            ?: Triple(y.year, plan?.month ?: 1, plan?.day ?: 1)
        val dateText = "${MemoryDays.label(date.second, date.third)}, ${date.first}"
        // Who is in the photo shown - not in any of the year's other photos.
        val who = y.best?.names.orEmpty().take(3)
        return when {
            who.isNotEmpty() -> "${join(who)} · $dateText"
            withCount && y.total > 1 -> "$dateText · ${y.total} photos and videos"
            else -> dateText
        }
    }

    fun ago(years: Int) = if (years == 1) "1 year ago" else "$years years ago"

    fun years(n: Int) = if (n == 1) "1 year" else "$n years"

    fun join(names: List<String>): String = when (names.size) {
        0 -> ""
        1 -> names[0]
        else -> names.dropLast(1).joinToString(", ") + " and " + names.last()
    }
}
