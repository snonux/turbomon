package org.buetow.turbomon

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Home-screen widget with CPU, RAM, battery and temperature. The background
 * service pushes fresh values on every sample; without it Android refreshes
 * the widget at most every 30 minutes, and each refresh reads the values
 * directly here.
 */
class TurboWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        push(context, quickReadings(context))
    }

    companion object {
        fun quickReadings(context: Context): Map<String, Any?> {
            val b = Metrics.battery(context)
            val zones = Metrics.thermalZonesDirect()
            return mapOf(
                "cpu" to Metrics.cpuFreqPercent(),
                "cpuProxy" to true,
                "ram" to Metrics.ramPercent(context),
                "battLevel" to b["level"],
                "powerW" to Metrics.powerW(b),
                "charging" to (b["status"] == "charging"),
                "hottestC" to (Metrics.hottestZone(zones) ?: b["tempC"]),
            )
        }

        fun refresh(context: Context) = push(context, quickReadings(context))

        fun push(context: Context, v: Map<String, Any?>) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, TurboWidget::class.java))
            if (ids.isEmpty()) return
            val views = RemoteViews(context.packageName, R.layout.widget_turbomon)
            fun pct(k: String) = (v[k] as Double?)?.let { "${it.toInt()}%" } ?: "–"
            views.setTextViewText(R.id.widget_cpu, pct("cpu"))
            views.setTextViewText(R.id.widget_cpu_label, if (v["cpuProxy"] == true) "CPU freq" else "CPU")
            views.setTextViewText(R.id.widget_ram, pct("ram"))
            views.setTextViewText(R.id.widget_battery, (v["battLevel"] as Int?)?.let { "$it%" } ?: "–")
            views.setTextViewText(
                R.id.widget_power,
                (v["powerW"] as Double?)?.let { "%.1f W%s".format(it, if (v["charging"] == true) " in" else "") } ?: "",
            )
            views.setTextViewText(
                R.id.widget_temp,
                ((v["hottestC"] ?: v["battTempC"]) as Double?)?.let { "${it.toInt()}°C" } ?: "–",
            )
            views.setTextViewText(R.id.widget_state, if (MonitorService.running) "live" else "")
            val open =
                PendingIntent.getActivity(
                    context,
                    3,
                    Intent(context, MainActivity::class.java),
                    PendingIntent.FLAG_IMMUTABLE,
                )
            views.setOnClickPendingIntent(R.id.widget_root, open)
            manager.updateAppWidget(ids, views)
        }
    }
}
