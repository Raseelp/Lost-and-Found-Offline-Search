package dev.raseel.lostandfound.embedder

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ScanNotificationTest {
    private fun indexing(photos: Int, videos: Int, photosDone: Int, videosDone: Int) =
        ScanNotification.Indexing(photos, videos, photosDone, videosDone, timeLeft = null)

    @Test
    fun timeLeftIsInWholeWordsToTheMinute() {
        assertEquals("1 min", ScanNotification.duration(0))
        assertEquals("1 min", ScanNotification.duration(20_000))
        assertEquals("8 min", ScanNotification.duration(7 * 60_000 + 1))
        assertEquals("1 h", ScanNotification.duration(60 * 60_000))
        assertEquals("1 h 20 min", ScanNotification.duration(80 * 60_000))
    }

    @Test
    fun progressIsOutOfMaxAndNeverPastIt() {
        assertEquals(0, ScanNotification.progress(5, 0))
        assertEquals(74, ScanNotification.progress(844, 11_376))
        assertEquals(ScanNotification.MAX, ScanNotification.progress(61, 60))
    }

    @Test
    fun duringThePhotosItNamesThePhotos() {
        val ix = indexing(9_876, 1_500, 844, 0)
        assertEquals("Indexing photos  ·  7%", ScanNotification.indexingTitle(ix))
        assertEquals("844 / 9,876", ScanNotification.indexingCount(ix))
        assertNull(ScanNotification.indexingContext(ix))
    }

    @Test
    fun duringTheVideosItNamesTheVideos() {
        val ix = indexing(9_876, 1_500, 9_876, 12)
        assertEquals("Indexing videos  ·  86%", ScanNotification.indexingTitle(ix))
        assertEquals("12 / 1,500", ScanNotification.indexingCount(ix))
        assertNull(ScanNotification.indexingContext(ix))
    }

    @Test
    fun speedIsInWords() {
        assertEquals("6.2 photos a second", ScanNotification.speed(6.2, "photo", "photos"))
        assertEquals("12 photos a second", ScanNotification.speed(12.4, "photo", "photos"))
        assertEquals("0.8 photos a second", ScanNotification.speed(0.8, "photo", "photos"))
        assertEquals("1 video every 4 s", ScanNotification.speed(0.25, "video", "videos"))
        assertEquals("1 video every 2 min", ScanNotification.speed(1 / 120.0, "video", "videos"))
        assertNull(ScanNotification.speed(null, "photo", "photos"))
    }

    @Test
    fun rateIsOverTheLastFewSecondsAndStartsOverOnANewRun() {
        val rate = ScanNotification.Rate(windowMs = 10_000)
        assertNull(rate.add(0, 0))
        assertNull(rate.add(500, 5))
        assertEquals(10.0, rate.add(2_000, 20)!!, 0.001)
        // Slower now: the old samples drop out of the window.
        rate.add(12_000, 40)
        assertEquals(2.0, rate.add(22_000, 60)!!, 0.001)
        // A lower count is a new batch.
        assertNull(rate.add(23_000, 3))
    }

    @Test
    fun withOnlyOneKindItSaysWhatItIsDoing() {
        assertEquals("Making them searchable, on this phone only", ScanNotification.indexingContext(indexing(40, 0, 3, 0)))
        assertEquals("Indexing videos  ·  50%", ScanNotification.indexingTitle(indexing(0, 8, 0, 4)))
        assertEquals("Getting ready to index", ScanNotification.indexingTitle(indexing(0, 0, 0, 0)))
    }
}
