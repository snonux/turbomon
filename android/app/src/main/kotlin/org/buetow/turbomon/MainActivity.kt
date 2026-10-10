package org.buetow.turbomon

import android.app.NotificationManager
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import rikka.shizuku.Shizuku
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val main = Handler(Looper.getMainLooper())

    // Slow calls (shell commands, per-app stats) run off the UI thread.
    private val worker = Executors.newCachedThreadPool()
    private var pendingPermission: MethodChannel.Result? = null
    private var pendingSave: Pair<File, MethodChannel.Result>? = null
    private var pendingShizuku: MethodChannel.Result? = null

    private val shizukuListener =
        Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
            if (requestCode == REQUEST_SHIZUKU) {
                pendingShizuku?.success(grantResult == PackageManager.PERMISSION_GRANTED)
                pendingShizuku = null
            }
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "org.buetow.turbomon/native").setMethodCallHandler { call, result ->
            try {
                handle(call, result)
            } catch (e: Exception) {
                result.error("native", e.toString(), null)
            }
        }
        EventChannel(messenger, "org.buetow.turbomon/wifi").setStreamHandler(WifiStream(applicationContext))
        EventChannel(messenger, "org.buetow.turbomon/bluetooth").setStreamHandler(BluetoothStream(applicationContext))
        runCatching { Shizuku.addRequestPermissionResultListener(shizukuListener) }
    }

    override fun onDestroy() {
        runCatching { Shizuku.removeRequestPermissionResultListener(shizukuListener) }
        worker.shutdown()
        super.onDestroy()
    }

    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            val r =
                try {
                    Result.success(block())
                } catch (e: Throwable) {
                    Result.failure(e)
                }
            main.post {
                r.fold({ result.success(it) }, { result.error("native", it.toString(), null) })
            }
        }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val ctx = applicationContext
        when (call.method) {
            "deviceInfo" -> result.success(Metrics.deviceInfo())
            "memoryInfo" -> result.success(Metrics.memory(ctx))
            "battery" -> result.success(Metrics.battery(ctx))
            "traffic" -> result.success(Metrics.traffic())
            "thermal" -> result.success(Metrics.thermal(ctx))
            "storageVolumes" -> result.success(Metrics.storageVolumes(ctx))
            "hasUsageAccess" -> result.success(Apps.hasUsageAccess(ctx))
            "openUsageAccessSettings" -> {
                startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                result.success(null)
            }
            "appSizes" -> background(result) { Apps.sizes(ctx) }
            "appNetworkUsage" -> {
                val window = (call.argument<Number>("windowMs") ?: 86_400_000L).toLong()
                background(result) { Apps.networkUsage(ctx, window) }
            }
            "startWifiScan" -> result.success(WifiInfo.startScan(ctx))
            "wifiScanResults" -> result.success(WifiInfo.results(ctx))
            "wifiConnection" -> result.success(WifiInfo.connection(ctx))
            "bluetoothEnabled" -> result.success(BluetoothInfo.enabled(ctx))
            "startClassicDiscovery" -> {
                BluetoothStream.startClassicDiscovery(ctx)
                result.success(null)
            }
            "connectedBluetooth" -> result.success(BluetoothInfo.connected(ctx))
            "hasPermissions" -> result.success(granted(call.argument<List<String>>("permissions") ?: emptyList()))
            "requestPermissions" -> requestPermissions(call.argument<List<String>>("permissions") ?: emptyList(), result)
            "canDrawOverlays" -> result.success(Settings.canDrawOverlays(ctx))
            "openOverlaySettings" -> {
                startActivity(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
                result.success(null)
            }
            "shizukuState" -> result.success(Privileged.shizukuState(ctx))
            "requestShizuku" -> requestShizuku(result)
            "shizukuExec" -> {
                val cmd = call.argument<String>("command") ?: ""
                background(result) {
                    val r = Privileged.shizukuExec(cmd)
                    mapOf("exitCode" to r.exitCode, "stdout" to r.stdout, "stderr" to r.stderr)
                }
            }
            "packagesForUids" -> {
                val uids = call.argument<List<Number>>("uids")?.map { it.toInt() } ?: emptyList()
                result.success(Apps.packagesForUids(ctx, uids))
            }
            "startBackground" -> {
                MonitorService.start(ctx, JSONObject(call.argument<Map<String, Any?>>("config") ?: emptyMap<String, Any?>()))
                result.success(null)
            }
            "updateServiceConfig" -> {
                MonitorService.update(ctx, JSONObject(call.argument<Map<String, Any?>>("config") ?: emptyMap<String, Any?>()))
                result.success(null)
            }
            "stopBackground" -> {
                MonitorService.stop(ctx)
                result.success(null)
            }
            "backgroundState" -> result.success(MonitorService.state(ctx))
            "filesDir" -> result.success(filesDir.absolutePath)
            "notify" -> {
                Notifications.alert(
                    ctx,
                    call.argument<Number>("id")?.toInt() ?: 1000,
                    call.argument<String>("title") ?: "TurboMon",
                    call.argument<String>("body") ?: "",
                )
                result.success(null)
            }
            "shareFile" -> {
                share(File(call.argument<String>("path")!!), call.argument<String>("mimeType") ?: "text/plain")
                result.success(null)
            }
            "saveFileAs" -> saveAs(call, result)
            "requestPinWidget" -> {
                val awm = AppWidgetManager.getInstance(ctx)
                val ok =
                    Build.VERSION.SDK_INT >= 26 &&
                        awm.isRequestPinAppWidgetSupported &&
                        awm.requestPinAppWidget(ComponentName(ctx, TurboWidget::class.java), null, null)
                result.success(ok)
            }
            "refreshWidget" -> {
                TurboWidget.refresh(ctx)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Permissions that do not exist on this Android version count as granted. */
    private fun granted(perms: List<String>): Boolean =
        perms.all { p ->
            val minSdk = PERMISSION_MIN_SDK[p] ?: 0
            Build.VERSION.SDK_INT < minSdk || checkSelfPermission(p) == PackageManager.PERMISSION_GRANTED
        }

    private fun requestPermissions(perms: List<String>, result: MethodChannel.Result) {
        val needed = perms.filter { (PERMISSION_MIN_SDK[it] ?: 0) <= Build.VERSION.SDK_INT }
        if (granted(needed)) {
            result.success(true)
            return
        }
        pendingPermission?.success(false)
        pendingPermission = result
        requestPermissions(needed.toTypedArray(), REQUEST_PERMISSIONS)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_PERMISSIONS) {
            pendingPermission?.success(grantResults.isNotEmpty() && grantResults.all { it == PackageManager.PERMISSION_GRANTED })
            pendingPermission = null
        }
    }

    private fun requestShizuku(result: MethodChannel.Result) {
        when (Privileged.shizukuState(applicationContext)) {
            "granted" -> result.success(true)
            "denied" -> {
                if (Shizuku.shouldShowRequestPermissionRationale()) {
                    // The user chose "deny and don't ask again" in Shizuku.
                    result.success(false)
                    return
                }
                pendingShizuku?.success(false)
                pendingShizuku = result
                Shizuku.requestPermission(REQUEST_SHIZUKU)
            }
            else -> result.success(false)
        }
    }

    private fun share(file: File, mime: String) {
        val uri = SnapshotProvider.uriFor(this, file)
        val send =
            Intent(Intent.ACTION_SEND).apply {
                type = mime
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, file.name)
                clipData = android.content.ClipData.newRawUri(file.name, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        startActivity(Intent.createChooser(send, "Share snapshot"))
    }

    private fun saveAs(call: MethodCall, result: MethodChannel.Result) {
        val file = File(call.argument<String>("path")!!)
        val intent =
            Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = call.argument<String>("mimeType") ?: "text/plain"
                putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: file.name)
            }
        pendingSave?.second?.success(false)
        pendingSave = Pair(file, result)
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_SAVE)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_SAVE) return
        val (file, result) = pendingSave ?: return
        pendingSave = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(false)
            return
        }
        worker.execute {
            val ok =
                try {
                    contentResolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out) } }
                    true
                } catch (e: Exception) {
                    false
                }
            main.post { result.success(ok) }
        }
    }

    companion object {
        private const val REQUEST_PERMISSIONS = 7301
        private const val REQUEST_SAVE = 7302
        private const val REQUEST_SHIZUKU = 7303

        private val PERMISSION_MIN_SDK =
            mapOf(
                "android.permission.NEARBY_WIFI_DEVICES" to 33,
                "android.permission.POST_NOTIFICATIONS" to 33,
                "android.permission.BLUETOOTH_SCAN" to 31,
                "android.permission.BLUETOOTH_CONNECT" to 31,
            )
    }
}

/** Alert and status notifications. */
object Notifications {
    const val CHANNEL_ALERTS = "alerts"
    const val CHANNEL_SERVICE = "background"

    fun ensureChannels(context: android.content.Context) {
        if (Build.VERSION.SDK_INT < 26) return
        val nm = context.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            android.app.NotificationChannel(CHANNEL_ALERTS, "Alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "CPU, temperature, battery drain and RAM limits you set"
            },
        )
        nm.createNotificationChannel(
            android.app.NotificationChannel(CHANNEL_SERVICE, "Background scanning", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while TurboMon records in the background"
            },
        )
    }

    fun alert(context: android.content.Context, id: Int, title: String, body: String) {
        ensureChannels(context)
        val open =
            android.app.PendingIntent.getActivity(
                context,
                0,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                android.app.PendingIntent.FLAG_IMMUTABLE or android.app.PendingIntent.FLAG_UPDATE_CURRENT,
            )
        val builder =
            if (Build.VERSION.SDK_INT >= 26) {
                android.app.Notification.Builder(context, CHANNEL_ALERTS)
            } else {
                @Suppress("DEPRECATION")
                android.app.Notification.Builder(context)
            }
        val n =
            builder
                .setSmallIcon(R.drawable.ic_stat_turbomon)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(android.app.Notification.BigTextStyle().bigText(body))
                .setContentIntent(open)
                .setAutoCancel(true)
                .build()
        try {
            context.getSystemService(NotificationManager::class.java).notify(id, n)
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS not granted.
        }
    }
}
