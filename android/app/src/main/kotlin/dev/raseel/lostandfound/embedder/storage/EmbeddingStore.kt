package dev.raseel.lostandfound.embedder.storage

import android.content.Context
import android.util.Log
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

    // Cache of the last readAll(); cleared on every write.
    @Volatile
    private var cachedRecords: List<EmbeddingRecord>? = null

    // Guards every read and write below. Search can now run at the same
    // time as a scan (its own thread - see MainActivity), and a search's
    // readAll() racing a scan's appendBatch() on the same underlying file
    // is exactly the kind of thing that corrupts data without ever
    // throwing. A single lock keeps this simple and obviously correct;
    // reads and writes are already fast, so there's no real cost to not
    // letting two reads run truly in parallel.
    private val lock = Any()

    companion object {
        private const val TAG = "EmbeddingStore"
        private const val MAGIC = 0x454D4244  // "EMBD"
        private const val VERSION = 3          // bumped: the header now says which model made the vectors
        private const val EMBEDDING_DIM = 512
        private const val HEADER_BYTES = 16L

        // Which model made the vectors in a file. Vectors of different models cannot be compared, so a file
        // made by another model is dropped (see dropIfOtherModel). Raise it whenever the search model, or how a
        // photo is prepared for it, changes.
        //   1: OpenAI CLIP ViT-B/32 (every file up to version 2 - those have no id in the header)
        //   2: Apple MobileCLIP-S2, 2024 weights, image tower fp16 (gave NaN on a real phone: never shipped to anyone)
        //   3: Apple MobileCLIP-S0, 2024 weights (image tower fp32, text tower int8), 256 px
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
                input.readInt() // the vector size
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

    // An index made by another model is of no use to this one and is not worth keeping a copy of (unlike a damaged
    // file, which readAll() sets aside): it is removed and the library has to be scanned again. People and their
    // faces are kept elsewhere and are not touched. What it was made by is remembered, so the app can say why.
    private fun dropIfOtherModel() {
        val madeBy = try {
            val header = ByteArray(minOf(HEADER_BYTES, storeFile.length()).toInt())
            DataInputStream(storeFile.inputStream()).use { it.readFully(header) }
            modelOfHeader(header)
        } catch (e: Exception) {
            null
        }
        // Not readable as an index at all is for readAll() to deal with, as before.
        if (madeBy == null || madeBy == MODEL_ID) return
        Log.i(TAG, "the index was made by model $madeBy, this app uses $MODEL_ID: starting a new one")
        storeFile.delete()
        createNewStore()
        prefs.edit().putInt(KEY_RESET_FROM, madeBy).apply()
        bumpGeneration()
    }

    /** The model that made the index which was dropped because the app now uses another one, or 0 if none was. */
    fun modelResetFrom(): Int = prefs.getInt(KEY_RESET_FROM, 0)

    /** The person has been told; forget it. */
    fun clearModelReset() {
        prefs.edit().remove(KEY_RESET_FROM).apply()
    }

    // The new index has begun to fill: there is nothing left to tell the person to do.
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
            cachedRecords = null
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
            cachedRecords = null
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

    // Tolerates a truncated trailing record (process killed mid-append) by
    // keeping everything before it, and a bad header by quarantining the
    // file and starting fresh - either way, callers never crash on this.
    fun readAll(): List<EmbeddingRecord> = synchronized(lock) {
        cachedRecords?.let { return@synchronized it }

        val records = mutableListOf<EmbeddingRecord>()

        try {
            DataInputStream(
                BufferedInputStream(storeFile.inputStream())
            ).use { input ->

                val magic = input.readInt()
                if (magic != MAGIC) throw IllegalStateException("Invalid embedding file header")

                val version = input.readInt()
                if (version != VERSION) {
                    throw IllegalStateException("Unsupported embedding store version: $version")
                }

                val dim = input.readInt()
                if (dim != EMBEDDING_DIM) throw IllegalStateException("Embedding dim mismatch")

                val model = input.readInt()
                if (model != MODEL_ID) throw IllegalStateException("Embedding model mismatch: $model")

                while (input.available() > 0) {
                    try {
                        val pathLength = input.readInt()
                        val pathBytes = ByteArray(pathLength)
                        input.readFully(pathBytes)
                        val path = String(pathBytes, Charsets.UTF_8)

                        val folderIdLength = input.readInt()
                        val folderIdBytes = ByteArray(folderIdLength)
                        input.readFully(folderIdBytes)
                        val folderId = String(folderIdBytes, Charsets.UTF_8)

                        val hash = input.readLong()

                        val videoUriLength = input.readInt()
                        val videoUriBytes = ByteArray(videoUriLength)
                        input.readFully(videoUriBytes)
                        val videoUri = String(videoUriBytes, Charsets.UTF_8).ifEmpty { null }

                        val timestampMs = input.readLong()

                        val embedding = FloatArray(EMBEDDING_DIM)
                        for (i in 0 until EMBEDDING_DIM) {
                            embedding[i] = input.readFloat()
                        }

                        records.add(
                            EmbeddingRecord(
                                imagePath = path,
                                hash = hash,
                                embedding = embedding,
                                folderId = folderId,
                                videoUri = videoUri,
                                timestampMs = timestampMs
                            )
                        )
                    } catch (e: EOFException) {
                        Log.w(TAG, "readAll: truncated trailing record, keeping ${records.size} good records")
                        break
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "readAll: store unreadable (${e.message}), resetting", e)
            quarantineAndReset()
            return@synchronized emptyList()
        }

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

    // A plain stat() call, not a read of the file's contents - cheap
    // enough to call as often as the library stats need it.
    fun sizeBytes(): Long = try { storeFile.length() } catch (e: Exception) { 0L }

    // Writes to a temp file and renames over the original so a crash
    // mid-write can't leave embeddings.bin half-written.
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
                // Some filesystems refuse to rename over an existing file -
                // fall back to delete-then-rename.
                storeFile.delete()
                tempFile.renameTo(storeFile)
            }

            cachedRecords = null
            bumpGeneration()
        }
    }

    // ---- a light read of what is in the store (for the dates of everything indexed) ----

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
     * Goes through the records from byte [from] on (a record boundary this returned before, or 0) and
     * gives each one's key and where to read it - never its embedding, which is skipped with a seek,
     * so a whole library takes a moment and no memory. A video's frames are one entry each time, with
     * [video] true. Returns the byte position after the last whole record (a half-written one at the end
     * is left for next time), or -1 when [from] is not somewhere in this file (it has been rewritten).
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
            Log.w(TAG, "scanMeta failed: ${e.message}")
            -1L
        }
    }
}
