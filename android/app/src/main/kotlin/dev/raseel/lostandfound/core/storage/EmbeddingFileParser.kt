package dev.raseel.lostandfound.core.storage

import java.nio.ByteBuffer
import java.nio.channels.ReadableByteChannel

/**
 * Reads the records of the embeddings file (layout in [EmbeddingStore.writeRecord]).
 *
 * It exists because reading the file a number at a time through a stream took seconds for a library of ten thousand
 * photos, and everything the app shows at its start waits for that read. Here the file is read in large pieces into a
 * buffer, and the 2 KB of an embedding are made into numbers in plain code. The file is not memory-mapped, because a
 * mapping stays until the garbage collector lets it go, and a big file can fail to map on a phone that is short of
 * address space. A view of the buffer as floats is not used either, because it reads at addresses that are not a
 * multiple of four, which not every phone does safely.
 */
object EmbeddingFileParser {
    /** The most a path or an address may take. A length beyond it means the bytes are not records. */
    private const val MAX_FIELD_BYTES = 1 shl 20

    /** How much of the file is read at a time. More than the largest record can be (three fields of the most, and the embedding). */
    const val CHUNK_BYTES = 4 shl 20

    /**
     * Reads the records from [channel], which is at the first record, into [out], and returns how many bytes at the end
     * were not a whole record: a half-written record from a process that was killed while it was adding, which is left
     * out. A length that cannot be right throws, so that the caller treats the file as damaged.
     */
    fun readRecords(
        channel: ReadableByteChannel,
        embeddingDim: Int,
        out: MutableList<EmbeddingRecord>,
        chunkBytes: Int = CHUNK_BYTES,
    ): Long {
        val buf = ByteBuffer.allocate(chunkBytes)
        while (true) {
            var ended = false
            while (buf.hasRemaining()) {
                if (channel.read(buf) < 0) {
                    ended = true
                    break
                }
            }
            buf.flip()
            val before = buf.position()
            val added = out.size
            parse(buf, embeddingDim, out)
            if (ended) return buf.remaining().toLong()
            if (buf.position() == before && out.size == added) throw IllegalStateException("A record is larger than $chunkBytes bytes")
            buf.compact()
        }
    }

    /**
     * Reads the whole records that [buf] holds, from its position to its limit, into [out], and leaves its position at
     * the first byte that is not part of a whole record. The buffer has to be big-endian, as a new one is.
     */
    fun parse(buf: ByteBuffer, embeddingDim: Int, out: MutableList<EmbeddingRecord>) {
        val embeddingBytes = embeddingDim * 4
        val raw = ByteArray(embeddingBytes)

        while (buf.remaining() > 0) {
            val start = buf.position()

            fun bytes(): ByteArray? {
                if (buf.remaining() < 4) return null
                val length = buf.getInt()
                if (length < 0 || length > MAX_FIELD_BYTES) throw IllegalStateException("A length of $length is not a record")
                if (buf.remaining() < length) return null
                return ByteArray(length).also { buf.get(it) }
            }

            val path = bytes()
            val folder = if (path == null) null else bytes()
            if (folder == null || buf.remaining() < 8) {
                buf.position(start)
                return
            }
            val hash = buf.getLong()
            val video = bytes()
            if (video == null || buf.remaining() < 8 + embeddingBytes) {
                buf.position(start)
                return
            }
            val timestampMs = buf.getLong()
            buf.get(raw)
            val embedding = FloatArray(embeddingDim)
            var at = 0
            for (i in 0 until embeddingDim) {
                val bits = ((raw[at].toInt() and 0xFF) shl 24) or ((raw[at + 1].toInt() and 0xFF) shl 16) or
                    ((raw[at + 2].toInt() and 0xFF) shl 8) or (raw[at + 3].toInt() and 0xFF)
                embedding[i] = java.lang.Float.intBitsToFloat(bits)
                at += 4
            }

            out.add(
                EmbeddingRecord(
                    imagePath = String(path!!, Charsets.UTF_8),
                    hash = hash,
                    embedding = embedding,
                    folderId = String(folder, Charsets.UTF_8),
                    videoUri = String(video, Charsets.UTF_8).ifEmpty { null },
                    timestampMs = timestampMs,
                )
            )
        }
    }
}
