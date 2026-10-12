package dev.raseel.lostandfound.export

import java.io.Closeable
import java.io.InputStream
import java.io.OutputStream
import java.util.Calendar
import java.util.TimeZone
import java.util.zip.CRC32

/**
 * Writes one zip file to a stream that cannot seek (a file being created through the system's
 * file pickers, say), one entry at a time, without compressing: the data is stored inside
 * "deflate" blocks of the stored kind, so a file's size and checksum are not needed before it is
 * written (they follow it, in a data descriptor) and every unzip tool reads it.
 *
 * [zip64] is chosen by the caller before the first entry, from what it expects to write: the
 * archive then uses 64-bit sizes and offsets, which it needs once it holds 4 GB or 65,535 files.
 * Plain zip is used otherwise, because it is understood everywhere.
 *
 * Entry names are UTF-8. No Android classes are used, so it can be tested on a plain JVM.
 */
class ZipPartWriter(output: OutputStream, private val zip64: Boolean) : Closeable {

    private class Entry(
        val name: ByteArray,
        val offset: Long,
        val dosTime: Int,
        val dosDate: Int,
    ) {
        var crc = 0L
        var size = 0L
        var compressedSize = 0L
    }

    private val out = output
    private var position = 0L
    private val entries = ArrayList<Entry>()
    private var finished = false

    /** Bytes written to the stream so far. */
    val bytesWritten: Long get() = position

    val entryCount: Int get() = entries.size

    /**
     * Adds [name] (with '/' between folders) holding everything [input] gives. [modifiedMs] is
     * stored as the file's date. [onBytes] is told about each chunk as it is copied, and may
     * throw to stop. Returns how many bytes of data the file had.
     */
    fun addFile(name: String, modifiedMs: Long, input: InputStream, onBytes: (Int) -> Unit = {}): Long {
        check(!finished) { "the zip is finished" }
        val entry = begin(name, modifiedMs)
        val crc = CRC32()
        var size = 0L
        var compressed = 0L

        // One chunk is held back so the last block can be marked as the last.
        var held = ByteArray(BLOCK)
        var heldLength = readChunk(input, held)
        var next = ByteArray(BLOCK)
        while (true) {
            val nextLength = if (heldLength == BLOCK) readChunk(input, next) else 0
            val last = nextLength <= 0
            crc.update(held, 0, heldLength)
            size += heldLength
            compressed += writeStoredBlock(held, heldLength, last)
            onBytes(heldLength)
            if (last) break
            val swap = held
            held = next
            next = swap
            heldLength = nextLength
        }
        end(entry, crc.value, size, compressed)
        return size
    }

    /** Adds a small file held in memory. */
    fun addBytes(name: String, modifiedMs: Long, data: ByteArray) {
        addFile(name, modifiedMs, data.inputStream())
    }

    /** Writes the index at the end of the file. The stream is left open. */
    fun finish() {
        if (finished) return
        finished = true
        val directoryStart = position
        for (entry in entries) writeCentralHeader(entry)
        val directorySize = position - directoryStart

        if (zip64) {
            val recordStart = position
            // Zip64 end of central directory record.
            u32(0x06064b50)
            u64(44)
            u16(45)
            u16(45)
            u32(0)
            u32(0)
            u64(entries.size.toLong())
            u64(entries.size.toLong())
            u64(directorySize)
            u64(directoryStart)
            // Its locator.
            u32(0x07064b50)
            u32(0)
            u64(recordStart)
            u32(1)
            // The ordinary end record, with the fields that no longer fit marked as such.
            u32(0x06054b50)
            u16(0)
            u16(0)
            u16(0xFFFF)
            u16(0xFFFF)
            u32(0xFFFFFFFFL)
            u32(0xFFFFFFFFL)
            u16(0)
        } else {
            require(entries.size < 0xFFFF && position < 0xFFFFFFFFL) { "too big for a plain zip" }
            u32(0x06054b50)
            u16(0)
            u16(0)
            u16(entries.size)
            u16(entries.size)
            u32(directorySize)
            u32(directoryStart)
            u16(0)
        }
        out.flush()
    }

    override fun close() {
        try {
            if (!finished) finish()
        } finally {
            out.close()
        }
    }

    // ---- an entry ----

    private fun begin(name: String, modifiedMs: Long): Entry {
        val nameBytes = name.toByteArray(Charsets.UTF_8)
        val (dosDate, dosTime) = dos(modifiedMs)
        val entry = Entry(nameBytes, position, dosTime, dosDate)
        entries.add(entry)
        // Local file header. The sizes and checksum follow the data (flag bit 3), so they are
        // zero here; with zip64 the sizes are marked as being in the extra field.
        u32(0x04034b50)
        u16(if (zip64) 45 else 20)
        u16(FLAGS)
        u16(METHOD_DEFLATE)
        u16(dosTime)
        u16(dosDate)
        u32(0)
        u32(if (zip64) 0xFFFFFFFFL else 0)
        u32(if (zip64) 0xFFFFFFFFL else 0)
        u16(nameBytes.size)
        u16(if (zip64) 20 else 0)
        raw(nameBytes, nameBytes.size)
        if (zip64) {
            u16(1)
            u16(16)
            u64(0)
            u64(0)
        }
        return entry
    }

    private fun end(entry: Entry, crc: Long, size: Long, compressed: Long) {
        entry.crc = crc
        entry.size = size
        entry.compressedSize = compressed
        // Data descriptor.
        u32(0x08074b50)
        u32(crc)
        if (zip64) {
            u64(compressed)
            u64(size)
        } else {
            require(compressed < 0xFFFFFFFFL && size < 0xFFFFFFFFL) { "a file is too big for a plain zip" }
            u32(compressed)
            u32(size)
        }
    }

    private fun writeCentralHeader(entry: Entry) {
        val bigOffset = entry.offset >= 0xFFFFFFFFL
        u32(0x02014b50)
        u16(if (zip64) 45 else 20)
        u16(if (zip64) 45 else 20)
        u16(FLAGS)
        u16(METHOD_DEFLATE)
        u16(entry.dosTime)
        u16(entry.dosDate)
        u32(entry.crc)
        if (zip64) {
            u32(0xFFFFFFFFL)
            u32(0xFFFFFFFFL)
        } else {
            u32(entry.compressedSize)
            u32(entry.size)
        }
        u16(entry.name.size)
        u16(if (!zip64) 0 else if (bigOffset) 28 else 20)
        u16(0)
        u16(0)
        u16(0)
        u32(0)
        u32(if (bigOffset) 0xFFFFFFFFL else entry.offset)
        raw(entry.name, entry.name.size)
        if (zip64) {
            u16(1)
            u16(if (bigOffset) 24 else 16)
            u64(entry.size)
            u64(entry.compressedSize)
            if (bigOffset) u64(entry.offset)
        }
    }

    // ---- data ----

    // Fills [buffer] from [input] as far as it will go; the number of bytes it got.
    private fun readChunk(input: InputStream, buffer: ByteArray): Int {
        var got = 0
        while (got < buffer.size) {
            val n = input.read(buffer, got, buffer.size - got)
            if (n < 0) break
            got += n
        }
        return got
    }

    // One block of "stored" deflate data: the data itself, with a five-byte header. Returns how
    // many bytes it took.
    private fun writeStoredBlock(data: ByteArray, length: Int, last: Boolean): Long {
        out.write(if (last) 1 else 0)
        out.write(length and 0xFF)
        out.write(length ushr 8 and 0xFF)
        out.write(length.inv() and 0xFF)
        out.write(length.inv() ushr 8 and 0xFF)
        out.write(data, 0, length)
        position += 5 + length
        return 5L + length
    }

    // ---- low level ----

    private fun raw(bytes: ByteArray, length: Int) {
        out.write(bytes, 0, length)
        position += length
    }

    private fun u16(v: Int) {
        out.write(v and 0xFF)
        out.write(v ushr 8 and 0xFF)
        position += 2
    }

    private fun u32(v: Long) {
        out.write((v and 0xFF).toInt())
        out.write((v ushr 8 and 0xFF).toInt())
        out.write((v ushr 16 and 0xFF).toInt())
        out.write((v ushr 24 and 0xFF).toInt())
        position += 4
    }

    private fun u32(v: Int) = u32(v.toLong() and 0xFFFFFFFFL)

    private fun u64(v: Long) {
        for (shift in 0 until 64 step 8) out.write((v ushr shift and 0xFF).toInt())
        position += 8
    }

    companion object {
        // A stored deflate block holds at most this many bytes.
        private const val BLOCK = 65535
        private const val METHOD_DEFLATE = 8

        // Bit 3: sizes and checksum follow the data. Bit 11: the names are UTF-8.
        private const val FLAGS = 0x0808

        /** A zip's date and time fields for [ms] (local time, 2-second steps, 1980 to 2107). */
        fun dos(ms: Long): Pair<Int, Int> {
            val calendar = Calendar.getInstance(TimeZone.getDefault())
            calendar.timeInMillis = if (ms > 0) ms else System.currentTimeMillis()
            val year = calendar.get(Calendar.YEAR)
            if (year < 1980) return Pair((1 shl 5) or 1, 0)
            val y = minOf(year, 2107) - 1980
            val date = (y shl 9) or ((calendar.get(Calendar.MONTH) + 1) shl 5) or calendar.get(Calendar.DAY_OF_MONTH)
            val time = (calendar.get(Calendar.HOUR_OF_DAY) shl 11) or
                (calendar.get(Calendar.MINUTE) shl 5) or (calendar.get(Calendar.SECOND) / 2)
            return Pair(date, time)
        }
    }
}
