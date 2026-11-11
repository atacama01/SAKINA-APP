package com.silent_timer.silent_timer

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings

/**
 * Owns the single "restore sound" alarm. Both the manual timer and the
 * automatic prayer silence use this alarm, which guarantees that only one
 * silence session is active at a time.
 */
object SilentAlarmScheduler {
    const val RESTORE_REQUEST_CODE = 1001

    fun canScheduleExactAlarms(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return alarm.canScheduleExactAlarms()
    }

    fun scheduleRestore(context: Context, endTimeMs: Long): Boolean {
        if (endTimeMs <= System.currentTimeMillis()) return false

        return try {
            setAlarm(context, endTimeMs, restorePendingIntent(context))
            true
        } catch (_: SecurityException) {
            // Exact alarm permission was revoked between the check and the
            // call. Try the inexact fallback once more.
            try {
                val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarm.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        endTimeMs,
                        restorePendingIntent(context)
                    )
                } else {
                    alarm.set(
                        AlarmManager.RTC_WAKEUP,
                        endTimeMs,
                        restorePendingIntent(context)
                    )
                }
                true
            } catch (_: Exception) {
                false
            }
        } catch (_: Exception) {
            false
        }
    }

    fun cancelRestore(context: Context) {
        try {
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                RESTORE_REQUEST_CODE,
                Intent(context, SilentRestoreReceiver::class.java),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            ) ?: return

            alarm.cancel(pendingIntent)
            pendingIntent.cancel()
        } catch (_: Exception) {
            // Nothing to cancel.
        }
    }

    fun setAlarm(
        context: Context,
        triggerAtMs: Long,
        pendingIntent: PendingIntent
    ) {
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val exact = canScheduleExactAlarms(context)

        when {
            exact && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ->
                alarm.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMs,
                    pendingIntent
                )

            exact ->
                alarm.setExact(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMs,
                    pendingIntent
                )

            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ->
                alarm.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMs,
                    pendingIntent
                )

            else ->
                alarm.set(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMs,
                    pendingIntent
                )
        }
    }

    fun openExactAlarmSettings(context: Context) {
        val packageUri = Uri.parse("package:${context.packageName}")
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, packageUri)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri)
        }
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)

        try {
            context.startActivity(intent)
        } catch (_: Exception) {
            val fallback = Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                packageUri
            )
            fallback.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                context.startActivity(fallback)
            } catch (_: Exception) {
                // Device does not expose the settings screen.
            }
        }
    }

    private fun restorePendingIntent(context: Context): PendingIntent {
        return PendingIntent.getBroadcast(
            context,
            RESTORE_REQUEST_CODE,
            Intent(context, SilentRestoreReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
