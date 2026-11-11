package com.silent_timer.silent_timer

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import android.text.format.DateFormat
import java.util.Date

/**
 * Notification helper shared by the Flutter plugin, the Quick Settings tile,
 * and the background prayer receivers.
 *
 * The timer notification intentionally uses the same channel and id as
 * flutter_local_notifications, so every path updates or removes one single
 * notification instead of creating duplicates.
 */
object SakinaNotifications {
    const val TIMER_NOTIFICATION_ID = 1
    private const val RESTORED_NOTIFICATION_ID = 2
    private const val STATUS_NOTIFICATION_ID = 3
    private const val TIMER_CHANNEL_ID = "silent_timer_channel"
    private const val STATUS_CHANNEL_ID = "sakina_status_channel"

    fun formatTime(context: Context, timestamp: Long): String {
        return DateFormat.getTimeFormat(context).format(Date(timestamp))
    }

    fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = context.getSystemService(NotificationManager::class.java)

        val timerChannel = NotificationChannel(
            TIMER_CHANNEL_ID,
            "Silent Timer",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Shows the active silent timer and prayer silence"
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        manager.createNotificationChannel(timerChannel)

        val statusChannel = NotificationChannel(
            STATUS_CHANNEL_ID,
            "Sakina alerts",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Prayer mode status and reminders"
            setShowBadge(false)
            enableVibration(false)
            setSound(null, null)
        }
        manager.createNotificationChannel(statusChannel)
    }

    fun showTimer(context: Context, title: String, text: String) {
        ensureChannels(context)

        val notification = baseBuilder(context, TIMER_CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

        notify(context, TIMER_NOTIFICATION_ID, notification)
    }

    fun showRestored(context: Context) {
        ensureChannels(context)

        // Replace the ongoing timer notification with a separate, short-lived
        // confirmation. The separate id keeps periodic app syncs from
        // cancelling this message before the user can see it.
        cancelTimer(context)

        val notification = baseBuilder(context, TIMER_CHANNEL_ID)
            .setContentTitle("Sound restored")
            .setContentText("Your phone is back to normal.")
            .setOngoing(false)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setTimeoutAfter(7_000L)
            .build()

        notify(context, RESTORED_NOTIFICATION_ID, notification)
    }

    fun cancelTimer(context: Context) {
        try {
            NotificationManagerCompat.from(context)
                .cancel(TIMER_NOTIFICATION_ID)
        } catch (_: Exception) {
            // Notification access can be revoked at any time.
        }
    }

    fun showPrayerUnavailable(context: Context, prayer: String) {
        ensureChannels(context)

        val label = prayer.replaceFirstChar { it.uppercase() }
        val notification = baseBuilder(context, STATUS_CHANNEL_ID)
            .setContentTitle("Prayer silence skipped")
            .setContentText(
                "$label — enable Do Not Disturb access so Sakina can " +
                    "silence your phone automatically."
            )
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "$label — enable Do Not Disturb access so Sakina can " +
                        "silence your phone automatically."
                )
            )
            .setOngoing(false)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setTimeoutAfter(20_000L)
            .build()

        notify(context, STATUS_NOTIFICATION_ID, notification)
    }

    fun showRefreshNeeded(context: Context) {
        ensureChannels(context)

        val notification = baseBuilder(context, STATUS_CHANNEL_ID)
            .setContentTitle("Prayer times need refreshing")
            .setContentText(
                "Open Sakina and tap Save & refresh to keep automatic " +
                    "prayer silence working."
            )
            .setStyle(
                NotificationCompat.BigTextStyle().bigText(
                    "Open Sakina and tap Save & refresh to keep automatic " +
                        "prayer silence working."
                )
            )
            .setOngoing(false)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .build()

        notify(context, STATUS_NOTIFICATION_ID, notification)
    }

    private fun baseBuilder(
        context: Context,
        channelId: String
    ): NotificationCompat.Builder {
        return NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_stat_sakina)
            .setContentIntent(contentIntent(context))
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
    }

    private fun contentIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun notify(
        context: Context,
        id: Int,
        notification: android.app.Notification
    ) {
        try {
            NotificationManagerCompat.from(context).notify(id, notification)
        } catch (_: SecurityException) {
            // POST_NOTIFICATIONS was denied. Silence still works; only the
            // status notification is missing.
        } catch (_: Exception) {
            // Never let a notification failure stop the timer/alarm logic.
        }
    }
}
