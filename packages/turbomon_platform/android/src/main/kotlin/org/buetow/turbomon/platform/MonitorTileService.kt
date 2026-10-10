package org.buetow.turbomon.platform

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Quick-settings tile: starts the last background scan configuration (a preset
 * such as "overnight drain check"), or stops the running one.
 */
class MonitorTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        refresh()
    }

    override fun onClick() {
        super.onClick()
        if (MonitorService.isRunning) {
            MonitorService.requestStop()
        } else if (MonitorService.savedConfig(this) == null || !tryStart()) {
            // Nothing configured yet, or Android refused a background start:
            // open the app, where background scanning is set up.
            openApp()
        }
        refresh()
    }

    private fun tryStart(): Boolean =
        runCatching { MonitorService.start(this, null) }.isSuccess

    private fun openApp() {
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_IMMUTABLE))
        } else {
            @Suppress("DEPRECATION", "StartActivityAndCollapseDeprecated")
            startActivityAndCollapse(launch)
        }
    }

    private fun refresh() {
        val tile = qsTile ?: return
        tile.state = if (MonitorService.isRunning) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (MonitorService.isRunning) "Scanning" else "Off"
        }
        tile.updateTile()
    }
}
