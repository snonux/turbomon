package org.buetow.turbomon

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
import android.net.wifi.ScanResult as WifiScanResult
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.plugin.common.EventChannel

/** Wi-Fi scanning and the connected network, as plain maps. */
@SuppressLint("MissingPermission")
object WifiInfo {
    fun manager(context: Context) = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

    @Suppress("DEPRECATION")
    fun startScan(context: Context): Boolean =
        try {
            manager(context).startScan()
        } catch (e: Exception) {
            false
        }

    fun results(context: Context): List<Map<String, Any?>> =
        try {
            manager(context).scanResults.map { toMap(it) }
        } catch (e: SecurityException) {
            emptyList()
        }

    @Suppress("DEPRECATION")
    private fun toMap(r: WifiScanResult): Map<String, Any?> {
        val width =
            when (r.channelWidth) {
                WifiScanResult.CHANNEL_WIDTH_20MHZ -> 20
                WifiScanResult.CHANNEL_WIDTH_40MHZ -> 40
                WifiScanResult.CHANNEL_WIDTH_80MHZ -> 80
                WifiScanResult.CHANNEL_WIDTH_160MHZ -> 160
                WifiScanResult.CHANNEL_WIDTH_80MHZ_PLUS_MHZ -> 160
                5 -> 320 // CHANNEL_WIDTH_320MHZ, API 33
                else -> 20
            }
        val standard =
            if (Build.VERSION.SDK_INT >= 30) {
                when (r.wifiStandard) {
                    1 -> "802.11a/b/g"
                    4 -> "Wi-Fi 4 (n)"
                    5 -> "Wi-Fi 5 (ac)"
                    6 -> "Wi-Fi 6 (ax)"
                    7 -> "802.11ad"
                    8 -> "Wi-Fi 7 (be)"
                    else -> ""
                }
            } else {
                ""
            }
        // timestamp is microseconds since boot; convert to wall-clock time.
        val ageMs = SystemClock.elapsedRealtime() - r.timestamp / 1000
        return mapOf(
            "ssid" to (r.SSID ?: ""),
            "bssid" to (r.BSSID ?: ""),
            "rssi" to r.level,
            "frequency" to r.frequency,
            "centerFreq0" to r.centerFreq0,
            "channelWidth" to width,
            "security" to security(r.capabilities ?: ""),
            "standard" to standard,
            "timestampMs" to System.currentTimeMillis() - ageMs,
        )
    }

    fun security(caps: String): String =
        when {
            caps.contains("SAE") && caps.contains("PSK") -> "WPA2/WPA3"
            caps.contains("SAE") -> "WPA3"
            caps.contains("EAP") -> "Enterprise"
            caps.contains("WPA2") || caps.contains("RSN") -> "WPA2"
            caps.contains("WPA") -> "WPA"
            caps.contains("WEP") -> "WEP"
            caps.contains("OWE") -> "OWE"
            else -> ""
        }

    @Suppress("DEPRECATION")
    fun connection(context: Context): Map<String, Any?>? {
        val info = manager(context).connectionInfo ?: return null
        if (info.networkId == -1 && info.rssi <= -127) return null
        val ssid = info.ssid?.removeSurrounding("\"")
        return mapOf(
            "ssid" to if (ssid == null || ssid == WifiManager.UNKNOWN_SSID) null else ssid,
            "bssid" to info.bssid,
            "rssi" to info.rssi,
            "linkSpeedMbps" to info.linkSpeed,
            "frequency" to info.frequency,
        )
    }
}

/** Streams scan results to Dart whenever anyone's scan completes. */
class WifiStream(private val context: Context) : EventChannel.StreamHandler {
    private var receiver: BroadcastReceiver? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val r =
            object : BroadcastReceiver() {
                override fun onReceive(c: Context, intent: Intent) {
                    events.success(WifiInfo.results(context))
                }
            }
        receiver = r
        val filter = IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION)
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(r, filter, Context.RECEIVER_EXPORTED)
        } else {
            context.registerReceiver(r, filter)
        }
    }

    override fun onCancel(arguments: Any?) {
        receiver?.let { runCatching { context.unregisterReceiver(it) } }
        receiver = null
    }
}

@SuppressLint("MissingPermission")
object BluetoothInfo {
    fun adapter(context: Context): BluetoothAdapter? =
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager?)?.adapter

    fun enabled(context: Context): Boolean =
        try {
            adapter(context)?.isEnabled == true
        } catch (e: Exception) {
            false
        }

    fun typeName(t: Int): String =
        when (t) {
            BluetoothDevice.DEVICE_TYPE_CLASSIC -> "classic"
            BluetoothDevice.DEVICE_TYPE_LE -> "le"
            BluetoothDevice.DEVICE_TYPE_DUAL -> "dual"
            else -> "unknown"
        }

    fun safeName(d: BluetoothDevice): String =
        try {
            d.name ?: ""
        } catch (e: SecurityException) {
            ""
        }

    fun fromScan(r: ScanResult): Map<String, Any?> {
        val record = r.scanRecord
        val m = record?.manufacturerSpecificData
        val d = r.device
        return mapOf(
            "address" to d.address,
            "name" to (record?.deviceName ?: safeName(d)),
            "rssi" to r.rssi,
            "type" to runCatching { typeName(d.type) }.getOrDefault("le"),
            "manufacturerId" to if (m != null && m.size() > 0) m.keyAt(0) else null,
            "txPower" to record?.txPowerLevel?.takeIf { it != Int.MIN_VALUE },
            "connectable" to if (Build.VERSION.SDK_INT >= 26) r.isConnectable else null,
            "bonded" to runCatching { d.bondState == BluetoothDevice.BOND_BONDED }.getOrDefault(false),
            "timestampMs" to System.currentTimeMillis(),
        )
    }

    private fun majorClass(d: BluetoothDevice): String =
        when (runCatching { d.bluetoothClass?.majorDeviceClass }.getOrNull()) {
            BluetoothClass.Device.Major.AUDIO_VIDEO -> "audio"
            BluetoothClass.Device.Major.PHONE -> "phone"
            BluetoothClass.Device.Major.COMPUTER -> "computer"
            BluetoothClass.Device.Major.WEARABLE -> "wearable"
            BluetoothClass.Device.Major.PERIPHERAL -> "input"
            BluetoothClass.Device.Major.HEALTH -> "health"
            BluetoothClass.Device.Major.IMAGING -> "imaging"
            BluetoothClass.Device.Major.TOY -> "toy"
            else -> "device"
        }

    /** Hidden but long-standing APIs (isConnected, getBatteryLevel), read reflectively. */
    private fun hidden(d: BluetoothDevice, name: String): Any? =
        try {
            BluetoothDevice::class.java.getMethod(name).invoke(d)
        } catch (e: Throwable) {
            null
        }

    fun connected(context: Context): List<Map<String, Any?>> {
        val out = LinkedHashMap<String, Map<String, Any?>>()
        try {
            val bonded = adapter(context)?.bondedDevices ?: emptySet()
            for (d in bonded) {
                if (hidden(d, "isConnected") != true) continue
                out[d.address] = mapOf(
                    "address" to d.address,
                    "name" to safeName(d),
                    "rssi" to -100,
                    "type" to "${majorClass(d)} (${typeName(d.type)})",
                    "bonded" to true,
                    "battery" to (hidden(d, "getBatteryLevel") as? Int),
                    "timestampMs" to System.currentTimeMillis(),
                )
            }
            val bm = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            for (d in bm.getConnectedDevices(BluetoothProfile.GATT)) {
                out.getOrPut(d.address) {
                    mapOf(
                        "address" to d.address,
                        "name" to safeName(d),
                        "rssi" to -100,
                        "type" to "LE (GATT)",
                        "bonded" to false,
                        "timestampMs" to System.currentTimeMillis(),
                    )
                }
            }
        } catch (e: SecurityException) {
            // No BLUETOOTH_CONNECT yet.
        }
        return out.values.toList()
    }
}

/**
 * Continuous Bluetooth LE scan streamed to Dart, plus classic discovery
 * results while the stream is open.
 */
@SuppressLint("MissingPermission")
class BluetoothStream(private val context: Context) : EventChannel.StreamHandler {
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var callback: ScanCallback? = null
    private var receiver: BroadcastReceiver? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        val scanner = BluetoothInfo.adapter(context)?.bluetoothLeScanner
        if (scanner == null) {
            events.success(mapOf("error" to "Bluetooth LE scanner unavailable (Bluetooth off?)"))
            return
        }
        val cb =
            object : ScanCallback() {
                override fun onScanResult(callbackType: Int, result: ScanResult) {
                    val m = BluetoothInfo.fromScan(result)
                    main.post { sink?.success(m) }
                }

                override fun onBatchScanResults(results: MutableList<ScanResult>) {
                    for (r in results) onScanResult(0, r)
                }

                override fun onScanFailed(errorCode: Int) {
                    main.post { sink?.success(mapOf("error" to "scan failed ($errorCode)")) }
                }
            }
        callback = cb
        try {
            val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
            scanner.startScan(null, settings, cb)
        } catch (e: SecurityException) {
            events.success(mapOf("error" to "permission missing"))
        }
        val r =
            object : BroadcastReceiver() {
                override fun onReceive(c: Context, intent: Intent) {
                    @Suppress("DEPRECATION")
                    val d = intent.getParcelableExtra<BluetoothDevice>(BluetoothDevice.EXTRA_DEVICE) ?: return
                    val rssi = intent.getShortExtra(BluetoothDevice.EXTRA_RSSI, Short.MIN_VALUE).toInt()
                    sink?.success(
                        mapOf(
                            "address" to d.address,
                            "name" to BluetoothInfo.safeName(d),
                            "rssi" to if (rssi == Short.MIN_VALUE.toInt()) -100 else rssi,
                            "type" to runCatching { BluetoothInfo.typeName(d.type) }.getOrDefault("classic"),
                            "bonded" to runCatching { d.bondState == BluetoothDevice.BOND_BONDED }.getOrDefault(false),
                            "timestampMs" to System.currentTimeMillis(),
                        ),
                    )
                }
            }
        receiver = r
        val filter = IntentFilter(BluetoothDevice.ACTION_FOUND)
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(r, filter, Context.RECEIVER_EXPORTED)
        } else {
            context.registerReceiver(r, filter)
        }
    }

    override fun onCancel(arguments: Any?) {
        try {
            callback?.let { BluetoothInfo.adapter(context)?.bluetoothLeScanner?.stopScan(it) }
            BluetoothInfo.adapter(context)?.cancelDiscovery()
        } catch (e: Exception) {
            // Bluetooth turned off or permission revoked meanwhile.
        }
        receiver?.let { runCatching { context.unregisterReceiver(it) } }
        receiver = null
        callback = null
        sink = null
    }

    companion object {
        fun startClassicDiscovery(context: Context) {
            try {
                BluetoothInfo.adapter(context)?.startDiscovery()
            } catch (e: SecurityException) {
                // Reported as no results.
            }
        }
    }
}
