package org.buetow.turbomon

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.TrafficStats
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.os.storage.StorageManager
import android.system.Os
import android.system.OsConstants
import java.io.File

/**
 * Readings that need Android APIs, shared by the Flutter channel (live
 * screens) and the background service. Everything returns plain maps or
 * numbers and never throws: a missing reading is null.
 */
object Metrics {
    fun readFile(path: String): String? =
        try {
            File(path).readText()
        } catch (e: Exception) {
            null
        }

    fun deviceInfo(): Map<String, Any?> =
        mapOf(
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "device" to Build.DEVICE,
            "release" to Build.VERSION.RELEASE,
            "sdk" to Build.VERSION.SDK_INT,
            "kernel" to System.getProperty("os.version"),
            "abi" to Build.SUPPORTED_ABIS.firstOrNull(),
            "cores" to Runtime.getRuntime().availableProcessors(),
            "pageSize" to Os.sysconf(OsConstants._SC_PAGESIZE),
            "board" to Build.BOARD,
            "hardware" to Build.HARDWARE,
        )

    fun memory(context: Context): Map<String, Any?> {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val info = ActivityManager.MemoryInfo()
        am.getMemoryInfo(info)
        return mapOf(
            "totalBytes" to info.totalMem,
            "availBytes" to info.availMem,
            "lowMemory" to info.lowMemory,
            "thresholdBytes" to info.threshold,
        )
    }

    /** RAM used in percent, from /proc/meminfo or ActivityManager. */
    fun ramPercent(context: Context): Double? {
        val text = readFile("/proc/meminfo")
        if (text != null) {
            val values = HashMap<String, Long>()
            for (line in text.lineSequence()) {
                val parts = line.split(Regex("\\s+"))
                if (parts.size >= 2) parts[1].toLongOrNull()?.let { values[parts[0].trimEnd(':')] = it }
            }
            val total = values["MemTotal"]
            val avail = values["MemAvailable"]
            if (total != null && avail != null && total > 0) return (total - avail) * 100.0 / total
        }
        val m = memory(context)
        val total = m["totalBytes"] as Long
        val avail = m["availBytes"] as Long
        return if (total > 0) (total - avail) * 100.0 / total else null
    }

    fun battery(context: Context): Map<String, Any?> {
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val bm = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, 100) ?: 100
        val status =
            when (intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1)) {
                BatteryManager.BATTERY_STATUS_CHARGING -> "charging"
                BatteryManager.BATTERY_STATUS_DISCHARGING -> "discharging"
                BatteryManager.BATTERY_STATUS_FULL -> "full"
                BatteryManager.BATTERY_STATUS_NOT_CHARGING -> "not_charging"
                else -> "unknown"
            }
        val plugged =
            when (intent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0)) {
                BatteryManager.BATTERY_PLUGGED_AC -> "ac"
                BatteryManager.BATTERY_PLUGGED_USB -> "usb"
                BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
                else -> "none"
            }
        val health =
            when (intent?.getIntExtra(BatteryManager.EXTRA_HEALTH, 0)) {
                BatteryManager.BATTERY_HEALTH_GOOD -> "good"
                BatteryManager.BATTERY_HEALTH_OVERHEAT -> "overheat"
                BatteryManager.BATTERY_HEALTH_DEAD -> "dead"
                BatteryManager.BATTERY_HEALTH_OVER_VOLTAGE -> "over_voltage"
                BatteryManager.BATTERY_HEALTH_COLD -> "cold"
                BatteryManager.BATTERY_HEALTH_UNSPECIFIED_FAILURE -> "failure"
                else -> "unknown"
            }
        val temp = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE) ?: Int.MIN_VALUE
        val volt = intent?.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1) ?: -1
        val current = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CURRENT_NOW)
        val counter = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER)
        return mapOf(
            "level" to if (level >= 0 && scale > 0) level * 100 / scale else null,
            "status" to status,
            "plugged" to plugged,
            "health" to health,
            "tempC" to if (temp == Int.MIN_VALUE) null else temp / 10.0,
            "voltageMv" to if (volt > 0) volt else null,
            "currentNowUa" to if (current == Int.MIN_VALUE || current == 0) null else current,
            "chargeCounterUah" to if (counter == Int.MIN_VALUE || counter <= 0) null else counter,
        )
    }

    /**
     * Drain in mA, positive while discharging. CURRENT_NOW is documented as
     * µA (positive = charging) but vendors differ in unit and sign; see
     * normalizeCurrentMa in lib/model/readings.dart, which this mirrors.
     */
    fun drainMa(b: Map<String, Any?>): Double? {
        val raw = (b["currentNowUa"] as Int?) ?: return null
        var ma = if (Math.abs(raw) > 20000) raw / 1000.0 else raw.toDouble()
        val charging = b["status"] == "charging"
        if (charging && ma < 0) ma = -ma
        if (!charging && ma > 0) ma = -ma
        return if (ma < 0) -ma else 0.0
    }

    fun powerW(b: Map<String, Any?>): Double? {
        val raw = (b["currentNowUa"] as Int?) ?: return null
        val mv = (b["voltageMv"] as Int?) ?: return null
        val ma = if (Math.abs(raw) > 20000) raw / 1000.0 else raw.toDouble()
        return Math.abs(ma) / 1000.0 * mv / 1000.0
    }

    fun traffic(): Map<String, Any?> =
        mapOf(
            "totalRx" to TrafficStats.getTotalRxBytes(),
            "totalTx" to TrafficStats.getTotalTxBytes(),
            "mobileRx" to TrafficStats.getMobileRxBytes(),
            "mobileTx" to TrafficStats.getMobileTxBytes(),
        )

    fun thermal(context: Context): Map<String, Any?> {
        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val status = if (Build.VERSION.SDK_INT >= 29) pm.currentThermalStatus else null
        val headroom =
            if (Build.VERSION.SDK_INT >= 30) {
                val h = pm.getThermalHeadroom(10)
                if (h.isNaN()) null else h.toDouble()
            } else {
                null
            }
        return mapOf("status" to status, "headroom" to headroom)
    }

    fun storageVolumes(context: Context): List<Map<String, Any?>> {
        val out = ArrayList<Map<String, Any?>>()
        val data = Environment.getDataDirectory()
        val internal = StatFs(data.path)
        out.add(
            mapOf(
                "label" to "Internal storage",
                "path" to data.path,
                "totalBytes" to internal.totalBytes,
                "freeBytes" to internal.availableBytes,
                "removable" to false,
            ),
        )
        if (Build.VERSION.SDK_INT >= 30) {
            val sm = context.getSystemService(Context.STORAGE_SERVICE) as StorageManager
            for (v in sm.storageVolumes) {
                if (!v.isRemovable || v.state != Environment.MEDIA_MOUNTED) continue
                val dir = v.directory ?: continue
                try {
                    val fs = StatFs(dir.path)
                    out.add(
                        mapOf(
                            "label" to v.getDescription(context),
                            "path" to dir.path,
                            "totalBytes" to fs.totalBytes,
                            "freeBytes" to fs.availableBytes,
                            "removable" to true,
                        ),
                    )
                } catch (e: Exception) {
                    // Volume went away between listing and reading.
                }
            }
        }
        return out
    }

    /** Average core frequency as a share of maximum, the no-root CPU proxy. */
    fun cpuFreqPercent(): Double? {
        val n = Runtime.getRuntime().availableProcessors()
        var sum = 0.0
        var count = 0
        for (i in 0 until 16.coerceAtLeast(n)) {
            val base = "/sys/devices/system/cpu/cpu$i/cpufreq"
            val cur = readFile("$base/scaling_cur_freq")?.trim()?.toLongOrNull() ?: continue
            val max = readFile("$base/cpuinfo_max_freq")?.trim()?.toLongOrNull() ?: continue
            if (max <= 0) continue
            sum += (cur * 100.0 / max).coerceIn(0.0, 100.0)
            count++
        }
        return if (count == 0) null else sum / count
    }

    /** (busy, total) jiffies of the aggregate cpu line of /proc/stat. */
    fun parseProcStat(text: String): Pair<Long, Long>? {
        val line = text.lineSequence().firstOrNull { it.startsWith("cpu ") } ?: return null
        val nums = line.trim().split(Regex("\\s+")).drop(1).mapNotNull { it.toLongOrNull() }.take(8)
        if (nums.size < 4) return null
        val idle = nums[3] + (if (nums.size > 4) nums[4] else 0L)
        val total = nums.sum()
        return Pair(total - idle, total)
    }

    /** Hottest SoC-like thermal zone in °C from `type=temp` lines. */
    fun hottestZone(text: String): Double? {
        var best: Double? = null
        var bestAny: Double? = null
        val soc = Regex("cpu|soc|tsens|big|little|mid|ap|tz", RegexOption.IGNORE_CASE)
        for (line in text.lineSequence()) {
            val i = line.lastIndexOf('=')
            if (i <= 0) continue
            val raw = line.substring(i + 1).trim().toDoubleOrNull() ?: continue
            val c = if (Math.abs(raw) > 1000) raw / 1000 else raw
            if (c < -40 || c > 150) continue
            if (bestAny == null || c > bestAny) bestAny = c
            if (soc.containsMatchIn(line.substring(0, i)) && (best == null || c > best)) best = c
        }
        return best ?: bestAny
    }

    fun thermalZonesDirect(): String {
        val sb = StringBuilder()
        for (i in 0 until 100) {
            val type = readFile("/sys/class/thermal/thermal_zone$i/type")?.trim() ?: if (i == 0) continue else break
            val temp = readFile("/sys/class/thermal/thermal_zone$i/temp")?.trim() ?: continue
            sb.append(type).append('=').append(temp).append('\n')
        }
        return sb.toString()
    }

    const val THERMAL_ZONES_COMMAND =
        "for z in /sys/class/thermal/thermal_zone*; do echo \"\$(cat \$z/type)=\$(cat \$z/temp)\"; done 2>/dev/null"

    val GPU_PATHS =
        listOf(
            "/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage",
            "/sys/class/kgsl/kgsl-3d0/gpubusy",
            "/sys/kernel/gpu/gpu_busy",
            "/sys/class/misc/mali0/device/utilization",
            "/sys/devices/platform/mali.0/utilization",
            "/sys/module/ged/parameters/gpu_loading",
        )

    fun parseGpu(path: String, text: String): Double? {
        val t = text.trim()
        if (t.isEmpty()) return null
        if (path.endsWith("/gpubusy")) {
            val p = t.split(Regex("\\s+"))
            val busy = p.getOrNull(0)?.toLongOrNull() ?: return null
            val total = p.getOrNull(1)?.toLongOrNull() ?: return null
            return if (total == 0L) null else (busy * 100.0 / total).coerceIn(0.0, 100.0)
        }
        val v = Regex("(\\d+(?:\\.\\d+)?)").find(t)?.value?.toDoubleOrNull() ?: return null
        return if (v > 100) null else v
    }

    /** Sum of read and written sectors (512 B) over whole disks in /proc/diskstats. */
    fun parseDiskSectors(text: String): Pair<Long, Long> {
        var r = 0L
        var w = 0L
        val whole = Regex("^(sd[a-z]+|mmcblk\\d+|nvme\\d+n\\d+|vd[a-z]+)$")
        for (line in text.lineSequence()) {
            val p = line.trim().split(Regex("\\s+"))
            if (p.size < 10 || !whole.matches(p[2])) continue
            r += p[5].toLongOrNull() ?: 0
            w += p[9].toLongOrNull() ?: 0
        }
        return Pair(r, w)
    }
}
