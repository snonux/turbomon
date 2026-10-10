package org.buetow.turbomon.platform

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Entry point for TurboMon's Android APIs. Registered on the UI engine and on
 * the background service's headless engine; the activity-bound calls
 * (permission dialogs, file picker) only work on the former.
 */
class TurboMonPlatformPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.RequestPermissionsResultListener,
    PluginRegistry.ActivityResultListener {

    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private lateinit var wifiEvents: EventChannel
    private lateinit var bluetoothEvents: EventChannel
    private lateinit var system: SystemInfo
    private lateinit var usage: AppUsage
    private lateinit var wifi: WifiMonitor
    private lateinit var bluetooth: BluetoothMonitor
    private lateinit var shizuku: ShizukuShell
    private lateinit var worker: ExecutorService
    private val main = Handler(Looper.getMainLooper())

    private var activity: ActivityPluginBinding? = null
    private var pendingPermissions: MethodChannel.Result? = null
    private var pendingSave: Pair<String, MethodChannel.Result>? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        system = SystemInfo(context)
        usage = AppUsage(context)
        wifi = WifiMonitor(context)
        bluetooth = BluetoothMonitor(context)
        shizuku = ShizukuShell(context)
        worker = Executors.newFixedThreadPool(WORKERS) { task -> Thread(task, "turbomon-platform") }
        channel = MethodChannel(binding.binaryMessenger, "org.buetow.turbomon/platform").also {
            it.setMethodCallHandler(this)
        }
        wifiEvents = EventChannel(binding.binaryMessenger, "org.buetow.turbomon/wifi").also {
            it.setStreamHandler(wifi)
        }
        bluetoothEvents = EventChannel(binding.binaryMessenger, "org.buetow.turbomon/bluetooth").also {
            it.setStreamHandler(bluetooth)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        wifiEvents.setStreamHandler(null)
        bluetoothEvents.setStreamHandler(null)
        wifi.onCancel(null)
        bluetooth.dispose()
        shizuku.dispose()
        worker.shutdownNow()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            dispatch(call, result)
        } catch (e: IllegalArgumentException) {
            result.error("bad_args", e.message, null)
        }
    }

    private fun dispatch(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Readings
            "device" -> result.success(system.device())
            "memory" -> result.success(system.memory())
            "battery" -> result.success(system.battery())
            "thermal" -> result.success(system.thermal())
            "traffic" -> result.success(system.traffic())
            "storageVolumes" -> background(result) { system.storageVolumes() }

            // Usage access
            "hasUsageAccess" -> result.success(usage.hasUsageAccess())
            "openUsageAccessSettings" -> result.success(launch(usage.usageAccessSettingsIntent()))
            "appStorage" -> background(result) { usage.appStorage() }
            "appNetwork" -> background(result) { usage.appNetwork(call.requireLong("sinceMs")) }
            "packagesForUids" -> background(result) { usage.packagesForUids(call.requireList("uids")) }

            // Wi-Fi
            "wifiEnabled" -> result.success(wifi.isEnabled)
            "wifiStartScan" -> result.success(wifi.startScan())
            "wifiScanResults" -> guarded(result) { wifi.scanResults() }
            "wifiConnection" -> result.success(wifi.connection())

            // Bluetooth
            "bluetoothState" -> result.success(bluetooth.state())
            "bluetoothPaired" -> guarded(result) { bluetooth.pairedDevices() }
            "bluetoothDiscover" -> guarded(result) { bluetooth.startDiscovery() }

            // Permissions and settings screens
            "permissionStatus" -> result.success(call.requireList<String>("permissions").associateWith(::granted))
            "requestPermissions" -> requestPermissions(call.requireList("permissions"), result)
            "canDrawOverlays" -> result.success(Settings.canDrawOverlays(context))
            "openOverlaySettings" -> result.success(
                launch(Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))),
            )

            // Shizuku
            "shizukuStatus" -> result.success(shizuku.status())
            "shizukuRequestPermission" -> shizuku.requestPermission { granted -> main.post { result.success(granted) } }
            "shizukuExec" -> background(result) { shizuku.exec(call.requireString("script")) }

            // Background service, widget, overlay, alerts
            "startService" -> guarded(result) { MonitorService.start(context, call.requireString("config")) }
            "stopService" -> guarded(result) { MonitorService.stop(context) }
            "serviceRunning" -> result.success(MonitorService.isRunning)
            "serviceConfig" -> result.success(MonitorService.savedConfig(context))
            "serviceStatus" -> guarded(result) { MonitorService.instance?.updateStatus(call.requireString("text")) }
            "overlay" -> guarded(result) { MonitorService.instance?.updateOverlay(call.argument<String>("text")) }
            "updateWidget" -> guarded(result) { TurboMonWidget.push(context, call.requireMap("values")) }
            "notify" -> guarded(result) {
                Notifications.alert(context, call.requireInt("id"), call.requireString("title"), call.requireString("text"))
            }

            // Snapshot export
            "shareFile" -> result.success(shareFile(call.requireString("path"), call.requireString("mime")))
            "saveFile" -> saveFile(call.requireString("name"), call.requireString("content"), result)
            else -> result.notImplemented()
        }
    }

    // ActivityAware

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding
        binding.addRequestPermissionsResultListener(this)
        binding.addActivityResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivity() {
        activity?.removeRequestPermissionsResultListener(this)
        activity?.removeActivityResultListener(this)
        activity = null
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray): Boolean {
        if (code != PERMISSION_REQUEST) return false
        val result = pendingPermissions ?: return true
        pendingPermissions = null
        result.success(permissions.indices.associate { permissions[it] to (results[it] == PackageManager.PERMISSION_GRANTED) })
        return true
    }

    override fun onActivityResult(code: Int, resultCode: Int, data: Intent?): Boolean {
        if (code != SAVE_REQUEST) return false
        val (content, result) = pendingSave ?: return true
        pendingSave = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(false)
            return true
        }
        background(result) {
            context.contentResolver.openOutputStream(uri, "wt")!!.use { it.write(content.toByteArray()) }
            true
        }
        return true
    }

    private fun granted(permission: String) =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED

    private fun requestPermissions(permissions: List<String>, result: MethodChannel.Result) {
        val host = activity?.activity
        if (host == null || pendingPermissions != null) {
            result.success(permissions.associateWith(::granted))
            return
        }
        val missing = permissions.filterNot(::granted)
        if (missing.isEmpty()) {
            result.success(permissions.associateWith { true })
            return
        }
        pendingPermissions = result
        host.requestPermissions(missing.toTypedArray(), PERMISSION_REQUEST)
    }

    private fun shareFile(path: String, mime: String): Boolean {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.snapshots", File(path))
        val send = Intent(Intent.ACTION_SEND)
            .setType(mime)
            .putExtra(Intent.EXTRA_STREAM, uri)
            .putExtra(Intent.EXTRA_SUBJECT, File(path).name)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        return launch(Intent.createChooser(send, "Share snapshot").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    /** Lets the user pick where to save [content] with the system file picker. */
    private fun saveFile(name: String, content: String, result: MethodChannel.Result) {
        val host = activity?.activity
        if (host == null || pendingSave != null) {
            result.success(false)
            return
        }
        pendingSave = content to result
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("text/markdown")
            .putExtra(Intent.EXTRA_TITLE, name)
        host.startActivityForResult(intent, SAVE_REQUEST)
    }

    private fun launch(intent: Intent): Boolean {
        val host = activity?.activity
        return runCatching {
            if (host != null) host.startActivity(intent) else context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }.isSuccess
    }

    /** Runs [block] on the main thread, turning exceptions into a Dart error. */
    private fun guarded(result: MethodChannel.Result, block: () -> Any?) {
        try {
            result.success(block().takeUnless { it == Unit })
        } catch (e: SecurityException) {
            result.error("permission", e.message, null)
        } catch (e: Exception) {
            result.error("failed", e.message, null)
        }
    }

    /** Runs a slow [block] on a worker thread and answers on the main thread. */
    private fun background(result: MethodChannel.Result, block: () -> Any?) {
        worker.execute {
            val outcome = runCatching(block)
            main.post {
                outcome.fold(
                    onSuccess = { result.success(it) },
                    onFailure = { result.error(if (it is SecurityException) "permission" else "failed", it.message, null) },
                )
            }
        }
    }

    private fun MethodCall.requireString(key: String): String =
        argument<String>(key) ?: throw IllegalArgumentException("$key is required")

    private fun MethodCall.requireInt(key: String): Int =
        argument<Int>(key) ?: throw IllegalArgumentException("$key is required")

    private fun MethodCall.requireLong(key: String): Long =
        argument<Number>(key)?.toLong() ?: throw IllegalArgumentException("$key is required")

    private fun <T> MethodCall.requireList(key: String): List<T> =
        argument<List<T>>(key) ?: throw IllegalArgumentException("$key is required")

    private fun <V> MethodCall.requireMap(key: String): Map<String, V> =
        argument<Map<String, V>>(key) ?: throw IllegalArgumentException("$key is required")

    private companion object {
        const val PERMISSION_REQUEST = 7301
        const val SAVE_REQUEST = 7302
        const val WORKERS = 3
    }
}
