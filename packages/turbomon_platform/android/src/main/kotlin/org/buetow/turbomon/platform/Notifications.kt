package org.buetow.turbomon.platform

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

/** Notification channels and the intents they open. */
object Notifications {
    const val MONITOR_CHANNEL = "monitor"
    const val ALERT_CHANNEL = "alerts"
    const val MONITOR_ID = 1

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(MONITOR_CHANNEL, "Background monitoring", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while TurboMon samples in the background."
                setShowBadge(false)
            },
        )
        manager.createNotificationChannel(
            NotificationChannel(ALERT_CHANNEL, "Threshold alerts", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "A monitored value stayed above your limit."
            },
        )
    }

    fun builder(context: Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, channel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

    /** Opens TurboMon's launcher activity, bringing an existing task forward. */
    fun openAppIntent(context: Context): PendingIntent? {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_IMMUTABLE)
    }

    fun alert(context: Context, id: Int, title: String, text: String) {
        ensureChannels(context)
        val notification = builder(context, ALERT_CHANNEL)
            .setSmallIcon(R.drawable.turbomon_notification)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(Notification.BigTextStyle().bigText(text))
            .setContentIntent(openAppIntent(context))
            .setAutoCancel(true)
            .build()
        // Without POST_NOTIFICATIONS (API 33+) this is a silent no-op.
        runCatching { context.getSystemService(NotificationManager::class.java).notify(ALERT_ID_BASE + id, notification) }
    }

    private const val ALERT_ID_BASE = 100
}
