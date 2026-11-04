package dev.raseel.lostandfound.embedder.memories

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.SweepGradient
import android.graphics.Typeface
import android.os.Build
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
import dev.raseel.lostandfound.embedder.ScanEngineHolder
import dev.raseel.lostandfound.embedder.ScanWorker
import dev.raseel.lostandfound.embedder.faces.FaceServices
import java.text.NumberFormat
import java.util.concurrent.TimeUnit

enum class NudgeKind { RING, PEOPLE, THIS_DAY, SEARCH }

enum class NudgeVerdict { SEND, WAIT, STOP }

/** What follows from the note coming due: the [verdict], how many have been sent after it, and the days to the next (null: none). */
class NudgeStep(val verdict: NudgeVerdict, val sent: Int, val nextDays: Int?)

/**
 * The note that asks to finish indexing: for someone whose photos and videos are not all in the search index, so search,
 * people and memories only see part of the phone. It comes [GAP_DAYS] days after the app was last used, and again,
 * further off each time, if it goes unanswered; after [MAX_NUDGES] there are no more. (A library that is found finished
 * starts the count again.) It says one thing the person is missing, in turn: how much can be found, more of
 * someone they know, the photos of this day, or what search can see (see [words]). Quiet, but on the lock screen (which
 * shows only the title). Opens the Library tab; its "Index now" button opens it too and starts the scan.
 *
 * Not while a scan runs, not on a day another note (the daily memory, the stories) went out, and never in the night.
 * On or off in Settings.
 */
object IndexNudge {
    const val ACTION_INDEX_NOW = "dev.raseel.lostandfound.INDEX_NOW"

    private const val WORK = "index_nudge"
    private const val CHANNEL_ID = "index_nudge"
    private const val NOTIFICATION_ID = 7320
    private const val ACCENT = 0xFF165E59.toInt()
    private const val DAY_MS = 86_400_000L

    // Days from the app being used, or a note going out, to the next note, by how many have gone out.
    private val GAP_DAYS = intArrayOf(3, 7, 14)
    const val MAX_NUDGES = 3

    // A day with this few photos missing from the memories is not worth a note.
    private const val MIN_THIS_DAY = 3

    private val PHRASES = listOf(
        "a birthday cake with candles", "sunset at the beach", "a dog in the snow",
        "friends laughing at dinner", "fireworks at night", "a plate of pasta",
    )

    // ---- the rules (no phone needed) ----

    /** Whether the note goes out now, waits a day, or is not sent (and no more are set). */
    fun verdict(share: IndexShare, scanning: Boolean, enabled: Boolean, sent: Int, noteToday: Boolean): NudgeVerdict = when {
        !enabled || share.finished || sent >= MAX_NUDGES -> NudgeVerdict.STOP
        scanning || noteToday -> NudgeVerdict.WAIT
        else -> NudgeVerdict.SEND
    }

    /** The verdict and what it changes: a note sent counts and sets the next, a day put off sets tomorrow, a finished library starts the count again. */
    fun step(share: IndexShare, scanning: Boolean, enabled: Boolean, sent: Int, noteToday: Boolean): NudgeStep {
        val verdict = verdict(share, scanning, enabled, sent, noteToday)
        return when (verdict) {
            NudgeVerdict.SEND -> NudgeStep(verdict, sent + 1, nextGapDays(sent + 1))
            NudgeVerdict.WAIT -> NudgeStep(verdict, sent, 1)
            NudgeVerdict.STOP -> NudgeStep(verdict, if (share.finished) 0 else sent, null)
        }
    }

    /** Days from now to the next note once [sent] have gone out; null: no more. */
    fun nextGapDays(sent: Int): Int? = if (sent in 0 until MAX_NUDGES) GAP_DAYS[sent] else null

    /** The thing to say: the kinds in turn, starting with the first, the next one (in a circle) when one is not possible. */
    fun pickKind(available: Set<NudgeKind>, sent: Int): NudgeKind {
        val all = NudgeKind.entries
        for (i in all.indices) {
            val kind = all[Math.floorMod(sent + i, all.size)]
            if (kind == NudgeKind.RING || kind in available) return kind
        }
        return NudgeKind.RING
    }

    /** The title and the line under it. [name] and [photos]: the person (PEOPLE); [thisDay]: the photos of this day (THIS_DAY). */
    fun words(kind: NudgeKind, share: IndexShare, name: String?, photos: Int, thisDay: Int, phrase: String): Pair<String, String> {
        val waiting = counts(share)
        return when (kind) {
            NudgeKind.RING ->
                if (share.indexed <= 0) {
                    "Your library cannot be searched yet" to "Index your ${number(share.onPhone)} photos and videos to find them by describing them."
                } else if (share.percent == 0) {
                    "Only ${number(share.indexed)} of your ${number(share.onPhone)} can be searched" to "$waiting are waiting. Index them to search all of your photos and videos."
                } else {
                    "${share.percent}% of your library can be searched" to "$waiting are waiting. Index them to search all of your photos and videos."
                }
            NudgeKind.PEOPLE ->
                "Find more of ${name ?: "the people you love"}" to
                    "${name ?: "They"} ${if (name == null) "are" else "is"} in ${number(photos)} photos so far. $waiting have not been looked at."
            NudgeKind.THIS_DAY ->
                "Photos from this day are waiting" to "About ${number(thisDay)} photos and videos from this day in earlier years are not in your memories yet."
            NudgeKind.SEARCH ->
                "Search can see ${number(share.indexed)} of your ${number(share.onPhone)}" to "Index the rest, then try \"$phrase\"."
        }
    }

    private fun number(n: Int): String = NumberFormat.getIntegerInstance().format(n)

    /** What is not indexed, told apart when it is known: "1,240 photos and 85 videos", "1 video", "300 photos and videos". */
    internal fun counts(share: IndexShare): String {
        val photos = share.missingPhotos
        val videos = share.missingVideos
        if (photos == null || videos == null) return "${number(share.missing)} photos and videos"
        val parts = listOfNotNull(
            photos.takeIf { it > 0 }?.let { if (it == 1) "1 photo" else "${number(it)} photos" },
            videos.takeIf { it > 0 }?.let { if (it == 1) "1 video" else "${number(it)} videos" },
        )
        return if (parts.isEmpty()) "${number(share.missing)} photos and videos" else parts.joinToString(" and ")
    }

    // ---- on and off, and the record ----

    private fun prefs(context: Context) = context.applicationContext.getSharedPreferences("index_nudge", Context.MODE_PRIVATE)

    fun enabled(context: Context): Boolean = prefs(context).getBoolean("enabled", true)

    fun setEnabled(context: Context, on: Boolean) {
        prefs(context).edit().putBoolean("enabled", on).apply()
        if (on) arm(context) else cancel(context)
    }

    /** Whether a note went out on [today] (a day number, see [MemoryDays.dayNumber]); the stories note skips such a day. */
    fun postedToday(context: Context, today: Int): Boolean = prefs(context).getInt("last_post_day", -1) == today

    // ---- scheduling ----

    /**
     * Sets the note for [GAP_DAYS] after now, in place of any waiting. Called whenever the app is left or a scan ends,
     * so it always comes that long after the last time the app was used. What is true is only looked at when it is due.
     */
    fun arm(context: Context) {
        val app = context.applicationContext
        val gap = nextGapDays(prefs(app).getInt("sent", 0))
        if (!enabled(app) || gap == null) {
            WorkManager.getInstance(app).cancelUniqueWork(WORK)
            return
        }
        schedule(app, System.currentTimeMillis() + gap * DAY_MS)
    }

    private fun schedule(context: Context, atMs: Long) {
        val now = System.currentTimeMillis()
        val delay = (StoriesReminder.outOfTheNight(maxOf(atMs, now)) - now).coerceAtLeast(0L)
        val request = OneTimeWorkRequestBuilder<IndexNudgeWorker>().setInitialDelay(delay, TimeUnit.MILLISECONDS).build()
        WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(WORK, ExistingWorkPolicy.REPLACE, request)
    }

    fun cancel(context: Context) {
        val app = context.applicationContext
        WorkManager.getInstance(app).cancelUniqueWork(WORK)
        NotificationManagerCompat.from(app).cancel(NOTIFICATION_ID)
    }

    /** The note is due: shown, or put off a day, or dropped. Runs on a worker thread. */
    fun fire(context: Context) {
        val app = context.applicationContext
        if (!enabled(app)) return
        val p = prefs(app)
        val now = System.currentTimeMillis()
        val today = MemoryDays.dayNumber(now)
        val sent = p.getInt("sent", 0)
        // The search model is not on the phone yet (the download is not finished): there is nothing to index with. The
        // app sets the note again the next time it is left.
        if (!ScanEngineHolder.modelManager(app).areModelsReady()) return
        // Cannot be measured (no access to the photos): nothing to say, and nothing more is set.
        val share = IndexGap.measure(app) ?: return
        val memories = MemoryPrefs(app)
        val noteToday = (memories.enabled && Slot.entries.any { memories.lastDay(it) == today }) ||
            StoriesReminder.postedToday(app, today)
        val step = step(share, ScanWorker.isRunning(), true, sent, noteToday)
        when (step.verdict) {
            NudgeVerdict.STOP -> {
                if (step.sent != sent) p.edit().putInt("sent", step.sent).apply()
                return
            }
            NudgeVerdict.WAIT -> {
                schedule(app, now + (step.nextDays ?: 1) * DAY_MS)
                return
            }
            NudgeVerdict.SEND -> Unit
        }
        val people = try {
            FaceServices.get(app).store.listPeople(false).filter { it.photoCount > 0 }.sortedByDescending { it.photoCount }
        } catch (_: Exception) {
            emptyList()
        }
        val named = people.firstOrNull { !it.name.isNullOrBlank() }
        val thisDay = IndexGap.missingOnThisDay(app, now)?.takeIf { it >= MIN_THIS_DAY }
        val available = buildSet {
            if (named != null) add(NudgeKind.PEOPLE)
            if (thisDay != null) add(NudgeKind.THIS_DAY)
            add(NudgeKind.SEARCH)
        }
        val kind = pickKind(available, sent)
        val phrase = PHRASES[Math.floorMod(today, PHRASES.size)]
        val (title, body) = words(kind, share, named?.name, named?.photoCount ?: 0, thisDay ?: 0, phrase)
        val picture = when (kind) {
            NudgeKind.RING -> ring(share.percent)
            NudgeKind.PEOPLE -> StoriesRingRow.render(
                app,
                people.take(5).map { StoryPreview(it.name.orEmpty(), it.coverFaceId) },
                people.size,
            )
            else -> null
        }
        if (!post(app, title, body, picture)) return
        p.edit().putInt("sent", step.sent).putInt("last_post_day", today).apply()
        // Last of all: this replaces the very work that is running, which is fine once it has done what it came to do.
        step.nextDays?.let { schedule(app, now + it * DAY_MS) }
    }

    // ---- the note ----

    private fun post(app: Context, title: String, body: String, picture: Bitmap?): Boolean {
        if (!MemoryNotifier.allowed(app)) return false
        ensureChannel(app)
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        fun open(action: String, code: Int) = PendingIntent.getActivity(
            app, code,
            Intent(app, MainActivity::class.java).setAction(action)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            flags,
        )
        // What a locked screen shows: the words only, no numbers and no faces.
        val publicVersion = NotificationCompat.Builder(app, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_memory)
            .setContentTitle("Finish indexing your photos")
            .build()
        val builder = NotificationCompat.Builder(app, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_memory)
            .setColor(ACCENT)
            .setContentTitle(title)
            .setContentText(body)
            .setContentIntent(open(MainActivity.ACTION_OPEN_LIBRARY, NOTIFICATION_ID))
            .addAction(NotificationCompat.Action.Builder(R.drawable.ic_memory, "Index now", open(ACTION_INDEX_NOW, NOTIFICATION_ID + 1)).build())
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_RECOMMENDATION)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(publicVersion)
        if (picture != null) {
            val small = RemoteViews(app.packageName, R.layout.notification_stories_small).apply {
                setTextViewText(R.id.stories_small_title, title)
                setImageViewBitmap(R.id.stories_small_row, picture)
            }
            val big = RemoteViews(app.packageName, R.layout.notification_stories_big).apply {
                setTextViewText(R.id.stories_title, title)
                setTextViewText(R.id.stories_body, body)
                setImageViewBitmap(R.id.stories_row, picture)
            }
            builder.setStyle(NotificationCompat.DecoratedCustomViewStyle()).setCustomContentView(small).setCustomBigContentView(big)
        } else {
            builder.setStyle(NotificationCompat.BigTextStyle().bigText(body))
        }
        return try {
            NotificationManagerCompat.from(app).notify(NOTIFICATION_ID, builder.build())
            true
        } catch (_: SecurityException) {
            false
        }
    }

    // Normal importance but no sound or buzz: the phones that keep quiet (low importance) notes off the lock screen show it.
    private fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(CHANNEL_ID, "Finish indexing", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "A reminder to index the rest of your photos and videos"
            setShowBadge(false)
            setSound(null, null)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    // A ring filled to [percent], in the colours of the stories rings, with the number inside. Transparent, so it sits on
    // whatever colour the note has.
    private fun ring(percent: Int): Bitmap {
        val size = 132
        val stroke = 14f
        val out = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val box = RectF(stroke / 2, stroke / 2, size - stroke / 2, size - stroke / 2)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = stroke
        paint.strokeCap = Paint.Cap.ROUND
        paint.color = Color.argb(60, 0x8A, 0x90, 0x8D)
        canvas.drawArc(box, 0f, 360f, false, paint)
        if (percent > 0) {
            paint.shader = SweepGradient(
                size / 2f, size / 2f,
                intArrayOf(Color.rgb(0x16, 0x5E, 0x59), Color.rgb(0x7F, 0xD6, 0xCC), Color.rgb(0x16, 0x5E, 0x59)),
                null,
            )
            canvas.save()
            canvas.rotate(-90f, size / 2f, size / 2f)
            canvas.drawArc(box, 0f, 360f * percent / 100f, false, paint)
            canvas.restore()
            paint.shader = null
        }
        paint.style = Paint.Style.FILL
        paint.textAlign = Paint.Align.CENTER
        paint.typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        paint.textSize = 38f
        paint.color = Color.rgb(0x2E, 0x9E, 0x93)
        canvas.drawText("$percent%", size / 2f, size / 2f + 13f, paint)
        return out
    }
}

class IndexNudgeWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        try {
            IndexNudge.fire(applicationContext)
        } catch (e: Exception) {
            android.util.Log.w("IndexNudge", "failed: ${e.message}")
        }
        return Result.success()
    }
}
