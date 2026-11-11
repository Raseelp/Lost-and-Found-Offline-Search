package dev.raseel.lostandfound.core.log

import java.io.File

/**
 * The app's own log on disk: one file that is written to, and the one before it. When the file passes [maxBytes] it
 * becomes the older one and a new one starts, so the log never takes more than about twice that.
 */
class RollingLogFile(private val folder: File, private val maxBytes: Long = DEFAULT_MAX_BYTES) {

    private val current = File(folder, "app.log")
    private val older = File(folder, "app.log.1")

    @Synchronized
    fun append(lines: List<String>) {
        if (lines.isEmpty()) return
        folder.mkdirs()
        if (current.length() >= maxBytes) {
            older.delete()
            current.renameTo(older)
        }
        current.appendText(lines.joinToString(separator = "\n", postfix = "\n"))
    }

    /** The newest [max] lines, oldest first. */
    @Synchronized
    fun recentLines(max: Int): List<String> {
        val all = ArrayList<String>()
        for (file in listOf(older, current)) {
            if (file.exists()) all += file.readLines()
        }
        return if (all.size > max) all.subList(all.size - max, all.size) else all
    }

    companion object {
        const val DEFAULT_MAX_BYTES = 512L * 1024
    }
}
