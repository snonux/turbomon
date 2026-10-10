package org.buetow.turbomon.platform

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel

/**
 * Nearby Bluetooth devices from one long-running LE scan, plus classic
 * discovery on request. Results are batched and sent to Dart once a second so
 * a busy room does not flood the platform channel.
 *
 * Every call assumes Dart already holds BLUETOOTH_SCAN/CONNECT (API 31+) or
 * location (older); a missing grant surfaces as a SecurityException.
 */
@SuppressLint("MissingPermission")
class BluetoothMonitor(private val context: Context) : EventChannel.StreamHandler {
    private val manager = context.getSystemService(BluetoothManager::class.java)
    private val adapter: BluetoothAdapter? = manager?.adapter
    private val handler = Handler(Looper.getMainLooper())
    private val pending = LinkedHashMap<String, Map<String, Any?>>()
    private val proxies = HashMap<Int, BluetoothProfile>()
    private var sink: EventChannel.EventSink? = null
    private var discoveryReceiver: BroadcastReceiver? = null

    private val flush = object : Runnable {
        override fun run() {
            if (pending.isNotEmpty()) {
                sink?.success(mapOf("type" to "devices", "devices" to pending.values.toList()))
                pending.clear()
            }
            if (sink != null) handler.postDelayed(this, FLUSH_MS)
        }
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) = record(result)

        override fun onBatchScanResults(results: MutableList<ScanResult>) = results.forEach(::record)

        override fun onScanFailed(errorCode: Int) {
            sink?.success(mapOf("type" to "error", "code" to errorCode))
        }
    }

    fun state(): Map<String, Any?> = mapOf(
        "supported" to (adapter != null),
        "enabled" to (adapter?.isEnabled == true),
        "le" to context.packageManager.hasSystemFeature("android.hardware.bluetooth_le"),
    )

    /** Paired devices, each with whether it is connected and over which profiles. */
    fun pairedDevices(): List<Map<String, Any?>> {
        val adapter = adapter ?: return emptyList()
        if (!adapter.isEnabled) return emptyList()
        ensureProxies(adapter)
        val gatt = runCatching { manager.getConnectedDevices(BluetoothProfile.GATT) }.getOrDefault(emptyList())
        return adapter.bondedDevices.orEmpty().map { device ->
            val profiles = proxies.filter { (_, proxy) ->
                runCatching { proxy.getConnectionState(device) == BluetoothProfile.STATE_CONNECTED }.getOrDefault(false)
            }.keys.map(::profileName).toMutableList()
            if (gatt.any { it.address == device.address }) profiles += "LE"
            mapOf(
                "name" to device.name,
                "address" to device.address,
                "type" to typeName(device.type),
                "kind" to majorClassName(device.bluetoothClass),
                "connected" to profiles.isNotEmpty(),
                "profiles" to profiles,
            )
        }
    }

    /** Starts a classic discovery pass (about 12 s); finds go to the same stream. */
    fun startDiscovery(): Boolean {
        val adapter = adapter ?: return false
        if (discoveryReceiver == null) {
            val receiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    val device = intent.parcelableDevice() ?: return
                    val rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE)
                    pending[device.address] = mapOf(
                        "name" to device.name,
                        "address" to device.address,
                        "rssi" to rssi.toInt().takeIf { rssi != Short.MIN_VALUE },
                        "type" to typeName(device.type),
                        "kind" to majorClassName(device.bluetoothClass),
                        "source" to "classic",
                    )
                }
            }
            ContextCompat.registerReceiver(
                context, receiver, IntentFilter(BluetoothDevice.ACTION_FOUND), ContextCompat.RECEIVER_EXPORTED,
            )
            discoveryReceiver = receiver
        }
        if (adapter.isDiscovering) adapter.cancelDiscovery()
        return adapter.startDiscovery()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        val scanner = adapter?.takeIf { it.isEnabled }?.bluetoothLeScanner
        if (scanner == null) {
            events.success(mapOf("type" to "error", "code" to -1))
            return
        }
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        try {
            scanner.startScan(null, settings, scanCallback)
        } catch (e: SecurityException) {
            events.success(mapOf("type" to "error", "code" to -2))
            return
        }
        handler.postDelayed(flush, FLUSH_MS)
    }

    override fun onCancel(arguments: Any?) {
        handler.removeCallbacks(flush)
        runCatching { adapter?.bluetoothLeScanner?.stopScan(scanCallback) }
        runCatching { if (adapter?.isDiscovering == true) adapter.cancelDiscovery() }
        discoveryReceiver?.let { runCatching { context.unregisterReceiver(it) } }
        discoveryReceiver = null
        pending.clear()
        sink = null
    }

    fun dispose() {
        onCancel(null)
        proxies.forEach { (profile, proxy) -> runCatching { adapter?.closeProfileProxy(profile, proxy) } }
        proxies.clear()
    }

    private fun record(result: ScanResult) {
        val device = result.device
        val record = result.scanRecord
        val makers = record?.manufacturerSpecificData
        pending[device.address] = mapOf(
            "name" to (record?.deviceName ?: device.name),
            "address" to device.address,
            "rssi" to result.rssi,
            "txPower" to record?.txPowerLevel?.takeIf { it != Int.MIN_VALUE },
            "type" to typeName(device.type),
            "kind" to majorClassName(device.bluetoothClass),
            "companyId" to if (makers != null && makers.size() > 0) makers.keyAt(0) else null,
            "connectable" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) result.isConnectable else null,
            "source" to "le",
        )
    }

    /** Profile proxies connect asynchronously; the first call may see none yet. */
    private fun ensureProxies(adapter: BluetoothAdapter) {
        val wanted = mutableListOf(BluetoothProfile.A2DP, BluetoothProfile.HEADSET)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) wanted += BluetoothProfile.HEARING_AID
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) wanted += BluetoothProfile.LE_AUDIO
        for (profile in wanted) {
            if (proxies.containsKey(profile)) continue
            adapter.getProfileProxy(context, object : BluetoothProfile.ServiceListener {
                override fun onServiceConnected(p: Int, proxy: BluetoothProfile) {
                    proxies[p] = proxy
                }

                override fun onServiceDisconnected(p: Int) {
                    proxies.remove(p)
                }
            }, profile)
        }
    }

    private fun Intent.parcelableDevice(): BluetoothDevice? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
        } else {
            @Suppress("DEPRECATION")
            getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
        }

    private fun profileName(profile: Int) = when (profile) {
        BluetoothProfile.A2DP -> "audio"
        BluetoothProfile.HEADSET -> "headset"
        21 -> "hearing aid" // BluetoothProfile.HEARING_AID
        22 -> "LE audio" // BluetoothProfile.LE_AUDIO
        else -> "profile $profile"
    }

    private fun typeName(type: Int) = when (type) {
        BluetoothDevice.DEVICE_TYPE_CLASSIC -> "classic"
        BluetoothDevice.DEVICE_TYPE_LE -> "LE"
        BluetoothDevice.DEVICE_TYPE_DUAL -> "dual"
        else -> "unknown"
    }

    private fun majorClassName(cls: BluetoothClass?) = when (cls?.majorDeviceClass) {
        BluetoothClass.Device.Major.AUDIO_VIDEO -> "audio"
        BluetoothClass.Device.Major.COMPUTER -> "computer"
        BluetoothClass.Device.Major.PHONE -> "phone"
        BluetoothClass.Device.Major.PERIPHERAL -> "input"
        BluetoothClass.Device.Major.WEARABLE -> "wearable"
        BluetoothClass.Device.Major.HEALTH -> "health"
        BluetoothClass.Device.Major.IMAGING -> "imaging"
        BluetoothClass.Device.Major.NETWORKING -> "network"
        BluetoothClass.Device.Major.TOY -> "toy"
        else -> null
    }

    private companion object {
        const val FLUSH_MS = 1000L
    }
}
