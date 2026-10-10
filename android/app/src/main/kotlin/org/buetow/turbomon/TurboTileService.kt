package org.buetow.turbomon

import android.content.ComponentName
import android.content.Context
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/** Quick-settings tile that starts or stops background scanning with the last plan or preset. */
class TurboTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        render()
    }

    override fun onClick() {
        super.onClick()
        if (MonitorService.running) {
            MonitorService.stop(this)
        } else {
            MonitorService.startLast(this)
        }
        render()
    }

    private fun render() {
        val tile = qsTile ?: return
        tile.state = if (MonitorService.running) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        if (Build.VERSION.SDK_INT >= 29) {
            tile.subtitle = if (MonitorService.running) "Scanning" else "Off"
        }
        tile.updateTile()
    }

    companion object {
        fun refresh(context: Context) {
            try {
                requestListeningState(context, ComponentName(context, TurboTileService::class.java))
            } catch (e: Exception) {
                // Tile not added; nothing to refresh.
            }
        }
    }
}
