package dev.raseel.lostandfound.features.memories

import android.content.Intent
import dev.raseel.lostandfound.MainActivity
import dev.raseel.lostandfound.core.native.FeatureChannel
import dev.raseel.lostandfound.features.library.ScanEngineHolder
import dev.raseel.lostandfound.features.memories.stories.StoriesReminder
import dev.raseel.lostandfound.features.people.FaceServices
import dev.raseel.lostandfound.features.search.EmbeddingEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel


class MemoriesChannel(activity: MainActivity) : FeatureChannel(activity) {

    private fun planPhotoMap(p: PlanPhoto) = mapOf(
        "key" to p.key,
        "uri" to p.uri,
        "isVideo" to p.video,
        "tsMs" to p.tsMs,
        "takenMs" to p.takenMs,
        "names" to p.names,
    )
    private fun dayYearMap(y: DayYear) = mapOf(
        "year" to y.year,
        "yearsAgo" to y.yearsAgo,
        "total" to y.total,
        "photos" to y.photos.map { planPhotoMap(it) },
        "names" to y.names,
        "strength" to y.strength.toDouble(),
    )
    private fun planMap(plan: Plan) = mapOf(
        "month" to plan.month,
        "day" to plan.day,
        "year" to plan.year,
        "exact" to plan.exact.map { dayYearMap(it) },
        "week" to plan.week.map { dayYearMap(it) },
        "anniversaries" to plan.anniversaries.map { a ->
            mapOf(
                "yearsAgo" to a.yearsAgo,
                "ids" to a.ids,
                "names" to a.names,
                "firstMs" to a.firstMs,
                "photo" to a.photo?.let { planPhotoMap(it) },
            )
        },
    )
    private fun memorySettingsMap(): Map<String, Any> {
        val prefs = MemoryPrefs(applicationContext)
        return mapOf(
            "enabled" to prefs.enabled,
            "allowed" to MemoryNotifier.allowed(applicationContext),
        )
    }
    /**
     * A tap on the daily memory's notification: remembered, and the app picks it up (takeLaunchMemory) to open the memory.
     */
    fun noteTap(intent: Intent?) {
        if (intent?.action != MemoryNotifier.ACTION_OPEN) return
        MemoryPrefs(applicationContext).setLaunch(
            intent.getStringExtra(MemoryNotifier.EXTRA_KIND),
            intent.getIntExtra(MemoryNotifier.EXTRA_YEAR, 0),
            intent.getLongExtra(MemoryNotifier.EXTRA_PERSON, 0L),
        )
    }
    private val embeddingEngine: EmbeddingEngine get() = ScanEngineHolder.embeddingEngine(this)
    private val faces by lazy { FaceServices.get(applicationContext) }

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {

            "memoryPrepare" -> memoryTask(result) {
                val budget = (call.argument<Number>("budgetMs") ?: 600).toLong()
                val dates = LibraryDates.get(applicationContext)
                val faceStore = faces.store
                dates.sync(embeddingEngine)
                val pending = dates.resolve(applicationContext, faceStore, budget)
                mapOf("total" to dates.progress().first, "pending" to pending)
            }

            "mediaDates" -> memoryTask(result) {
                val uris = call.argument<List<String>>("uris") ?: emptyList()
                val dates = LibraryDates.get(applicationContext)
                try {
                    dates.sync(embeddingEngine)
                    dates.resolve(applicationContext, faces.store, 150L)
                } catch (e: Exception) {
                    android.util.Log.w("MainActivity", "dates for stories failed: ${e.message}")
                }
                dates.datesFor(uris).map { mapOf("uri" to it.uri, "takenMs" to it.takenMs, "junk" to it.junk) }
            }

            "storiesReminder" -> {
                call.argument<Boolean>("enabled")?.let { StoriesReminder.setEnabled(applicationContext, it) }
                if (call.hasArgument("ringsJson")) StoriesReminder.setRings(applicationContext, call.argument<String>("ringsJson"))
                if (call.argument<Boolean>("cancel") == true) StoriesReminder.cancel(applicationContext)
                call.argument<Number>("atMs")?.let { StoriesReminder.schedule(applicationContext, it.toLong()) }
                result.success(
                    mapOf(
                        "enabled" to StoriesReminder.enabled(applicationContext),
                        "allowed" to MemoryNotifier.allowed(applicationContext),
                    )
                )
            }

            "storiesReminderTest" -> memoryTask(result) {
                StoriesReminder.post(applicationContext, call.argument<String>("ringsJson"), test = true)
            }

            "onThisDay" -> memoryTask(result) {
                val planner = MemoryPlanner(LibraryDates.get(applicationContext), faces.store)
                planMap(planner.plan(System.currentTimeMillis(), withWeek = true, withAnniversaries = true))
            }

            "memoryDay" -> memoryTask(result) {
                val start = (call.argument<Number>("startMs") ?: 0).toLong()
                val end = (call.argument<Number>("endMs") ?: 0).toLong()
                val limit = (call.argument<Number>("limit") ?: 2000).toInt()
                val dates = LibraryDates.get(applicationContext)
                mapOf(
                    "total" to dates.count(start, end),
                    "items" to dates.photos(start, end, limit).map { m ->
                        mapOf(
                            "key" to m.key,
                            "uri" to m.uri,
                            "isVideo" to m.video,
                            "tsMs" to (if (m.video) 1000L else 0L),
                            "takenMs" to m.takenMs,
                        )
                    },
                )
            }

            "memorySettings" -> result.success(memorySettingsMap())

            "setMemorySettings" -> {
                val prefs = MemoryPrefs(applicationContext)
                call.argument<Boolean>("enabled")?.let { prefs.enabled = it }
                MemoryScheduler.apply(applicationContext, replace = true)
                result.success(memorySettingsMap())
            }

            "memoryTest" -> memoryTask(result) {
                val outcome = MemoryDay.run(applicationContext, test = true, budgetMs = 4_000L)
                mapOf("sent" to outcome.sent?.code, "message" to outcome.message)
            }

            "takeLaunchMemory" -> {
                val launch = MemoryPrefs(applicationContext).takeLaunch()
                result.success(launch?.let { mapOf("kind" to it.kind, "year" to it.year, "personId" to it.personId) })
            }

            else -> return false
        }
        return true
    }
}

internal fun FeatureChannel.memoryTask(result: MethodChannel.Result, block: () -> Any?) {
    memoryExecutor.execute {
        try {
            val value = block()
            runOnUiThread { result.success(value) }
        } catch (e: Throwable) {
            android.util.Log.w("MainActivity", "memory call failed: ${e.message}", e)
            runOnUiThread { result.error("MEMORY_FAILED", e.message, null) }
        }
    }
}
