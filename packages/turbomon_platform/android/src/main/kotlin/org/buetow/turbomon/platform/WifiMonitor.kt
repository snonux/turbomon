package org.buetow.turbomon.platform

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.ScanResult
import android.net.wifi.WifiInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.SystemClock
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.EventChannel

/**
 * Wi-Fi scans and the connected network's link.
 *
 * Scan results arrive passively too: any scan the system or another app runs
 * fires SCAN_RESULTS_AVAILABLE_ACTION, which is forwarded to Dart without
 * spending TurboMon's own 4-scans-per-2-minutes budget.
 */
class WifiMonitor(private val context: Context) : EventChannel.StreamHandler {
    private val wifi = context.applicationContext.getSystemService(WifiManager::class.java)
    private val connectivity = context.getSystemService(ConnectivityManager::class.java)
    private var sink: EventChannel.EventSink? = null
    private var receiver: BroadcastReceiver? = null
    private var callback: ConnectivityManager.NetworkCallback? = null
    @Volatile private var lastInfo: WifiInfo? = null

    val isEnabled: Boolean get() = wifi.isWifiEnabled

    /** Requests a scan; false means Android rejected it (throttled or Wi-Fi off). */
    @Suppress("DEPRECATION") // No replacement: startScan is the only way to ask for a scan.
    fun startScan(): Boolean = wifi.startScan()

    @Suppress("MissingPermission") // Dart only calls this once the scan permission is granted.
    fun scanResults(): List<Map<String, Any?>> = wifi.scanResults.map(::toMap)

    /** The current link: signal, speed and frequency. SSID needs location rights on API 29+. */
    fun connection(): Map<String, Any?>? {
        @Suppress("DEPRECATION")
        val info = lastInfo ?: wifi.connectionInfo ?: return null
        if (info.networkId == -1 && lastInfo == null) return null
        return mapOf(
            "ssid" to info.ssid?.removeSurrounding("\"")?.takeUnless { it == WifiManager.UNKNOWN_SSID },
            "bssid" to info.bssid?.takeUnless { it == "02:00:00:00:00:00" },
            "rssi" to info.rssi,
            "linkMbps" to info.linkSpeed,
            "frequency" to info.frequency,
            "txMbps" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) info.txLinkSpeedMbps else null,
            "rxMbps" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) info.rxLinkSpeedMbps else null,
            "standard" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) info.wifiStandard else null,
        )
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        val scanReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val updated = intent.getBooleanExtra(WifiManager.EXTRA_RESULTS_UPDATED, false)
                sink?.success(mapOf("type" to "scan", "updated" to updated))
            }
        }
        ContextCompat.registerReceiver(
            context,
            scanReceiver,
            IntentFilter(WifiManager.SCAN_RESULTS_AVAILABLE_ACTION),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        receiver = scanReceiver
        watchConnection()
    }

    override fun onCancel(arguments: Any?) {
        receiver?.let { runCatching { context.unregisterReceiver(it) } }
        receiver = null
        callback?.let { runCatching { connectivity.unregisterNetworkCallback(it) } }
        callback = null
        lastInfo = null
        sink = null
    }

    /**
     * Link changes (including RSSI) arrive through a network callback, which is
     * not throttled. From API 31 the WifiInfo comes with the capabilities, and
     * FLAG_INCLUDE_LOCATION_INFO keeps its SSID when location is granted.
     */
    private fun watchConnection() {
        val request = NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build()
        val cb = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            object : ConnectivityManager.NetworkCallback(FLAG_INCLUDE_LOCATION_INFO) {
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                    lastInfo = caps.transportInfo as? WifiInfo
                    sink?.success(mapOf("type" to "link"))
                }

                override fun onLost(network: Network) {
                    lastInfo = null
                    sink?.success(mapOf("type" to "link"))
                }
            }
        } else {
            object : ConnectivityManager.NetworkCallback() {
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                    sink?.success(mapOf("type" to "link"))
                }
            }
        }
        runCatching { connectivity.registerNetworkCallback(request, cb) }.onSuccess { callback = cb }
    }

    private fun toMap(r: ScanResult): Map<String, Any?> {
        val ssid = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            r.wifiSsid?.toString()?.removeSurrounding("\"")
        } else {
            @Suppress("DEPRECATION")
            r.SSID
        }
        return mapOf(
            "ssid" to ssid.orEmpty(),
            "bssid" to r.BSSID,
            "rssi" to r.level,
            "frequency" to r.frequency,
            "centerFreq0" to r.centerFreq0,
            "centerFreq1" to r.centerFreq1,
            "channelWidth" to channelWidthMhz(r.channelWidth),
            "capabilities" to r.capabilities,
            "standard" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) r.wifiStandard else null,
            // ScanResult.timestamp is µs since boot; convert to an age in ms.
            "ageMs" to (SystemClock.elapsedRealtime() - r.timestamp / 1000).coerceAtLeast(0),
        )
    }

    private fun channelWidthMhz(width: Int) = when (width) {
        ScanResult.CHANNEL_WIDTH_20MHZ -> 20
        ScanResult.CHANNEL_WIDTH_40MHZ -> 40
        ScanResult.CHANNEL_WIDTH_80MHZ -> 80
        ScanResult.CHANNEL_WIDTH_160MHZ, ScanResult.CHANNEL_WIDTH_80MHZ_PLUS_MHZ -> 160
        5 -> 320 // ScanResult.CHANNEL_WIDTH_320MHZ, API 33
        else -> 20
    }
}
