package dev.raseel.lostandfound.features.library

import android.content.Context
import dev.raseel.lostandfound.core.log.AppLog
import java.io.File

/** One photo or video that a run of automatic indexing stored. */
class AutoShownItem(val uri: String, val video: Boolean)

/** What the app is given once: how many photos and videos were indexed by themselves, and a few of them to show. */
class AutoShownBatch(val photos: Int, val videos: Int, val items: List<AutoShownItem>)

/**
 * What automatic indexing stored since the app last asked, for the card on the Search tab that tells the person about
 * them. The counts are all of it, and only a handful of items are kept to show. The app takes it once, when it opens, so
 * a batch is shown in one visit and not in the next. It is kept in a small file, because a run may end while the app is
 * closed.
 */
object AutoShown {
    private const val TAG = "AutoShown"
    private const val FILE = "auto_shown.txt"
    private const val MAX_ITEMS = 24

    private val lock = Any()

    /**
     * Adds what a run stored. Newest first, and photos and videos alternate, so that a few videos among many photos are
     * not pushed out of what is shown.
     */
    fun add(context: Context, photos: List<String>, videos: List<String>) {
        if (photos.isEmpty() && videos.isEmpty()) return
        val fresh = ArrayList<AutoShownItem>()
        var p = 0
        var v = 0
        while (p < photos.size || v < videos.size) {
            if (p < photos.size) fresh.add(AutoShownItem(photos[p++], false))
            if (v < videos.size) fresh.add(AutoShownItem(videos[v++], true))
        }
        synchronized(lock) {
            val before = read(context)
            val items = (fresh + before.items).take(MAX_ITEMS)
            write(context, AutoShownBatch(before.photos + photos.size, before.videos + videos.size, items))
        }
    }

    /** What was stored since the last call, which is then forgotten. */
    fun take(context: Context): AutoShownBatch = synchronized(lock) {
        val batch = read(context)
        File(context.filesDir, FILE).delete()
        batch
    }

    /** Forgets what was stored, because the index it is about was cleared. */
    fun clear(context: Context): Unit = synchronized(lock) {
        File(context.filesDir, FILE).delete()
    }

    /** The file: the number of photos, the number of videos, then one item per line as P or V, a tab and the address. */
    private fun read(context: Context): AutoShownBatch {
        val file = File(context.filesDir, FILE)
        if (!file.exists()) return AutoShownBatch(0, 0, emptyList())
        return try {
            val lines = file.readLines()
            val items = lines.drop(2).mapNotNull { line ->
                val tab = line.indexOf('\t')
                if (tab != 1 || tab == line.length - 1) null else AutoShownItem(line.substring(2), line[0] == 'V')
            }
            AutoShownBatch(lines[0].toInt(), lines[1].toInt(), items)
        } catch (e: Exception) {
            AppLog.w(TAG, "read: ${e.message}")
            AutoShownBatch(0, 0, emptyList())
        }
    }

    /** An address with a line break in it is left out, because the file holds one item per line. */
    private fun write(context: Context, batch: AutoShownBatch) {
        try {
            val lines = ArrayList<String>()
            lines.add(batch.photos.toString())
            lines.add(batch.videos.toString())
            for (item in batch.items) {
                if (item.uri.indexOf('\n') >= 0 || item.uri.indexOf('\r') >= 0) continue
                lines.add((if (item.video) "V" else "P") + "\t" + item.uri)
            }
            File(context.filesDir, FILE).writeText(lines.joinToString("\n"))
        } catch (e: Exception) {
            AppLog.w(TAG, "write: ${e.message}")
        }
    }
}
