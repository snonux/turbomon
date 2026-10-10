package org.buetow.turbomon.platform

import android.app.ActivityManager
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.widget.RemoteViews
import java.text.DateFormat
import java.util.Date

/**
 * Home-screen widget with CPU, RAM, battery and temperature. The background
 * service pushes fresh values through [push]; otherwise Android refreshes it
 * every 30 minutes (its minimum) and the widget reads what needs no rights.
 */
class TurboMonWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val values = cached(context) ?: fallback(context)
        ids.forEach { manager.updateAppWidget(it, views(context, values)) }
    }

    companion object {
        private const val PREFS = "turbomon_widget"
        private const val STALE_MS = 5 * 60 * 1000L

        /** Stores [values] (cpu, ram, battery, temp as display strings) and redraws. */
        fun push(context: Context, values: Map<String, String>) {
            val editor = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            values.forEach { (key, value) -> editor.putString(key, value) }
            editor.putLong("at", System.currentTimeMillis()).apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, TurboMonWidget::class.java))
            ids.forEach { manager.updateAppWidget(it, views(context, values + ("at" to now()))) }
        }

        private fun cached(context: Context): Map<String, String>? {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val at = prefs.getLong("at", 0)
            if (System.currentTimeMillis() - at > STALE_MS) return null
            return listOf("cpu", "ram", "battery", "temp").associateWith { prefs.getString(it, "–") ?: "–" } +
                ("at" to DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(at)))
        }

        private fun fallback(context: Context): Map<String, String> {
            val battery = SystemInfo(context).battery()
            val memory = ActivityManager.MemoryInfo().also {
                context.getSystemService(ActivityManager::class.java).getMemoryInfo(it)
            }
            val ramPercent = if (memory.totalMem > 0) 100 - memory.availMem * 100 / memory.totalMem else 0
            return mapOf(
                "cpu" to "–",
                "ram" to "$ramPercent%",
                "battery" to ((battery["percent"] as? Double)?.let { "${it.toInt()}%" } ?: "–"),
                "temp" to ((battery["temperatureC"] as? Double)?.let { "%.0f°C".format(it) } ?: "–"),
                "at" to now(),
            )
        }

        private fun views(context: Context, values: Map<String, String>) =
            RemoteViews(context.packageName, R.layout.turbomon_widget).apply {
                setTextViewText(R.id.widget_cpu, values["cpu"] ?: "–")
                setTextViewText(R.id.widget_ram, values["ram"] ?: "–")
                setTextViewText(R.id.widget_battery, values["battery"] ?: "–")
                setTextViewText(R.id.widget_temp, values["temp"] ?: "–")
                setTextViewText(R.id.widget_time, values["at"] ?: "")
                Notifications.openAppIntent(context)?.let { setOnClickPendingIntent(R.id.widget_root, it) }
            }

        private fun now() = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date())
    }
}
