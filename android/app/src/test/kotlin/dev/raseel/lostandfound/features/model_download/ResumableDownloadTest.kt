package dev.raseel.lostandfound.features.model_download

import java.io.File
import java.net.ServerSocket
import java.net.Socket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** A tiny HTTP server on a socket, so the tests need nothing outside the JDK and the phone's classes. */
private class FakeServer(private val handler: (Exchange) -> Unit) {
    class Exchange(val socket: Socket, val range: String?) {
        private val out = socket.getOutputStream()

        fun head(status: Int, length: Long, extra: String = "") {
            out.write("HTTP/1.1 $status X\r\nContent-Length: $length\r\n${extra}Connection: close\r\n\r\n".toByteArray())
        }

        fun write(bytes: ByteArray, from: Int = 0, count: Int = bytes.size - from) = out.write(bytes, from, count)

        fun flush() = out.flush()
    }

    private val server = ServerSocket(0, 50, java.net.InetAddress.getByName("127.0.0.1"))
    private val open = mutableListOf<Socket>()
    val requests = AtomicInteger()
    val ranges = java.util.Collections.synchronizedList(mutableListOf<String?>())
    val port get() = server.localPort

    init {
        Thread {
            while (!server.isClosed) {
                val socket = try { server.accept() } catch (_: Exception) { break }
                synchronized(open) { open.add(socket) }
                Thread { serve(socket) }.apply { isDaemon = true }.start()
            }
        }.apply { isDaemon = true }.start()
    }

    private fun serve(socket: Socket) {
        try {
            val reader = socket.getInputStream().bufferedReader()
            var range: String? = null
            reader.readLine() ?: return
            while (true) {
                val line = reader.readLine() ?: break
                if (line.isEmpty()) break
                if (line.startsWith("Range:", ignoreCase = true)) range = line.substringAfter(":").trim()
            }
            requests.incrementAndGet()
            ranges.add(range)
            handler(Exchange(socket, range))
        } catch (_: Exception) {
        } finally {
            runCatching { socket.close() }
        }
    }

    fun close() {
        runCatching { server.close() }
        synchronized(open) { open.forEach { runCatching { it.close() } } }
    }
}

class ResumableDownloadTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val body = ByteArray(300_000) { (it % 251).toByte() }
    private val quick = RetrySchedule(maxAttempts = 3, quickConnectMs = 1_000, patientConnectMs = 1_000, readTimeoutMs = 5_000, pauseStepMs = 5L)
    private var server: FakeServer? = null

    @After
    fun stop() {
        server?.close()
    }

    private fun serve(handler: (FakeServer.Exchange) -> Unit): FakeServer = FakeServer(handler).also { server = it }

    private fun url() = "http://127.0.0.1:${server!!.port}/file"

    private fun part() = File(folder.root, "model.part")

    /** Answers like a server that honours Range. */
    private fun FakeServer.Exchange.sendBody() {
        val start = range?.removePrefix("bytes=")?.removeSuffix("-")?.toInt()
        if (start != null) {
            head(206, (body.size - start).toLong(), "Content-Range: bytes $start-${body.size - 1}/${body.size}\r\n")
            write(body, start)
        } else {
            head(200, body.size.toLong())
            write(body)
        }
        flush()
    }

    @Test
    fun aWholeFileIsFetchedAndTheByteCountGrowsToItsSize() {
        serve { it.sendBody() }
        val counts = mutableListOf<Long>()

        val done = ResumableDownload(url(), part(), body.size.toLong(), quick) { counts.add(it) }.run()

        assertTrue(done)
        assertTrue(part().readBytes().contentEquals(body))
        assertEquals(body.size.toLong(), counts.last())
        assertEquals(counts.sorted(), counts)
    }

    @Test
    fun aPartialFileIsPickedUpFromWhereItStopped() {
        serve { it.sendBody() }
        part().writeBytes(body.copyOfRange(0, 100_000))

        val done = ResumableDownload(url(), part(), body.size.toLong(), quick) {}.run()

        assertTrue(done)
        assertTrue(part().readBytes().contentEquals(body))
        assertEquals("bytes=100000-", server!!.ranges.first())
    }

    @Test
    fun aServerThatIgnoresRangeMakesItStartOverAndStillEndWithTheRightFile() {
        serve {
            it.head(200, body.size.toLong())
            it.write(body)
            it.flush()
        }
        part().writeBytes(ByteArray(50_000) { 9 })

        val done = ResumableDownload(url(), part(), body.size.toLong(), quick) {}.run()

        assertTrue(done)
        assertTrue(part().readBytes().contentEquals(body))
    }

    @Test
    fun aPartFileLargerThanTheModelIsDiscarded() {
        serve { it.sendBody() }
        part().writeBytes(ByteArray(body.size + 10))

        val done = ResumableDownload(url(), part(), body.size.toLong(), quick) {}.run()

        assertTrue(done)
        assertTrue(part().readBytes().contentEquals(body))
        assertNull(server!!.ranges.first())
    }

    @Test
    fun aFailedFirstTryIsRetriedAndTheSecondSucceeds() {
        val calls = AtomicInteger()
        serve { if (calls.incrementAndGet() == 1) it.head(500, 0) else it.sendBody() }

        val done = ResumableDownload(url(), part(), body.size.toLong(), quick) {}.run()

        assertTrue(done)
        assertEquals(2, server!!.requests.get())
        assertTrue(part().readBytes().contentEquals(body))
    }

    @Test
    fun aConnectionThatClosesEarlyIsRetriedAndResumedFromWhatArrived() {
        val calls = AtomicInteger()
        serve {
            if (calls.incrementAndGet() == 1) {
                it.head(200, body.size.toLong())
                it.write(body, 0, 120_000)
                it.flush()
            } else {
                it.sendBody()
            }
        }

        val done = ResumableDownload(url(), part(), body.size.toLong(), quick) {}.run()

        assertTrue(done)
        assertTrue(part().readBytes().contentEquals(body))
        assertEquals(2, server!!.requests.get())
        assertTrue("the second try asked to resume", server!!.ranges.last()?.startsWith("bytes=") == true)
    }

    @Test
    fun whenEveryTryFailsTheLastErrorIsThrownAfterTheSetNumberOfTries() {
        serve { it.head(503, 0) }

        try {
            ResumableDownload(url(), part(), body.size.toLong(), quick) {}.run()
            fail("expected an error")
        } catch (e: java.io.IOException) {
            assertTrue(e.message!!.contains("503"))
        }
        assertEquals(3, server!!.requests.get())
    }

    @Test
    fun stopEndsTheDownloadWhileTheServerIsSilentAfterConnecting() {
        val arrived = CountDownLatch(1)
        val release = CountDownLatch(1)
        serve {
            arrived.countDown()
            release.await(10, TimeUnit.SECONDS)
        }
        val job = ResumableDownload(url(), part(), body.size.toLong(), RetrySchedule(readTimeoutMs = 20_000)) {}
        val result = AtomicReference<Boolean?>()
        val worker = Thread { result.set(job.run()) }.apply { start() }

        assertTrue(arrived.await(5, TimeUnit.SECONDS))
        val started = System.nanoTime()
        job.stop()
        worker.join(3_000)
        val took = (System.nanoTime() - started) / 1_000_000
        release.countDown()

        assertFalse("the download should have ended", worker.isAlive)
        assertEquals(false, result.get())
        assertTrue("took $took ms to stop", took < 2_500)
    }

    @Test
    fun stopEndsTheDownloadInTheMiddleOfTheBodyAndKeepsWhatArrived() {
        val half = CountDownLatch(1)
        serve {
            it.head(200, body.size.toLong())
            it.write(body, 0, 100_000)
            it.flush()
            half.countDown()
            Thread.sleep(600)
            it.write(body, 100_000)
            it.flush()
        }
        val job = ResumableDownload(url(), part(), body.size.toLong(), RetrySchedule(readTimeoutMs = 20_000)) {}
        val result = AtomicReference<Boolean?>()
        val worker = Thread { result.set(job.run()) }.apply { start() }

        assertTrue(half.await(5, TimeUnit.SECONDS))
        Thread.sleep(200)
        job.stop()
        worker.join(5_000)

        assertFalse(worker.isAlive)
        assertEquals(false, result.get())
        assertTrue("what arrived is kept for a later resume", part().length() in 1 until body.size.toLong())
    }

    @Test
    fun stopEndsTheWaitBetweenTwoTries() {
        serve { it.head(500, 0) }
        val slowRetries = RetrySchedule(maxAttempts = 5, quickConnectMs = 1_000, patientConnectMs = 1_000, pauseStepMs = 5_000L)
        val job = ResumableDownload(url(), part(), body.size.toLong(), slowRetries) {}
        val result = AtomicReference<Boolean?>()
        val worker = Thread { result.set(job.run()) }.apply { start() }

        val waitedFor = System.nanoTime()
        while (server!!.requests.get() < 2 && (System.nanoTime() - waitedFor) < 3_000_000_000L) Thread.sleep(10)
        Thread.sleep(200)
        val stoppedAt = System.nanoTime()
        job.stop()
        worker.join(3_000)

        assertFalse("it should not sit out the 5 s pause", worker.isAlive)
        assertEquals(false, result.get())
        assertTrue("took too long to stop", (System.nanoTime() - stoppedAt) < 2_000_000_000L)
    }

    @Test
    fun aDownloadStoppedBeforeItStartsDoesNothing() {
        serve { it.sendBody() }
        val job = ResumableDownload(url(), part(), body.size.toLong(), quick) {}
        job.stop()

        assertFalse(job.run())
        assertEquals(0, server!!.requests.get())
    }

    @Test
    fun theFirstTwoTriesGiveUpQuicklyAndTheLaterOnesWaitLonger() {
        val schedule = RetrySchedule()

        assertEquals(8_000, schedule.connectTimeoutMs(0))
        assertEquals(8_000, schedule.connectTimeoutMs(1))
        assertEquals(15_000, schedule.connectTimeoutMs(2))
        assertEquals(15_000, schedule.connectTimeoutMs(4))
    }

    @Test
    fun theFirstRetryIsAtOnceAndThePausesThenGrow() {
        val schedule = RetrySchedule()

        assertEquals(0L, schedule.pauseMs(1))
        assertEquals(1_000L, schedule.pauseMs(2))
        assertEquals(2_000L, schedule.pauseMs(3))
        assertEquals(3_000L, schedule.pauseMs(4))
    }
}
