package dev.raseel.lostandfound.features.search

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class EmbeddingMathTest {
    @Test
    fun normalisedVectorHasLengthOne() {
        val v = EmbeddingMath.l2Normalize(floatArrayOf(3f, 4f))
        assertArrayEquals(floatArrayOf(0.6f, 0.8f), v, 1e-6f)
        assertEquals(1f, EmbeddingMath.dot(v, v), 1e-6f)
    }

    @Test
    fun normalisingKeepsTheDirection() {
        val n = EmbeddingMath.l2Normalize(floatArrayOf(1f, -2f, 2f))
        assertEquals(n[0] * 2f, -n[1], 1e-6f)
        assertEquals(n[1], -n[2], 1e-6f)
    }

    @Test
    fun aVectorOfZerosIsReturnedAsItIs() {
        val zeros = floatArrayOf(0f, 0f, 0f)
        assertSame(zeros, EmbeddingMath.l2Normalize(zeros))
    }

    @Test
    fun normalisingDoesNotChangeTheInput() {
        val v = floatArrayOf(3f, 4f)
        EmbeddingMath.l2Normalize(v)
        assertArrayEquals(floatArrayOf(3f, 4f), v, 0f)
    }

    @Test
    fun dotProductOfSameDirectionIsOneAndOfOppositeIsMinusOne() {
        val a = EmbeddingMath.l2Normalize(floatArrayOf(1f, 2f, 3f))
        val opposite = FloatArray(a.size) { -a[it] }
        assertEquals(1f, EmbeddingMath.dot(a, a), 1e-6f)
        assertEquals(-1f, EmbeddingMath.dot(a, opposite), 1e-6f)
    }

    @Test
    fun dotProductOfPerpendicularVectorsIsZero() {
        assertEquals(0f, EmbeddingMath.dot(floatArrayOf(1f, 0f), floatArrayOf(0f, 5f)), 0f)
    }

    @Test
    fun anEmbeddingWithNanOrInfinityIsNotFinite() {
        assertTrue(EmbeddingMath.isFinite(floatArrayOf(0f, 1f, -2f)))
        assertFalse(EmbeddingMath.isFinite(floatArrayOf(0f, Float.NaN)))
        assertFalse(EmbeddingMath.isFinite(floatArrayOf(Float.POSITIVE_INFINITY)))
        assertTrue(EmbeddingMath.isFinite(floatArrayOf()))
    }
}
