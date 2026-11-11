package com.silent_timer.silent_timer

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Builds the native alarm schedule for automatic prayer silence.
 *
 * Flutter fetches and caches the prayer times, then calls refresh(). Native
 * code only reads the cached JSON, so the schedule keeps working when the app
 * is closed or killed, without any network call in the background.
 */
object PrayerAlarmScheduler {
    private const val START_REQUEST_BASE = 2100
    private const val MAX_START_ALARMS = 64
    private const val MAINTENANCE_REQUEST_CODE = 3100

    private const val DAY_MS = 24L * 60L * 60L * 1000L
    private const val MAX_DAYS_AHEAD_MS = 8L * DAY_MS

    private val PRAYERS = listOf("fajr", "dhuhr", "asr", "maghrib", "isha")

    private val DEFAULT_DELAYS = mapOf(
        "fajr" to 20,
        "dhuhr" to 15,
        "asr" to 15,
        "maghrib" to 7,
        "isha" to 15
    )

    private const val DEFAULT_DURATION = 20

    /**
     * Cancels and rebuilds every prayer alarm. Safe to call often: it is
     * invoked when the app opens, after fetching new times, after a prayer
     * silence, and by the daily maintenance receiver.
     */
    fun refresh(context: Context): Boolean {
        cancelStartAlarms(context)
        cancelMaintenance(context)

        val prefs = SakinaPrefs.get(context)
        val config = readConfig(prefs) ?: return true
        if (!config.enabled) return true

        val cache = readCache(prefs)
        val now = System.currentTimeMillis()

        if (cache.times.isEmpty()) {
            // Nothing to schedule yet. Remind the user later instead of
            // waking up constantly.
            scheduleMaintenance(context, now + DAY_MS)
            return true
        }

        val upcoming = cache.times
            .asSequence()
            .mapNotNull { entry ->
                val rule = config.rules[entry.prayer] ?: return@mapNotNull null
                if (!rule.enabled) return@mapNotNull null

                val start = entry.adhan +
                    rule.delayMinutes * 60_000L
                val end = start +
                    rule.durationMinutes * 60_000L

                if (end <= now || start <= now ||
                    start > now + MAX_DAYS_AHEAD_MS
                ) {
                    null
                } else {
                    Occurrence(entry.prayer, start, end)
                }
            }
            .sortedBy { it.start }
            .take(MAX_START_ALARMS)
            .toList()

        upcoming.forEachIndexed { index, occurrence ->
            try {
                SilentAlarmScheduler.setAlarm(
                    context,
                    occurrence.start,
                    startPendingIntent(context, index, occurrence)
                )
            } catch (_: Exception) {
                // One malformed occurrence should not stop the rest.
            }
        }

        // Rebuild the schedule every few days so alarms continue to roll
        // forward even when the app is never opened. If the cached times are
        // about to end, check again tomorrow and remind the user.
        val maintenanceAt = if (cache.lastTs < now + 2L * DAY_MS) {
            now + DAY_MS
        } else {
            now + 3L * DAY_MS
        }
        scheduleMaintenance(context, maintenanceAt)

        return true
    }

    /**
     * True when prayer mode is enabled but the cached times are missing or
     * close to running out.
     */
    fun needsRefresh(context: Context): Boolean {
        val prefs = SakinaPrefs.get(context)
        val config = readConfig(prefs) ?: return false
        if (!config.enabled) return false

        val cache = readCache(prefs)
        if (cache.lastTs <= 0L) return true

        return cache.lastTs < System.currentTimeMillis() + 2L * DAY_MS
    }

    private fun scheduleMaintenance(context: Context, triggerAtMs: Long) {
        try {
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                MAINTENANCE_REQUEST_CODE,
                Intent(context, PrayerMaintenanceReceiver::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            alarm.set(AlarmManager.RTC_WAKEUP, triggerAtMs, pendingIntent)
        } catch (_: Exception) {
            // Maintenance is best effort; prayer starts still have their own
            // alarms.
        }
    }

    private fun cancelMaintenance(context: Context) {
        try {
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                MAINTENANCE_REQUEST_CODE,
                Intent(context, PrayerMaintenanceReceiver::class.java),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            ) ?: return

            alarm.cancel(pendingIntent)
            pendingIntent.cancel()
        } catch (_: Exception) {
            // Nothing to cancel.
        }
    }

    private fun startPendingIntent(
        context: Context,
        index: Int,
        occurrence: Occurrence
    ): PendingIntent {
        val intent = Intent(context, PrayerSilenceReceiver::class.java).apply {
            action = PrayerSilenceReceiver.ACTION_PRAYER_SILENCE
            putExtra(PrayerSilenceReceiver.EXTRA_PRAYER, occurrence.prayer)
            putExtra(PrayerSilenceReceiver.EXTRA_SILENCE_END, occurrence.end)
        }
        return PendingIntent.getBroadcast(
            context,
            START_REQUEST_BASE + index,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun cancelStartAlarms(context: Context) {
        try {
            val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val baseIntent = Intent(
                context,
                PrayerSilenceReceiver::class.java
            ).apply {
                action = PrayerSilenceReceiver.ACTION_PRAYER_SILENCE
            }

            for (index in 0 until MAX_START_ALARMS) {
                val pendingIntent = PendingIntent.getBroadcast(
                    context,
                    START_REQUEST_BASE + index,
                    baseIntent,
                    PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
                ) ?: continue

                alarm.cancel(pendingIntent)
                pendingIntent.cancel()
            }
        } catch (_: Exception) {
            // Best effort.
        }
    }

    private fun readConfig(prefs: SharedPreferences): PrayerConfig? {
        val raw = prefs.getString(SakinaPrefs.KEY_PRAYER_CONFIG, null)
            ?: return null

        return try {
            val json = JSONObject(raw)
            val rulesJson = json.optJSONObject("rules")
            val rules = HashMap<String, Rule>()

            for (prayer in PRAYERS) {
                val ruleJson = rulesJson?.optJSONObject(prayer)
                val enabled = ruleJson?.optBoolean("enabled", true) ?: true
                val delay = ruleJson?.optInt(
                    "delay",
                    DEFAULT_DELAYS[prayer] ?: 15
                ) ?: (DEFAULT_DELAYS[prayer] ?: 15)
                val duration = ruleJson?.optInt(
                    "duration",
                    DEFAULT_DURATION
                ) ?: DEFAULT_DURATION

                rules[prayer] = Rule(
                    enabled = enabled,
                    delayMinutes = delay.coerceIn(0, 120),
                    durationMinutes = duration.coerceIn(1, 180)
                )
            }

            PrayerConfig(
                enabled = json.optBoolean("enabled", false),
                rules = rules
            )
        } catch (_: Exception) {
            null
        }
    }

    private fun readCache(prefs: SharedPreferences): Cache {
        val raw = prefs.getString(SakinaPrefs.KEY_PRAYER_CACHE, null)
            ?: return Cache(emptyList(), 0L)

        return try {
            val json = JSONObject(raw)
            val array: JSONArray = json.optJSONArray("times")
                ?: JSONArray()
            val times = ArrayList<TimeEntry>(array.length())

            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index) ?: continue
                val prayer = item.optString("prayer").lowercase()
                val timestamp = item.optLong("ts", 0L)

                if (timestamp > 0L && PRAYERS.contains(prayer)) {
                    times.add(TimeEntry(prayer, timestamp))
                }
            }

            times.sortBy { it.adhan }
            Cache(times, times.maxOfOrNull { it.adhan } ?: 0L)
        } catch (_: Exception) {
            Cache(emptyList(), 0L)
        }
    }

    private data class PrayerConfig(
        val enabled: Boolean,
        val rules: Map<String, Rule>
    )

    private data class Rule(
        val enabled: Boolean,
        val delayMinutes: Int,
        val durationMinutes: Int
    )

    private data class TimeEntry(
        val prayer: String,
        val adhan: Long
    )

    private data class Cache(
        val times: List<TimeEntry>,
        val lastTs: Long
    )

    private data class Occurrence(
        val prayer: String,
        val start: Long,
        val end: Long
    )
}
