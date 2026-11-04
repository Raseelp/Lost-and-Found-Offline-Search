package dev.raseel.lostandfound.embedder.faces

import org.junit.Assert.assertArrayEquals
import org.junit.Test

class FaceCropsTest {
    private fun area(cx: Float, cy: Float, cw: Float, ch: Float, w: Float, h: Float) =
        FaceCrops.fillArea(cx, cy, cw, ch, w, h)

    @Test
    fun anAreaInsideThePhotoStaysAsItIs() {
        assertArrayEquals(floatArrayOf(300f, 400f, 400f, 200f), area(500f, 500f, 400f, 200f, 1000f, 1000f), 0.01f)
    }

    @Test
    fun anAreaOverAnEdgeMovesInside() {
        assertArrayEquals(floatArrayOf(0f, 0f, 400f, 200f), area(100f, 50f, 400f, 200f, 1000f, 1000f), 0.01f)
        assertArrayEquals(floatArrayOf(600f, 800f, 400f, 200f), area(950f, 990f, 400f, 200f, 1000f, 1000f), 0.01f)
    }

    @Test
    fun aWideAreaOnATallPhotoClosesInToItsWidthKeepingTheShape() {
        assertArrayEquals(floatArrayOf(0f, 375f, 900f, 450f), area(500f, 600f, 1600f, 800f, 900f, 1600f), 0.01f)
    }

    @Test
    fun awkwardSizesNeverFail() {
        for (w in listOf(333f, 719f, 1001f, 4031f)) {
            for (h in listOf(97f, 457f, 3023f)) {
                val a = area(w / 3f, h / 7f, w * 2.1f, h * 1.3f, w, h)
                assert(a[0] >= 0f && a[1] >= 0f && a[2] <= w * 1.0001f && a[3] <= h * 1.0001f)
            }
        }
    }
}
