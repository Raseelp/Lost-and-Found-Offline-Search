package dev.raseel.lostandfound.embedder.memories

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import dev.raseel.lostandfound.MainActivity
import dev.raseel.lostandfound.R
import java.util.Calendar
import java.util.concurrent.TimeUnit

/**
 * The note that says the stories have refreshed. The app sets it for a day after the stories were last
 * looked at (each look sets it again, replacing the one waiting), so it comes when there is something new
 * to see. Never in the night: a time between 22:00 and 08:00 is moved to 09:00. It opens the app; on or off in
 * Settings. Opened out, it shows a row of the rings that are ready (see [StoriesRingRow]): the app sends who they
 * will be when it sets the note, since the note is made later without the app running. On the lock screen only the
 * plain title shows.
 */
object StoriesReminder {
    private const val WORK = "stories_reminder"
    private const val CHANNEL_ID = "stories"
    private const val NOTIFICATION_ID = 7310
    private const val ACCENT = 0xFF165E59.toInt()

    private fun prefs(context: Context) = context.applicationContext.getSharedPreferences("stories", Context.MODE_PRIVATE)

    fun enabled(context: Context): Boolean = prefs(context).getBoolean("reminder", true)

    /** Who the rings in the note will be (see [StoryPreview.parse]), as the app last said. */
    fun setRings(context: Context, json: String?) {
        prefs(context).edit().putString("reminder_rings", json).apply()
    }

    fun setEnabled(context: Context, on: Boolean) {
        prefs(context).edit().putBoolean("reminder", on).apply()
        if (!on) cancel(context)
    }

    /** Sets the note for [atMs] (moved out of the night), in place of any that was waiting. */
    fun schedule(context: Context, atMs: Long) {
        val app = context.applicationContext
        if (!enabled(app)) return
        val now = System.currentTimeMillis()
        val delay = (outOfTheNight(maxOf(atMs, now)) - now).coerceAtLeast(0L)
        val request = OneTimeWorkRequestBuilder<StoriesReminderWorker>()
            .setInitialDelay(delay, TimeUnit.MILLISECONDS)
            .build()
        WorkManager.getInstance(app).enqueueUniqueWork(WORK, ExistingWorkPolicy.REPLACE, request)
    }

    fun cancel(context: Context) {
        val app = context.applicationContext
        WorkManager.getInstance(app).cancelUniqueWork(WORK)
        NotificationManagerCompat.from(app).cancel(NOTIFICATION_ID)
    }

    // 22:00 to 08:00 becomes 09:00 (of that morning, or of the next day).
    internal fun outOfTheNight(ms: Long): Long {
        val cal = Calendar.getInstance().apply { timeInMillis = ms }
        val hour = cal.get(Calendar.HOUR_OF_DAY)
        if (hour in 8..21) return ms
        if (hour >= 22) cal.add(Calendar.DAY_OF_MONTH, 1)
        cal.set(Calendar.HOUR_OF_DAY, 9)
        cal.set(Calendar.MINUTE, 0)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        return cal.timeInMillis
    }

    /**
     * Shows the note. [ringsJson] (for "send one now") is who is in it; null: the rings the app last said. [test]: it is
     * shown even if the reminder is off, so what it looks like can be seen.
     */
    fun post(context: Context, ringsJson: String? = null, test: Boolean = false): Boolean {
        val app = context.applicationContext
        if ((!test && !enabled(app)) || !MemoryNotifier.allowed(app)) return false
        ensureChannel(app)
        val open = PendingIntent.getActivity(
            app,
            NOTIFICATION_ID,
            Intent(app, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val title = "Your stories have refreshed"
        val rings = StoryPreview.parse(ringsJson ?: prefs(app).getString("reminder_rings", null))
        val text = StoryPreview.sentence(rings)
        // What a locked screen shows: the words only, never a face or a name.
        val publicVersion = NotificationCompat.Builder(app, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_memory)
            .setContentTitle(title)
            .build()
        val builder = NotificationCompat.Builder(app, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_memory)
            .setColor(ACCENT)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(open)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_RECOMMENDATION)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(publicVersion)
        // Opened out: the words and, under them, the row of rings. Without a picture it is the plain note.
        val row = if (rings.isEmpty()) null else try {
            StoriesRingRow.render(app, rings)
        } catch (_: Exception) {
            null
        }
        if (row != null) {
            // Folded, the rings are already there (a note cannot be made to open out by itself): the title and a small row
            // of them. Opened out: the words and a bigger row.
            val small = RemoteViews(app.packageName, R.layout.notification_stories_small).apply {
                setTextViewText(R.id.stories_small_title, title)
                setImageViewBitmap(R.id.stories_small_row, row)
            }
            val big = RemoteViews(app.packageName, R.layout.notification_stories_big).apply {
                setTextViewText(R.id.stories_title, title)
                setTextViewText(R.id.stories_body, text)
                setImageViewBitmap(R.id.stories_row, row)
            }
            builder.setStyle(NotificationCompat.DecoratedCustomViewStyle()).setCustomContentView(small).setCustomBigContentView(big)
        }
        return try {
            NotificationManagerCompat.from(app).notify(NOTIFICATION_ID, builder.build())
            true
        } catch (_: SecurityException) {
            false
        }
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(CHANNEL_ID, "Stories", NotificationManager.IMPORTANCE_LOW).apply {
            description = "A note when your stories have refreshed"
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }
}

class StoriesReminderWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        StoriesReminder.post(applicationContext)
        return Result.success()
    }
}
