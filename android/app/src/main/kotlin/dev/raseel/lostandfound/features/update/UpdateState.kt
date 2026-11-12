package dev.raseel.lostandfound.features.update

import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability

/** What Google Play says about an update, in the words the app uses. */
object UpdateState {
    const val NONE = "none"
    const val AVAILABLE = "available"
    const val DOWNLOADING = "downloading"
    const val DOWNLOADED = "downloaded"

    /**
     * An update that is downloaded or on its way comes first, because Play still says one is available then. An update is
     * offered only if it can be installed in the background while the app is used, which is what the app asks for.
     */
    fun of(installStatus: Int, availability: Int, backgroundAllowed: Boolean): String = when {
        installStatus == InstallStatus.DOWNLOADED -> DOWNLOADED
        installStatus == InstallStatus.DOWNLOADING || installStatus == InstallStatus.PENDING -> DOWNLOADING
        availability == UpdateAvailability.UPDATE_AVAILABLE && backgroundAllowed -> AVAILABLE
        else -> NONE
    }
}
