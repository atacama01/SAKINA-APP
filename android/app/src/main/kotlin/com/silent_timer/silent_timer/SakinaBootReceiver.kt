package com.silent_timer.silent_timer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Restores the native state after a reboot or an app update:
 * - an active silence session is resumed after a reboot,
 * - the restore alarm is re-registered,
 * - the rolling prayer alarm window is rebuilt.
 */
class SakinaBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED -> resumeAfterBoot(context)
            else -> rescheduleRestore(context)
        }

        PrayerAlarmScheduler.refresh(context)
    }

    private fun resumeAfterBoot(context: Context) {
        val prefs = SakinaPrefs.get(context)
        val endTime = prefs.getLong(SakinaPrefs.KEY_END_TIME, 0L)
        val now = System.currentTimeMillis()

        if (endTime <= 0L) return

        if (endTime <= now) {
            prefs.edit()
                .remove(SakinaPrefs.KEY_END_TIME)
                .remove(SakinaPrefs.KEY_PREVIOUS_MODE)
                .apply()
            SilentAlarmScheduler.cancelRestore(context)
            SakinaNotifications.cancelTimer(context)
            return
        }

        // The ringer mode resets during boot. Start a fresh session that keeps
        // the original end time instead of restoring to a stale mode.
        prefs.edit()
            .remove(SakinaPrefs.KEY_END_TIME)
            .remove(SakinaPrefs.KEY_PREVIOUS_MODE)
            .apply()

        val started = SakinaSilence.start(context, prefs, endTime)
        if (started) {
            SakinaNotifications.showTimer(
                context,
                "Phone is silenced",
                "Sound returns at " +
                    SakinaNotifications.formatTime(context, endTime)
            )
        } else {
            // Without DND access the phone cannot be silenced, but still
            // clean up the stored session when the timer expires.
            SilentAlarmScheduler.scheduleRestore(context, endTime)
        }
    }

    private fun rescheduleRestore(context: Context) {
        val prefs = SakinaPrefs.get(context)
        val endTime = prefs.getLong(SakinaPrefs.KEY_END_TIME, 0L)
        val now = System.currentTimeMillis()

        if (endTime > now) {
            SilentAlarmScheduler.scheduleRestore(context, endTime)
        } else if (endTime > 0L) {
            SakinaSilence.restore(context, prefs)
            SakinaNotifications.cancelTimer(context)
        }
    }
}
