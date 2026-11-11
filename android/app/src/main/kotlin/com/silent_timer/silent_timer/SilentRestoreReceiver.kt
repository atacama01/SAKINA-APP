package com.silent_timer.silent_timer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Natural end of a timer or prayer silence. Restores the saved ringer mode,
 * removes the ongoing notification, shows a short "Sound restored" message,
 * and rebuilds the next prayer alarms.
 */
class SilentRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val prefs = SakinaPrefs.get(context)
        val endTime = prefs.getLong(SakinaPrefs.KEY_END_TIME, 0L)
        val now = System.currentTimeMillis()

        if (endTime <= 0L) {
            SakinaNotifications.cancelTimer(context)
            PrayerAlarmScheduler.refresh(context)
            return
        }

        // A newer timer replaced this alarm while it was in flight. Keep the
        // newer session instead of restoring sound too early.
        if (endTime > now + 3_000L) {
            SilentAlarmScheduler.scheduleRestore(context, endTime)
            return
        }

        val restored = SakinaSilence.restore(context, prefs)
        if (restored) {
            SakinaNotifications.showRestored(context)
        } else {
            SakinaNotifications.cancelTimer(context)
        }

        PrayerAlarmScheduler.refresh(context)
    }
}
