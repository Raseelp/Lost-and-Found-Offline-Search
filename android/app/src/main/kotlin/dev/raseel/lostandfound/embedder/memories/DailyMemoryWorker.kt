package dev.raseel.lostandfound.embedder.memories

import android.content.Context
import android.util.Log
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import dev.raseel.lostandfound.embedder.ScanEngineHolder
import dev.raseel.lostandfound.embedder.faces.FaceServices
import java.util.Calendar
import java.util.concurrent.TimeUnit

/** What came of looking for today's memory. */
class MemoryOutcome(val sent: MemoryKind?, val message: String)

/**
 * Makes today's memory: brings the catalog of dates up to date, works out what there is - for today's
 * date, and about the people (see [MemoryEvergreen]) - picks one kind (see [MemoryRotation]) and sends it.
 * At most once a day, and only when there is something good - a quiet day gets nothing.
 */
object MemoryDay {
    private const val TAG = "MemoryDay"

    // What "send one now" has already shown, so pressing again shows something else (kept while the app lives).
    private val testPhotos = HashSet<Long>()
    private val testSubjects = HashMap<String, Int>()

    /**
     * [test]: sends something there is for today right now - each press a different kind, and different
     * photos and people - regardless of whether one went out today, and without using up the real one.
     */
    fun run(context: Context, slot: Slot = Slot.MORNING, test: Boolean = false, budgetMs: Long = 15_000L): MemoryOutcome {
        val app = context.applicationContext
        val prefs = MemoryPrefs(app)
        if (!test && !prefs.enabled) return MemoryOutcome(null, "Off")
        if (!MemoryNotifier.allowed(app)) return MemoryOutcome(null, "Notifications are off for this app")
        // Work that was held up (the phone was off) and runs hours late would be out of place: the other time is coming.
        val hour = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
        if (!test && hour !in slot.fromHour until slot.untilHour) return MemoryOutcome(null, "Too late for the ${slot.code} one")

        val dates = LibraryDates.get(app)
        val faces = FaceServices.get(app).store
        try {
            dates.sync(ScanEngineHolder.embeddingEngine(app))
            dates.resolve(app, faces, budgetMs)
        } catch (e: Exception) {
            Log.w(TAG, "dates failed: ${e.message}")
        }
        val (total, pending) = dates.progress()
        if (total == 0) return MemoryOutcome(null, "Nothing is indexed yet")

        val now = System.currentTimeMillis()
        val today = MemoryDays.dayNumber(now)
        if (!test && prefs.lastDay(slot) == today) return MemoryOutcome(null, "Already sent this ${slot.code}")

        val seen = MemoryRotation.prune(prefs.seen, today)
        val subjects = MemoryRotation.pruneSubjects(prefs.subjects, today)
        val exclude = if (test) seen.keys + testPhotos else seen.keys
        val recent = if (test) subjects + testSubjects else subjects

        // The people's round numbers are noted the first time, so only what is passed from now on is told.
        val saved = prefs.milestones
        val announced: Map<Long, Int> = saved ?: faces.listPeople(false)
            .filter { !it.name.isNullOrBlank() }
            .associate { it.id to Milestones.reached(it.photoCount) }
            .also { prefs.milestones = it }

        val planner = MemoryPlanner(dates, faces)
        val plan = planner.plan(now, exclude = exclude, withWeek = true, withAnniversaries = true)
        val notices = LinkedHashMap(planner.notices(plan))
        try {
            val ctx = MemoryEvergreen.Ctx(now, today, java.util.TimeZone.getDefault(), exclude, recent, if (saved == null) null else if (test) emptyMap() else announced)
            notices += MemoryEvergreen(dates, faces, planner).build(ctx)
        } catch (e: Exception) {
            Log.w(TAG, "people memories failed: ${e.message}")
        }

        val kind = if (test) {
            MemoryRotation.chooseForTest(notices.keys, prefs.lastTestKind)
        } else {
            MemoryRotation.choose(notices.keys, prefs.history, today, slot)
        }
        val notice = kind?.let { notices[it] }
        if (notice == null) {
            val extra = if (pending > 0) " ($pending photos still being dated)" else ""
            return MemoryOutcome(null, "No memory for today's date$extra")
        }
        if (!MemoryNotifier.post(app, notice, if (test) null else slot)) return MemoryOutcome(null, "Could not show the notification")

        val key = notice.photo?.key
        if (test) {
            prefs.lastTestKind = notice.kind
            if (key != null) {
                if (testPhotos.size > 300) testPhotos.clear()
                testPhotos += key
            }
            notice.subject?.let { testSubjects[it] = today }
        } else {
            prefs.history = prefs.history + MemoryRotation.Used(notice.kind, today, slot)
            prefs.setLastDay(slot, today)
            prefs.seen = if (key == null) seen else seen + (key to today)
            notice.subject?.let { prefs.subjects = subjects + (it to today) }
            notice.milestone?.let { (person, step) -> prefs.milestones = (announced + (person to step)) }
        }
        return MemoryOutcome(notice.kind, notice.title)
    }
}

/**
 * The once-a-day work. It is one piece of work that sets up the next one when it is done, for the exact
 * time of day chosen: periodic work drifts, and keeps the schedule it first had when it is updated, so a
 * new time would not take.
 */
class DailyMemoryWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    override fun doWork(): Result {
        val slot = Slot.fromCode(inputData.getString(MemoryScheduler.KEY_SLOT))
        try {
            val outcome = MemoryDay.run(applicationContext, slot)
            Log.i("DailyMemory", "${slot.code}: ${outcome.sent?.code ?: "nothing"}: ${outcome.message}")
        } catch (e: Exception) {
            Log.w("DailyMemory", "failed: ${e.message}") // tomorrow is another day
        }
        // Last of all: replacing this very work is fine once it has done what it came to do.
        MemoryScheduler.apply(applicationContext, replace = true, only = slot)
        return Result.success()
    }
}

/**
 * Sets the daily work up (or takes it away): two a day, at fixed times - early morning and evening - each
 * its own piece of work that sets up the next one when it is done.
 */
object MemoryScheduler {
    const val KEY_SLOT = "slot"
    private const val LEGACY = "daily_memory"

    private fun nameOf(slot: Slot) = "daily_memory_${slot.code}"

    /** Time from [now] to the next [hour]:[minute] (today if it has not come yet, else tomorrow). */
    fun delayUntil(now: Long, hour: Int, minute: Int): Long {
        val cal = Calendar.getInstance()
        cal.timeInMillis = now
        cal.set(Calendar.HOUR_OF_DAY, hour)
        cal.set(Calendar.MINUTE, minute)
        cal.set(Calendar.SECOND, 0)
        cal.set(Calendar.MILLISECOND, 0)
        if (cal.timeInMillis <= now) cal.add(Calendar.DAY_OF_MONTH, 1)
        return cal.timeInMillis - now
    }

    /**
     * Makes sure the next run of each time (or of [only]) is set (or takes them away when the daily memory
     * is off). [replace]: set it again even if one is waiting (the one before just ran, or the setting
     * changed); otherwise a waiting one is left as it is (the app starting).
     */
    fun apply(context: Context, replace: Boolean = false, only: Slot? = null) {
        val app = context.applicationContext
        val work = WorkManager.getInstance(app)
        work.cancelUniqueWork(LEGACY) // the one-a-day work of before
        val prefs = MemoryPrefs(app)
        for (slot in Slot.entries) {
            if (only != null && slot != only) continue
            if (!prefs.enabled) {
                work.cancelUniqueWork(nameOf(slot))
                continue
            }
            val request = OneTimeWorkRequestBuilder<DailyMemoryWorker>()
                .setInitialDelay(delayUntil(System.currentTimeMillis(), slot.hour, slot.minute), TimeUnit.MILLISECONDS)
                .setInputData(workDataOf(KEY_SLOT to slot.code))
                .setConstraints(Constraints.Builder().setRequiresBatteryNotLow(true).build())
                .build()
            work.enqueueUniqueWork(nameOf(slot), if (replace) ExistingWorkPolicy.REPLACE else ExistingWorkPolicy.KEEP, request)
        }
    }
}
