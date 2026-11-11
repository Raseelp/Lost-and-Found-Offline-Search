package dev.raseel.lostandfound.embedder.models

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class DownloadProgressTrackerTest {
    private val vision = RemoteModel("vision", "vision.onnx", "http://x/vision", "aa", 100L)
    private val text = RemoteModel("text", "text.onnx", "http://x/text", "bb", 200L)

    private class Clock(var now: Long = 1_000L) : () -> Long {
        override fun invoke() = now
    }

    private fun tracker(
        models: List<RemoteModel>,
        pending: List<RemoteModel>,
        events: MutableList<ModelDownloadProgress>,
        clock: Clock = Clock()
    ) = DownloadProgressTracker(models, pending, { events.add(it) }, clock, intervalMs = 250L)

    @Test
    fun theOverallNumbersAddUpModelsThatDownloadAtTheSameTime() {
        val events = mutableListOf<ModelDownloadProgress>()
        val clock = Clock()
        val t = tracker(listOf(vision, text), listOf(vision, text), events, clock)

        t.received(vision, 40L)
        clock.now += 300
        t.received(text, 60L)

        val last = events.last()
        assertEquals(100L, last.overallBytesDownloaded)
        assertEquals(300L, last.overallTotalBytes)
    }

    @Test
    fun aModelThatIsAlreadyHereCountsAsDoneFromTheStart() {
        val events = mutableListOf<ModelDownloadProgress>()
        val t = tracker(listOf(vision, text), listOf(text), events)

        t.received(text, 50L)

        assertEquals(150L, events.single().overallBytesDownloaded)
        assertEquals(300L, events.single().overallTotalBytes)
        assertEquals("text", events.single().modelId)
    }

    @Test
    fun theFirstBlockIsReportedAtOnceAndLaterOnesOnlyOncePerInterval() {
        val events = mutableListOf<ModelDownloadProgress>()
        val clock = Clock(now = 10_000L)
        val t = tracker(listOf(vision), listOf(vision), events, clock)

        t.received(vision, 10L)
        clock.now += 100
        t.received(vision, 20L)
        clock.now += 100
        t.received(vision, 30L)
        assertEquals(1, events.size)

        clock.now += 100
        t.received(vision, 40L)
        assertEquals(2, events.size)
        assertEquals(40L, events.last().bytesForModel)
    }

    @Test
    fun theEventNamesTheFirstModelThatIsStillDownloading() {
        val events = mutableListOf<ModelDownloadProgress>()
        val clock = Clock()
        val t = tracker(listOf(vision, text), listOf(vision, text), events, clock)

        t.received(vision, 30L)
        assertEquals("vision", events.last().modelId)

        clock.now += 300
        t.received(vision, 100L)
        t.allBytesReceived(vision)
        assertEquals("text", events.last().modelId)
        assertFalse(events.last().isVerifyingEvent())
    }

    @Test
    fun aModelThatFinishesFirstDoesNotMakeTheScreenSayCheckingWhileTheOtherDownloads() {
        val events = mutableListOf<ModelDownloadProgress>()
        val clock = Clock()
        val t = tracker(listOf(vision, text), listOf(vision, text), events, clock)

        clock.now += 300
        t.received(text, 120L)
        t.allBytesReceived(vision)
        t.finished(vision)

        val last = events.last()
        assertEquals("text", last.modelId)
        assertEquals(120L, last.bytesForModel)
        assertFalse(last.done)
        assertEquals(220L, last.overallBytesDownloaded)
    }

    @Test
    fun whenEveryByteIsInTheLastModelBeingCheckedIsNamedAndNotYetDone() {
        val events = mutableListOf<ModelDownloadProgress>()
        val t = tracker(listOf(vision, text), listOf(vision, text), events)

        t.allBytesReceived(vision)
        t.allBytesReceived(text)

        val last = events.last()
        assertEquals("vision", last.modelId)
        assertTrue(last.isVerifyingEvent())
        assertEquals(300L, last.overallBytesDownloaded)
    }

    @Test
    fun theFinalEventIsDoneAndFull() {
        val events = mutableListOf<ModelDownloadProgress>()
        val t = tracker(listOf(vision, text), listOf(vision, text), events)

        t.allBytesReceived(text)
        t.finished(text)
        t.allBytesReceived(vision)
        t.finished(vision)

        val last = events.last()
        assertTrue(last.done)
        assertEquals(last.overallTotalBytes, last.overallBytesDownloaded)
        assertEquals(300L, last.overallTotalBytes)
    }

    @Test
    fun theOverallCountNeverPassesTheTotal() {
        val events = mutableListOf<ModelDownloadProgress>()
        val t = tracker(listOf(vision), listOf(vision), events)

        t.received(vision, 5_000L)

        assertEquals(100L, events.single().overallBytesDownloaded)
    }

    private fun ModelDownloadProgress.isVerifyingEvent() = !done && totalBytesForModel > 0 && bytesForModel >= totalBytesForModel
}
