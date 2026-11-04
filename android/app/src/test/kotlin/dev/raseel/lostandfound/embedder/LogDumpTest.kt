package dev.raseel.lostandfound.embedder

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LogDumpTest {
    @Test
    fun keepsEverythingWhenItFits() {
        val out = LogDump.text("head\n", listOf("a", "b", "c"), maxChars = 100)
        assertEquals("head\na\nb\nc\n", out)
    }

    /**
     * A limit of 29 characters fits the header (5), line10 (7), and line9 and line8 (6 each), which is 24. Line7 would
     * make 30.
     */
    @Test
    fun keepsTheNewestLinesAndSaysOlderOnesWereLeftOut() {
        val lines = (1..10).map { "line$it" }
        val out = LogDump.text("head\n", lines, maxChars = 29)
        assertTrue(out.startsWith("head\n(7 older lines left out)\n"))
        assertTrue(out.endsWith("line8\nline9\nline10\n"))
        assertFalse(out.contains("line7"))
    }

    @Test
    fun anEmptyLogIsJustTheHeader() {
        assertEquals("head\n", LogDump.text("head\n", emptyList()))
    }
}
