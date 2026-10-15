package dev.raseel.lostandfound.embedder.memories

import dev.raseel.lostandfound.embedder.faces.FaceCrops
import dev.raseel.lostandfound.embedder.faces.FaceStore
import java.util.TimeZone

/**
 * The kinds of memory that are about people rather than a date: someone's first day in the photos, a round
 * number of photos, then and now (one person, or two together), years together, a few days of a trip, a
 * lovely picture out of the blue. Every one is computed from a bounded amount: one person's dated faces,
 * one pair's photos, one year's week - never the whole library - and only for a handful of people a day
 * (the day decides which, so it is different every day and the same all day).
 *
 * All warm: what there is, never what is missing.
 */
class MemoryEvergreen(
    private val dates: LibraryDates,
    private val faces: FaceStore,
    private val planner: MemoryPlanner,
) {
    /** What the day's choices depend on. */
    class Ctx(
        val now: Long,
        val today: Int,
        val tz: TimeZone,
        /** Photos not to show (shown lately). */
        val exclude: Set<Long>,
        /** People and pairs it was about lately, by subject. */
        val subjects: Map<String, Int>,
        /** The round number already told about, by person (null: not set up yet, so there is nothing to announce). */
        val announced: Map<Long, Int>?,
    )

    fun build(c: Ctx): Map<MemoryKind, Notice> {
        val out = LinkedHashMap<MemoryKind, Notice>()
        val stats = faces.personStats()
        fun add(kind: MemoryKind, make: () -> Notice?) {
            try {
                make()?.let { out[kind] = it }
            } catch (e: Exception) {
                android.util.Log.w("MemoryEvergreen", "$kind failed: ${e.message}")
            }
        }
        add(MemoryKind.PERSON_ANNIVERSARY) { personAnniversary(c, stats) }
        add(MemoryKind.MILESTONE) { milestone(c) }
        add(MemoryKind.THEN_NOW) { thenNow(c, stats) }
        add(MemoryKind.VAULT) { vault(c, stats) }
        add(MemoryKind.TRIP) { trip(c) }
        pairs(c, out)
        return out
    }

    // ---- someone's first day ----

    private fun personAnniversary(c: Ctx, stats: List<FaceStore.PersonStat>): Notice? {
        val (year, month, day) = MemoryDays.ymd(c.now, c.tz)
        for (s in stats) {
            if (s.photos < MIN_FOR_PERSON) continue
            val (y, m, d) = MemoryDays.ymd(s.firstMs, c.tz)
            if (m != month || d != day || y >= year) continue
            val all = faces.personDatedFaces(s.id)
            // One photo with a wrong date is not a beginning.
            if (!FirstAppearance.real(all.map { it.takenMs }, s.firstMs)) continue
            val early = all.filter { it.takenMs - s.firstMs <= 60 * DAY_MS && it.key !in c.exclude }
            val pick = early.maxByOrNull { suited(it) } ?: continue
            val n = year - y
            return Notice(
                MemoryKind.PERSON_ANNIVERSARY,
                "${s.name} · ${MemoryNotices.years(n)} in your photos",
                "${s.name} first showed up in your photos on this day in $y.",
                planPhoto(pick, listOf(s.name)),
                y,
                pics = listOf(portrait(pick, null)),
                personId = s.id,
            )
        }
        return null
    }

    // ---- a round number ----

    private fun milestone(c: Ctx): Notice? {
        val announced = c.announced ?: return null
        for (p in faces.listPeople(false)) {
            val name = p.name?.takeIf { it.isNotBlank() } ?: continue
            val step = Milestones.crossed(p.photoCount, announced[p.id] ?: 0) ?: continue
            val all = faces.personDatedFaces(p.id).filter { it.key !in c.exclude }
            // The latest good picture of them.
            val recent = all.filter { it.takenMs >= c.now - 365 * DAY_MS }.ifEmpty { all }
            val pick = recent.maxByOrNull { suited(it) } ?: continue
            return Notice(
                MemoryKind.MILESTONE,
                "$name is in $step of your photos",
                DayChoice.pick(c.today, "$step photos, and counting.", "A lot of memories with $name."),
                planPhoto(pick, listOf(name)),
                MemoryDays.ymd(pick.takenMs, c.tz).first,
                pics = listOf(portrait(pick, null)),
                subject = MemoryRotation.personSubject(p.id),
                milestone = p.id to step,
                personId = p.id,
            )
        }
        return null
    }

    // ---- one person, then and now ----

    private fun thenNow(c: Ctx, stats: List<FaceStore.PersonStat>): Notice? {
        val eligible = stats.filter {
            it.photos >= MIN_FOR_THEN_NOW && it.lastMs - it.firstMs >= 200 * DAY_MS &&
                MemoryRotation.personSubject(it.id) !in c.subjects
        }.sortedBy { it.id }
        for (s in DayChoice.rotated(eligible, c.today).take(TRIES)) {
            val r = ThenNow.choose(faces.personDatedFaces(s.id).map { cand(it) }, c.tz, seed = c.today * 31L + s.id) ?: continue
            val a = r.then[r.startThen]
            val b = r.now[r.startNow]
            // The pictures can be mixed (on their own one time, with someone the other); another person
            // is only spoken of - and framed - when they have a name.
            val names = faces.namesOf(listOfNotNull(a.partner, b.partner))
            val withA = a.partner?.takeIf { names[it] != null }
            val withB = b.partner?.takeIf { names[it] != null }
            val same = withA != null && withA == withB
            val title = if (same) "${s.name} and ${names[withA]} · then and now" else "${s.name} · then and now"
            val body = if (same) "The two of you, ${span(r.spanMonths)} apart." else "${span(r.spanMonths)} between these two."
            return Notice(
                MemoryKind.THEN_NOW, title, body, planPhoto(b, listOf(s.name)),
                MemoryDays.ymd(a.takenMs, c.tz).first,
                pics = listOf(portrait(a, withA, year(a, c.tz)), portrait(b, withB, year(b, c.tz))),
                connector = span(r.spanMonths),
                subject = MemoryRotation.personSubject(s.id),
                personId = s.id,
            )
        }
        return null
    }

    // ---- a lovely picture, out of the blue ----

    private fun vault(c: Ctx, stats: List<FaceStore.PersonStat>): Notice? {
        val eligible = stats.filter { it.photos >= MIN_FOR_VAULT && MemoryRotation.personSubject(it.id) !in c.subjects }.sortedBy { it.id }
        for (s in DayChoice.rotated(eligible, c.today).take(TRIES)) {
            val old = faces.personDatedFaces(s.id).filter { it.takenMs < c.now - 300 * DAY_MS && it.key !in c.exclude }
            if (old.size < 5) continue
            // On their own if there are enough such, else the best there is; one of the best few, by the day.
            val solo = old.filter { it.faces == 1 }
            val pool = if (solo.size >= 3) solo else old
            val top = pool.sortedByDescending { suited(it) }.take(5)
            val pick = top[Math.floorMod(c.today, top.size)]
            val (y, m, _) = MemoryDays.ymd(pick.takenMs, c.tz)
            return Notice(
                MemoryKind.VAULT,
                DayChoice.pick(c.today, "Remember this one?", "A smile from $y", "Look who it is"),
                "${s.name} · ${MemoryDays.MONTHS[m - 1].take(3)} $y",
                planPhoto(pick, listOf(s.name)),
                y,
                pics = listOf(portrait(pick, null)),
                subject = MemoryRotation.personSubject(s.id),
                personId = s.id,
            )
        }
        return null
    }

    // ---- a few busy days in a row ----

    private fun trip(c: Ctx): Notice? {
        val (year, month, day) = MemoryDays.ymd(c.now, c.tz)
        val firstYear = dates.bounds()?.let { MemoryDays.ymd(it.first, c.tz).first } ?: return null
        var best: Triple<Trips.Run, Int, List<LibraryDates.DayPhoto>>? = null
        for (y in year - 1 downTo maxOf(firstYear, year - MemoryPlanner.MAX_YEARS)) {
            val wide = MemoryDays.range(y, month, day, TRIP_SPREAD, c.tz) ?: continue
            if (dates.count(wide.first, wide.second) < MIN_TRIP_PHOTOS) continue
            val photos = dates.photos(wide.first, wide.second, TRIP_CANDIDATES)
            val perDay = photos.groupingBy { MemoryDays.dayNumber(it.takenMs, c.tz) }.eachCount()
            val centre = MemoryDays.dayNumber(MemoryDays.range(y, month, day, 0, c.tz)!!.first + 12 * 3_600_000L, c.tz)
            val run = Trips.near(Trips.find(perDay), centre, 3) ?: continue
            if (best == null || run.total > best.first.total) best = Triple(run, y, photos)
        }
        val (run, y, photos) = best ?: return null

        // The best photo of the first, a middle and the last day.
        val days = listOf(run.startDay, (run.startDay + run.endDay) / 2, run.endDay).distinct()
        val byDay = photos.filter { MemoryDays.dayNumber(it.takenMs, c.tz) in run.startDay..run.endDay && it.key !in c.exclude }
            .groupBy { MemoryDays.dayNumber(it.takenMs, c.tz) }
        val scores = faces.faceScores(byDay.values.flatten().map { it.key })
        val chosen = days.mapNotNull { d ->
            val list = byDay[d] ?: return@mapNotNull null
            list.maxByOrNull { scores[it.key] ?: 0f } ?: list[list.size / 2]
        }
        if (chosen.isEmpty()) return null
        val names = faces.namesIn(chosen.map { it.key }).values.flatten().distinctBy { it.first }.map { it.second }.take(3)
        val last = MemoryDays.ymd(run.endDay * 86_400_000L + 43_200_000L, TimeZone.getTimeZone("UTC"))
        val begin = MemoryDays.ymd(run.startDay * 86_400_000L + 43_200_000L, TimeZone.getTimeZone("UTC"))
        val dateText = if (begin.second == last.second) {
            "${MemoryDays.MONTHS[begin.second - 1]} ${begin.third}-${last.third}, $y"
        } else {
            "${MemoryDays.label(begin.second, begin.third)} - ${MemoryDays.label(last.second, last.third)}, $y"
        }
        return Notice(
            MemoryKind.TRIP,
            "A few days to remember · ${MemoryNotices.ago(year - y)}",
            listOfNotNull(names.takeIf { it.isNotEmpty() }?.let { MemoryNotices.join(it) }, dateText, "${run.total} photos and videos")
                .joinToString(" · "),
            chosen.first().let { PlanPhoto(it.key, it.uri, it.video, 0L, it.takenMs, 0f, names) },
            y,
            pics = chosen.map {
                val (_, m, d) = MemoryDays.ymd(it.takenMs, c.tz)
                Pic(it.uri, it.video, label = MemoryDays.label(m, d))
            },
        )
    }

    // ---- two people ----

    private fun pairs(c: Ctx, out: MutableMap<MemoryKind, Notice>) {
        val together = planner.timeline(c.now).together
        val seen = HashSet<Pair<Long, Long>>()
        val candidates = together.filter { it.count >= MIN_PAIR_PHOTOS }
            .map { minOf(it.personId, it.withId) to maxOf(it.personId, it.withId) }
            .filter { seen.add(it) && MemoryRotation.pairSubject(it.first, it.second) !in c.subjects }
            .sortedWith(compareBy({ it.first }, { it.second }))
        if (candidates.isEmpty()) return
        val names = faces.namesOf(candidates.flatMap { listOf(it.first, it.second) })
        val named = candidates.filter { names[it.first] != null && names[it.second] != null }
        for ((a, b) in DayChoice.rotated(named, c.today).take(TRIES)) {
            if (MemoryKind.PAIR_THEN_NOW in out && MemoryKind.TOGETHER_SINCE in out) return
            val pp = faces.pairPhotos(a, b)
            if (pp.size < MIN_PAIR_PHOTOS) continue
            val nameA = names[a]!!
            val nameB = names[b]!!
            val subject = MemoryRotation.pairSubject(a, b)
            if (MemoryKind.PAIR_THEN_NOW !in out) pairThenNow(c, pp, a, b, nameA, nameB, subject)?.let { out[MemoryKind.PAIR_THEN_NOW] = it }
            if (MemoryKind.TOGETHER_SINCE !in out) togetherSince(c, pp, a, nameA, nameB, subject)?.let { out[MemoryKind.TOGETHER_SINCE] = it }
        }
    }

    private fun pairThenNow(c: Ctx, pp: List<FaceStore.PairPhoto>, a: Long, b: Long, nameA: String, nameB: String, subject: String): Notice? {
        val cands = pp.map {
            ThenNow.Cand(
                it.key, it.key, it.uri, it.takenMs, it.rankA + it.rankB,
                it.boxA[0], it.boxA[1], it.boxA[2], it.boxA[3], it.photoW, it.photoH, it.faces,
                listOf(ThenNow.Other(b, it.boxB[0], it.boxB[1], it.boxB[2], it.boxB[3])),
                pair = b,
            )
        }
        // Both of them are in every one of these pictures: the two of them alone, or in a small group.
        val r = ThenNow.choose(cands, c.tz, seed = c.today * 31L + a) ?: return null
        val x = r.then[r.startThen]
        val y = r.now[r.startNow]
        return Notice(
            MemoryKind.PAIR_THEN_NOW,
            "$nameA and $nameB · then and now",
            "The two of you, ${span(r.spanMonths)} apart.",
            planPhoto(y, listOf(nameA, nameB)),
            MemoryDays.ymd(x.takenMs, c.tz).first,
            pics = listOf(portrait(x, b, year(x, c.tz)), portrait(y, b, year(y, c.tz))),
            connector = span(r.spanMonths),
            subject = subject,
            personId = a,
        )
    }

    private fun togetherSince(c: Ctx, pp: List<FaceStore.PairPhoto>, a: Long, nameA: String, nameB: String, subject: String): Notice? {
        val times = pp.map { it.takenMs }
        val start = times.firstOrNull { FirstAppearance.real(times, it) } ?: return null
        val span = (pp.last().takenMs - start) / (365.0 * DAY_MS)
        if (span < 1.0) return null
        val count = pp.count { it.takenMs >= start }
        val pick = pp.filter { it.takenMs >= start && it.faces <= 4 && it.key !in c.exclude }
            .maxByOrNull { (it.rankA + it.rankB) / (1f + 0.3f * (it.faces - 2)) } ?: return null
        val since = MemoryDays.ymd(start, c.tz).first
        val years = Math.round(span).toInt().coerceAtLeast(1)
        val box = floatArrayOf(
            minOf(pick.boxA[0], pick.boxB[0]), minOf(pick.boxA[1], pick.boxB[1]),
            maxOf(pick.boxA[2], pick.boxB[2]), maxOf(pick.boxA[3], pick.boxB[3]),
        )
        return Notice(
            MemoryKind.TOGETHER_SINCE,
            "$nameA and $nameB · together since $since",
            "$count photos of the two of you over ${MemoryNotices.years(years)}.",
            PlanPhoto(pick.key, pick.uri, false, 0L, pick.takenMs, 0f, listOf(nameA, nameB)),
            since,
            // The two of them now, and - small, in the corner - the first photo of the two of them.
            pics = listOfNotNull(
                Pic(pick.uri, false, box, pick.photoW, pick.photoH, DUO_MARGIN, 0f),
                pp.firstOrNull { it.takenMs >= start && it.key != pick.key }?.let {
                    Pic(
                        it.uri, false,
                        floatArrayOf(minOf(it.boxA[0], it.boxB[0]), minOf(it.boxA[1], it.boxB[1]), maxOf(it.boxA[2], it.boxB[2]), maxOf(it.boxA[3], it.boxB[3])),
                        it.photoW, it.photoH, DUO_MARGIN, 0f,
                    )
                },
            ),
            connector = "since $since",
            subject = subject,
            personId = a,
        )
    }

    // ---- bits ----

    // How good a picture of the person it is, crowds counting for less.
    private fun suited(f: FaceStore.ThenNowFace): Float = f.rank / (1f + 0.35f * (f.faces - 1).coerceAtLeast(0))

    private fun planPhoto(f: FaceStore.ThenNowFace, names: List<String>) = PlanPhoto(f.key, f.uri, false, 0L, f.takenMs, 0f, names)

    private fun planPhoto(c: ThenNow.Cand, names: List<String>) = PlanPhoto(c.key, c.uri, false, 0L, c.takenMs, 0f, names)

    private fun year(c: ThenNow.Cand, tz: TimeZone) = MemoryDays.ymd(c.takenMs, tz).first.toString()

    /** [f] framed head-and-shoulders. */
    private fun portrait(f: FaceStore.ThenNowFace, label: String? = null): Pic =
        Pic(f.uri, false, floatArrayOf(f.boxL, f.boxT, f.boxR, f.boxB), f.photoW, f.photoH, FaceCrops.PORTRAIT_MARGIN, FaceCrops.PORTRAIT_LIFT, label)

    /** [c] framed: the person alone, or - with [withId] in the photo too - the two of them. */
    private fun portrait(c: ThenNow.Cand, withId: Long?, label: String? = null): Pic {
        val box = c.box(withId)
        val pair = withId != null && c.others.any { it.personId == withId }
        return Pic(
            c.uri, false, box, c.photoW, c.photoH,
            if (pair) DUO_MARGIN else FaceCrops.PORTRAIT_MARGIN, if (pair) 0f else FaceCrops.PORTRAIT_LIFT, label,
        )
    }

    companion object {
        const val DAY_MS = 86_400_000L
        const val TRIES = 6
        const val MIN_FOR_PERSON = 20
        const val MIN_FOR_THEN_NOW = 8
        const val MIN_FOR_VAULT = 15
        const val MIN_PAIR_PHOTOS = 10
        const val MIN_TRIP_PHOTOS = 24
        const val TRIP_SPREAD = 8
        const val TRIP_CANDIDATES = 4000
        const val DUO_MARGIN = 1.9f

        /** As the chooser wants it. */
        fun cand(f: FaceStore.ThenNowFace): ThenNow.Cand = ThenNow.Cand(
            f.faceId, f.key, f.uri, f.takenMs, f.rank, f.boxL, f.boxT, f.boxR, f.boxB, f.photoW, f.photoH, f.faces,
            f.others.map { ThenNow.Other(it.personId, it.boxL, it.boxT, it.boxR, it.boxB) },
        )

        /** "8 years", "1 year 4 months", "11 months". */
        fun span(months: Int): String {
            val years = months / 12
            val rest = months % 12
            if (years == 0) return if (rest == 1) "1 month" else "$rest months"
            val y = MemoryNotices.years(years)
            return if (rest == 0 || years >= 5) y else "$y ${if (rest == 1) "1 month" else "$rest months"}"
        }
    }
}
