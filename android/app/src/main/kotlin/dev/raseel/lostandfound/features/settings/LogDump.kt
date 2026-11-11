package dev.raseel.lostandfound.features.settings

import android.content.Context
import android.os.Build
import dev.raseel.lostandfound.core.log.AppLog

/**
 * The app's recent log as one piece of text, for the log viewer and the problem report in Settings > About > Note from
 * the developer.
 *
 * The log is the one the app keeps in its own folder (see [AppLog]), not Android's, which some phones do not let an
 * app read. It holds the app's own messages and, after a crash, why.
 */
object LogDump {
    private const val MAX_LINES = 4000

    /** Well under the 1 MB the clipboard can carry, even if every character takes three bytes. */
    private const val MAX_CHARS = 200_000

    /** The text of the log: the app and phone, then the newest log lines. Call off the main thread. */
    fun collect(context: Context): String = text(header(context), AppLog.recentLines(MAX_LINES))

    /** The app and phone details that open the log, and close the text of a problem report. */
    fun header(context: Context): String {
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
