package org.buetow.turbomon.platform

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.TrafficStats
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.StatFs
import android.os.SystemClock
import android.os.storage.StorageManager
import java.io.File

/** Device-wide readings that every app may take without special rights. */
class SystemInfo(private val context: Context) {
    private val activityManager = context.getSystemService(ActivityManager::class.java)
    private val batteryManager = context.getSystemService(BatteryManager::class.java)
    private val powerManager = context.getSystemService(PowerManager::class.java)

    fun device(): Map<String, Any?> = mapOf(
        "manufacturer" to Build.MANUFACTURER,
        "model" to Build.MODEL,
        "device" to Build.DEVICE,
        "hardware" to Build.HARDWARE,
        "board" to Build.BOARD,
        "socModel" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Build.SOC_MODEL else null,
        "release" to Build.VERSION.RELEASE,
        "sdk" to Build.VERSION.SDK_INT,
        "kernel" to System.getProperty("os.version"),
        "abis" to Build.SUPPORTED_ABIS.toList(),
        "cores" to Runtime.getRuntime().availableProcessors(),
    )

    fun memory(): Map<String, Any?> {
        val info = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(info)
        return mapOf(
            "total" to info.totalMem,
            "available" to info.availMem,
            "threshold" to info.threshold,
            "low" to info.lowMemory,
        )
    }

    /**
     * Battery state from the sticky ACTION_BATTERY_CHANGED broadcast plus
     * BatteryManager properties. The current is returned raw (µA on most
     * devices); the Dart side normalises sign and unit against [charging].
     */
    fun battery(): Map<String, Any?> {
        val sticky = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = sticky?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = sticky?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val status = sticky?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        return mapOf(
            "percent" to if (level >= 0 && scale > 0) level * 100.0 / scale else null,
            "status" to statusName(status),
            "charging" to (status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL),
            "plugged" to pluggedName(sticky?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0),
            "health" to healthName(sticky?.getIntExtra(BatteryManager.EXTRA_HEALTH, 0) ?: 0),
            "temperatureC" to sticky?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
                ?.takeIf { it != Int.MIN_VALUE }?.let { it / 10.0 },
            "voltageMv" to sticky?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1)?.takeIf { it > 0 },
            "technology" to sticky?.getStringExtra(BatteryManager.EXTRA_TECHNOLOGY),
            "currentNow" to property(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW),
            "currentAverage" to property(BatteryManager.BATTERY_PROPERTY_CURRENT_AVERAGE),
            "chargeCounter" to property(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER),
            "screenOn" to powerManager.isInteractive,
        )
    }

    /** Thermal status (API 29+) and headroom (API 30+); null where unsupported. */
    fun thermal(): Map<String, Any?> = mapOf(
        "status" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) powerManager.currentThermalStatus else null,
        "headroom" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            powerManager.getThermalHeadroom(0).takeIf { !it.isNaN() }?.toDouble()
        } else {
            null
        },
    )

    /** Byte counters since boot; the Dart side turns two readings into rates. */
    fun traffic(): Map<String, Any?> = mapOf(
        "elapsedMs" to SystemClock.elapsedRealtime(),
        "totalRx" to TrafficStats.getTotalRxBytes(),
        "totalTx" to TrafficStats.getTotalTxBytes(),
        "mobileRx" to TrafficStats.getMobileRxBytes(),
        "mobileTx" to TrafficStats.getMobileTxBytes(),
    )

    /** Mounted volumes with StatFs totals: internal storage, SD cards, USB drives. */
    fun storageVolumes(): List<Map<String, Any?>> {
        val storage = context.getSystemService(StorageManager::class.java)
        val volumes = mutableListOf<Map<String, Any?>>()
        val seen = mutableSetOf<String>()
        fun add(label: String, dir: File?, removable: Boolean, primary: Boolean) {
            if (dir == null || !seen.add(dir.absolutePath)) return
            val stat = runCatching { StatFs(dir.absolutePath) }.getOrNull() ?: return
            volumes += mapOf(
                "label" to label,
                "path" to dir.absolutePath,
                "removable" to removable,
                "primary" to primary,
                "total" to stat.totalBytes,
                "free" to stat.availableBytes,
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            for (volume in storage.storageVolumes) {
                add(volume.getDescription(context), volume.directory, volume.isRemovable, volume.isPrimary)
            }
        } else {
            // Before API 30 a volume is only reachable through its app-specific
            // directory; StatFs reports the whole volume for any path on it.
            context.getExternalFilesDirs(null).filterNotNull().forEachIndexed { index, dir ->
                add(if (index == 0) "Internal shared storage" else "SD card", dir, index > 0, index == 0)
            }
        }
        return volumes
    }

    private fun property(id: Int): Long? =
        batteryManager.getLongProperty(id).takeIf { it != Long.MIN_VALUE && it != 0L }

    private fun statusName(status: Int) = when (status) {
        BatteryManager.BATTERY_STATUS_CHARGING -> "charging"
        BatteryManager.BATTERY_STATUS_DISCHARGING -> "discharging"
        BatteryManager.BATTERY_STATUS_FULL -> "full"
        BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "not charging"
        else -> "unknown"
    }

    private fun pluggedName(plugged: Int) = when (plugged) {
        BatteryManager.BATTERY_PLUGGED_AC -> "AC"
        BatteryManager.BATTERY_PLUGGED_USB -> "USB"
        BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
        0 -> null
        else -> "other"
    }

    private fun healthName(health: Int) = when (health) {
        BatteryManager.BATTERY_HEALTH_GOOD -> "good"
        BatteryManager.BATTERY_HEALTH_OVERHEAT -> "overheat"
        BatteryManager.BATTERY_HEALTH_DEAD -> "dead"
        BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "over voltage"
        BatteryManager.BATTERY_HEALTH_COLD -> "cold"
        BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "failure"
        else -> "unknown"
    }
}
