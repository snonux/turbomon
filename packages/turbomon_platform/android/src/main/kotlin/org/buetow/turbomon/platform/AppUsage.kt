package org.buetow.turbomon.platform

import android.app.AppOpsManager
import android.app.usage.NetworkStats
import android.app.usage.NetworkStatsManager
import android.app.usage.StorageStatsManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import android.os.Process
import android.os.storage.StorageManager
import android.provider.Settings

/**
 * Per-app figures that need "usage access", which the user grants in system
 * settings (there is no runtime dialog for it).
 */
class AppUsage(private val context: Context) {
    private val packageManager = context.packageManager

    fun hasUsageAccess(): Boolean {
        val appOps = context.getSystemService(AppOpsManager::class.java)
        @Suppress("DEPRECATION")
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        } else {
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    fun usageAccessSettingsIntent(): Intent =
        Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

    /** App, data and cache size of every installed package, largest first. */
    fun appStorage(): List<Map<String, Any?>> {
        val stats = context.getSystemService(StorageStatsManager::class.java)
        val user = Process.myUserHandle()
        return installedApps().mapNotNull { app ->
            val s = runCatching {
                stats.queryStatsForPackage(StorageManager.UUID_DEFAULT, app.packageName, user)
            }.getOrNull() ?: return@mapNotNull null
            mapOf(
                "package" to app.packageName,
                "label" to label(app),
                "appBytes" to s.appBytes,
                "dataBytes" to s.dataBytes - s.cacheBytes,
                "cacheBytes" to s.cacheBytes,
            )
        }.sortedByDescending { (it["appBytes"] as Long) + (it["dataBytes"] as Long) + (it["cacheBytes"] as Long) }
    }

    /** Bytes each app moved over Wi-Fi and mobile since [sinceMs]. */
    fun appNetwork(sinceMs: Long): List<Map<String, Any?>> {
        val stats = context.getSystemService(NetworkStatsManager::class.java)
        val totals = HashMap<Int, LongArray>()
        val now = System.currentTimeMillis()
        for (type in listOf(ConnectivityManager.TYPE_WIFI, ConnectivityManager.TYPE_MOBILE)) {
            val summary = runCatching { stats.querySummary(type, null, sinceMs, now) }.getOrNull() ?: continue
            // NetworkStats is only AutoCloseable from API 31, so no use {} here.
            try {
                val bucket = NetworkStats.Bucket()
                while (summary.hasNextBucket()) {
                    summary.getNextBucket(bucket)
                    val sums = totals.getOrPut(bucket.uid) { LongArray(2) }
                    sums[0] += bucket.rxBytes
                    sums[1] += bucket.txBytes
                }
            } finally {
                summary.close()
            }
        }
        return totals.map { (uid, sums) ->
            mapOf(
                "uid" to uid,
                "name" to (packageManager.getNameForUid(uid) ?: uidName(uid)),
                "rxBytes" to sums[0],
                "txBytes" to sums[1],
            )
        }.sortedByDescending { (it["rxBytes"] as Long) + (it["txBytes"] as Long) }
    }

    /** Package names for kernel uids, used to label process and battery rows. */
    fun packagesForUids(uids: List<Int>): Map<String, String> =
        uids.associate { uid -> uid.toString() to (packageManager.getNameForUid(uid) ?: uidName(uid)) }

    private fun installedApps(): List<ApplicationInfo> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            packageManager.getInstalledApplications(0)
        }

    private fun label(app: ApplicationInfo): String =
        runCatching { packageManager.getApplicationLabel(app).toString() }.getOrDefault(app.packageName)

    private fun uidName(uid: Int): String = when (uid) {
        Process.ROOT_UID -> "root"
        Process.SYSTEM_UID -> "system"
        -4 -> "removed apps"
        -5 -> "tethering"
        else -> "uid $uid"
    }
}
