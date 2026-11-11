package dev.raseel.lostandfound.features.settings

import android.os.Build
import dev.raseel.lostandfound.BuildConfig
import dev.raseel.lostandfound.MainActivity
import dev.raseel.lostandfound.core.native.FeatureChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel


class SettingsChannel(activity: MainActivity) : FeatureChannel(activity) {

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {

            "getBenchLogs" -> result.success(BenchLog.enabled(applicationContext))

            "setBenchLogs" -> {
                BenchLog.setEnabled(applicationContext, call.argument<Boolean>("enabled") ?: true)
                result.success(true)
            }

            "appLogs" -> logExecutor.execute {
                try {
                    val text = LogDump.collect(applicationContext)
                    runOnUiThread { result.success(text) }
                } catch (e: Throwable) {
                    runOnUiThread { result.error("LOGS_FAILED", e.message, null) }
                }
            }

            "androidSdk" -> result.success(Build.VERSION.SDK_INT)

            "getIndexNudge" -> result.success(IndexNudge.enabled(applicationContext))

            "setIndexNudge" -> {
                IndexNudge.setEnabled(applicationContext, call.argument<Boolean>("enabled") ?: true)
                result.success(true)
            }

            "buildInfo" -> result.success(
                mapOf(
                    "version" to BuildConfig.VERSION_NAME,
                    "build" to BuildConfig.VERSION_CODE,
                    "commit" to BuildConfig.GIT_COMMIT,
                    "commitDate" to BuildConfig.GIT_COMMIT_DATE,
                    "debug" to BuildConfig.DEBUG,
                ),
            )

            "deviceChip" -> {
                val soc = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
                val cores = Runtime.getRuntime().availableProcessors()
                var maxKhz = 0L
                for (i in 0 until cores) {
                    try {
                        val khz = java.io.File("/sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq")
                            .readText().trim().toLong()
                        if (khz > maxKhz) maxKhz = khz
                    } catch (_: Exception) {
                    }
                }
                val memory = android.app.ActivityManager.MemoryInfo()
                (getSystemService(android.content.Context.ACTIVITY_SERVICE) as android.app.ActivityManager)
                    .getMemoryInfo(memory)
                result.success(
                    mapOf(
                        "maker" to (if (soc) Build.SOC_MANUFACTURER else ""),
                        "model" to (if (soc) Build.SOC_MODEL else ""),
                        "hardware" to Build.HARDWARE,
                        "cores" to cores,
                        "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: ""),
                        "maxMhz" to (maxKhz / 1000).toInt(),
                        "ramMb" to (memory.totalMem / (1024 * 1024)).toInt(),
                        "release" to Build.VERSION.RELEASE,
                    )
                )
            }

            else -> return false
        }
        return true
    }
}
