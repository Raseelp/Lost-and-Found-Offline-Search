package dev.raseel.lostandfound.core.log

import android.content.Context
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.LinkedBlockingQueue
import kotlin.concurrent.thread

/**
 * The app's logging. A line goes to Android's log like before, and also to a file in the app's own folder, because
 * some phones do not let an app read its log back, and the log is what a problem report carries. The file is written
 * by one background thread, so logging never waits for the disk.
 */
object AppLog {

    private const val MAX_PENDING = 2000
    private const val MAX_TRACE_LINES = 25

    private val pending = LinkedBlockingQueue<String>(MAX_PENDING)
    private val timeFormat = object : ThreadLocal<SimpleDateFormat>() {
        override fun initialValue() = SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US)
    }

    @Volatile
    private var file: RollingLogFile? = null

    /** Starts writing the log file. Call it once, when the app starts. Lines logged before are kept and written now. */
    fun init(context: Context) {
        if (file != null) return
        file = RollingLogFile(File(context.applicationContext.filesDir, "logs"))
        thread(name = "app-log", isDaemon = true) {
            while (true) {
                val batch = ArrayList<String>()
                batch += pending.take()
                pending.drainTo(batch)
                try {
                    file?.append(batch)
                } catch (_: Exception) {
                }
            }
        }
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                val lines = ArrayList<String>()
                pending.drainTo(lines)
                lines += line('E', "Crash", "Uncaught exception in ${thread.name}", error)
                file?.append(lines)
            } catch (_: Exception) {
            }
            previous?.uncaughtException(thread, error)
        }
    }

    fun d(tag: String, message: String, error: Throwable? = null) {
        if (error == null) Log.d(tag, message) else Log.d(tag, message, error)
        record('D', tag, message, error)
    }

    fun i(tag: String, message: String, error: Throwable? = null) {
        if (error == null) Log.i(tag, message) else Log.i(tag, message, error)
        record('I', tag, message, error)
    }

    fun w(tag: String, message: String, error: Throwable? = null) {
        if (error == null) Log.w(tag, message) else Log.w(tag, message, error)
        record('W', tag, message, error)
    }

    fun e(tag: String, message: String, error: Throwable? = null) {
        if (error == null) Log.e(tag, message) else Log.e(tag, message, error)
        record('E', tag, message, error)
    }

    /** The newest [max] lines of the log, oldest first. Lines still waiting to be written are written first. */
    fun recentLines(max: Int): List<String> {
        val log = file ?: return emptyList()
        val waiting = ArrayList<String>()
        pending.drainTo(waiting)
        log.append(waiting)
        return log.recentLines(max)
    }

    private fun record(level: Char, tag: String, message: String, error: Throwable?) {
        pending.offer(line(level, tag, message, error))
    }

    private fun line(level: Char, tag: String, message: String, error: Throwable?): String {
        val head = "${timeFormat.get()!!.format(Date())} $level/$tag: $message"
        if (error == null) return head
        val trace = Log.getStackTraceString(error).trim().lines().take(MAX_TRACE_LINES)
        return head + "\n" + trace.joinToString("\n")
    }
}
