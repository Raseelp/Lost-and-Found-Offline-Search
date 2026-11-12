package dev.raseel.lostandfound.features.update

import android.app.Activity
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallState
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability
import dev.raseel.lostandfound.MainActivity
import dev.raseel.lostandfound.core.log.AppLog
import dev.raseel.lostandfound.core.native.FeatureChannel
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Asks Google Play whether a newer version of the app is waiting, and starts the update. Play shows its own consent
 * screen, downloads the update while the app is used, and the app restarts into it when the person says so. Nothing
 * goes to the developer, and a build that did not come from Play simply finds no update.
 */
class UpdateChannel(activity: MainActivity) : FeatureChannel(activity) {

    private val manager: AppUpdateManager by lazy { AppUpdateManagerFactory.create(applicationContext) }
    private var sink: EventChannel.EventSink? = null
    private var listening = false

    private val listener = InstallStateUpdatedListener { state -> report(state) }

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {

            "checkForUpdate" -> manager.appUpdateInfo
                .addOnSuccessListener { info -> result.success(describe(info)) }
                .addOnFailureListener { e ->
                    AppLog.i(TAG, "no update check: ${e.message}")
                    result.success(mapOf("state" to UpdateState.NONE))
                }

            "startUpdate" -> manager.appUpdateInfo
                .addOnSuccessListener { info -> start(info, result) }
                .addOnFailureListener { e ->
                    AppLog.w(TAG, "the update could not be started: ${e.message}")
                    result.success("failed")
                }

            "completeUpdate" -> {
                manager.completeUpdate()
                result.success(null)
            }

            else -> return false
        }
        return true
    }

    override fun registerStreams(messenger: BinaryMessenger) {
        EventChannel(messenger, "lostandfound/updateStatus").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                sink = events
            }

            override fun onCancel(arguments: Any?) {
                sink = null
            }
        })
    }

    /** Lets go of Play's listener when the activity goes. */
    fun release() = stopListening()

    private fun describe(info: AppUpdateInfo): Map<String, Any> {
        val state = UpdateState.of(
            info.installStatus(),
            info.updateAvailability(),
            info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
        )
        // A download started before the app was opened again goes on, so follow it from here.
        if (state == UpdateState.DOWNLOADING) startListening()
        return mapOf("state" to state, "versionCode" to info.availableVersionCode())
    }

    private fun start(info: AppUpdateInfo, result: MethodChannel.Result) {
        val offered = info.updateAvailability() == UpdateAvailability.UPDATE_AVAILABLE &&
            info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE)
        if (!offered) {
            result.success("failed")
            return
        }
        startListening()
        manager.startUpdateFlow(info, activity, AppUpdateOptions.newBuilder(AppUpdateType.FLEXIBLE).build())
            .addOnSuccessListener { code ->
                when (code) {
                    Activity.RESULT_OK -> result.success("accepted")
                    Activity.RESULT_CANCELED -> {
                        stopListening()
                        result.success("declined")
                    }
                    else -> {
                        stopListening()
                        result.success("failed")
                    }
                }
            }
            .addOnFailureListener { e ->
                AppLog.w(TAG, "the update flow failed: ${e.message}")
                stopListening()
                result.success("failed")
            }
    }

    private fun startListening() {
        if (listening) return
        manager.registerListener(listener)
        listening = true
    }

    private fun stopListening() {
        if (!listening) return
        manager.unregisterListener(listener)
        listening = false
    }

    /** Tells the app how the download is going, and lets go of Play's listener once it has ended one way or the other. */
    private fun report(state: InstallState) {
        val event: Map<String, Any> = when (state.installStatus()) {
            InstallStatus.DOWNLOADING -> mapOf(
                "status" to "downloading",
                "bytes" to state.bytesDownloaded(),
                "total" to state.totalBytesToDownload(),
            )
            InstallStatus.DOWNLOADED -> mapOf("status" to "downloaded")
            InstallStatus.INSTALLED -> mapOf("status" to "installed")
            InstallStatus.FAILED, InstallStatus.CANCELED -> mapOf("status" to "failed")
            else -> return
        }
        sink?.success(event)
        if (event["status"] != "downloading") stopListening()
    }

    private companion object {
        const val TAG = "UpdateChannel"
    }
}
