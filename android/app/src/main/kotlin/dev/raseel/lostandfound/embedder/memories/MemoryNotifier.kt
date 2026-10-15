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
import dev.raseel.lostandfound.MainActivity
import dev.raseel.lostandfound.R

/** What the person chose about the daily memory, and what has been sent (all kept on the phone). */
class MemoryPrefs(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("memories", Context.MODE_PRIVATE)

    var enabled: Boolean
        get() = prefs.getBoolean("enabled", false)
        set(v) = prefs.edit().putBoolean("enabled", v).apply()

    var lastKind: MemoryKind?
        get() = MemoryKind.fromCode(prefs.getString("last_kind", null))
        set(v) = prefs.edit().putString("last_kind", v?.code).apply()

    /** The day (see [MemoryDays.dayNumber]) the last notification of [slot] went out. */
    fun lastDay(slot: Slot): Int = prefs.getInt("last_day_${slot.code}", -1)

    fun setLastDay(slot: Slot, day: Int) {
        prefs.edit().putInt("last_day_${slot.code}", day).apply()
    }

    /** The kinds that went out lately, with their days (so the kinds take turns). */
    var history: List<MemoryRotation.Used>
        get() = MemoryRotation.decodeHistory(prefs.getString("history", null))
        set(v) = prefs.edit().putString("history", MemoryRotation.encodeHistory(v)).apply()

    /** Who the memories were about lately (a person or a pair), with the day. */
    var subjects: Map<String, Int>
        get() = MemoryRotation.decodeSubjects(prefs.getString("subjects", null))
        set(v) = prefs.edit().putString("subjects", MemoryRotation.encodeSubjects(v)).apply()

    /** The round number of photos already told about, by person; null until it has been set up. */
    var milestones: Map<Long, Int>?
        get() = if (!prefs.getBoolean("milestones_ready", false)) null else MemoryRotation.decode(prefs.getString("milestones", null))
        set(v) {
            if (v == null) {
                prefs.edit().remove("milestones_ready").remove("milestones").apply()
            } else {
                prefs.edit().putBoolean("milestones_ready", true).putString("milestones", MemoryRotation.encode(v)).apply()
            }
        }

    /** The kind "send one now" showed last, so the next press shows another. */
    var lastTestKind: MemoryKind?
        get() = MemoryKind.fromCode(prefs.getString("last_test_kind", null))
        set(v) = prefs.edit().putString("last_test_kind", v?.code).apply()

    /** The photos shown lately, by key, with the day they were. */
    var seen: Map<Long, Int>
        get() = MemoryRotation.decode(prefs.getString("seen", null))
        set(v) = prefs.edit().putString("seen", MemoryRotation.encode(v)).apply()

    /** A tap on a notification: which memory the app should open to (taken once). */
    fun setLaunch(kind: String?, year: Int, personId: Long = 0L) {
        prefs.edit().putString("launch_kind", kind).putInt("launch_year", year).putLong("launch_person", personId).apply()
    }

    /** What a tapped notification was about: its kind, a year, and a person (0 for none). */
    class Launch(val kind: String, val year: Int, val personId: Long)

    fun takeLaunch(): Launch? {
        val kind = prefs.getString("launch_kind", null) ?: return null
        val launch = Launch(kind, prefs.getInt("launch_year", 0), prefs.getLong("launch_person", 0L))
        prefs.edit().remove("launch_kind").remove("launch_year").remove("launch_person").apply()
        return launch
    }
}

/** Puts the daily memory in the notification shade. */
object MemoryNotifier {
    const val CHANNEL_ID = "daily_memory"
    const val ACTION_OPEN = "dev.raseel.lostandfound.OPEN_MEMORY"
    const val EXTRA_KIND = "memory_kind"
    const val EXTRA_YEAR = "memory_year"
    const val EXTRA_PERSON = "memory_person"
    // One each for the morning and the evening, so the evening one does not take the morning one's place.
    private fun notificationId(slot: Slot?) = when (slot) {
        Slot.MORNING -> 7301
        Slot.EVENING -> 7302
        null -> 7303 // "send one now"
    }
    // The app's teal, for the small icon and the app name.
    private const val ACCENT = 0xFF165E59.toInt()

    /** Whether the system lets this app show notifications at all (the Android 13 permission included). */
    fun allowed(context: Context): Boolean = NotificationManagerCompat.from(context).areNotificationsEnabled()

    /** Sends [notice] with its picture (the lock screen only ever shows the words). Returns whether it went out. */
    fun post(context: Context, notice: Notice, slot: Slot? = null): Boolean {
        val app = context.applicationContext
        if (!allowed(app)) return false
        ensureChannel(app)

        val open = PendingIntent.getActivity(
            app,
            notificationId(slot) * 100 + notice.kind.ordinal,
            Intent(app, MainActivity::class.java)
                .setAction(ACTION_OPEN)
                .putExtra(EXTRA_KIND, notice.kind.code)
                .putExtra(EXTRA_YEAR, notice.year)
                .putExtra(EXTRA_PERSON, notice.personId ?: 0L)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // What shows on a locked screen: the words only, never the photo.
        val publicVersion = NotificationCompat.Builder(app, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_memory)
            .setContentTitle("A memory from this day")
            .build()

        // Its own look: a rounded picture and a small heading folded, the postcard and the words opened - the
        // text colours follow the system's (light or dark).
        val rendered = renderedOf(app, notice)
        val small = RemoteViews(app.packageName, R.layout.notification_memory).apply {
            setTextViewText(R.id.memory_eyebrow, notice.kind.label)
            setTextViewText(R.id.memory_title, notice.title)
            setTextViewText(R.id.memory_body, notice.body)
            if (rendered != null) setImageViewBitmap(R.id.memory_thumb, rendered.thumb) else setViewVisibility(R.id.memory_thumb, View.GONE)
        }
        val big = RemoteViews(app.packageName, R.layout.notification_memory_big).apply {
            setTextViewText(R.id.memory_eyebrow, notice.kind.label)
            setTextViewText(R.id.memory_title, notice.title)
            setTextViewText(R.id.memory_body, notice.body)
            if (rendered != null) setImageViewBitmap(R.id.memory_card, rendered.card) else setViewVisibility(R.id.memory_card, View.GONE)
        }

        val builder = NotificationCompat.Builder(app, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_memory)
            .setColor(ACCENT)
            .setContentTitle(notice.title)
            .setContentText(notice.body)
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(small)
            .setCustomBigContentView(big)
            .setContentIntent(open)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_RECOMMENDATION)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(publicVersion)


        return try {
            NotificationManagerCompat.from(app).notify(notificationId(slot), builder.build())
            true
        } catch (_: SecurityException) {
            false
        }
    }

    // The postcard of the notice's own pictures (framed faces, side by side), else of its photo with the date
    // written on it.
    private fun renderedOf(context: Context, notice: Notice): Rendered? {
        if (notice.pics.isNotEmpty()) MemoryPictures.render(context, notice.pics, PictureStyle.of(notice.kind), notice.connector)?.let { return it }
        val photo = notice.photo ?: return null
        val (year, month, day) = MemoryDays.ymd(photo.takenMs)
        val label = if (photo.takenMs > 0) "${MemoryDays.label(month, day)}, $year" else null
        return try {
            MemoryPictures.render(context, listOf(Pic(photo.uri, photo.video, label = label)), PictureStyle.HERO)
        } catch (_: Exception) {
            null
        }
    }

    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(CHANNEL_ID, "Daily memory", NotificationManager.IMPORTANCE_LOW).apply {
            description = "One memory a day from your own photos"
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }
}
