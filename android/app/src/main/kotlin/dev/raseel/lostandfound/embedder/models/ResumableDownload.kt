package dev.raseel.lostandfound.embedder.models

import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL

/**
 * How a download copes with a failing connection: how many tries it makes, how long each waits for the server and how
 * long it pauses between tries.
 *
 * The first two tries give up on a silent server quickly, so a path that does not work is left for the next try in
 * seconds and not half a minute. The later tries wait longer, for a slow but working network. The first retry starts
 * at once, because a failed first try is often just a stale connection.
 */
class RetrySchedule(
    val maxAttempts: Int = 5,
    private val quickConnectMs: Int = 8_000,
    private val patientConnectMs: Int = 15_000,
    val readTimeoutMs: Int = 20_000,
    private val pauseStepMs: Long = 1_000L
) {
    /** How long to wait for the connection after [failures] failed tries. */
    fun connectTimeoutMs(failures: Int): Int = if (failures < 2) quickConnectMs else patientConnectMs

    /** How long to pause after [failures] failed tries, before the next one. */
    fun pauseMs(failures: Int): Long = if (failures <= 1) 0L else pauseStepMs * (failures - 1)
}

/**
 * Fetches one URL into a file, picking up from the bytes already in it when the server honours a Range request. It
 * gives [onBytes] the number of bytes the file holds after each block. [stop] ends it at once, even when it is waiting
 * for the server or for a pause between tries, by closing the connection.
 *
 * It does not check the size or the contents of the finished file.
 */
class ResumableDownload(
    private val url: String,
    private val part: File,
    private val expectedSize: Long,
    private val schedule: RetrySchedule = RetrySchedule(),
    private val onBytes: (Long) -> Unit
) {
    @Volatile
    private var stopped = false

    @Volatile
    private var connection: HttpURLConnection? = null

    /**
     * Ends the download. It can be called from any thread, including the main thread: the connection is closed on a
     * thread of its own, because closing a socket is network work.
     */
    fun stop() {
        stopped = true
        val open = connection ?: return
        Thread { runCatching { open.disconnect() } }.apply { isDaemon = true }.start()
    }

    /**
     * Returns true when the file holds every byte the server sends, false when [stop] ended it first. Throws the last
     * error when the tries are used up.
     */
    fun run(): Boolean {
        var existing = if (part.exists()) part.length() else 0L
        if (existing > expectedSize) {
            part.delete()
            existing = 0L
        }

        var failures = 0
        while (true) {
            if (stopped) return false
            var open: HttpURLConnection? = null
            try {
                open = URL(url).openConnection() as HttpURLConnection
                connection = open
                if (stopped) return false
                open.connectTimeout = schedule.connectTimeoutMs(failures)
                open.readTimeout = schedule.readTimeoutMs
                if (existing > 0) open.setRequestProperty("Range", "bytes=$existing-")
                open.connect()
                if (stopped) return false

                val code = open.responseCode
                if (existing > 0 && code != HttpURLConnection.HTTP_PARTIAL) {
                    existing = 0L
                    part.delete()
                }
                if (code !in 200..299) throw IOException("HTTP $code for $url")

                if (!copy(open, existing)) return false
                if (part.length() < expectedSize) {
                    throw IOException("The connection closed after ${part.length()} of $expectedSize bytes")
                }
                return true
            } catch (e: Exception) {
                if (stopped) return false
                failures++
                existing = if (part.exists()) part.length() else 0L
                if (failures >= schedule.maxAttempts) throw e
                if (!pause(schedule.pauseMs(failures))) return false
            } finally {
                open?.disconnect()
            }
        }
    }

    /** Writes the body to the file from [from] on. Returns false when stopped part way. */
    private fun copy(open: HttpURLConnection, from: Long): Boolean {
        RandomAccessFile(part, "rw").use { file ->
            file.seek(from)
            open.inputStream.use { input ->
                val buffer = ByteArray(BUFFER_SIZE)
                var written = from
                while (true) {
                    val read = input.read(buffer)
                    if (read == -1) break
                    if (stopped) return false
                    file.write(buffer, 0, read)
                    written += read
                    onBytes(written)
                }
            }
        }
        return true
    }

    /** Waits for [ms] in short steps. Returns false when [stop] came during the wait. */
    private fun pause(ms: Long): Boolean {
        var left = ms
        while (left > 0) {
            if (stopped) return false
            val step = minOf(left, PAUSE_SLICE_MS)
            Thread.sleep(step)
            left -= step
        }
        return !stopped
    }

    private companion object {
        const val BUFFER_SIZE = 64 * 1024
        const val PAUSE_SLICE_MS = 50L
    }
}
