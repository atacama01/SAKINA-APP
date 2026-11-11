package com.silent_timer.silent_timer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Starts a prayer silence session. The exact end time comes from the alarm
 * that was scheduled by [PrayerAlarmScheduler].
 */
class PrayerSilenceReceiver : BroadcastReceiver() {

    companion object {
        const val ACTION_PRAYER_SILENCE =
            "com.silent_timer.silent_timer.action.PRAYER_SILENCE"
        const val EXTRA_PRAYER = "prayer"
        const val EXTRA_SILENCE_END = "silence_end"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_PRAYER_SILENCE) return

        val prayer = intent.getStringExtra(EXTRA_PRAYER) ?: "Prayer"
        val silenceEnd = intent.getLongExtra(EXTRA_SILENCE_END, 0L)
        val now = System.currentTimeMillis()

        if (silenceEnd <= now) {
            PrayerAlarmScheduler.refresh(context)
            return
        }

        val prefs = SakinaPrefs.get(context)
        val activeBefore = prefs.getLong(
            SakinaPrefs.KEY_END_TIME,
            0L
        ) > now
        val previousEnd = prefs.getLong(SakinaPrefs.KEY_END_TIME, 0L)

        val started = SakinaSilence.start(context, prefs, silenceEnd)
        val label = prayer.replaceFirstChar { it.uppercase() }

        if (started) {
            when {
                !activeBefore -> SakinaNotifications.showTimer(
                    context,
                    "Phone is silenced",
                    "$label · sound returns at " +
                        SakinaNotifications.formatTime(context, silenceEnd)
                )

                silenceEnd > previousEnd -> SakinaNotifications.showTimer(
                    context,
                    "Prayer silence",
                    "$label · sound returns at " +
                        SakinaNotifications.formatTime(context, silenceEnd)
                )
            }
        } else {
            SakinaNotifications.showPrayerUnavailable(context, prayer)
        }

        // Roll the next few days forward now that this occurrence fired.
        PrayerAlarmScheduler.refresh(context)
    }
}
