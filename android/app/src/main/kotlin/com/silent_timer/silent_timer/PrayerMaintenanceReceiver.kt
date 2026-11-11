package com.silent_timer.silent_timer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Periodic background check. Rebuilds the rolling alarm window and reminds
 * the user when cached prayer times are close to running out.
 */
class PrayerMaintenanceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val needsRefresh = PrayerAlarmScheduler.needsRefresh(context)

        PrayerAlarmScheduler.refresh(context)

        if (needsRefresh) {
            SakinaNotifications.showRefreshNeeded(context)
        }
    }
}
