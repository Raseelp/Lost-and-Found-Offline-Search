package dev.raseel.lostandfound.embedder.faces

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class FaceQualityTest {
    // Landmarks as left eye, right eye, nose (x and y each), the other two points unused. The eyes are 40 apart.
    private fun landmarks(noseX: Float, noseY: Float = 70f) =
        floatArrayOf(60f, 50f, 100f, 50f, noseX, noseY, 0f, 0f, 0f, 0f)

    @Test
    fun aNoseBetweenTheEyesIsAFaceLookingStraightAtTheCamera() {
        assertEquals(0f, FaceQuality.yaw(landmarks(80f)), 1e-6f)
    }

    @Test
    fun aNoseBesideTheEyesIsAFaceTurnedAway() {
        assertEquals(0.5f, FaceQuality.yaw(landmarks(100f)), 1e-6f)
        assertEquals(0.5f, FaceQuality.yaw(landmarks(60f)), 1e-6f)
    }

    @Test
    fun yawIsMeasuredAlongTheLineBetweenTheEyesWhateverWayTheHeadIsTilted() {
        // Eyes one above the other (a head on its side): the nose beside the lower eye is as turned as before.
        val tilted = floatArrayOf(50f, 60f, 50f, 100f, 70f, 100f, 0f, 0f, 0f, 0f)
        assertEquals(0.5f, FaceQuality.yaw(tilted), 1e-6f)
    }

    @Test
    fun aNoseOffTheLineBetweenTheEyesButMidwayAlongItIsNotTurned() {
        val tilted = floatArrayOf(50f, 60f, 50f, 100f, 80f, 80f, 0f, 0f, 0f, 0f)
        assertEquals(0f, FaceQuality.yaw(tilted), 1e-6f)
    }

    @Test
    fun eyesOnTheSamePointCountAsFullyTurned() {
        val same = floatArrayOf(10f, 10f, 10f, 10f, 20f, 20f, 0f, 0f, 0f, 0f)
        assertEquals(1f, FaceQuality.yaw(same), 0f)
    }

    @Test
    fun aGoodFaceIsBigClearSharpAndNotTurnedTooFar() {
        assertTrue(FaceQuality.isGood(sizePx = 48, score = 0.6f, sharpness = 20f, yaw = 0.55f))
        assertFalse(FaceQuality.isGood(sizePx = 47, score = 0.9f, sharpness = 90f, yaw = 0.1f))
        assertFalse(FaceQuality.isGood(sizePx = 80, score = 0.59f, sharpness = 90f, yaw = 0.1f))
        assertFalse(FaceQuality.isGood(sizePx = 80, score = 0.9f, sharpness = 19.9f, yaw = 0.1f))
        assertFalse(FaceQuality.isGood(sizePx = 80, score = 0.9f, sharpness = 90f, yaw = 0.56f))
    }

    @Test
    fun aFaceInAVideoFrameIsJudgedMoreGently() {
        assertTrue(FaceQuality.isGoodVideo(sizePx = 44, score = 0.5f, sharpness = 14f, yaw = 0.65f))
        assertFalse(FaceQuality.isGoodVideo(sizePx = 43, score = 0.9f, sharpness = 90f, yaw = 0.1f))
        assertTrue(FaceQuality.isGoodVideo(sizePx = 46, score = 0.55f, sharpness = 16f, yaw = 0.6f))
        assertFalse(FaceQuality.isGood(sizePx = 46, score = 0.55f, sharpness = 16f, yaw = 0.6f))
    }

    @Test
    fun aBiggerSurerMoreFrontalFaceRanksHigher() {
        val base = FaceQuality.rank(sizePx = 100, score = 0.8f, yaw = 0.2f)
        assertTrue(FaceQuality.rank(sizePx = 150, score = 0.8f, yaw = 0.2f) > base)
        assertTrue(FaceQuality.rank(sizePx = 100, score = 0.9f, yaw = 0.2f) > base)
        assertTrue(FaceQuality.rank(sizePx = 100, score = 0.8f, yaw = 0.0f) > base)
    }

    @Test
    fun sizeStopsCountingAt200AndYawAtOne() {
        assertEquals(
            FaceQuality.rank(sizePx = 200, score = 0.8f, yaw = 0.3f),
            FaceQuality.rank(sizePx = 900, score = 0.8f, yaw = 0.3f),
            0f,
        )
        assertEquals(
            FaceQuality.rank(sizePx = 100, score = 0.8f, yaw = 1f),
            FaceQuality.rank(sizePx = 100, score = 0.8f, yaw = 3f),
            0f,
        )
    }
}
