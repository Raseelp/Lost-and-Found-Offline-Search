package dev.raseel.lostandfound

import android.app.Application
import dev.raseel.lostandfound.core.log.AppLog
import dev.raseel.lostandfound.features.settings.ReportMail
import kotlin.concurrent.thread

/** The app. It starts the log file, so what happens from the first moment is in a problem report, and clears what an earlier report left behind. */
class LostFoundApp : Application() {
    override fun onCreate() {
        super.onCreate()
        AppLog.init(this)
        thread(isDaemon = true) { ReportMail.cleanUp(this) }
    }
}
