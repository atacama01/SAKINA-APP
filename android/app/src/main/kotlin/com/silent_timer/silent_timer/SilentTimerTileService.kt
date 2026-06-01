package com.silent_timer.silent_timer

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

@RequiresApi(Build.VERSION_CODES.N)
class SilentTimerTileService : TileService() {

    companion object {
        const val ALARM_REQUEST_CODE = 1001
    }

    override fun onStartListening() {
        super.onStartListening()
        refreshTile()
    }

    override fun onClick() {
        super.onClick()
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val endTime = prefs.getLong("flutter.end_time", 0L)
        val isActive = endTime > System.currentTimeMillis()

        if (isActive) {
            stopTimer(prefs)
        } else {
            startTimer(prefs)
        }
        refreshTile()
    }

    private fun startTimer(prefs: android.content.SharedPreferences) {
        val notif = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (!notif.isNotificationPolicyAccessGranted) {
            openApp()
            return
        }

        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val previousMode = audio.ringerMode
        val presetMinutes = prefs.getLong("flutter.tile_preset_minutes", 30L).toInt()
        val endTimeMs = System.currentTimeMillis() + (presetMinutes * 60 * 1000L)

        audio.ringerMode = AudioManager.RINGER_MODE_SILENT

        prefs.edit()
            .putLong("flutter.previous_mode", previousMode.toLong())
            .putLong("flutter.end_time", endTimeMs)
            .apply()

        scheduleRestore(endTimeMs)
    }

    private fun stopTimer(prefs: android.content.SharedPreferences) {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val previousMode = prefs.getLong("flutter.previous_mode", 2L).toInt()
        audio.ringerMode = previousMode

        prefs.edit()
            .remove("flutter.end_time")
            .remove("flutter.previous_mode")
            .apply()

        cancelRestore()
    }

    private fun scheduleRestore(endTimeMs: Long) {
        val alarm = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = PendingIntent.getBroadcast(
            this, ALARM_REQUEST_CODE,
            Intent(this, SilentRestoreReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarm.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, endTimeMs, pi)
        } else {
            alarm.setExact(AlarmManager.RTC_WAKEUP, endTimeMs, pi)
        }
    }

    private fun cancelRestore() {
        val alarm = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = PendingIntent.getBroadcast(
            this, ALARM_REQUEST_CODE,
            Intent(this, SilentRestoreReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        alarm.cancel(pi)
    }

    private fun openApp() {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(
                PendingIntent.getActivity(
                    this, 0, intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun refreshTile() {
        val tile = qsTile ?: return
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val endTime = prefs.getLong("flutter.end_time", 0L)
        val preset = prefs.getLong("flutter.tile_preset_minutes", 30L).toInt()
        val active = endTime > System.currentTimeMillis()

        tile.state = if (active) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = "Silent Timer"
        tile.contentDescription = if (active) "Tap to restore sound" else "Silence for ${preset}m"
        tile.updateTile()
    }
}