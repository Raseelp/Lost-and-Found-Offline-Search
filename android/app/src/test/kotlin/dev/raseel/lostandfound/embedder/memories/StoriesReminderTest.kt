package dev.raseel.lostandfound.embedder.memories

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StoriesReminderTest {

    @Test
    fun unansweredNotesComeFurtherApartThenStop() {
        assertEquals(2, StoriesReminder.nextGapDays(1))
        assertEquals(4, StoriesReminder.nextGapDays(2))
        assertEquals(7, StoriesReminder.nextGapDays(3))
        assertNull(StoriesReminder.nextGapDays(StoriesReminder.MAX_UNANSWERED))
        assertNull(StoriesReminder.nextGapDays(0))
    }

    @Test
    fun atMostOneADay() {
        assertTrue(StoriesReminder.shouldWait(lastPostDay = 100, today = 100, memoryToday = false, memorySkips = 0))
        assertFalse(StoriesReminder.shouldWait(lastPostDay = 99, today = 100, memoryToday = false, memorySkips = 0))
    }

    @Test
    fun aDayWithAMemoryIsSkippedButNotForever() {
        assertTrue(StoriesReminder.shouldWait(lastPostDay = 90, today = 100, memoryToday = true, memorySkips = 0))
        assertTrue(StoriesReminder.shouldWait(lastPostDay = 90, today = 100, memoryToday = true, memorySkips = 1))
        assertFalse(
            StoriesReminder.shouldWait(lastPostDay = 90, today = 100, memoryToday = true, memorySkips = StoriesReminder.MAX_MEMORY_SKIPS)
        )
    }

    private fun person(name: String) = StoryPreview(name, faceId = 1L)
    private fun place(name: String) = StoryPreview(name, coverUri = "content://$name")

    @Test
    fun theNoteNamesThePeopleThenThePlaces() {
        assertEquals(
            "Maya and Sam have new stories. So do Beach and Rainy.",
            StoryPreview.sentence(listOf(person("Maya"), place("Beach"), person("Sam"), place("Rainy"))),
        )
        assertEquals(
            "Maya has a new story. So does Beach.",
            StoryPreview.sentence(listOf(place("Beach"), person("Maya"))),
        )
        assertEquals(
            "Maya has a new story. So do Beach, Rainy and 1 more.",
            StoryPreview.sentence(listOf(person("Maya"), place("Beach"), place("Rainy"), person(""))),
        )
    }

    @Test
    fun withOneKindItIsOneSentence() {
        assertEquals("Beach and Rainy have new stories.", StoryPreview.sentence(listOf(place("Beach"), place("Rainy"))))
        assertEquals("Maya and 2 more have new stories.", StoryPreview.sentence(listOf(person("Maya"), person(""), person(""))))
        assertEquals("Maya has a new story.", StoryPreview.sentence(listOf(person("Maya"))))
        assertEquals("2 stories are ready to watch.", StoryPreview.sentence(listOf(person(""), person(""))))
    }
}
