package dev.raseel.lostandfound.core.storage

import java.io.DataInputStream
import java.io.EOFException
import java.io.InputStream

/**
 * Reads what is in the embedding records except the embeddings themselves (layout in [EmbeddingStore.writeRecord]):
 * the key, where to read the file, and whether it is a video. The embedding and the unneeded fields are skipped with a
 * seek, so a library of a hundred thousand photos goes by in a moment and memory does not grow with it.
 */
object EmbeddingMetaReader {
    private const val MAX_FIELD_BYTES = 1 shl 20

    /**
     * Reads the records from [input], at a record boundary [startPos] bytes into the file, and calls [onRecord] for
     * each whole record. Returns the position after the last one (a half-written record is left for next time), or -1
     * when the bytes do not look like records, so the position is not a boundary. The 8 bytes after the video field
     * are the time of the video frame.
     */
    fun read(input: InputStream, startPos: Long, embeddingDim: Int, onRecord: (key: Long, uri: String, video: Boolean) -> Unit): Long {
        val data = DataInputStream(input)
        val embeddingBytes = embeddingDim * 4L
        var pos = startPos

        fun skip(n: Long) {
            var left = n
            while (left > 0) {
                val skipped = data.skip(left)
                if (skipped <= 0) {
                    if (data.read() < 0) throw EOFException()
                    left -= 1
                } else {
                    left -= skipped
                }
            }
        }

        while (true) {
            try {
                var size = 0L
                val pathLength = data.readInt()
                if (pathLength !in 0..MAX_FIELD_BYTES) return -1L
                val pathBytes = ByteArray(pathLength)
                data.readFully(pathBytes)
                size += 4 + pathLength

                val folderLength = data.readInt()
                if (folderLength !in 0..MAX_FIELD_BYTES) return -1L
                skip(folderLength.toLong())
                size += 4 + folderLength

                val hash = data.readLong()
                size += 8

                val videoLength = data.readInt()
                if (videoLength !in 0..MAX_FIELD_BYTES) return -1L
                skip(videoLength.toLong())
                size += 4 + videoLength

                skip(8)
                skip(embeddingBytes)
                size += 8 + embeddingBytes

                onRecord(hash, String(pathBytes, Charsets.UTF_8), videoLength > 0)
                pos += size
            } catch (_: EOFException) {
                return pos
            }
        }
    }
}
