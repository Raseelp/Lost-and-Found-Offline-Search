package dev.raseel.lostandfound.embedder.storage

import java.io.DataInputStream
import java.io.EOFException
import java.io.InputStream

/**
 * Reads what is in the embedding records except the embeddings themselves (see
 * [EmbeddingStore.writeRecord] for the layout): the key, where to read the file, whether it is a
 * video. The embedding (and the fields that are not needed) are skipped with a seek, so a library of
 * a hundred thousand photos goes by in a moment and the memory used does not grow with it.
 */
object EmbeddingMetaReader {
    private const val MAX_FIELD_BYTES = 1 shl 20

    /**
     * [input] is positioned at a record boundary, [startPos] bytes into the file. Calls [onRecord] for each
     * whole record and returns the position after the last one (a half-written record at the end is left
     * for next time), or -1 when the bytes do not look like records (a position that is not a boundary).
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

                skip(8) // the video frame's time
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
