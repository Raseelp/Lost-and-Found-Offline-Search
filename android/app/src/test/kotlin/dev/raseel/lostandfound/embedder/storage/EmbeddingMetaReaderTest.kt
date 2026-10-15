package dev.raseel.lostandfound.embedder.storage

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import org.junit.Assert.assertEquals
import org.junit.Test

class EmbeddingMetaReaderTest {
    private val dim = 8

    // The same layout EmbeddingStore.writeRecord writes.
    private fun record(out: DataOutputStream, path: String, folder: String, hash: Long, video: String?, ts: Long) {
        val p = path.toByteArray()
        out.writeInt(p.size); out.write(p)
        val f = folder.toByteArray()
        out.writeInt(f.size); out.write(f)
        out.writeLong(hash)
        val v = (video ?: "").toByteArray()
        out.writeInt(v.size); out.write(v)
        out.writeLong(ts)
        repeat(dim) { out.writeFloat(it * 0.5f) }
    }

    private fun bytes(block: (DataOutputStream) -> Unit): ByteArray {
        val b = ByteArrayOutputStream()
        DataOutputStream(b).use(block)
        return b.toByteArray()
    }

    private class Seen(val key: Long, val uri: String, val video: Boolean)

    private fun read(data: ByteArray, start: Long = 0): Pair<Long, List<Seen>> {
        val seen = ArrayList<Seen>()
        val end = EmbeddingMetaReader.read(ByteArrayInputStream(data), start, dim) { k, u, v -> seen += Seen(k, u, v) }
        return end to seen
    }

    @Test
    fun readsPhotosAndVideosWithoutTheirEmbeddings() {
        val data = bytes {
            record(it, "content://media/1", "folderA", 11L, null, 0)
            record(it, "content://media/2", "folderA", 22L, "content://media/2", 0)
            record(it, "content://media/2", "folderA", 22L, "content://media/2", 1500)
            record(it, "content://äö/3", "folderB", -33L, null, 0)
        }
        val (end, seen) = read(data)
        assertEquals(data.size.toLong(), end)
        assertEquals(listOf(11L, 22L, 22L, -33L), seen.map { it.key })
        assertEquals(listOf(false, true, true, false), seen.map { it.video })
        assertEquals("content://äö/3", seen.last().uri)
    }

    @Test
    fun aHalfWrittenLastRecordIsLeftForNextTime() {
        val whole = bytes {
            record(it, "u1", "f", 1L, null, 0)
            record(it, "u2", "f", 2L, null, 0)
        }
        val one = bytes { record(it, "u1", "f", 1L, null, 0) }
        val cut = whole.copyOf(whole.size - 5)
        val (end, seen) = read(cut)
        assertEquals(one.size.toLong(), end)
        assertEquals(listOf(1L), seen.map { it.key })
        // Next time, from where it stopped, the rest is read.
        val (end2, seen2) = read(whole.copyOfRange(one.size, whole.size), start = end)
        assertEquals(whole.size.toLong(), end2)
        assertEquals(listOf(2L), seen2.map { it.key })
    }

    @Test
    fun nothingNewGivesTheSamePosition() {
        val (end, seen) = read(ByteArray(0), start = 777)
        assertEquals(777L, end)
        assertEquals(0, seen.size)
    }

    @Test
    fun bytesThatAreNotRecordsAreRefusedNotGuessedAt() {
        val garbage = bytes { it.writeInt(Int.MAX_VALUE); it.writeInt(5) }
        assertEquals(-1L, read(garbage).first)
    }
}
