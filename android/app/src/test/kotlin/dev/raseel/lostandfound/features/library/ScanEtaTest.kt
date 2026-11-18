package dev.raseel.lostandfound.features.library

import org.junit.Assert.assertEquals
import org.junit.Test

class ScanEtaTest {
    private fun eta(photos: Int, videos: Int) = ScanEta().also { it.start(0L, photos, videos) }

    @Test
    fun saysNothingBeforeEnoughIsDone() {
        val eta = eta(1000, 0)
        eta.photosDone(5)
        assertEquals(ScanEta.UNKNOWN, eta.leftMs(30_000))
        eta.photosDone(50)
        assertEquals(ScanEta.UNKNOWN, eta.leftMs(2_000))
    }

    @Test
    fun aScanThatCarriesOnCountsOnlyTheFilesItHasToDo() {
        val eta = eta(1000, 0)
        eta.photosDone(100)
        assertEquals(180_000L, eta.leftMs(20_000))
    }

    @Test
    fun videosAreCountedAsSeveralPhotosUntilTheyAreTimed() {
        val eta = eta(100, 10)
        eta.photosDone(50)
        assertEquals((50 * 200 + 10 * 1200).toLong(), eta.leftMs(10_000))
    }

    @Test
    fun videosAreTimedOnceTheyBegin() {
        val eta = eta(100, 10)
        eta.photosDone(100)
        eta.photosOver(20_000)
        assertEquals((10 * 1200).toLong(), eta.leftMs(20_000))
        eta.videosDone(2)
        assertEquals((8 * 3000).toLong(), eta.leftMs(26_000))
    }

    @Test
    fun aScanOfVideosOnlyWaitsForTwoVideos() {
        val eta = eta(0, 10)
        eta.videosDone(1)
        assertEquals(ScanEta.UNKNOWN, eta.leftMs(10_000))
        eta.videosDone(2)
        assertEquals((8 * 5000).toLong(), eta.leftMs(10_000))
    }

    @Test
    fun saysNothingWhenNothingIsLeft() {
        val eta = eta(20, 0)
        eta.photosDone(20)
        assertEquals(ScanEta.UNKNOWN, eta.leftMs(10_000))
    }

    @Test
    fun saysNothingBeforeTheWorkBegins() {
        assertEquals(ScanEta.UNKNOWN, ScanEta().leftMs(10_000))
    }

    @Test
    fun theWorkIsTimedFromWhenItBegan() {
        val eta = ScanEta()
        eta.start(100_000L, 1000, 0)
        eta.photosDone(100)
        assertEquals(180_000L, eta.leftMs(120_000L))
    }

    @Test
    fun startsFromTheRatioOfTheLastScan() {
        val eta = ScanEta()
        eta.start(0L, 100, 10, videoPrior = 12.0)
        eta.photosDone(50)
        assertEquals((50 * 200 + 10 * 2400).toLong(), eta.leftMs(10_000))
    }

    @Test
    fun aRatioOutOfReasonIsHeldWithinLimits() {
        val eta = ScanEta()
        eta.start(0L, 100, 10, videoPrior = 500.0)
        eta.photosDone(50)
        assertEquals((50 * 200 + 10 * 200 * 40).toLong(), eta.leftMs(10_000))
    }

    @Test
    fun measuresHowManyPhotosAVideoTook() {
        val eta = ScanEta()
        eta.start(0L, 100, 10)
        eta.photosDone(100)
        assertEquals(null, eta.measuredVideoRatio(20_000))
        eta.photosOver(20_000)
        eta.videosDone(4)
        assertEquals(null, eta.measuredVideoRatio(32_000))
        eta.videosDone(5)
        assertEquals(15.0, eta.measuredVideoRatio(35_000)!!, 0.001)
    }

    @Test
    fun hasNoRatioWithoutBothKinds() {
        val videosOnly = ScanEta()
        videosOnly.start(0L, 0, 10)
        videosOnly.videosDone(6)
        assertEquals(null, videosOnly.measuredVideoRatio(30_000))
    }
}
