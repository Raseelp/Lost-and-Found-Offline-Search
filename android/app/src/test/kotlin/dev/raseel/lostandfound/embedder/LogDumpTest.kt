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

    @Test
    fun keepsTheNewestLinesAndSaysOlderOnesWereLeftOut() {
        val lines = (1..10).map { "line$it" }
        // "head\n" is 5 characters, line10 takes 7, line9 and line8 take 6 each: 24. Line7 would make 30.
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
