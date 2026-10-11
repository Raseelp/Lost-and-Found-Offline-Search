package dev.twentyonevision.app.embedder

import android.content.Context
import android.util.Log
import java.io.File

/**
 * The items the latest indexing scan stored, so the app can tag them as new.
 *
 * A scan collects the items it stores as it goes ([add]) and, when it ends (it ran to its end,
 * or the user stopped it), they become the latest scan's items ([finish]). A scan that stored
 * nothing leaves the previous ones alone. The app takes them once with [take]; after that they
 * are gone from here, so opening the app from scratch later shows no tags.
 *
 * The scan runs in the background and may end while the app is closed (or may be restarted by
 * the system part-way), so the items are also kept in two small files in the app's own storage:
 * the ones of the scan still running (so a restarted scan carries on with the same list) and the
 * finished ones until the app has taken them.
 */
object LatestScan {
    private const val TAG = "LatestScan"
    private const val RUNNING_FILE = "latest_scan_running.txt"
    private const val READY_FILE = "latest_scan_ready.txt"

    private val lock = Any()

    // Guarded by [lock]: the running scan's items, the ones not yet in its file, and the
    // finished items waiting for the app to take them.
    private val keys = LinkedHashSet<String>()
    private val unwritten = ArrayList<String>()
    private var ready: List<String>? = null

    /** A scan starts. [resume]: the system restarted it, so it carries on with the same items. */
    fun begin(context: Context, resume: Boolean): Unit = synchronized(lock) {
        keys.clear()
        unwritten.clear()
        val running = File(context.filesDir, RUNNING_FILE)
        if (resume && running.exists()) {
            try {
                running.forEachLine { if (it.isNotEmpty()) keys.add(it) }
            } catch (e: Exception) {
                Log.w(TAG, "begin: the running list could not be read (${e.message})")
            }
        } else {
            running.delete()
        }
    }

    /** Items the scan has just stored. */
    fun add(uris: Collection<String>): Unit = synchronized(lock) {
        for (uri in uris) {
            // A line per item; a name with a line break in it cannot be kept, and cannot be a uri.
            if (uri.isEmpty() || uri.indexOf('\n') >= 0) continue
            if (keys.add(uri)) unwritten.add(uri)
        }
    }

    /** Writes the items stored since the last time to the running scan's file. */
    fun flush(context: Context): Unit = synchronized(lock) {
        if (unwritten.isEmpty()) return@synchronized
        try {
            File(context.filesDir, RUNNING_FILE).appendText(unwritten.joinToString("\n", postfix = "\n"))
            unwritten.clear()
        } catch (e: Exception) {
            Log.w(TAG, "flush: ${e.message}")
        }
    }

    /** The scan has ended: what it stored is now the latest scan's items (if it stored any). */
    fun finish(context: Context): Unit = synchronized(lock) {
        val running = File(context.filesDir, RUNNING_FILE)
        if (keys.isEmpty()) {
            running.delete()
            return@synchronized
        }
        val list = keys.toList()
        ready = list
        try {
            val temp = File(context.filesDir, "$READY_FILE.tmp")
            temp.writeText(list.joinToString("\n"))
            val target = File(context.filesDir, READY_FILE)
            target.delete()
            if (!temp.renameTo(target)) temp.delete()
        } catch (e: Exception) {
            Log.w(TAG, "finish: the list could not be saved (${e.message})")
        }
        keys.clear()
        unwritten.clear()
        running.delete()
    }

    /** The latest scan's items, if the app has not taken them yet; they are not kept after this. */
    fun take(context: Context): List<String> = synchronized(lock) {
        val file = File(context.filesDir, READY_FILE)
        val list = ready ?: try {
            if (file.exists()) file.readLines().filter { it.isNotEmpty() } else emptyList()
        } catch (e: Exception) {
            Log.w(TAG, "take: ${e.message}")
            emptyList()
        }
        ready = null
        file.delete()
        list
    }
}
