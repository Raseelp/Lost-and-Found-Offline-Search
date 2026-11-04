package dev.raseel.lostandfound.embedder.memories

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MemoryKindsTest {
    @Test
    fun aTripIsSeveralBusyDaysInARow() {
        val runs = Trips.find(mapOf(10 to 6, 11 to 9, 12 to 12))
        assertEquals(1, runs.size)
        assertEquals(10, runs[0].startDay)
        assertEquals(12, runs[0].endDay)
        assertEquals(27, runs[0].total)
        assertEquals(3, runs[0].days)
    }

    @Test
    fun aQuietDayBreaksATripInTwo() {
        val perDay = mapOf(1 to 10, 2 to 10, 3 to 10, 4 to 1, 5 to 10, 6 to 10, 7 to 10)
        val runs = Trips.find(perDay)
        assertEquals(listOf(1 to 3, 5 to 7), runs.map { it.startDay to it.endDay })
    }

    @Test
    fun tooFewDaysOrTooFewPhotosIsNotATrip() {
        assertTrue(Trips.find(mapOf(1 to 30, 2 to 30)).isEmpty())
        assertTrue(Trips.find(mapOf(1 to 5, 2 to 5, 3 to 5)).isEmpty())
        assertTrue(Trips.find(emptyMap()).isEmpty())
    }

    @Test
    fun nearPicksTheBiggestTripWithinReachOfTheDay() {
        val runs = Trips.find(mapOf(10 to 10, 11 to 10, 12 to 10, 40 to 20, 41 to 20, 42 to 20))
        assertEquals(10, Trips.near(runs, centreDay = 12, spread = 3)?.startDay)
        assertEquals(40, Trips.near(runs, centreDay = 41, spread = 0)?.startDay)
        assertNull(Trips.near(runs, centreDay = 100, spread = 5))
        assertEquals(40, Trips.near(runs, centreDay = 25, spread = 20)?.startDay)
    }

    @Test
    fun aMilestoneIsTheBiggestRoundNumberReached() {
        assertEquals(0, Milestones.reached(49))
        assertEquals(50, Milestones.reached(50))
        assertEquals(250, Milestones.reached(499))
        assertEquals(10000, Milestones.reached(123456))
    }

    @Test
    fun aMilestoneIsOnlyNewWhenItIsAboveTheOneAlreadyTold() {
        assertEquals(100, Milestones.crossed(count = 130, announced = 50))
        assertNull(Milestones.crossed(count = 130, announced = 100))
        assertNull(Milestones.crossed(count = 30, announced = 0))
        assertEquals(1000, Milestones.crossed(count = 1000, announced = 0))
    }

    @Test
    fun milestoneWordsShowTheRealCount() {
        val before = Locale.getDefault()
        Locale.setDefault(Locale.US)
        try {
            assertEquals("Maya is in 1,234 of your photos", Milestones.title("Maya", 1234))
            assertEquals("1,234 photos, and counting.", Milestones.counted(1234))
        } finally {
            Locale.setDefault(before)
        }
    }

    @Test
    fun aFirstAppearanceIsRealWhenEnoughPhotosFollowWithinTheWindow() {
        val day = 86_400_000L
        val first = 1_000L * day
        assertTrue(FirstAppearance.real(listOf(first, first + 10 * day, first + 80 * day), first))
        assertFalse(FirstAppearance.real(listOf(first, first + 10 * day), first))
        assertFalse(FirstAppearance.real(listOf(first, first + 100 * day, first + 200 * day), first))
        assertFalse(FirstAppearance.real(listOf(first - day, first - 2 * day, first - 3 * day), first))
    }

    @Test
    fun aDayRotatesTheListTheSameWayEveryTime() {
        val list = listOf("a", "b", "c", "d", "e")
        assertEquals(DayChoice.rotated(list, 20_000), DayChoice.rotated(list, 20_000))
        assertEquals(list.sorted(), DayChoice.rotated(list, 20_000).sorted())
        assertEquals(list, DayChoice.rotated(list, 0))
    }

    @Test
    fun differentDaysStartTheListAtDifferentPlaces() {
        val list = (1..7).toList()
        val firsts = (20_000..20_030).map { DayChoice.rotated(list, it).first() }.toSet()
        assertTrue(firsts.size > 3)
    }

    @Test
    fun aListOfOneOrNoneIsLeftAlone() {
        assertEquals(listOf("x"), DayChoice.rotated(listOf("x"), 5))
        assertEquals(emptyList<String>(), DayChoice.rotated(emptyList<String>(), 5))
    }

    @Test
    fun pickingByDayWrapsAroundAndAcceptsNegativeDays() {
        assertEquals("b", DayChoice.pick(1, "a", "b", "c"))
        assertEquals("b", DayChoice.pick(4, "a", "b", "c"))
        assertEquals("c", DayChoice.pick(-1, "a", "b", "c"))
    }
}
