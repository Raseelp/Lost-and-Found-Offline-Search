package dev.raseel.lostandfound.core.storage

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.nio.ByteBuffer
import java.nio.channels.Channels
import java.util.Random

class EmbeddingFileParserTest {
    private val dim = 8

    private fun records(n: Int, seed: Long = 1): List<EmbeddingRecord> {
        val rnd = Random(seed)
        return (0 until n).map { i ->
            val video = i % 3 == 0
            EmbeddingRecord(
                imagePath = "content://media/external/images/media/${100 + i}" + if (i % 5 == 0) "/näme-é-日本" else "",
                hash = rnd.nextLong(),
                embedding = FloatArray(dim) { rnd.nextFloat() - 0.5f },
                folderId = "__device_scan__",
                videoUri = if (video) "content://media/external/video/media/$i" else null,
                timestampMs = if (video) rnd.nextInt(60000).toLong() else 0L,
            )
        }
    }

    /** The bytes of the records, laid out as the store writes them, without the header. */
    private fun bytes(records: List<EmbeddingRecord>): ByteArray {
        val bytes = ByteArrayOutputStream()
        DataOutputStream(bytes).use { out ->
            for (r in records) {
                val path = r.imagePath.toByteArray()
                out.writeInt(path.size)
                out.write(path)
                val folder = r.folderId.toByteArray()
                out.writeInt(folder.size)
                out.write(folder)
                out.writeLong(r.hash)
                val video = (r.videoUri ?: "").toByteArray()
                out.writeInt(video.size)
                out.write(video)
                out.writeLong(r.timestampMs)
                for (x in r.embedding) out.writeFloat(x)
            }
        }
        return bytes.toByteArray()
    }

    /** Reads [data] through a channel, in pieces of [chunk] bytes, and returns what was read and what was left over. */
    private fun read(data: ByteArray, chunk: Int = EmbeddingFileParser.CHUNK_BYTES): Pair<List<EmbeddingRecord>, Long> {
        val out = ArrayList<EmbeddingRecord>()
        val leftover = EmbeddingFileParser.readRecords(Channels.newChannel(data.inputStream()), dim, out, chunk)
        return out to leftover
    }

    private fun assertSame(expected: List<EmbeddingRecord>, actual: List<EmbeddingRecord>) {
        assertEquals(expected.size, actual.size)
        for (i in expected.indices) {
            val e = expected[i]
            val a = actual[i]
            assertEquals(e.imagePath, a.imagePath)
            assertEquals(e.hash, a.hash)
            assertEquals(e.folderId, a.folderId)
            assertEquals(e.videoUri, a.videoUri)
            assertEquals(e.timestampMs, a.timestampMs)
            assertTrue(e.embedding.contentEquals(a.embedding))
        }
    }

    @Test
    fun readsWhatTheStoreWrites() {
        val written = records(50)
        val (read, leftover) = read(bytes(written))
        assertSame(written, read)
        assertEquals(0L, leftover)
    }

    @Test
    fun readsTheSameWhereverTheChunksEnd() {
        val written = records(120)
        val data = bytes(written)
        for (chunk in listOf(600, 601, 777, 1024, 4096, 100_000)) {
            val (read, leftover) = read(data, chunk)
            assertSame(written, read)
            assertEquals("chunk $chunk", 0L, leftover)
        }
    }

    @Test
    fun readsNothingFromNothing() {
        val (read, leftover) = read(ByteArray(0))
        assertEquals(0, read.size)
        assertEquals(0L, leftover)
    }

    @Test
    fun aHalfWrittenRecordAtTheEndIsLeftOutWhereverItIsCut() {
        val written = records(10)
        val data = bytes(written)
        val lastStart = bytes(written.take(9)).size
        for (cut in lastStart until data.size) {
            for (chunk in listOf(700, EmbeddingFileParser.CHUNK_BYTES)) {
                val (read, leftover) = read(data.copyOf(cut), chunk)
                assertSame(written.take(9), read)
                assertEquals((cut - lastStart).toLong(), leftover)
            }
        }
    }

    @Test
    fun aLengthThatCannotBeRightMeansTheBytesAreNotRecords() {
        for (length in listOf(-5, Int.MAX_VALUE)) {
            try {
                read(ByteBuffer.allocate(8).putInt(length).array())
                fail("a length of $length should not be read")
            } catch (e: IllegalStateException) {
                // The caller treats the file as damaged.
            }
        }
    }

    @Test
    fun aRecordLargerThanTheBufferMeansTheBytesAreNotRecords() {
        val data = bytes(records(3))
        try {
            read(data, 100)
            fail("a record that does not fit should not be read")
        } catch (e: IllegalStateException) {
            // Never an endless loop.
        }
    }

    @Test
    fun parseLeavesThePositionAtTheFirstByteThatIsNotAWholeRecord() {
        val written = records(4)
        val whole = bytes(written)
        val data = whole + ByteArray(3) { 1 }
        val buf = ByteBuffer.wrap(data)
        val out = ArrayList<EmbeddingRecord>()
        EmbeddingFileParser.parse(buf, dim, out)
        assertSame(written, out)
        assertEquals(whole.size, buf.position())
    }
}
