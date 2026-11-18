package dev.raseel.lostandfound.core.storage

import dev.raseel.lostandfound.core.log.AppLog
import android.content.Context
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.EOFException
import java.io.File
import java.io.FileOutputStream

class EmbeddingStore(private val context: Context) {

    private val storeFile: File =
        File(context.filesDir, "embeddings.bin")

    /**
     * Cache of the last readAll(). A write adds what it wrote to it, so that the file is not read again after every
     * batch of a scan, and a change that rewrites the file clears it.
     */
    @Volatile
    private var cachedRecords: List<EmbeddingRecord>? = null

    /**
     * Guards every read and write below. Search runs on its own thread (see SearchChannel) at the same time as a scan,
     * and a search's readAll() racing a scan's appendBatch() on the same file could corrupt data without throwing. One
     * lock is simple and enough, because reads and writes are fast.
     */
    private val lock = Any()

    companion object {
        private const val TAG = "EmbeddingStore"
        private const val MAGIC = 0x454D4244
        private const val VERSION = 3
        private const val EMBEDDING_DIM = 512
        private const val HEADER_BYTES = 16L

        /**
         * Which model made the vectors in a file. Vectors of different models cannot be compared, so a file made by
         * another model is dropped (see [dropIfOtherModel]). Raise it whenever the search model, or how a photo is
         * prepared for it, changes. Ids 1 (OpenAI CLIP ViT-B/32, also every file before version 3) and 2
         * (MobileCLIP-S2) are taken.
         */
        const val MODEL_ID = 3
        private const val OLD_FILES_MODEL_ID = 1
        private const val KEY_RESET_FROM = "model_reset_from"

        /**
         * The model that made the vectors of an index file whose first bytes are [header] (a file of version 2 or
         * earlier says nothing and was always made by model 1), or null if it is not an index file at all.
         */
        internal fun modelOfHeader(header: ByteArray): Int? {
            val input = DataInputStream(header.inputStream())
            return try {
                if (input.readInt() != MAGIC) return null
                val version = input.readInt()
                input.readInt()
                if (version >= 3) input.readInt() else OLD_FILES_MODEL_ID
            } catch (_: EOFException) {
                null
            }
        }
    }

    init {
        if (!storeFile.exists()) {
            createNewStore()
        } else {
            dropIfOtherModel()
        }
    }

    private fun createNewStore() {
        DataOutputStream(
            BufferedOutputStream(FileOutputStream(storeFile, false))
        ).use { out ->
            out.writeInt(MAGIC)
            out.writeInt(VERSION)
            out.writeInt(EMBEDDING_DIM)
            out.writeInt(MODEL_ID)
        }
        cachedRecords = null
    }

    /**
     * An index made by another model is no use to this one and not worth a copy (unlike a damaged file, which
     * readAll() sets aside): it is removed and the library has to be scanned again. People and faces are kept
     * elsewhere. The model is remembered so the app can say why. A file that is not an index at all is left to
     * readAll().
     */
    private fun dropIfOtherModel() {
        val madeBy = try {
            val header = ByteArray(minOf(HEADER_BYTES, storeFile.length()).toInt())
            DataInputStream(storeFile.inputStream()).use { it.readFully(header) }
            modelOfHeader(header)
        } catch (e: Exception) {
            null
        }
        if (madeBy == null || madeBy == MODEL_ID) return
        AppLog.i(TAG, "the index was made by model $madeBy, this app uses $MODEL_ID: starting a new one")
        storeFile.delete()
        createNewStore()
        prefs.edit().putInt(KEY_RESET_FROM, madeBy).apply()
        bumpGeneration()
    }

    /** The model that made the index which was dropped because the app uses another one, or 0 if none was. */
    fun modelResetFrom(): Int = prefs.getInt(KEY_RESET_FROM, 0)

    /** The person has been told; forget it. */
    fun clearModelReset() {
        prefs.edit().remove(KEY_RESET_FROM).apply()
    }

    /** The index has begun to fill again: there is nothing left to tell the person to do. */
    private fun noteScanned() {
        if (modelResetFrom() != 0) clearModelReset()
    }

    fun append(record: EmbeddingRecord) {
        require(record.embedding.size == EMBEDDING_DIM) {
            "Embedding must be $EMBEDDING_DIM dimensions"
        }
        synchronized(lock) {
            DataOutputStream(
                BufferedOutputStream(FileOutputStream(storeFile, true))
            ).use { out ->
                writeRecord(out, record)
            }
            cachedRecords = cachedRecords?.plus(record)
            noteScanned()
        }
    }

    fun appendBatch(records: List<EmbeddingRecord>) {
        if (records.isEmpty()) return
        for (record in records) {
            require(record.embedding.size == EMBEDDING_DIM) {
                "Embedding must be $EMBEDDING_DIM dimensions"
            }
        }
        synchronized(lock) {
            DataOutputStream(
                BufferedOutputStream(FileOutputStream(storeFile, true))
            ).use { out ->
                for (record in records) {
                    writeRecord(out, record)
                }
            }
            cachedRecords = cachedRecords?.plus(records)
            noteScanned()
        }
    }

    private fun writeRecord(out: DataOutputStream, record: EmbeddingRecord) {
        val pathBytes = record.imagePath.toByteArray(Charsets.UTF_8)
        out.writeInt(pathBytes.size)
        out.write(pathBytes)

        val folderIdBytes = record.folderId.toByteArray(Charsets.UTF_8)
        out.writeInt(folderIdBytes.size)
        out.write(folderIdBytes)

        out.writeLong(record.hash)

        val videoUriBytes = (record.videoUri ?: "").toByteArray(Charsets.UTF_8)
        out.writeInt(videoUriBytes.size)
        out.write(videoUriBytes)

        out.writeLong(record.timestampMs)

        for (v in record.embedding) {
            out.writeFloat(v)
        }
    }

    /**
     * Tolerates a truncated trailing record (process killed mid-append) by keeping everything before it, and a bad
     * header by quarantining the file and starting fresh. Callers never crash on this.
     */
    fun readAll(): List<EmbeddingRecord> = synchronized(lock) {
        cachedRecords?.let { return@synchronized it }

        val records = ArrayList<EmbeddingRecord>()
        val startedMs = android.os.SystemClock.elapsedRealtime()

        try {
            java.io.RandomAccessFile(storeFile, "r").use { raf ->
                val channel = raf.channel
                val header = java.nio.ByteBuffer.allocate(HEADER_BYTES.toInt())
                while (header.hasRemaining() && channel.read(header) >= 0) {
                    // Fills the header. A file that ends before it is full is not a store.
                }
                if (header.hasRemaining()) throw IllegalStateException("Invalid embedding file header")
                header.flip()
                if (header.getInt() != MAGIC) throw IllegalStateException("Invalid embedding file header")
                val version = header.getInt()
                if (version != VERSION) throw IllegalStateException("Unsupported embedding store version: $version")
                if (header.getInt() != EMBEDDING_DIM) throw IllegalStateException("Embedding dim mismatch")
                val model = header.getInt()
                if (model != MODEL_ID) throw IllegalStateException("Embedding model mismatch: $model")

                val leftover = EmbeddingFileParser.readRecords(channel, EMBEDDING_DIM, records)
                if (leftover > 0) AppLog.w(TAG, "readAll: truncated trailing record, keeping ${records.size} good records")
            }
        } catch (e: Exception) {
            AppLog.e(TAG, "readAll: store unreadable (${e.message}), resetting", e)
            quarantineAndReset()
            return@synchronized emptyList()
        }

        AppLog.i(TAG, "readAll: ${records.size} records in ${android.os.SystemClock.elapsedRealtime() - startedMs} ms")
        cachedRecords = records
        records
    }

    private fun quarantineAndReset() {
        try {
            val backup = File(context.filesDir, "embeddings.bin.corrupt-${System.currentTimeMillis()}")
            storeFile.copyTo(backup, overwrite = true)
        } catch (_: Exception) {
        }
        createNewStore()
        bumpGeneration()
    }

    fun clear() {
        synchronized(lock) {
            storeFile.delete()
            createNewStore()
            bumpGeneration()
        }
    }

    fun countForFolder(folderId: String): Int =
        readAll().count { it.folderId == folderId }

    /**
     * The file's size from a plain stat(), not a read of its contents, so it is cheap enough to call as often as the
     * library stats need.
     */
    fun sizeBytes(): Long = try { storeFile.length() } catch (e: Exception) { 0L }

    /**
     * Writes to a temp file and renames over the original so a crash mid-write cannot leave embeddings.bin
     * half-written. Some filesystems refuse to rename over an existing file, so it falls back to delete then rename.
     */
    fun deleteByFolderId(folderId: String) {
        synchronized(lock) {
            val remaining = readAll().filter { it.folderId != folderId }
            val tempFile = File(context.filesDir, "embeddings.bin.tmp")

            DataOutputStream(
                BufferedOutputStream(FileOutputStream(tempFile, false))
            ).use { out ->
                out.writeInt(MAGIC)
                out.writeInt(VERSION)
                out.writeInt(EMBEDDING_DIM)
                out.writeInt(MODEL_ID)

                for (record in remaining) {
                    writeRecord(out, record)
                }
            }

            if (!tempFile.renameTo(storeFile)) {
                storeFile.delete()
                tempFile.renameTo(storeFile)
            }

            cachedRecords = null
            bumpGeneration()
        }
    }

    private val prefs get() = context.getSharedPreferences("embedding_store", Context.MODE_PRIVATE)

    /**
     * Changes whenever the file is rewritten rather than only added to (a folder removed, everything
     * cleared, a damaged file reset): byte positions from before are then no good.
     */
    fun generation(): Long = prefs.getLong("generation", 0L)

    private fun bumpGeneration() {
        prefs.edit().putLong("generation", generation() + 1).apply()
    }

    /**
     * Calls [onRecord] with each record's key and where to read it, from byte [from] on (a record boundary this
     * returned before, or 0). Embeddings are skipped with a seek, so a whole library takes a moment and no memory. A
     * video's frames are one entry each time, with [video] true. Returns the position after the last whole record, or
     * -1 when [from] is not in this file because it was rewritten.
     */
    fun scanMeta(from: Long, onRecord: (key: Long, uri: String, video: Boolean) -> Unit): Long = synchronized(lock) {
        try {
            java.io.RandomAccessFile(storeFile, "r").use { file ->
                val length = file.length()
                if (length < HEADER_BYTES) return@synchronized -1L
                file.seek(0)
                if (file.readInt() != MAGIC || file.readInt() != VERSION || file.readInt() != EMBEDDING_DIM ||
                    file.readInt() != MODEL_ID
                ) {
                    return@synchronized -1L
                }
                val pos = if (from < HEADER_BYTES) HEADER_BYTES else from
                if (pos > length) return@synchronized -1L
                file.seek(pos)
                val input = BufferedInputStream(java.io.FileInputStream(file.fd), 1 shl 16)
                EmbeddingMetaReader.read(input, pos, EMBEDDING_DIM, onRecord)
            }
        } catch (e: Exception) {
            AppLog.w(TAG, "scanMeta failed: ${e.message}")
            -1L
        }
    }
}
