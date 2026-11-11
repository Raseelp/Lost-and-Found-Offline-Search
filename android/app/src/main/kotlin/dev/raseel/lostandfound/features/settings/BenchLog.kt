package dev.raseel.lostandfound.features.settings

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import java.io.File

/**
 * The performance logs for finding where indexing's time goes.
 * CLIP and faces both log through here under [TAG], so they can be read side by side. The "Performance logs" setting
 * switches them, and they are on unless the user turns them off.
 */
object BenchLog {

    const val TAG = "LostFoundBench"

    private const val PREFS = "bench_log"
    private const val KEY_ENABLED = "enabled"

    @Volatile
    private var cached: Boolean? = null

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun enabled(context: Context): Boolean =
        cached ?: synchronized(this) {
            cached ?: prefs(context).getBoolean(KEY_ENABLED, true).also { cached = it }
        }

    fun setEnabled(context: Context, value: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, value).apply()
        cached = value
    }

    /** Logs [message] if the logs are on. The message is only built then. */
    fun log(context: Context, message: () -> String) {
        if (enabled(context)) Log.i(TAG, message())
    }

    /**
     * The phone's state in one short string for the timing lines, so a model that slows down over a long scan can be
     * told from a throttling phone. It holds the thermal status, the thermal headroom (0 is cool, 1 is the limit), the
     * battery temperature in degrees C and [cpuSpeeds]. Older Android versions and some phones lack the first two.
     */
    fun device(context: Context): String {
        val parts = ArrayList<String>()
        try {
            val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                parts += "thermal=${thermalName(power.currentThermalStatus)}"
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val headroom = power.getThermalHeadroom(10)
                if (!headroom.isNaN()) parts += "headroom=${"%.2f".format(headroom)}"
            }
            if (power.isPowerSaveMode) parts += "BATTERY-SAVER"
        } catch (_: Exception) {
        }
        try {
            val battery = context.applicationContext
                .registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val tenths = battery?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE) ?: Int.MIN_VALUE
            if (tenths != Int.MIN_VALUE) parts += "battery=${"%.1f".format(tenths / 10.0)}C"
        } catch (_: Exception) {
        }
        cpuSpeeds()?.let { parts += it }
        return parts.joinToString(" ")
    }

    private fun thermalName(status: Int): String = when (status) {
        PowerManager.THERMAL_STATUS_NONE -> "NONE"
        PowerManager.THERMAL_STATUS_LIGHT -> "LIGHT"
        PowerManager.THERMAL_STATUS_MODERATE -> "MODERATE"
        PowerManager.THERMAL_STATUS_SEVERE -> "SEVERE"
        PowerManager.THERMAL_STATUS_CRITICAL -> "CRITICAL"
        PowerManager.THERMAL_STATUS_EMERGENCY -> "EMERGENCY"
        PowerManager.THERMAL_STATUS_SHUTDOWN -> "SHUTDOWN"
        else -> "status$status"
    }

    /**
     * The current and maximum MHz per group of cores that share a maximum, such as
     * "cpu[MHz now/max] 0-3:1180/1800 4-5:1500/2400". A cluster far below its maximum is
     * a throttled one. Null when the phone does not let an app read the current speed.
     */
    private fun cpuSpeeds(): String? {
        val count = Runtime.getRuntime().availableProcessors()
        val now = LongArray(count)
        val max = LongArray(count)
        for (i in 0 until count) {
            val dir = "/sys/devices/system/cpu/cpu$i/cpufreq/"
            try {
                now[i] = File(dir + "scaling_cur_freq").readText().trim().toLong()
                max[i] = File(dir + "cpuinfo_max_freq").readText().trim().toLong()
            } catch (_: Exception) {
                return null
            }
        }
        val groups = StringBuilder("cpu[MHz now/max]")
        var start = 0
        while (start < count) {
            var end = start
            while (end + 1 < count && max[end + 1] == max[start]) end++
            val avgNow = (start..end).map { now[it] }.average() / 1000.0
            val label = if (start == end) "$start" else "$start-$end"
            groups.append(" $label:${avgNow.toInt()}/${max[start] / 1000}")
            start = end + 1
        }
        return groups.toString()
    }
}
