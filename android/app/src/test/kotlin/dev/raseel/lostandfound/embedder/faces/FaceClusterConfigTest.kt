package dev.raseel.lostandfound.embedder.faces

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FaceClusterConfigTest {
    private val strict = FaceClusterConfig.forStrictness(FaceClusterConfig.STRICT)
    private val balanced = FaceClusterConfig.forStrictness(FaceClusterConfig.BALANCED)
    private val loose = FaceClusterConfig.forStrictness(FaceClusterConfig.LOOSE)

    @Test
    fun noChoiceOrAnUnknownOneMeansBalanced() {
        assertEquals(balanced.join, FaceClusterConfig.forStrictness(null).join, 0f)
        assertEquals(balanced.merge, FaceClusterConfig.forStrictness("something else").merge, 0f)
    }

    @Test
    fun strictAsksForMoreSimilarityThanBalancedAndBalancedThanLoose() {
        assertTrue(strict.join > balanced.join && balanced.join > loose.join)
        assertTrue(strict.weakJoin > balanced.weakJoin && balanced.weakJoin > loose.weakJoin)
        assertTrue(strict.link > balanced.link && balanced.link > loose.link)
        assertTrue(strict.merge > balanced.merge && balanced.merge > loose.merge)
    }

    @Test
    fun withinEachSettingJoiningIsEasierThanLinkingAndLinkingThanMerging() {
        for (c in listOf(strict, balanced, loose)) {
            assertTrue(c.join < c.weakJoin)
            assertTrue(c.weakJoin < c.link)
            assertTrue(c.link < c.merge)
        }
    }
}
