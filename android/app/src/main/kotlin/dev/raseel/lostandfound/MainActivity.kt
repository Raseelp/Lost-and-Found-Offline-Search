package dev.raseel.lostandfound

import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import androidx.core.view.WindowCompat
import dev.raseel.lostandfound.core.media.MediaChannel
import dev.raseel.lostandfound.core.native.FeatureChannel
import dev.raseel.lostandfound.features.collections.CollectionsChannel
import dev.raseel.lostandfound.features.export.ExportChannel
import dev.raseel.lostandfound.features.home.HomeChannel
import dev.raseel.lostandfound.features.library.LibraryChannel
import dev.raseel.lostandfound.features.library.SafPicker
import dev.raseel.lostandfound.features.memories.MemoriesChannel
import dev.raseel.lostandfound.features.memories.MemoryScheduler
import dev.raseel.lostandfound.features.memories.stories.StoriesReminder
import dev.raseel.lostandfound.features.model_download.ModelDownloadChannel
import dev.raseel.lostandfound.features.people.PeopleChannel
import dev.raseel.lostandfound.features.search.SearchChannel
import dev.raseel.lostandfound.features.settings.IndexNudge
import dev.raseel.lostandfound.features.settings.SettingsChannel
import dev.raseel.lostandfound.features.viewer.ViewerChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The one activity. It owns what only an activity can do (the window, the notification taps that start it, the
 * folder picker's result) and hands every method channel call to the feature that owns it.
 */
class MainActivity : FlutterActivity() {

    companion object {
        /** What a tap on the scan's notification (indexing or faces) opens with: the Library tab, where the scan is. */
        const val ACTION_OPEN_LIBRARY = "dev.raseel.lostandfound.OPEN_LIBRARY"

        /** What a tap on the stories note opens with: the Search tab, where the rings are. */
        const val ACTION_OPEN_STORIES = "dev.raseel.lostandfound.OPEN_STORIES"

        private const val CHANNEL = "lostandfound/native"
    }

    val picker = SafPicker(this)

    private val home = HomeChannel(this)
    private val memories = MemoriesChannel(this)

    /** In the order calls are offered to them. Every call belongs to exactly one. */
    private val channels: List<FeatureChannel> = listOf(
        home,
        LibraryChannel(this),
        SearchChannel(this),
        CollectionsChannel(this),
        ViewerChannel(this),
        MediaChannel(this),
        ModelDownloadChannel(this),
        SettingsChannel(this),
        memories,
        PeopleChannel(this),
        ExportChannel(this),
    )

    /**
     * Notes the tap that started the Activity, but not when it is only recreated, because that tap was already shown.
     * Draws behind the system bars with the navigation bar in the app background colour, because some OEM skins (a
     * vivo/iQOO was tested) keep an opaque black bar unless the window opts in natively. Keeps the daily memory
     * scheduled.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        memories.noteTap(intent)
        if (savedInstanceState == null) home.noteTap(intent)
        try { MemoryScheduler.apply(applicationContext) } catch (_: Exception) {}

        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.WHITE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
            window.isStatusBarContrastEnforced = false
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        memories.noteTap(intent)
        home.noteTap(intent)
    }

    /**
     * The app is left: makes sure the "finish indexing" note is waiting. It comes only if the library is not all
     * indexed then.
     */
    override fun onStop() {
        super.onStop()
        try { IndexNudge.ensureArmed(applicationContext) } catch (_: Exception) {}
    }

    /** The app is in use: unanswered stories notes stop counting. */
    override fun onResume() {
        super.onResume()
        try { StoriesReminder.noteOpened(applicationContext) } catch (_: Exception) {}
    }

    /**
     * Registers the method channel handlers. Anything that can block (hashing a model, reading the whole store,
     * SQLite) runs on a dedicated executor, never on the platform thread. Starting a scan replaces any queued one,
     * because Dart calls it only when nothing is scanning, and its result comes when the work is enqueued, not
     * finished.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            if (channels.none { it.handle(call, result) }) result.notImplemented()
        }

        channels.forEach { it.registerStreams(messenger) }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        picker.onResult(requestCode, resultCode, data)
    }
}
