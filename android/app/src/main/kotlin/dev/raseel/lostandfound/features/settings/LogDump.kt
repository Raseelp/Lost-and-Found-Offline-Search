package dev.raseel.lostandfound.features.settings

import android.content.Context
import android.os.Build
import java.util.concurrent.TimeUnit

/**
 * The app's recent log as one piece of text, for "Copy logs" in Settings, Diagnostics.
 *
 * Android lets an app read only its own log lines, which is what a bug report needs: the
 * app's own messages and, after a crash, why.
 */
object LogDump {
    private const val MAX_LINES = 4000

    /** Well under the 1 MB the clipboard can carry, even if every character takes three bytes. */
    private const val MAX_CHARS = 200_000
    private const val WAIT_SECONDS = 8L

    /** The text to copy: the app and phone, then the newest log lines. Call off the main thread. */
    fun collect(context: Context): String = text(header(context), lines())

    private fun header(context: Context): String {
        val info = try {
            context.packageManager.getPackageInfo(context.packageName, 0)
        } catch (_: Exception) {
            null
        }
        return "Lost & Found log\n" +
            "App: ${info?.versionName ?: "unknown"}\n" +
            "Android: ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})\n" +
            "Phone: ${Build.MANUFACTURER} ${Build.MODEL}\n"
    }

    /**
     * The newest [MAX_LINES] log lines, oldest first.
     *
     * Older lines are dropped as the log is read, so a long log is not held whole. A watchdog ends the reader after
     * [WAIT_SECONDS] in case `logcat -d` does not end by itself, so a tap cannot leave it waiting for good.
     */
    private fun lines(): List<String> {
        val process = ProcessBuilder("logcat", "-d", "-v", "threadtime").redirectErrorStream(true).start()
        val watchdog = Thread {
            try {
                Thread.sleep(TimeUnit.SECONDS.toMillis(WAIT_SECONDS))
                process.destroy()
            } catch (_: InterruptedException) {
            }
        }.apply {
            isDaemon = true
            start()
        }
        try {
            val kept = ArrayDeque<String>()
            process.inputStream.bufferedReader().useLines { all ->
                for (line in all) {
                    kept.addLast(line)
                    if (kept.size > MAX_LINES) kept.removeFirst()
                }
            }
            return kept.toList()
        } finally {
            watchdog.interrupt()
            process.destroy()
        }
    }

    /** [header], then as many of the newest [lines] as fit in [maxChars], saying so when older ones are left out. */
    internal fun text(header: String, lines: List<String>, maxChars: Int = MAX_CHARS): String {
        var used = header.length
        var first = lines.size
        while (first > 0 && used + lines[first - 1].length + 1 <= maxChars) {
            first--
            used += lines[first].length + 1
        }
        val out = StringBuilder(header)
        if (first > 0) out.append("(").append(first).append(" older lines left out)\n")
        for (i in first until lines.size) out.append(lines[i]).append('\n')
        return out.toString()
    }
}
