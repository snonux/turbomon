package org.buetow.turbomon

import android.app.AppOpsManager
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.app.usage.StorageStatsManager
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import android.os.Process
import android.os.storage.StorageManager

/** Per-app storage and data use; both need the usage access special permission. */
object Apps {
    fun hasUsageAccess(context: Context): Boolean {
        val ops = context.getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode =
            if (Build.VERSION.SDK_INT >= 29) {
                ops.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
            } else {
                @Suppress("DEPRECATION")
                ops.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
            }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun label(pm: PackageManager, pkg: String): String =
        try {
            pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
        } catch (e: Exception) {
            pkg
        }

    @Suppress("DEPRECATION")
    fun sizes(context: Context): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < 26) return emptyList()
        val pm = context.packageManager
        val ssm = context.getSystemService(Context.STORAGE_STATS_SERVICE) as StorageStatsManager
        val user = Process.myUserHandle()
        val out = ArrayList<Map<String, Any?>>()
        for (app in pm.getInstalledApplications(0)) {
            try {
                val s = ssm.queryStatsForPackage(StorageManager.UUID_DEFAULT, app.packageName, user)
                out.add(
                    mapOf(
                        "package" to app.packageName,
                        "label" to pm.getApplicationLabel(app).toString(),
                        "appBytes" to s.appBytes,
                        "dataBytes" to s.dataBytes - s.cacheBytes,
                        "cacheBytes" to s.cacheBytes,
                    ),
                )
            } catch (e: Exception) {
                // Package removed meanwhile, or no access.
            }
        }
        return out
    }

    fun networkUsage(context: Context, windowMs: Long): List<Map<String, Any?>> {
        val nsm = context.getSystemService(Context.NETWORK_STATS_SERVICE) as NetworkStatsManager
        val end = System.currentTimeMillis()
        val start = end - windowMs
        val rx = HashMap<Int, Long>()
        val tx = HashMap<Int, Long>()
        @Suppress("DEPRECATION")
        for (type in intArrayOf(ConnectivityManager.TYPE_WIFI, ConnectivityManager.TYPE_MOBILE)) {
            try {
                val stats = nsm.querySummary(type, null, start, end)
                val b = NetworkStats.Bucket()
                while (stats.hasNextBucket()) {
                    stats.getNextBucket(b)
                    rx[b.uid] = (rx[b.uid] ?: 0L) + b.rxBytes
                    tx[b.uid] = (tx[b.uid] ?: 0L) + b.txBytes
                }
                stats.close()
            } catch (e: Exception) {
                // Mobile stats can be unavailable without a SIM.
            }
        }
        val pm = context.packageManager
        return rx.keys.map { uid ->
            val pkg = pm.getPackagesForUid(uid)?.firstOrNull()
            mapOf(
                "uid" to uid,
                "package" to (pkg ?: uidName(uid)),
                "label" to (pkg?.let { label(pm, it) } ?: uidName(uid)),
                "rxBytes" to (rx[uid] ?: 0L),
                "txBytes" to (tx[uid] ?: 0L),
            )
        }
    }

    private fun uidName(uid: Int): String =
        when (uid) {
            NetworkStats.Bucket.UID_REMOVED -> "Removed apps"
            NetworkStats.Bucket.UID_TETHERING -> "Tethering"
            Process.SYSTEM_UID -> "Android system"
            else -> "uid $uid"
        }

    fun packagesForUids(context: Context, uids: List<Int>): Map<Int, String> {
        val pm = context.packageManager
        val out = HashMap<Int, String>()
        for (u in uids) pm.getPackagesForUid(u)?.firstOrNull()?.let { out[u] = it }
        return out
    }
}
