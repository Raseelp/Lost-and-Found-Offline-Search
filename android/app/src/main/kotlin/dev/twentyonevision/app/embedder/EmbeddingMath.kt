package dev.twentyonevision.app.embedder

object EmbeddingMath {

    fun l2Normalize(vec: FloatArray): FloatArray {
        var sum = 0f
        for (v in vec) {
            sum += v * v
        }

        val norm = kotlin.math.sqrt(sum)
        if (norm == 0f) return vec

        val out = FloatArray(vec.size)
        for (i in vec.indices) {
            out[i] = vec[i] / norm
        }
        return out
    }

    fun dot(a: FloatArray, b: FloatArray): Float {
        var sum = 0f
        for (i in a.indices) {
            sum += a[i] * b[i]
        }
        return sum
    }
}
