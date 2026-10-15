package dev.raseel.lostandfound.embedder.faces

import org.junit.Assert.assertEquals
import org.junit.Test

class TimelinePicksTest {
    private val minute = 60_000L
    private val day = 24 * 60 * minute

    // Months of 30 days, counted from 0.
    private fun monthOf(ms: Long): Int = (ms / (30 * day)).toInt()

    private fun c(key: Long, takenMs: Long, score: Float) =
        TimelinePicks.Candidate(key, "uri$key", false, 0, takenMs, score)

    @Test
    fun theBestOfEveryMonthInTheOrderTheyWereTaken() {
        val list = listOf(
            c(1, 2 * day, 10f), c(2, 5 * day, 30f), c(3, 9 * day, 20f), c(4, 12 * day, 5f),
            c(5, 31 * day, 7f), c(6, 40 * day, 9f),
        )
        val picks = TimelinePicks.bestPerMonth(list, ::monthOf, perMonth = 2, burstMs = 2 * minute)
        assertEquals(listOf(2L, 3L, 5L, 6L), picks.map { it.key })
    }

    @Test
    fun shotsTakenAlmostTogetherCountOnce() {
        val list = listOf(
            c(1, 3 * day, 40f), c(2, 3 * day + 20_000, 39f), c(3, 3 * day + 90_000, 38f), c(4, 8 * day, 10f),
        )
        val picks = TimelinePicks.bestPerMonth(list, ::monthOf, perMonth = 3, burstMs = 2 * minute)
        assertEquals(listOf(1L, 4L), picks.map { it.key })
    }

    @Test
    fun aMonthWithNothingGivesNothing() {
        val picks = TimelinePicks.bestPerMonth(emptyList(), ::monthOf, perMonth = 3, burstMs = minute)
        assertEquals(emptyList<Long>(), picks.map { it.key })
    }

    @Test
    fun moreAndClearerFacesScoreHigher() {
        val group = TimelinePicks.score(listOf(80f, 70f, 60f, 10f))
        val single = TimelinePicks.score(listOf(150f))
        assertEquals(210f, group, 0.001f)
        assertEquals(150f, single, 0.001f)
    }
}
