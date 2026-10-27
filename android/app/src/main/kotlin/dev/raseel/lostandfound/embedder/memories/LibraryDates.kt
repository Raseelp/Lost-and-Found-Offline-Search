package dev.raseel.lostandfound.embedder.memories

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.os.SystemClock
import dev.raseel.lostandfound.embedder.EmbeddingEngine
import dev.raseel.lostandfound.embedder.faces.FaceStore
import dev.raseel.lostandfound.embedder.faces.MediaDates

/**
 * When every photo and video in the search index was taken - the catalog behind "on this day".
 *
 * Built to stay cheap however big the library is:
 *  - **Following the index, not re-reading it.** The embedding file only ever grows (until a folder is
 *    removed), so [sync] reads just what was added since last time, from a saved byte position, and
 *    never loads an embedding. A rewrite of the file (a folder removed, everything cleared) is noticed
 *    by its generation number and the catalog is then checked against the whole file once, keeping the
 *    dates already found.
 *  - **Looking dates up a slice at a time.** [resolve] works through the files without a date for a
 *    time budget, so it can be called again and again, and takes the dates the people timeline already
 *    found before reading anything itself.
 *  - **One range scan per past year.** A day is found with the date index, so the cost of "this day in
 *    every year" depends on the years there are, not on the photos there are.
 * Only dates that can be trusted count for a memory (the gallery's taken date, the picture's own, a
 * date in its name): a file's change date is when it was copied, not when it was taken. Screenshots
 * are left out.
 */
class LibraryDates private constructor(context: Context) : SQLiteOpenHelper(context.applicationContext, "library_dates.db", null, 1) {

    class DayPhoto(val key: Long, val uri: String, val video: Boolean, val takenMs: Long)

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """CREATE TABLE days (
                key INTEGER PRIMARY KEY,
                uri TEXT NOT NULL,
                video INTEGER NOT NULL DEFAULT 0,
                taken_ms INTEGER NOT NULL DEFAULT 0,
                src INTEGER NOT NULL DEFAULT -1,
                junk INTEGER NOT NULL DEFAULT 0
            )"""
        )
        // Only what can be used for a memory is in the date index, and only what is still to look up in the other.
        db.execSQL("CREATE INDEX days_taken ON days(taken_ms) WHERE $RELIABLE")
        db.execSQL("CREATE INDEX days_pending ON days(src) WHERE src = -1")
        db.execSQL("CREATE TABLE meta (k TEXT PRIMARY KEY, v TEXT NOT NULL)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {}

    private fun meta(db: SQLiteDatabase, key: String): String? =
        db.rawQuery("SELECT v FROM meta WHERE k = ?", arrayOf(key)).use { if (it.moveToFirst()) it.getString(0) else null }

    private fun setMeta(db: SQLiteDatabase, key: String, value: String) {
        db.execSQL("INSERT OR REPLACE INTO meta(k, v) VALUES (?, ?)", arrayOf(key, value))
    }

    /**
     * Brings the catalog up to date with the search index. Cheap when nothing was added. Returns how
     * many files are in the catalog afterwards.
     */
    @Synchronized
    fun sync(engine: EmbeddingEngine): Int {
        val db = writableDatabase
        val generation = engine.storeGeneration()
        val savedGeneration = meta(db, "generation")?.toLongOrNull()
        var offset = meta(db, "offset")?.toLongOrNull() ?: 0L
        val full = savedGeneration != generation || offset <= 0L
        if (full) offset = 0L

        db.beginTransaction()
        try {
            if (full) {
                db.execSQL("DROP TABLE IF EXISTS temp.seen")
                db.execSQL("CREATE TEMP TABLE seen (key INTEGER PRIMARY KEY)")
            }
            val insert = db.compileStatement("INSERT OR IGNORE INTO days(key, uri, video) VALUES (?, ?, ?)")
            val mark = if (full) db.compileStatement("INSERT OR IGNORE INTO seen(key) VALUES (?)") else null
            val end = engine.scanStoreMeta(offset) { key, uri, video ->
                insert.clearBindings()
                insert.bindLong(1, key)
                insert.bindString(2, uri)
                insert.bindLong(3, if (video) 1 else 0)
                insert.executeInsert()
                if (mark != null) {
                    mark.clearBindings()
                    mark.bindLong(1, key)
                    mark.executeInsert()
                }
            }
            if (end < 0) {
                // Not where a record starts: the file changed under us without a new generation. Everything is looked at again next time.
                setMeta(db, "generation", "-1")
                db.setTransactionSuccessful()
                return count(db)
            }
            if (full) {
                // Files no longer in the index go; the dates of those that stay are kept.
                db.execSQL("DELETE FROM days WHERE key NOT IN (SELECT key FROM temp.seen)")
                db.execSQL("DROP TABLE temp.seen")
            }
            setMeta(db, "generation", generation.toString())
            setMeta(db, "offset", end.toString())
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
        return count(db)
    }

    private fun count(db: SQLiteDatabase): Int =
        db.rawQuery("SELECT COUNT(*) FROM days", null).use { it.moveToFirst(); it.getInt(0) }

    /** Files in the catalog, and how many of them have no date looked up yet. */
    fun progress(): Pair<Int, Int> {
        val db = readableDatabase
        val pending = db.rawQuery("SELECT COUNT(*) FROM days WHERE src = -1", null).use { it.moveToFirst(); it.getInt(0) }
        return count(db) to pending
    }

    /**
     * Looks up dates for files that have none, for up to [budgetMs]: first those the people timeline
     * already knows, then the rest from the gallery, the pictures or their names. Returns how many
     * files are still waiting.
     */
    fun resolve(context: Context, faces: FaceStore, budgetMs: Long): Int {
        val deadline = SystemClock.elapsedRealtime() + budgetMs
        val now = System.currentTimeMillis()
        while (SystemClock.elapsedRealtime() < deadline) {
            val batch = pending(BATCH)
            if (batch.isEmpty()) break
            val known = faces.datesForKeys(batch.map { it.first })
            val rest = batch.filter { it.first !in known }
            val found = HashMap<Long, MediaDates.Found>(known)
            if (rest.isNotEmpty()) found.putAll(MediaDates.resolve(context, rest, now, deadline))
            if (found.isEmpty()) break
            put(found)
        }
        return progress().second
    }

    private fun pending(limit: Int): List<Pair<Long, String>> {
        val out = ArrayList<Pair<Long, String>>(limit)
        readableDatabase.rawQuery("SELECT key, uri FROM days WHERE src = -1 LIMIT ?", arrayOf(limit.toString())).use {
            while (it.moveToNext()) out += it.getLong(0) to it.getString(1)
        }
        return out
    }

    private fun put(found: Map<Long, MediaDates.Found>) {
        val db = writableDatabase
        db.beginTransaction()
        try {
            val stmt = db.compileStatement("UPDATE days SET taken_ms = ?, src = ?, junk = ? WHERE key = ?")
            for ((key, d) in found) {
                stmt.clearBindings()
                stmt.bindLong(1, d.ms)
                stmt.bindLong(2, d.src.toLong())
                stmt.bindLong(3, if (d.junk) 1 else 0)
                stmt.bindLong(4, key)
                stmt.executeUpdateDelete()
            }
            db.setTransactionSuccessful()
        } finally {
            db.endTransaction()
        }
    }

    // ---- what the memories ask ----

    /** The first and last time a trustworthy date was found, or null when there are none. */
    fun bounds(): Pair<Long, Long>? {
        fun edge(order: String): Long? =
            readableDatabase.rawQuery("SELECT taken_ms FROM days WHERE $RELIABLE ORDER BY taken_ms $order LIMIT 1", null).use {
                if (it.moveToFirst()) it.getLong(0) else null
            }
        val first = edge("ASC") ?: return null
        return first to (edge("DESC") ?: first)
    }

    /** When a file was taken (0 when it is not known, or not trustworthy) and whether it is a screenshot or a screen recording. */
    class DateOf(val uri: String, val takenMs: Long, val junk: Boolean)

    /** What the catalog knows about each of [uris] (those it has not got are left out). */
    @Synchronized
    fun datesFor(uris: List<String>): List<DateOf> {
        val out = ArrayList<DateOf>(uris.size)
        // Looked up by file, so the file has its own index (made once, here: the catalog only had one by date).
        if (!uriIndexed) {
            writableDatabase.execSQL("CREATE INDEX IF NOT EXISTS days_uri ON days(uri)")
            uriIndexed = true
        }
        val db = readableDatabase
        for (chunk in uris.chunked(400)) {
            val marks = chunk.joinToString(",") { "?" }
            db.rawQuery("SELECT uri, taken_ms, src, junk FROM days WHERE uri IN ($marks)", chunk.toTypedArray()).use {
                while (it.moveToNext()) {
                    val reliable = it.getInt(2) in 1..3
                    out += DateOf(it.getString(0), if (reliable) it.getLong(1) else 0L, it.getInt(3) == 1)
                }
            }
        }
        return out
    }

    /** How many photos and videos were taken from [startMs] up to [endMs]. */
    fun count(startMs: Long, endMs: Long): Int =
        readableDatabase.rawQuery(
            "SELECT COUNT(*) FROM days WHERE $RELIABLE AND taken_ms >= ? AND taken_ms < ?",
            arrayOf(startMs.toString(), endMs.toString())
        ).use { it.moveToFirst(); it.getInt(0) }

    /** Up to [limit] of the photos and videos taken from [startMs] up to [endMs], in the order taken. */
    fun photos(startMs: Long, endMs: Long, limit: Int): List<DayPhoto> {
        val out = ArrayList<DayPhoto>()
        readableDatabase.rawQuery(
            "SELECT key, uri, video, taken_ms FROM days WHERE $RELIABLE AND taken_ms >= ? AND taken_ms < ? ORDER BY taken_ms LIMIT ?",
            arrayOf(startMs.toString(), endMs.toString(), limit.toString())
        ).use { while (it.moveToNext()) out += DayPhoto(it.getLong(0), it.getString(1), it.getInt(2) == 1, it.getLong(3)) }
        return out
    }

    private var uriIndexed = false

    companion object {
        private const val BATCH = 300

        /** A date that can be believed (see [MediaDates]: taken 1, picture 2, name 3) on something that is not a screenshot. */
        const val RELIABLE = "src IN (1, 2, 3) AND junk = 0"

        @Volatile
        private var instance: LibraryDates? = null

        fun get(context: Context): LibraryDates =
            instance ?: synchronized(this) { instance ?: LibraryDates(context).also { instance = it } }
    }
}
