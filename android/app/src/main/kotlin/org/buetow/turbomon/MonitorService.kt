package org.buetow.turbomon

import android.annotation.SuppressLint
import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.Color
import android.graphics.PixelFormat
import android.net.TrafficStats
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Background scanning: a foreground service with a permanent notification
 * that samples the monitors chosen in Settings at their own intervals,
 * appends each sample to files/history/YYYY-MM-DD.jsonl, raises alerts,
 * feeds the widget and overlay, and stops itself as configured.
 *
 * Snapshots are not written here: the service leaves a request in
 * files/snapshot-requests/ and the app turns it into a report, so the
 * report format lives in one place (lib/services/snapshot.dart).
 */
class MonitorService : Service() {
    private lateinit var thread: HandlerThread
    private lateinit var handler: Handler
    private val main = Handler(Looper.getMainLooper())
    private var config = JSONObject()
    private var startedAt = 0L
    private var stopAt: Long? = null
    private val lastSampled = HashMap<String, Long>()
    private var runner: ((String) -> ExecResult)? = null
    private var accessChecked = 0L

    // Previous counters for rates.
    private var prevStat: Pair<Long, Long>? = null
    private var prevTraffic: Pair<Long, Long>? = null
    private var prevTrafficAt = 0L
    private var prevDisk: Pair<Long, Long>? = null
    private var prevDiskAt = 0L
    private var prevPidTicks: Map<Int, Long> = emptyMap()
    private var prevTotalForPids: Long? = null

    // Alert state, as in lib/services/alerts.dart.
    private val overSince = HashMap<String, Long>()
    private val lastFired = HashMap<String, Long>()

    // Latest values for the overlay, widget and notification.
    private val latest = HashMap<String, Any?>()
    private var overlay: TextView? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        thread = HandlerThread("turbomon-sampler").also { it.start() }
        handler = Handler(thread.looper)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                finish("Stopped by hand")
                return START_NOT_STICKY
            }
            ACTION_UPDATE -> {
                config = loadConfig(this)
                handler.post { applyOverlay() }
                return START_NOT_STICKY
            }
        }
        config = loadConfig(this)
        val wasRunning = running
        running = true
        if (!wasRunning) {
            startedAt = System.currentTimeMillis()
            stopAt = computeStopAt(startedAt)
            saveState()
        }
        startInForeground()
        if (!wasRunning) {
            handler.post {
                runner = Privileged.runnerFor(this, config.optString("accessMode", "auto"))
                accessChecked = System.currentTimeMillis()
                append(JSONObject().put("t", startedAt).put("event", "start").put("monitors", config.optJSONArray("monitors")))
                pruneHistory()
                tick()
            }
        }
        return START_NOT_STICKY
    }

    private fun computeStopAt(start: Long): Long? {
        val a = config.optJSONObject("autoStop") ?: return null
        return when (a.optString("kind")) {
            "duration" -> start + a.optLong("minutes", 60) * 60_000
            "timeOfDay" -> {
                val cal = java.util.Calendar.getInstance()
                cal.timeInMillis = start
                cal.set(java.util.Calendar.HOUR_OF_DAY, a.optInt("hour", 7))
                cal.set(java.util.Calendar.MINUTE, a.optInt("minute", 0))
                cal.set(java.util.Calendar.SECOND, 0)
                if (cal.timeInMillis <= start) cal.add(java.util.Calendar.DAY_OF_MONTH, 1)
                cal.timeInMillis
            }
            else -> null
        }
    }

    private fun monitors(): Set<String> {
        val arr = config.optJSONArray("monitors") ?: return emptySet()
        return (0 until arr.length()).map { arr.getString(it) }.toSet()
    }

    private fun intervalMs(m: String): Long =
        (config.optJSONObject("intervals")?.optInt(m, 30) ?: 30).coerceAtLeast(5) * 1000L

    private fun overlayOn() = config.optBoolean("overlay") && Settings.canDrawOverlays(this)

    /** One pass: sample what is due, write it, check alerts and auto-stop. */
    private fun tick() {
        if (!running) return
        val now = System.currentTimeMillis()
        // Shizuku may start or be granted after the run began.
        if (runner == null && now - accessChecked > 300_000) {
            runner = Privileged.runnerFor(this, config.optString("accessMode", "auto"))
            accessChecked = now
        }
        val due = monitors().filter { now - (lastSampled[it] ?: 0L) >= intervalMs(it) - 500 }.toSet()
        // The overlay and widget want fresh basics even between history samples.
        val live = if (overlayOn()) setOf("cpu", "ram", "battery", "temperature") else emptySet()
        val sample = JSONObject().put("t", now)
        try {
            sampleInto(sample, due + live, due)
        } catch (e: Exception) {
            sample.put("error", e.toString())
        }
        for (m in due) lastSampled[m] = now
        if (due.isNotEmpty()) {
            sample.put("screenOn", (getSystemService(Context.POWER_SERVICE) as PowerManager).isInteractive)
            append(sample)
        }
        checkAlerts(now)
        updateOutputs()
        if (shouldStop(now)) {
            main.post { finish("Auto-stop: ${describeStop()}") }
            return
        }
        val next = (monitors().map { intervalMs(it) } + if (overlayOn()) listOf(5_000L) else emptyList()).minOrNull() ?: 30_000L
        handler.postDelayed({ tick() }, next.coerceIn(5_000L, 60_000L))
    }

    private fun shouldStop(now: Long): Boolean {
        stopAt?.let { if (now >= it) return true }
        val a = config.optJSONObject("autoStop") ?: return false
        if (a.optString("kind") == "batteryBelow") {
            val level = Metrics.battery(this)["level"] as Int? ?: return false
            return level < a.optInt("batteryPercent", 20)
        }
        return false
    }

    private fun describeStop(): String {
        val a = config.optJSONObject("autoStop") ?: return "configured limit"
        return when (a.optString("kind")) {
            "duration" -> "after ${a.optInt("minutes")} min"
            "timeOfDay" -> "at %02d:%02d".format(a.optInt("hour"), a.optInt("minute"))
            "batteryBelow" -> "battery below ${a.optInt("batteryPercent")} %"
            else -> "configured limit"
        }
    }

    private fun read(path: String): String? {
        val direct = Metrics.readFile(path)
        if (!direct.isNullOrEmpty()) return direct
        val r = runner ?: return null
        val res = r("cat $path")
        return if (res.exitCode == 0) res.stdout else null
    }

    @SuppressLint("MissingPermission")
    private fun sampleInto(s: JSONObject, wanted: Set<String>, history: Set<String>) {
        fun put(key: String, value: Any?, monitor: String) {
            latest[key] = value
            if (monitor in history && value != null) s.put(key, value)
        }

        if ("cpu" in wanted || "processes" in wanted) {
            var stat = Metrics.readFile("/proc/stat")
            var procs: JSONArray? = null
            val r = runner
            if (r != null && (stat == null || "processes" in history)) {
                val res =
                    r(
                        "cat /proc/stat; echo '@@TM@@'; ps -A -o PID,USER,NAME; echo '@@TM@@'; cat /proc/[0-9]*/stat 2>/dev/null",
                    )
                val parts = res.stdout.split("@@TM@@")
                if (parts.size == 3) {
                    stat = parts[0]
                    procs = topProcesses(parts[1], parts[2], Metrics.parseProcStat(parts[0])?.second)
                }
            }
            val parsed = stat?.let { Metrics.parseProcStat(it) }
            if (parsed != null) {
                val prev = prevStat
                if (prev != null && parsed.second > prev.second) {
                    put("cpu", (parsed.first - prev.first) * 100.0 / (parsed.second - prev.second), "cpu")
                    latest["cpuProxy"] = false
                    if ("cpu" in history) s.put("cpuProxy", false)
                }
                prevStat = parsed
            } else {
                put("cpu", Metrics.cpuFreqPercent(), "cpu")
                latest["cpuProxy"] = true
                if ("cpu" in history) s.put("cpuProxy", true)
            }
            if (procs != null && "processes" in history) s.put("procs", procs)
        }
        if ("ram" in wanted) put("ram", Metrics.ramPercent(this), "ram")
        if ("gpu" in wanted) {
            for (p in Metrics.GPU_PATHS) {
                val v = read(p)?.let { Metrics.parseGpu(p, it) } ?: continue
                put("gpu", v, "gpu")
                break
            }
        }
        if ("battery" in wanted) {
            val b = Metrics.battery(this)
            put("battLevel", b["level"], "battery")
            put("drainMa", Metrics.drainMa(b), "battery")
            put("powerW", Metrics.powerW(b), "battery")
            put("battTempC", b["tempC"], "battery")
            put("charging", b["status"] == "charging", "battery")
        }
        if ("network" in wanted) {
            val now = System.currentTimeMillis()
            val cur = Pair(TrafficStats.getTotalRxBytes(), TrafficStats.getTotalTxBytes())
            prevTraffic?.let { p ->
                val secs = (now - prevTrafficAt) / 1000.0
                if (secs > 0 && cur.first >= p.first) {
                    put("rxBps", (cur.first - p.first) / secs, "network")
                    put("txBps", (cur.second - p.second) / secs, "network")
                }
            }
            prevTraffic = cur
            prevTrafficAt = now
        }
        if ("temperature" in wanted) {
            val zones = runner?.let { r -> r(Metrics.THERMAL_ZONES_COMMAND).takeIf { it.exitCode == 0 }?.stdout } ?: Metrics.thermalZonesDirect()
            put("hottestC", Metrics.hottestZone(zones), "temperature")
            put("thermal", Metrics.thermal(this)["status"], "temperature")
            put("battTempC", Metrics.battery(this)["tempC"], "temperature")
        }
        if ("diskUsage" in wanted) {
            val fs = StatFs(Environment.getDataDirectory().path)
            put("diskFreeB", fs.availableBytes, "diskUsage")
            put("diskTotalB", fs.totalBytes, "diskUsage")
        }
        if ("diskIo" in wanted) {
            val text = read("/proc/diskstats")
            if (text != null) {
                val now = System.currentTimeMillis()
                val cur = Metrics.parseDiskSectors(text)
                prevDisk?.let { p ->
                    val secs = (now - prevDiskAt) / 1000.0
                    if (secs > 0) {
                        put("diskReadBps", (cur.first - p.first).coerceAtLeast(0) * 512 / secs, "diskIo")
                        put("diskWriteBps", (cur.second - p.second).coerceAtLeast(0) * 512 / secs, "diskIo")
                    }
                }
                prevDisk = cur
                prevDiskAt = now
            }
        }
        if ("wifi" in history) {
            WifiInfo.startScan(this)
            val res = WifiInfo.results(this)
            put("wifiCount", res.size, "wifi")
            put("wifiBest", res.maxOfOrNull { it["rssi"] as Int }, "wifi")
        }
        if ("bluetooth" in history) {
            val seen = bleBurst(8_000)
            if (seen != null) {
                put("btCount", seen.size, "bluetooth")
                put("btBest", seen.values.maxOrNull(), "bluetooth")
            }
        }
    }

    /** Top 10 processes by CPU since the previous sample. */
    private fun topProcesses(psText: String, pidText: String, total: Long?): JSONArray {
        val names = HashMap<Int, String>()
        for (line in psText.lineSequence().drop(1)) {
            val p = line.trim().split(Regex("\\s+"), limit = 3)
            if (p.size == 3) p[0].toIntOrNull()?.let { names[it] = p[2] }
        }
        val ticks = HashMap<Int, Long>()
        val rss = HashMap<Int, Long>()
        for (line in pidText.lineSequence()) {
            val open = line.indexOf('(')
            val close = line.lastIndexOf(')')
            if (open <= 0 || close <= open) continue
            val pid = line.substring(0, open).trim().toIntOrNull() ?: continue
            val rest = line.substring(close + 1).trim().split(Regex("\\s+"))
            if (rest.size < 22) continue
            ticks[pid] = (rest[11].toLongOrNull() ?: 0) + (rest[12].toLongOrNull() ?: 0)
            rss[pid] = (rest[21].toLongOrNull() ?: 0) * 4
            if (pid !in names) names[pid] = line.substring(open + 1, close)
        }
        val prevTotal = prevTotalForPids
        val dTotal = if (total != null && prevTotal != null) total - prevTotal else 0L
        val rows =
            ticks.entries.map { (pid, t) ->
                val before = prevPidTicks[pid]
                val pct = if (before == null || dTotal <= 0) 0.0 else ((t - before) * 100.0 / dTotal).coerceIn(0.0, 100.0)
                Triple(pid, pct, rss[pid] ?: 0)
            }.sortedByDescending { it.second }.take(10)
        prevPidTicks = ticks
        prevTotalForPids = total
        val arr = JSONArray()
        for ((pid, pct, kb) in rows) {
            arr.put(JSONObject().put("pid", pid).put("name", names[pid] ?: "?").put("cpu", Math.round(pct * 10) / 10.0).put("rssKb", kb))
        }
        latest["topProcess"] = rows.firstOrNull()?.let { names[it.first] }
        return arr
    }

    /** A short BLE scan from the sampler thread; returns address to best RSSI. */
    @SuppressLint("MissingPermission")
    private fun bleBurst(ms: Long): Map<String, Int>? {
        val scanner = BluetoothInfo.adapter(this)?.bluetoothLeScanner ?: return null
        val seen = HashMap<String, Int>()
        val cb =
            object : ScanCallback() {
                override fun onScanResult(callbackType: Int, result: ScanResult) {
                    synchronized(seen) {
                        val a = result.device.address
                        seen[a] = maxOf(seen[a] ?: -200, result.rssi)
                    }
                }
            }
        return try {
            scanner.startScan(null, ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_POWER).build(), cb)
            Thread.sleep(ms)
            scanner.stopScan(cb)
            synchronized(seen) { HashMap(seen) }
        } catch (e: Exception) {
            null
        }
    }

    private fun checkAlerts(now: Long) {
        val rules = config.optJSONObject("alerts") ?: return
        val sustain = rules.optInt("sustainSeconds", 60) * 1000L
        fun one(kind: String, title: String, unit: String, enabled: Boolean, value: Double?, limit: Double) {
            if (!enabled || value == null || value < limit) {
                overSince.remove(kind)
                return
            }
            val since = overSince.getOrPut(kind) { now }
            if (now - since < sustain) return
            val last = lastFired[kind]
            if (last != null && now - last < 600_000) return
            lastFired[kind] = now
            val top = latest["topProcess"]?.let { " Top process: $it." } ?: ""
            val msg = "$title: ${value.toInt()} $unit (limit ${limit.toInt()} $unit) for ${(now - since) / 1000} s.$top"
            Notifications.alert(this, 2000 + kind.hashCode() % 100, title, msg)
            append(JSONObject().put("t", now).put("event", "alert").put("alert", JSONObject().put("kind", kind).put("value", value).put("limit", limit).put("message", msg)))
            if (rules.optBoolean("autoSnapshot", true)) {
                requestSnapshot(maxOf(startedAt, since - 600_000), now, "Automatic, after background alert: $msg")
            }
        }
        val cpuProxy = latest["cpuProxy"] == true
        val temps = listOfNotNull(latest["hottestC"] as Double?, latest["battTempC"] as Double?)
        one("cpu", "High CPU", "%", rules.optBoolean("cpuEnabled"), if (cpuProxy) null else latest["cpu"] as Double?, rules.optDouble("cpuPercent", 80.0))
        one("temperature", "High temperature", "°C", rules.optBoolean("tempEnabled"), temps.maxOrNull(), rules.optDouble("tempC", 45.0))
        one("drain", "Fast battery drain", "mA", rules.optBoolean("drainEnabled"), latest["drainMa"] as Double?, rules.optDouble("drainMa", 600.0))
        one("ram", "High RAM use", "%", rules.optBoolean("ramEnabled"), latest["ram"] as Double?, rules.optDouble("ramPercent", 90.0))
    }

    private fun summaryLine(): String {
        val parts = ArrayList<String>()
        (latest["cpu"] as Double?)?.let { parts.add("CPU ${it.toInt()}%") }
        (latest["ram"] as Double?)?.let { parts.add("RAM ${it.toInt()}%") }
        (latest["battLevel"] as Int?)?.let { parts.add("Bat $it%") }
        (latest["powerW"] as Double?)?.let { parts.add("%.1f W".format(it)) }
        ((latest["hottestC"] ?: latest["battTempC"]) as Double?)?.let { parts.add("${it.toInt()}°C") }
        return parts.joinToString("  ")
    }

    private fun updateOutputs() {
        val line = summaryLine()
        main.post {
            if (!running) return@post
            getSystemService(android.app.NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification(line))
            TurboWidget.push(this, latest)
            applyOverlay()
            overlay?.text = line.replace("  ", "\n")
        }
    }

    private fun applyOverlay() {
        main.post {
            if (overlayOn() && running) {
                if (overlay == null) showOverlay()
            } else {
                hideOverlay()
            }
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun showOverlay() {
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        val type =
            if (Build.VERSION.SDK_INT >= 26) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            }
        val params =
            WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                type,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT,
            ).apply {
                gravity = Gravity.TOP or Gravity.START
                x = 24
                y = 160
            }
        val tv =
            TextView(this).apply {
                setTextColor(Color.WHITE)
                setBackgroundColor(Color.argb(190, 11, 37, 69))
                textSize = 11f
                setPadding(16, 10, 16, 10)
                typeface = android.graphics.Typeface.MONOSPACE
                text = "TurboMon"
            }
        // Drag to move, tap to open the app.
        var downX = 0f
        var downY = 0f
        var startX = 0
        var startY = 0
        tv.setOnTouchListener { _, e ->
            when (e.action) {
                MotionEvent.ACTION_DOWN -> {
                    downX = e.rawX
                    downY = e.rawY
                    startX = params.x
                    startY = params.y
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    params.x = startX + (e.rawX - downX).toInt()
                    params.y = startY + (e.rawY - downY).toInt()
                    wm.updateViewLayout(tv, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (Math.abs(e.rawX - downX) < 10 && Math.abs(e.rawY - downY) < 10) {
                        startActivity(Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }
                    true
                }
                else -> false
            }
        }
        try {
            wm.addView(tv, params)
            overlay = tv
        } catch (e: Exception) {
            overlay = null
        }
    }

    private fun hideOverlay() {
        overlay?.let { runCatching { (getSystemService(WINDOW_SERVICE) as WindowManager).removeView(it) } }
        overlay = null
    }

    private fun buildNotification(line: String): Notification {
        Notifications.ensureChannels(this)
        val open =
            PendingIntent.getActivity(
                this,
                1,
                Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE,
            )
        val stop =
            PendingIntent.getService(
                this,
                2,
                Intent(this, MonitorService::class.java).setAction(ACTION_STOP),
                PendingIntent.FLAG_IMMUTABLE,
            )
        val left =
            stopAt?.let {
                val mins = ((it - System.currentTimeMillis()) / 60_000).coerceAtLeast(0)
                if (mins >= 60) " · ${mins / 60} h ${mins % 60} min left" else " · $mins min left"
            } ?: " · ${describeStop()}"
        val names = monitors().joinToString(", ") { MONITOR_LABELS[it] ?: it }
        val b =
            if (Build.VERSION.SDK_INT >= 26) {
                Notification.Builder(this, Notifications.CHANNEL_SERVICE)
            } else {
                @Suppress("DEPRECATION")
                Notification.Builder(this)
            }
        return b
            .setSmallIcon(R.drawable.ic_stat_turbomon)
            .setContentTitle("Scanning: $names")
            .setContentText(if (line.isEmpty()) "Starting$left" else "$line$left")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(open)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build())
            .build()
    }

    private fun startInForeground() {
        val n = buildNotification("")
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, n)
        }
    }

    private fun append(line: JSONObject) {
        try {
            val dir = File(filesDir, "history").apply { mkdirs() }
            val day = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(line.optLong("t", System.currentTimeMillis())))
            File(dir, "$day.jsonl").appendText(line.toString() + "\n")
        } catch (e: Exception) {
            // Disk full: drop the sample rather than crash the service.
        }
    }

    private fun pruneHistory() {
        val days = config.optInt("historyDays", 7)
        val cutoff = SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(System.currentTimeMillis() - days * 86_400_000L))
        File(filesDir, "history").listFiles()?.forEach { f ->
            if (f.name.endsWith(".jsonl") && f.name.removeSuffix(".jsonl") < cutoff) f.delete()
        }
    }

    private fun requestSnapshot(fromMs: Long, toMs: Long, reason: String) {
        try {
            val dir = File(filesDir, "snapshot-requests").apply { mkdirs() }
            File(dir, "$toMs.json").writeText(JSONObject().put("fromMs", fromMs).put("toMs", toMs).put("reason", reason).toString())
        } catch (e: Exception) {
            // Best effort.
        }
    }

    private fun finish(reason: String) {
        if (running) {
            val now = System.currentTimeMillis()
            append(JSONObject().put("t", now).put("event", "stop").put("reason", reason))
            if (config.optBoolean("snapshotOnStop", true) && startedAt > 0) {
                requestSnapshot(startedAt, now, "Background run ended ($reason)")
                Notifications.alert(this, 3000, "TurboMon run finished", "$reason. Open TurboMon for the snapshot.")
            }
        }
        running = false
        saveState()
        hideOverlay()
        handler.removeCallbacksAndMessages(null)
        TurboTileService.refresh(this)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        if (running) finish("Stopped by the system")
        thread.quitSafely()
        super.onDestroy()
    }

    private fun saveState() {
        getSharedPreferences(PREFS, MODE_PRIVATE).edit()
            .putBoolean("running", running)
            .putLong("startedAt", startedAt)
            .putLong("stopAt", stopAt ?: 0L)
            .apply()
        TurboTileService.refresh(this)
    }

    companion object {
        const val ACTION_START = "org.buetow.turbomon.START"
        const val ACTION_UPDATE = "org.buetow.turbomon.UPDATE"
        const val ACTION_STOP = "org.buetow.turbomon.STOP"
        private const val NOTIFICATION_ID = 42
        private const val PREFS = "turbomon_service"

        @Volatile
        var running = false
            private set

        private val MONITOR_LABELS =
            mapOf(
                "cpu" to "CPU", "ram" to "RAM", "gpu" to "GPU", "battery" to "battery", "network" to "network",
                "temperature" to "temps", "diskUsage" to "disk", "diskIo" to "disk I/O", "wifi" to "Wi-Fi",
                "bluetooth" to "Bluetooth", "processes" to "processes",
            )

        private fun configFile(context: Context) = File(context.filesDir, "service-config.json")

        fun loadConfig(context: Context): JSONObject =
            try {
                JSONObject(configFile(context).readText())
            } catch (e: Exception) {
                JSONObject(DEFAULT_CONFIG)
            }

        fun hasConfig(context: Context) = configFile(context).exists()

        private fun saveConfig(context: Context, config: JSONObject) {
            configFile(context).writeText(config.toString())
        }

        fun start(context: Context, config: JSONObject) {
            saveConfig(context, config)
            val i = Intent(context, MonitorService::class.java).setAction(ACTION_START)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(i) else context.startService(i)
        }

        /** Starts with the last saved configuration (quick-settings tile). */
        fun startLast(context: Context) = start(context, loadConfig(context))

        fun update(context: Context, config: JSONObject) {
            saveConfig(context, config)
            if (running) context.startService(Intent(context, MonitorService::class.java).setAction(ACTION_UPDATE))
        }

        fun stop(context: Context) {
            if (running) context.startService(Intent(context, MonitorService::class.java).setAction(ACTION_STOP))
        }

        fun state(context: Context): Map<String, Any?> {
            val p = context.getSharedPreferences(PREFS, MODE_PRIVATE)
            val cfg = loadConfig(context)
            val mons = cfg.optJSONArray("monitors")
            return mapOf(
                "running" to running,
                "startedAtMs" to if (running) p.getLong("startedAt", 0) else null,
                "stopAtMs" to if (running) p.getLong("stopAt", 0).takeIf { it > 0 } else null,
                "monitors" to (0 until (mons?.length() ?: 0)).map { mons!!.getString(it) },
            )
        }

        private const val DEFAULT_CONFIG =
            """{"monitors":["cpu","ram","battery","network","temperature"],"intervals":{},"autoStop":{"kind":"duration","minutes":60},"snapshotOnStop":true,"alerts":{},"historyDays":7,"accessMode":"auto"}"""
    }
}
