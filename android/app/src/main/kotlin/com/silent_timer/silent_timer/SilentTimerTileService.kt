package com.silent_timer.silent_timer

import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.N)
class SilentTimerTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        refreshTile()
    }

    override fun onClick() {
        super.onClick()
        val prefs = SakinaPrefs.get(this)
        val endTime = prefs.getLong(SakinaPrefs.KEY_END_TIME, 0L)
        val isActive = endTime > System.currentTimeMillis()

        if (isActive) {
            stopTimer(prefs)
        } else {
            startTimer(prefs)
        }
        refreshTile()
    }

    private fun startTimer(prefs: android.content.SharedPreferences) {
        val presetMinutes = prefs
            .getLong(SakinaPrefs.KEY_TILE_PRESET_MINUTES, 30L)
            .toInt()
            .coerceIn(1, 24 * 60)
        val endTimeMs = System.currentTimeMillis() +
            presetMinutes * 60_000L

        if (!SakinaSilence.start(this, prefs, endTimeMs)) {
            openApp()
            return
        }

        SakinaNotifications.showTimer(
            this,
            "Phone is silenced",
            "Restoring sound in ${formatDuration(presetMinutes)}"
        )
    }

    private fun stopTimer(prefs: android.content.SharedPreferences) {
        SakinaSilence.restore(this, prefs)
        SakinaNotifications.cancelTimer(this)
    }

    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(
                android.app.PendingIntent.getActivity(
                    this, 0, intent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                        android.app.PendingIntent.FLAG_IMMUTABLE
                )
            )
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun refreshTile() {
        val tile = qsTile ?: return
        val prefs = SakinaPrefs.get(this)
        val endTime = prefs.getLong(SakinaPrefs.KEY_END_TIME, 0L)
        val preset = prefs
            .getLong(SakinaPrefs.KEY_TILE_PRESET_MINUTES, 30L)
            .toInt()
            .coerceIn(1, 24 * 60)
        val active = endTime > System.currentTimeMillis()

        tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "Sakina"
        tile.icon = Icon.createWithResource(this, R.drawable.ic_qs_sakina)
        tile.contentDescription = if (active) {
            "Silent until ${SakinaNotifications.formatTime(this, endTime)}. " +
                "Tap to restore sound."
        } else {
            "Silence for ${preset} minutes"
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            tile.subtitle = if (active) {
                "Until ${SakinaNotifications.formatTime(this, endTime)}"
            } else {
                "$preset min"
            }
        }

        tile.updateTile()
    }

    private fun formatDuration(minutes: Int): String {
        val hours = minutes / 60
        val mins = minutes % 60
        return "%02d:%02d".format(hours, mins)
    }
}
