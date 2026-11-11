package dev.raseel.lostandfound.core.log

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

class RollingLogFileTest {
    @get:Rule
    val temp = TemporaryFolder()

    private fun log(maxBytes: Long = 1000) = RollingLogFile(File(temp.root, "logs"), maxBytes)

    @Test
    fun linesComeBackInTheOrderTheyWereWritten() {
        val log = log()
        log.append(listOf("one", "two"))
        log.append(listOf("three"))
        assertEquals(listOf("one", "two", "three"), log.recentLines(10))
    }

    @Test
    fun onlyTheNewestLinesAreReturned() {
        val log = log()
        log.append((1..10).map { "line$it" })
        assertEquals(listOf("line8", "line9", "line10"), log.recentLines(3))
    }

    @Test
    fun aLogThatWasNeverWrittenIsEmpty() {
        assertTrue(log().recentLines(10).isEmpty())
    }

    @Test
    fun aFullFileBecomesTheOlderOneAndNothingIsLostYet() {
        val log = log(maxBytes = 20)
        log.append(listOf("a".repeat(30)))
        log.append(listOf("newer"))
        assertEquals(listOf("a".repeat(30), "newer"), log.recentLines(10))
    }

    @Test
    fun theLogStaysAboutTwiceTheLimit() {
        val log = log(maxBytes = 100)
        repeat(50) { log.append(listOf("line number $it with some padding")) }
        val folder = File(temp.root, "logs")
        val total = folder.listFiles()!!.sumOf { it.length() }
        assertTrue("took $total bytes", total < 300)
        assertEquals("line number 49 with some padding", log.recentLines(1).single())
    }
}
