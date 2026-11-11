package com.silent_timer.silent_timer

import android.app.NotificationManager
import android.content.Context
import android.content.SharedPreferences
import android.media.AudioManager

/**
 * Small state machine around the single native silence session.
 *
 * The session is described by `flutter.end_time` and
 * `flutter.previous_mode`, which are also read by the Quick Settings tile
 * and the Flutter timer provider.
 */
object SakinaSilence {

    fun canSilence(context: Context): Boolean {
        val notifications = context.getSystemService(
            Context.NOTIFICATION_SERVICE
        ) as NotificationManager
        return notifications.isNotificationPolicyAccessGranted
    }

    /**
     * Restores the ringer mode if the stored session already expired but its
     * alarm was missed (for example after a device reboot). Returns true when
     * an expired session was cleaned up.
     */
    fun restoreIfExpired(
        context: Context,
        prefs: SharedPreferences = SakinaPrefs.get(context)
    ): Boolean {
        val endTime = prefs.getLong(SakinaPrefs.KEY_END_TIME, 0L)
        if (endTime <= 0L || endTime > System.currentTimeMillis()) return false

        restore(context, prefs)
        return true
    }

    /**
     * Ends the current silence session, restoring the saved ringer mode and
     * clearing the persisted state. Returns true if a session existed.
     */
    fun restore(
        context: Context,
        prefs: SharedPreferences = SakinaPrefs.get(context)
    ): Boolean {
        val endTime = prefs.getLong(SakinaPrefs.KEY_END_TIME, 0L)
        val previousMode = prefs.getLong(
            SakinaPrefs.KEY_PREVIOUS_MODE,
            AudioManager.RINGER_MODE_NORMAL.toLong()
        ).toInt()

        val hadSession = endTime > 0L || prefs.contains(SakinaPrefs.KEY_PREVIOUS_MODE)
        if (!hadSession) return false

        try {
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audio.ringerMode = previousMode
        } catch (_: Exception) {
            // DND access can be revoked while the timer is running.
        }

        prefs.edit()
            .remove(SakinaPrefs.KEY_END_TIME)
            .remove(SakinaPrefs.KEY_PREVIOUS_MODE)
            .apply()

        SilentAlarmScheduler.cancelRestore(context)
        return true
    }

    /**
     * Silences the phone until [endTimeMs]. If a silence session is already
     * active the existing original ringer mode is preserved, and the end time
     * is extended when the new session ends later.
     *
     * Returns false only when the phone cannot be silenced (DND access is
     * missing) or the alarm could not be scheduled.
     */
    fun start(
        context: Context,
        prefs: SharedPreferences = SakinaPrefs.get(context),
        endTimeMs: Long
    ): Boolean {
        val now = System.currentTimeMillis()
        if (endTimeMs <= now) return false

        // Clean up a session whose alarm was missed before deciding whether
        // the phone is already silent.
        restoreIfExpired(context, prefs)

        val activeEnd = prefs.getLong(SakinaPrefs.KEY_END_TIME, 0L)
        if (activeEnd > now) {
            if (endTimeMs > activeEnd) {
                prefs.edit()
                    .putLong(SakinaPrefs.KEY_END_TIME, endTimeMs)
                    .apply()
                SilentAlarmScheduler.scheduleRestore(context, endTimeMs)
            }
            return true
        }

        if (!canSilence(context)) return false

        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val previousMode = audio.ringerMode

        audio.ringerMode = AudioManager.RINGER_MODE_SILENT

        prefs.edit()
            .putLong(SakinaPrefs.KEY_PREVIOUS_MODE, previousMode.toLong())
            .putLong(SakinaPrefs.KEY_END_TIME, endTimeMs)
            .apply()

        if (!SilentAlarmScheduler.scheduleRestore(context, endTimeMs)) {
            // Roll back instead of leaving the phone silent forever.
            try {
                audio.ringerMode = previousMode
            } catch (_: Exception) {
                // Ignore.
            }
            prefs.edit()
                .remove(SakinaPrefs.KEY_END_TIME)
                .remove(SakinaPrefs.KEY_PREVIOUS_MODE)
                .apply()
            return false
        }

        return true
    }
}
