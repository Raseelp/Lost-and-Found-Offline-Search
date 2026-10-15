package dev.raseel.lostandfound.embedder.faces

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TimelineTogetherTest {
    // The file key of the nth entry is 1000 + n.
    private fun asItems(media: List<kotlin.Pair<Long, List<Long>>>) =
        media.mapIndexed { i, (ms, people) -> TimelineTogether.Item(1000L + i, ms, people) }

    @Test
    fun theCompanionIsWhoTheyAreInTheMostPhotosWith() {
        val media = listOf(
            100L to listOf(1L, 2L),
            200L to listOf(1L, 2L, 3L),
            300L to listOf(1L, 3L),
            400L to listOf(2L, 1L),
            500L to listOf(4L),
        )
        val byPerson = TimelineTogether.companions(asItems(media)).associateBy { it.personId }
        assertEquals(2L, byPerson[1L]!!.withId)
        assertEquals(3, byPerson[1L]!!.count)
        assertEquals(100L, byPerson[1L]!!.firstMs)
        assertEquals(1000L, byPerson[1L]!!.firstKey)
        assertEquals(1L, byPerson[2L]!!.withId)
        // 3 is in 2 photos with 1 and 1 with 2: 1 wins
        assertEquals(1L, byPerson[3L]!!.withId)
        assertNull(byPerson[4L])
    }

    @Test
    fun aTieGoesToTheEarlierFirstPhoto() {
        val media = listOf(
            500L to listOf(1L, 2L),
            100L to listOf(1L, 3L),
            600L to listOf(1L, 2L),
            200L to listOf(1L, 3L),
        )
        val byPerson = TimelineTogether.companions(asItems(media)).associateBy { it.personId }
        assertEquals(3L, byPerson[1L]!!.withId)
        assertEquals(100L, byPerson[1L]!!.firstMs)
        assertEquals(1001L, byPerson[1L]!!.firstKey)
    }

    @Test
    fun hugeGroupsSayNothingAboutAPair() {
        val crowd = (1L..20L).toList()
        val media = listOf(100L to crowd, 200L to listOf(1L, 2L))
        val byPerson = TimelineTogether.companions(asItems(media)).associateBy { it.personId }
        assertEquals(1, byPerson[1L]!!.count)
        assertEquals(200L, byPerson[1L]!!.firstMs)
        assertNull(byPerson[5L])
    }

    private val day = 86_400_000L

    private fun item(key: Long, days: Int, vararg people: Long) = TimelineTogether.Item(key, days * day, people.toList())

    @Test
    fun theWholeGangIsTheMostPeopleInOneShotEachYear() {
        val media = listOf(
            item(1, 10, 1, 2, 3, 4),
            item(2, 20, 1, 2, 3, 4, 5, 6),
            item(3, 30, 1, 2, 3),
            item(4, 400, 1, 2, 3, 4, 5),
            item(5, 410, 1, 2, 3, 4, 5),
        )
        val crowds = TimelineTogether.crowds(media, yearOf = { (it / day / 365).toInt() }, minPeople = 4, perYear = 1)
        assertEquals(listOf(2L, 4L), crowds.map { it.key })
        assertEquals(6, crowds[0].people.size)
    }

    @Test
    fun aReunionIsPeopleComingBackTogetherAfterALongTime() {
        val media = listOf(
            item(1, 10, 1, 2, 3),       // together early on
            item(2, 40, 1, 2, 3),
            item(3, 900, 1, 2, 3, 4),   // ~2.4 years later: a reunion
            item(4, 905, 5, 6, 7),      // people who never met before: not a reunion
        )
        val reunions = TimelineTogether.reunions(media)
        assertEquals(listOf(3L), reunions.map { it.key })
        assertEquals(860, reunions[0].gapDays)
    }

    @Test
    fun noReunionWhileTheyKeepMeetingOrWhenOnlyOnePairReturns() {
        val keepMeeting = listOf(
            item(1, 10, 1, 2, 3),
            item(2, 400, 1, 2),          // 1 and 2 met again after a year: but 3 not
            item(3, 500, 1, 2, 3),       // 1 and 2 were together 100 days ago: not a reunion
        )
        assertEquals(emptyList<Long>(), TimelineTogether.reunions(keepMeeting).map { it.key })
        val onePair = listOf(item(1, 10, 1, 2), item(2, 900, 1, 2, 3))
        // only the pair (1,2) returns: not enough
        assertEquals(emptyList<Long>(), TimelineTogether.reunions(onePair).map { it.key })
    }

    @Test
    fun theBestPhotoOfTheGetTogetherIsTheReunion() {
        val media = listOf(
            item(1, 10, 1, 2, 3, 4),
            item(2, 40, 1, 2, 3, 4),
            item(3, 900, 1, 2, 3),           // the first photo of the day: three of them
            item(4, 900, 1, 2, 3, 4),        // later that day: all four, the one to show
        )
        assertEquals(listOf(4L), TimelineTogether.reunions(media).map { it.key })
    }

    @Test
    fun oneReunionADaysStretch() {
        val media = listOf(
            item(1, 10, 1, 2, 3),
            item(2, 900, 1, 2, 3),
            item(3, 1000, 1, 2, 3, 4, 5),  // within the 180 days of the last one, but nobody is "away" any more
        )
        val reunions = TimelineTogether.reunions(media)
        assertEquals(listOf(2L), reunions.map { it.key })
    }
}
