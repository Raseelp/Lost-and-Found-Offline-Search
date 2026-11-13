package dev.raseel.lostandfound.features.library

import android.content.Context
import dev.raseel.lostandfound.core.log.AppLog
import org.json.JSONObject

/**
 * The last progress an indexing scan reported, kept in a small file. When the app is opened again after the scan ended
 * or was cut short while the app was away, this is how it learns how far the scan got and whether it was finished, which
 * the progress stream cannot tell it any more. A scan clears it when it starts, so it is never from an earlier scan.
 */
object LastScanProgress {
    private const val TAG = "LastScanProgress"
    private const val PREFS = "last_scan_progress"
    private const val KEY = "json"
    private const val SAVE_EVERY_MS = 2000L

    private val lock = Any()
    private var savedAt = 0L

    private val numbers = listOf("total", "processed", "embedded", "skipped", "failed", "elapsedMs", "activeMs")

    /** Keeps [map] (a progress payload), at most every couple of seconds, except the last one of a scan, which is always kept. */
    fun save(context: Context, map: Map<String, Any?>) {
        val done = map["done"] == true
        val now = System.currentTimeMillis()
        synchronized(lock) {
            if (!done && now - savedAt < SAVE_EVERY_MS) return
            savedAt = now
            try {
                val json = JSONObject()
                json.put("id", map["id"] as? String ?: "")
                json.put("path", map["path"] as? String ?: "")
                json.put("done", done)
                for (key in numbers) json.put(key, (map[key] as? Number)?.toLong() ?: 0L)
                context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString(KEY, json.toString()).apply()
            } catch (e: Exception) {
                AppLog.w(TAG, "save: ${e.message}")
            }
        }
    }

    /** What was kept as a progress payload, or null when nothing was. */
    fun read(context: Context): Map<String, Any?>? = synchronized(lock) {
        try {
            val raw = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null) ?: return@synchronized null
            val json = JSONObject(raw)
            val out = HashMap<String, Any?>()
            out["id"] = json.optString("id")
            out["path"] = json.optString("path")
            out["done"] = json.optBoolean("done")
            for (key in numbers) out[key] = json.optLong(key)
            out
        } catch (e: Exception) {
            AppLog.w(TAG, "read: ${e.message}")
            null
        }
    }

    /** Forgets it, because a scan is starting or the index was cleared. */
    fun clear(context: Context): Unit = synchronized(lock) {
        savedAt = 0L
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().remove(KEY).apply()
    }
}
