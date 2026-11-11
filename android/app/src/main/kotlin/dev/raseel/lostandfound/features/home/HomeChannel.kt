package dev.raseel.lostandfound.features.home

import android.content.Intent
import dev.raseel.lostandfound.MainActivity
import dev.raseel.lostandfound.core.native.FeatureChannel
import dev.raseel.lostandfound.features.settings.IndexNudge
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel


class HomeChannel(activity: MainActivity) : FeatureChannel(activity) {

    /** The home tab a tapped notification wants shown, not yet taken by the app (takeOpenTab); -1: none. */
    @Volatile
    private var openTab = -1
    /** The "Index now" button of the note was pressed. takeIndexNow gives it to the app once. */
    @Volatile
    private var indexNow = false
    fun noteTap(intent: Intent?) {
        when (intent?.action) {
            MainActivity.ACTION_OPEN_LIBRARY -> openTab = TAB_LIBRARY
            MainActivity.ACTION_OPEN_STORIES -> openTab = TAB_SEARCH
            IndexNudge.ACTION_INDEX_NOW -> {
                openTab = TAB_LIBRARY
                indexNow = true
            }
        }
    }
    private companion object {
        /** The home tabs a notification can open (as the app numbers them). */
        const val TAB_SEARCH = 0
        const val TAB_LIBRARY = 2
    }

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {

            "takeOpenTab" -> {
                result.success(openTab)
                openTab = -1
            }

            "takeIndexNow" -> {
                result.success(indexNow)
                indexNow = false
            }

            else -> return false
        }
        return true
    }
}
