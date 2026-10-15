package dev.raseel.lostandfound.embedder.memories

import dev.raseel.lostandfound.embedder.faces.TimelinePicks
import java.util.Calendar
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MemoriesTest {
    private val utc = TimeZone.getTimeZone("UTC")
    private val minute = 60_000L
    private val hour = 60 * minute

    private fun ms(y: Int, m: Int, d: Int, h: Int = 12, tz: TimeZone = utc): Long {
        val cal = Calendar.getInstance(tz)
        cal.clear()
        cal.set(y, m - 1, d, h, 0, 0)
        return cal.timeInMillis
    }

    // ---- days ----

    @Test
    fun aDayIsMidnightToMidnightInThePhonesZone() {
        val (start, end) = MemoryDays.range(2022, 5, 3, tz = utc)!!
        assertEquals(ms(2022, 5, 3, 0), start)
        assertEquals(ms(2022, 5, 4, 0), end)
        // A photo at 23:50 is still on its day, one at 00:10 the next is not.
        assertTrue(ms(2022, 5, 3, 23) + 50 * minute in start until end)
        assertFalse(ms(2022, 5, 4, 0) + 10 * minute in start until end)
    }

    @Test
    fun aDayInAnotherZoneIsAnotherStretchOfTime() {
        val tokyo = TimeZone.getTimeZone("Asia/Tokyo")
        val (start, _) = MemoryDays.range(2022, 5, 3, tz = tokyo)!!
        assertEquals(ms(2022, 5, 3, 0, tokyo), start)
        assertEquals(9 * hour, ms(2022, 5, 3, 0, utc) - start)
    }

    @Test
    fun theWeekAroundADayIsSevenDays() {
        val (start, end) = MemoryDays.range(2022, 5, 3, spread = 3, tz = utc)!!
        assertEquals(ms(2022, 4, 30, 0), start)
        assertEquals(ms(2022, 5, 7, 0), end)
    }

    @Test
    fun the29thOfFebruaryOnlyExistsInLeapYears() {
        assertNotNull(MemoryDays.range(2024, 2, 29, tz = utc))
        assertNull(MemoryDays.range(2023, 2, 29, tz = utc))
    }

    @Test
    fun dayNumbersCountUpByOne() {
        val a = MemoryDays.dayNumber(ms(2024, 2, 28), utc)
        assertEquals(a + 1, MemoryDays.dayNumber(ms(2024, 2, 29), utc))
        assertEquals(a + 2, MemoryDays.dayNumber(ms(2024, 3, 1), utc))
        assertEquals(Triple(2024, 3, 1), MemoryDays.ymd(ms(2024, 3, 1), utc))
    }

    // ---- which photos ----

    private fun c(key: Long, takenMs: Long, score: Float) = TimelinePicks.Candidate(key, "u$key", false, 0, takenMs, score)

    @Test
    fun photosWithTheClearestFacesComeFirstAndBurstsCountOnce() {
        val list = listOf(
            c(1, 1 * hour, 50f), c(2, 1 * hour + 30_000, 90f), // a burst: only the better
            c(3, 3 * hour, 70f), c(4, 5 * hour, 10f),
        )
        val picks = MemoryPicks.pick(list, 3)
        assertEquals(listOf(2L, 3L, 4L), picks.map { it.key })
    }

    @Test
    fun photosWithNoPeopleFillTheRestSpreadThroughTheDay() {
        val none = (0 until 100).map { c(it.toLong(), it * 10 * minute, 0f) }
        val picks = MemoryPicks.pick(none, 4)
        assertEquals(4, picks.size)
        // Not the first four taken: the middles of four equal parts of the list.
        assertEquals(listOf(12L, 37L, 62L, 87L), picks.map { it.key })
    }

    @Test
    fun nothingToPickGivesNothing() {
        assertEquals(emptyList<Long>(), MemoryPicks.pick(emptyList(), 6).map { it.key })
        assertEquals(emptyList<Long>(), MemoryPicks.pick(listOf(c(1, 0, 5f)), 0).map { it.key })
    }

    @Test
    fun aFewPicksAreNotPaddedWithTheSameBurst() {
        val burst = (0 until 5).map { c(it.toLong(), it * 10_000L, 0f) }
        assertEquals(1, MemoryPicks.pick(burst, 4).size)
    }

    @Test
    fun aYearWithPeopleOrAnEventfulDayQualifiesALoneLandscapeDoesNot() {
        assertTrue(MemoryPicks.qualifies(1, 40f))
        assertTrue(MemoryPicks.qualifies(6, 0f))
        assertFalse(MemoryPicks.qualifies(1, 0f))
        assertTrue(MemoryPicks.strength(10, 120f) > MemoryPicks.strength(10, 0f))
        assertTrue(MemoryPicks.strength(30, 0f) > MemoryPicks.strength(2, 0f))
    }

    // ---- rotation ----

    private fun used(kind: MemoryKind, day: Int, slot: Slot = Slot.MORNING) = MemoryRotation.Used(kind, day, slot)

    @Test
    fun aSpecialKindBelongsToItsTimeOfDay() {
        val all = MemoryKind.entries.toSet()
        assertEquals(MemoryKind.ANNIVERSARY, MemoryRotation.choose(all, emptyList(), 100, Slot.MORNING))
        assertEquals(MemoryKind.PERSON_ANNIVERSARY, MemoryRotation.choose(all - MemoryKind.ANNIVERSARY, emptyList(), 100, Slot.MORNING))
        // A round number of photos waits for the evening; the morning goes on with an ordinary one.
        val there = setOf(MemoryKind.MILESTONE, MemoryKind.THEN_NOW)
        assertEquals(MemoryKind.THEN_NOW, MemoryRotation.choose(there, emptyList(), 100, Slot.MORNING))
        assertEquals(MemoryKind.MILESTONE, MemoryRotation.choose(there, emptyList(), 100, Slot.EVENING))
        // ... and an anniversary the morning missed is still told in the evening.
        assertEquals(MemoryKind.ANNIVERSARY, MemoryRotation.choose(setOf(MemoryKind.ANNIVERSARY), emptyList(), 100, Slot.EVENING))
    }

    @Test
    fun theMorningLooksBackAndTheEveningIsAboutPeople() {
        val ordinary = setOf(MemoryKind.THEN_NOW, MemoryKind.ON_THIS_DAY, MemoryKind.VAULT)
        assertEquals(MemoryKind.ON_THIS_DAY, MemoryRotation.choose(ordinary, emptyList(), 50, Slot.MORNING))
        assertEquals(MemoryKind.THEN_NOW, MemoryRotation.choose(ordinary, emptyList(), 50, Slot.EVENING))
    }

    @Test
    fun theKindThatHasGoneLongestWithoutComesNextAndNeverYesterdaysTwice() {
        val ordinary = setOf(MemoryKind.THEN_NOW, MemoryKind.ON_THIS_DAY, MemoryKind.VAULT)
        // then-and-now yesterday, on-this-day a week ago, vault never: the vault has waited longest.
        val h = listOf(used(MemoryKind.ON_THIS_DAY, 43), used(MemoryKind.THEN_NOW, 49))
        assertEquals(MemoryKind.VAULT, MemoryRotation.choose(ordinary, h, 50))
        // With only yesterday's kind there, it is used again rather than nothing.
        assertEquals(MemoryKind.THEN_NOW, MemoryRotation.choose(setOf(MemoryKind.THEN_NOW), h, 50))
    }

    @Test
    fun twoADayAreNeverTheSameKindAndEveryKindGetsATurn() {
        val ordinary = setOf(MemoryKind.THEN_NOW, MemoryKind.ON_THIS_DAY, MemoryKind.TRIP, MemoryKind.VAULT, MemoryKind.TOGETHER_SINCE)
        val history = ArrayList<MemoryRotation.Used>()
        val sent = ArrayList<MemoryKind>()
        for (day in 1..10) {
            for (slot in Slot.entries) {
                val k = MemoryRotation.choose(ordinary, history, day, slot)!!
                if (slot == Slot.EVENING) assertTrue(k != sent.last()) // not the same as this morning's
                sent += k
                history += used(k, day, slot)
            }
        }
        assertEquals(ordinary, sent.take(8).toSet())
        assertTrue(sent.zipWithNext().none { it.first == it.second })
    }

    @Test
    fun thisWeekIsOnlyTheFallbackAndAQuietDayGetsNothing() {
        assertEquals(MemoryKind.THIS_WEEK, MemoryRotation.choose(setOf(MemoryKind.THIS_WEEK), emptyList(), 5))
        assertEquals(MemoryKind.SAME_DAY, MemoryRotation.choose(setOf(MemoryKind.THIS_WEEK, MemoryKind.SAME_DAY), emptyList(), 5))
        assertNull(MemoryRotation.choose(emptySet(), emptyList(), 5))
        // Already told today (this morning): not told again this evening.
        val h = listOf(used(MemoryKind.ON_THIS_DAY, 5, Slot.MORNING))
        assertNull(MemoryRotation.choose(setOf(MemoryKind.ON_THIS_DAY), h, 5, Slot.EVENING))
    }

    @Test
    fun sendOneNowShowsADifferentKindEachPress() {
        val there = setOf(MemoryKind.THEN_NOW, MemoryKind.ON_THIS_DAY, MemoryKind.VAULT, MemoryKind.ANNIVERSARY)
        val shown = ArrayList<MemoryKind>()
        var last: MemoryKind? = null
        repeat(8) {
            last = MemoryRotation.chooseForTest(there, last)
            shown += last!!
        }
        assertEquals(there, shown.take(4).toSet())
        assertEquals(shown.take(4), shown.drop(4))
        assertNull(MemoryRotation.chooseForTest(emptySet(), null))
    }

    @Test
    fun historyAndSubjectsSurviveBeingSaved() {
        val h = listOf(used(MemoryKind.TRIP, 10), used(MemoryKind.VAULT, 11, Slot.EVENING))
        val back = MemoryRotation.decodeHistory(MemoryRotation.encodeHistory(h))
        assertEquals(listOf("trip" to 10, "vault" to 11), back.map { it.kind.code to it.day })
        assertEquals(listOf(Slot.MORNING, Slot.EVENING), back.map { it.slot })
        // The old form, without a time of day, still reads.
        assertEquals(Slot.MORNING, MemoryRotation.decodeHistory("trip:10").single().slot)
        assertEquals(emptyList<MemoryRotation.Used>(), MemoryRotation.decodeHistory("nonsense,x:1,trip:y"))
        val subjects = mapOf(MemoryRotation.personSubject(12) to 100, MemoryRotation.pairSubject(7, 3) to 90)
        assertEquals(subjects, MemoryRotation.decodeSubjects(MemoryRotation.encodeSubjects(subjects)))
        assertEquals("pair:3-7", MemoryRotation.pairSubject(7, 3))
        // Forgotten after 45 days.
        assertEquals(setOf("p12"), MemoryRotation.pruneSubjects(subjects, 140).keys)
    }

    // ---- the small algorithms behind the kinds ----

    @Test
    fun aTripIsSeveralBusyDaysInARowNotOneParty() {
        val busy = mapOf(100 to 3, 101 to 12, 102 to 20, 103 to 9, 104 to 2, 200 to 60, 300 to 8, 301 to 7, 302 to 6)
        val runs = Trips.find(busy)
        // days 101-103 (41 photos); 200 is a single day; 300-302 has only 21.
        assertEquals(1, runs.size)
        assertEquals(101, runs[0].startDay)
        assertEquals(103, runs[0].endDay)
        assertEquals(41, runs[0].total)
        assertEquals(3, runs[0].days)
        assertEquals(runs[0], Trips.near(runs, centreDay = 105, spread = 3))
        assertNull(Trips.near(runs, centreDay = 120, spread = 3))
    }

    @Test
    fun roundNumbersAreToldOnceAsTheyArePassed() {
        assertEquals(0, Milestones.reached(49))
        assertEquals(100, Milestones.reached(180))
        assertEquals(100, Milestones.crossed(180, 50))
        assertNull(Milestones.crossed(180, 100)) // already told
        assertEquals(1000, Milestones.crossed(1200, 250)) // passed two: the bigger one
        assertNull(Milestones.crossed(30, 0))
    }

    @Test
    fun aFirstDayIsRealOnlyWithPhotosRightAfterIt() {
        val day = 86_400_000L
        val start = ms(2020, 5, 3)
        assertTrue(FirstAppearance.real(listOf(start, start + 3 * day, start + 40 * day, start + 400 * day), start))
        // A lone photo with a wrong date: nothing follows it.
        assertFalse(FirstAppearance.real(listOf(start, start + 400 * day, start + 410 * day), start))
    }

    @Test
    fun theDaysChoiceIsTheSameAllDayAndDiffersFromDayToDay() {
        val list = listOf("a", "b", "c", "d", "e")
        assertEquals(DayChoice.rotated(list, 40), DayChoice.rotated(list, 40))
        assertEquals(list.toSet(), DayChoice.rotated(list, 41).toSet())
        assertTrue((1..30).map { DayChoice.rotated(list, it).first() }.toSet().size >= 3)
        assertEquals("x", DayChoice.pick(0, "x"))
        assertEquals(listOf("z"), DayChoice.rotated(listOf("z"), 5))
    }

    @Test
    fun whatWasShownIsRememberedForAWhileThenForgotten() {
        val seen = mapOf(1L to 1000, 2L to 900, 3L to 800)
        val kept = MemoryRotation.prune(seen, today = 1000, keepDays = 120)
        assertEquals(setOf(1L, 2L), kept.keys)
        assertEquals(listOf(5L), MemoryRotation.fresh(listOf(1L, 5L, 2L), kept))
        assertEquals(kept, MemoryRotation.decode(MemoryRotation.encode(kept)))
        assertEquals(emptyMap<Long, Int>(), MemoryRotation.decode("junk,=,a=b"))
    }

    // ---- then and now ----

    private fun cc(key: Long, y: Int, m: Int, rank: Float, faces: Int = 1, vararg with: Long) =
        ThenNow.Cand(
            key, key, "u$key", ms(y, m, 10), rank, 0.4f, 0.3f, 0.6f, 0.6f, 3000, 4000, faces,
            with.map { ThenNow.Other(it, 0.1f, 0.3f, 0.3f, 0.6f) },
        )

    // The same with a day of the month, for photos that have to be a fortnight apart.
    private fun cd(key: Long, y: Int, m: Int, d: Int, rank: Float, faces: Int = 1, vararg with: Long) =
        ThenNow.Cand(
            key, key, "u$key", ms(y, m, d), rank, 0.4f, 0.3f, 0.6f, 0.6f, 3000, 4000, faces,
            with.map { ThenNow.Other(it, 0.1f, 0.3f, 0.3f, 0.6f) },
        )

    // A person with, at each end, one photo on their own, one with one other person, one in a group.
    private fun mixedEnds() = listOf(
        cd(1, 2016, 3, 5, 40f), cd(2, 2016, 3, 25, 90f, 2, 7), cd(3, 2016, 4, 12, 70f, 4, 7, 8, 9),
        cd(4, 2016, 3, 14, 200f, 9, 1, 2, 3, 4, 5, 6, 7, 8), // a crowd: counts for little
        cd(5, 2024, 4, 5, 30f), cd(6, 2024, 4, 25, 80f, 2, 9), cd(7, 2024, 5, 12, 60f, 3, 9, 10),
    )

    private fun years(vararg ym: Triple<Int, Int, Float>) =
        ym.mapIndexed { i, (y, m, r) -> cc(i + 1L, y, m, r) }

    private fun ThenNow.Result.thens() = then
    private fun ThenNow.Result.nows() = now

    @Test
    fun aboutTheStartAndAboutNowNotTheLiteralEnds() {
        val list = listOf(
            cc(1, 2016, 3, 40f), // the very first photo: not forced
            cc(2, 2016, 3, 90f), cc(3, 2016, 4, 70f),
            cc(4, 2016, 11, 200f), // best of all, but months later: outside the first couple of months
            cc(9, 2020, 6, 100f),
            cc(5, 2024, 5, 30f), // the very last
            cc(6, 2024, 4, 80f), cc(7, 2024, 4, 60f),
            cc(8, 2023, 12, 150f), // months before: outside
        )
        // Three at each end is not there in two months, so the window widens - but only as far as it must.
        val r = ThenNow.choose(list, utc)!!
        assertTrue(r.thens().all { it.takenMs < ms(2017, 1, 1) })
        assertTrue(r.nows().all { it.takenMs > ms(2023, 11, 1) })
        assertTrue(r.spanMonths >= 95)
    }

    @Test
    fun threeOptionsAtEachEndWheneverThereAreThreePhotosToTellApart() {
        val list = listOf(
            cd(1, 2016, 3, 2, 50f), cd(2, 2016, 3, 20, 80f), cd(3, 2016, 4, 8, 60f), cd(4, 2016, 4, 27, 40f),
            cd(5, 2024, 4, 2, 50f), cd(6, 2024, 4, 20, 80f), cd(7, 2024, 5, 8, 60f), cd(8, 2024, 5, 27, 40f),
        )
        val r = ThenNow.choose(list, utc)!!
        assertEquals(3, r.then.size)
        assertEquals(3, r.now.size)
        // Best first; each end has three different photos, and what is shown first is from the options.
        assertEquals(listOf(2L, 3L, 1L), r.then.map { it.key })
        assertEquals(3, r.now.map { it.key }.toSet().size)
        assertTrue(r.then[r.startThen].takenMs < r.now[r.startNow].takenMs)
    }

    @Test
    fun fewerOptionsWhenThereAreNotEnoughPhotosForThree() {
        val list = listOf(
            cd(1, 2016, 3, 2, 50f), cd(2, 2016, 3, 20, 80f),
            cd(5, 2024, 4, 2, 50f), cd(6, 2024, 4, 20, 80f), cd(7, 2024, 5, 8, 60f),
        )
        val r = ThenNow.choose(list, utc)!!
        assertEquals(2, r.then.size)
        assertEquals(3, r.now.size)
    }

    @Test
    fun threeOptionsEvenWhenThePhotosAreCloseInTime() {
        // Three photos a few days apart: still told apart rather than dropped for being near each other.
        val list = listOf(
            cd(1, 2016, 3, 2, 50f), cd(2, 2016, 3, 6, 80f), cd(3, 2016, 3, 9, 60f),
            cd(5, 2024, 4, 2, 50f), cd(6, 2024, 4, 6, 80f), cd(7, 2024, 4, 9, 60f),
        )
        val r = ThenNow.choose(list, utc)!!
        assertEquals(3, r.then.size)
        assertEquals(3, r.now.size)
    }

    @Test
    fun theComparisonAppearsWithLessThanItDidBefore() {
        // Four photos over eight months: it was too little before (six photos, a year); it is enough now.
        val list = listOf(
            cd(1, 2024, 1, 5, 60f), cd(2, 2024, 1, 25, 50f), cd(3, 2024, 9, 5, 70f), cd(4, 2024, 9, 25, 55f),
        )
        val r = ThenNow.choose(list, utc)
        assertNotNull(r)
        assertTrue(r!!.then.isNotEmpty() && r.now.isNotEmpty())
        // But still not on one stretch of a few weeks.
        assertNull(ThenNow.choose(list.map { cd(it.key, 2024, 1 + (it.key % 2).toInt(), 5 + it.key.toInt(), it.rank) }, utc))
    }

    @Test
    fun theWindowWidensOnlyWhenTheFirstMonthsHaveTooLittle() {
        val list = listOf(
            cd(1, 2016, 3, 5, 40f), // the only photo of the first two months
            cd(2, 2016, 6, 5, 90f), cd(3, 2016, 9, 5, 70f), cd(4, 2018, 1, 5, 50f),
            cd(5, 2024, 4, 5, 80f), cd(6, 2024, 5, 5, 60f), cd(7, 2024, 2, 5, 55f),
        )
        val r = ThenNow.choose(list, utc)!!
        assertTrue(r.thens().size >= 2)
        assertTrue(r.thens().all { it.takenMs < ms(2017, 4, 1) })
        assertTrue(r.thens().any { it.key == 2L })
    }

    @Test
    fun theComparisonsAreMixedOnTheirOwnWithOnePersonInAGroup() {
        val r = ThenNow.choose(mixedEnds(), utc, perSide = 3)!!
        assertEquals(3, r.then.size)
        for (side in listOf(r.thens(), r.nows())) {
            assertEquals(setOf(ThenNow.Kind.SOLO, ThenNow.Kind.DUO, ThenNow.Kind.GROUP), side.map { it.kind }.toSet())
        }
        assertFalse(r.thens().any { it.kind == ThenNow.Kind.CROWD })
    }

    @Test
    fun whichOnesAreShownFirstIsRandomButSteadyForASeed() {
        val list = mixedEnds()
        fun start(seed: Long) = ThenNow.choose(list, utc, seed = seed)!!.let { it.startThen to it.startNow }
        assertEquals(start(12), start(12))
        assertTrue((0L..40L).map { start(it) }.toSet().size >= 4)
        // Whatever the seed, the options are the same and in the same order.
        assertEquals(ThenNow.choose(list, utc, seed = 1)!!.then.map { it.key }, ThenNow.choose(list, utc, seed = 2)!!.then.map { it.key })
    }

    @Test
    fun aPictureOfTwoPeopleIsAlwaysFramedWithTheOther() {
        val c = ThenNow.Cand(1, 1, "u1", ms(2016, 3, 10), 90f, 0.4f, 0.3f, 0.6f, 0.6f, 3000, 4000, 3, listOf(ThenNow.Other(7, 0.1f, 0.3f, 0.3f, 0.6f)), pair = 7)
        assertEquals(ThenNow.Kind.DUO, c.kind)
        assertEquals(7L, c.partner)
        assertEquals(0.1f, c.box(7)[0], 0.001f)
        val alone = cc(2, 2016, 3, 50f)
        assertEquals(ThenNow.Kind.SOLO, alone.kind)
        assertNull(alone.partner)
        assertEquals(ThenNow.Kind.DUO, cc(3, 2016, 3, 50f, 2, 7).kind)
        assertEquals(ThenNow.Kind.GROUP, cc(4, 2016, 3, 50f, 4, 7, 8, 9).kind)
        assertEquals(ThenNow.Kind.CROWD, cc(5, 2016, 3, 50f, 9).kind)
    }

    @Test
    fun aLonePhotoWithAWrongDateIsNotTheFirstTime() {
        val list = years(
            Triple(2001, 1, 300f), // a camera with the wrong clock
            Triple(2016, 3, 40f), Triple(2016, 4, 50f), Triple(2016, 8, 60f),
            Triple(2023, 5, 60f), Triple(2024, 2, 150f),
        )
        val r = ThenNow.choose(list, utc)!!
        assertTrue(r.thens().all { it.takenMs >= ms(2016, 1, 1) })
    }

    @Test
    fun tooFewPhotosOrTooLittleTimeGivesNothing() {
        assertNull(ThenNow.choose(years(Triple(2020, 1, 1f), Triple(2024, 1, 1f)), utc))
        val shortTime = (0 until 8).map { cc(it + 1L, 2024, 1 + it % 5, 50f + it) }
        assertNull(ThenNow.choose(shortTime, utc)) // five months: too short to be a before and an after
    }

    @Test
    fun aShortStretchIsSplitSoTheTwoEndsNeverMeet() {
        // 18 months: each end is at most 9 months and they never overlap.
        val list = (0 until 10).map { cc(it + 1L, 2023 + (it * 2) / 12, 1 + (it * 2) % 12, 10f + it) }
        val r = ThenNow.choose(list, utc)!!
        assertTrue(r.now[r.startNow].takenMs - r.then[r.startThen].takenMs > 4 * 30 * 24 * hour)
    }

    // ---- the words never name someone who is not in the photo shown ----

    @Test
    fun theWordsNameOnlyThosePhotoShown() {
        val shown = PlanPhoto(1, "a", false, 0L, ms(2020, 5, 3), 9f, listOf("Anna"))
        val other = PlanPhoto(2, "b", false, 0L, ms(2020, 5, 3, 15), 1f, listOf("Anna", "Dev"))
        val year = DayYear(2020, 6, 2, listOf(shown, other), 5f, true)
        val plan = Plan(5, 3, 2026, listOf(year), emptyList(), emptyList())
        val notice = MemoryNotices.build(plan)[MemoryKind.ON_THIS_DAY]!!
        assertTrue(notice.body, notice.body.startsWith("Anna ·"))
        assertFalse(notice.body, notice.body.contains("Dev"))
    }
}
