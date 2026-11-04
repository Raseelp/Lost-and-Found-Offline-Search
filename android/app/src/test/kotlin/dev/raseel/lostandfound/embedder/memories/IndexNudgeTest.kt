package dev.raseel.lostandfound.embedder.memories

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class IndexNudgeTest {
    @Test
    fun nineTenthsIsFinishedAndLessIsNot() {
        assertTrue(IndexShare(onPhone = 100, indexed = 90).finished)
        assertFalse(IndexShare(onPhone = 100, indexed = 89).finished)
        assertTrue(IndexShare(onPhone = 0, indexed = 0).finished)
        assertTrue(IndexShare(onPhone = 50, indexed = 60).finished)
    }

    @Test
    fun thePercentIsRoundedDownAndTheMissingCountNeverGoesBelowZero() {
        assertEquals(89, IndexShare(onPhone = 1000, indexed = 899).percent)
        assertEquals(0, IndexShare(onPhone = 1000, indexed = 0).percent)
        assertEquals(100, IndexShare(onPhone = 50, indexed = 60).percent)
        assertEquals(0, IndexShare(onPhone = 50, indexed = 60).missing)
        assertEquals(300, IndexShare(onPhone = 400, indexed = 100).missing)
    }

    @Test
    fun theNoteIsSentOnlyWhenThereIsSomethingToSayAndNothingElseIsGoingOn() {
        val partly = IndexShare(onPhone = 400, indexed = 100)
        assertEquals(NudgeVerdict.SEND, IndexNudge.verdict(partly, scanning = false, enabled = true, sent = 0, noteToday = false))
        assertEquals(NudgeVerdict.WAIT, IndexNudge.verdict(partly, scanning = true, enabled = true, sent = 0, noteToday = false))
        assertEquals(NudgeVerdict.WAIT, IndexNudge.verdict(partly, scanning = false, enabled = true, sent = 1, noteToday = true))
        assertEquals(NudgeVerdict.STOP, IndexNudge.verdict(partly, scanning = false, enabled = false, sent = 0, noteToday = false))
        assertEquals(NudgeVerdict.STOP, IndexNudge.verdict(IndexShare(400, 380), scanning = false, enabled = true, sent = 0, noteToday = false))
        assertEquals(NudgeVerdict.STOP, IndexNudge.verdict(partly, scanning = false, enabled = true, sent = 3, noteToday = false))
        assertEquals(NudgeVerdict.STOP, IndexNudge.verdict(IndexShare(400, 380), scanning = true, enabled = true, sent = 0, noteToday = true))
    }

    @Test
    fun theGapsGrowAndStopAfterThree() {
        assertEquals(3, IndexNudge.nextGapDays(0))
        assertEquals(7, IndexNudge.nextGapDays(1))
        assertEquals(14, IndexNudge.nextGapDays(2))
        assertNull(IndexNudge.nextGapDays(3))
    }

    @Test
    fun theKindsTakeTurnsAndSkipTheOnesThatAreNotPossible() {
        val everything = NudgeKind.entries.toSet()
        assertEquals(NudgeKind.RING, IndexNudge.pickKind(everything, 0))
        assertEquals(NudgeKind.PEOPLE, IndexNudge.pickKind(everything, 1))
        assertEquals(NudgeKind.THIS_DAY, IndexNudge.pickKind(everything, 2))
        assertEquals(NudgeKind.SEARCH, IndexNudge.pickKind(everything, 3))
        assertEquals(NudgeKind.RING, IndexNudge.pickKind(everything, 4))
        assertEquals(NudgeKind.SEARCH, IndexNudge.pickKind(setOf(NudgeKind.SEARCH), 1))
        assertEquals(NudgeKind.RING, IndexNudge.pickKind(emptySet(), 1))
    }

    @Test
    fun aLibraryThatIsNeverFinishedGetsThreeNotesAndThenNoMore() {
        val partly = IndexShare(onPhone = 400, indexed = 100)
        var sent = 0
        var due: Int? = IndexNudge.nextGapDays(0)
        val sentOn = mutableListOf<Int>()
        while (due != null) {
            val day: Int = due
            val step = IndexNudge.step(partly, scanning = false, enabled = true, sent = sent, noteToday = false)
            when (step.verdict) {
                NudgeVerdict.SEND -> {
                    sentOn += day
                    sent = step.sent
                    due = step.nextDays?.let { day + it }
                }
                NudgeVerdict.WAIT -> due = day + step.nextDays!!
                NudgeVerdict.STOP -> due = null
            }
        }
        assertEquals(listOf(3, 10, 24), sentOn)
        assertEquals(3, sent)
    }

    @Test
    fun aDayPutOffKeepsTheCountAndAFinishedLibraryStartsItAgain() {
        val partly = IndexShare(onPhone = 400, indexed = 100)
        val waiting = IndexNudge.step(partly, scanning = true, enabled = true, sent = 1, noteToday = false)
        assertEquals(NudgeVerdict.WAIT, waiting.verdict)
        assertEquals(1, waiting.sent)
        assertEquals(1, waiting.nextDays)
        val done = IndexNudge.step(IndexShare(400, 380), scanning = false, enabled = true, sent = 2, noteToday = false)
        assertEquals(NudgeVerdict.STOP, done.verdict)
        assertEquals(0, done.sent)
        assertNull(done.nextDays)
        assertEquals(2, IndexNudge.step(partly, scanning = false, enabled = false, sent = 2, noteToday = false).sent)
    }

    @Test
    fun almostNothingIndexedIsNotCalledZeroPercent() {
        val tiny = IndexShare(onPhone = 500, indexed = 1)
        assertEquals(0, tiny.percent)
        assertEquals(
            "Only 1 of your 500 can be searched" to "499 photos and videos are waiting. Index them to search all of your photos and videos.",
            IndexNudge.words(NudgeKind.RING, tiny, null, 0, 0, "x"),
        )
    }
/** Also covers a day the clocks went forward (New York, 10 March 2019), which is 23 hours long. */

    @Test
    fun thisDayInEarlierYearsHandlesLeapDaysAndClockChanges() {
        val utc = java.util.TimeZone.getTimeZone("UTC")
        fun at(zone: java.util.TimeZone, y: Int, m: Int, d: Int) =
            java.util.Calendar.getInstance(zone).apply { clear(); set(y, m - 1, d, 15, 30, 0) }.timeInMillis

        val ordinary = IndexGap.sameDayInEarlierYears(at(utc, 2026, 11, 4), utc)
        assertEquals(20, ordinary.size)
        assertTrue(ordinary.all { (from, to) -> to - from == 86_400_000L })
        assertEquals(at(utc, 2025, 11, 4) - 15 * 3_600_000L - 30 * 60_000L, ordinary.first().first)

        val leap = IndexGap.sameDayInEarlierYears(at(utc, 2024, 2, 29), utc)
        assertEquals(listOf(2020, 2016, 2012, 2008, 2004), leap.map {
            java.util.Calendar.getInstance(utc).apply { timeInMillis = it.first }.get(java.util.Calendar.YEAR)
        })

        val ny = java.util.TimeZone.getTimeZone("America/New_York")
        val clocks = IndexGap.sameDayInEarlierYears(at(ny, 2020, 3, 10), ny, yearsBack = 1)
        assertEquals(1, clocks.size)
        assertEquals(23 * 3_600_000L, clocks[0].second - clocks[0].first)
    }

    @Test
    fun theNoteSaysHowManyPhotosAndHowManyVideosAreWaiting() {
        fun share(photos: Int?, videos: Int?) = IndexShare(onPhone = 400, indexed = 100, missingPhotos = photos, missingVideos = videos)
        assertEquals("250 photos and 50 videos", IndexNudge.counts(share(250, 50)))
        assertEquals("300 photos", IndexNudge.counts(share(300, 0)))
        assertEquals("1 video", IndexNudge.counts(share(0, 1)))
        assertEquals("1 photo and 1 video", IndexNudge.counts(share(1, 1)))
        assertEquals("300 photos and videos", IndexNudge.counts(share(null, null)))
        assertEquals("300 photos and videos", IndexNudge.counts(share(0, 0)))
        assertEquals(
            "25% of your library can be searched" to "250 photos and 50 videos are waiting. Index them to search all of your photos and videos.",
            IndexNudge.words(NudgeKind.RING, share(250, 50), null, 0, 0, "x"),
        )
        assertEquals(
            "Find more of Maya" to "Maya is in 120 photos so far. 250 photos and 50 videos have not been looked at.",
            IndexNudge.words(NudgeKind.PEOPLE, share(250, 50), "Maya", 120, 0, "x"),
        )
    }

    @Test
    fun theWordsUseTheRealNumbers() {
        val share = IndexShare(onPhone = 400, indexed = 100)
        assertEquals(
            "25% of your library can be searched" to "300 photos and videos are waiting. Index them to search all of your photos and videos.",
            IndexNudge.words(NudgeKind.RING, share, null, 0, 0, "x"),
        )
        assertEquals(
            "Your library cannot be searched yet" to "Index your 400 photos and videos to find them by describing them.",
            IndexNudge.words(NudgeKind.RING, IndexShare(400, 0), null, 0, 0, "x"),
        )
        assertEquals(
            "Find more of Maya" to "Maya is in 120 photos so far. 300 photos and videos have not been looked at.",
            IndexNudge.words(NudgeKind.PEOPLE, share, "Maya", 120, 0, "x"),
        )
        assertEquals(
            "Photos from this day are waiting" to "About 12 photos and videos from this day in earlier years are not in your memories yet.",
            IndexNudge.words(NudgeKind.THIS_DAY, share, null, 0, 12, "x"),
        )
        assertEquals(
            "Search can see 100 of your 400" to "Index the rest, then try \"sunset at the beach\".",
            IndexNudge.words(NudgeKind.SEARCH, share, null, 0, 0, "sunset at the beach"),
        )
    }
}
