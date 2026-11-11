package com.silent_timer.silent_timer

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class SilentModePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private lateinit var context: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "silent_timer/audio")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val notif =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        when (call.method) {
            "getCurrentMode" -> result.success(audio.ringerMode)

            "enableSilent" -> {
                if (notif.isNotificationPolicyAccessGranted) {
                    audio.ringerMode = AudioManager.RINGER_MODE_SILENT
                    result.success(true)
                } else {
                    result.error("PERMISSION_DENIED", "DND permission not granted", null)
                }
            }

            "restoreMode" -> {
                val mode = call.argument<Int>("mode") ?: AudioManager.RINGER_MODE_NORMAL
                audio.ringerMode = mode
                result.success(true)
            }

            "hasDndPermission" -> result.success(notif.isNotificationPolicyAccessGranted)

            "openDndSettings" -> {
                try {
                    val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                    intent.flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    context.startActivity(intent)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("FAILED", e.message, null)
                }
            }

            "scheduleRestore" -> {
                val endTime = call.argument<Number>("endTime")?.toLong()
                if (endTime == null) {
                    result.error("INVALID_ARGUMENT", "Missing endTime", null)
                } else {
                    result.success(
                        SilentAlarmScheduler.scheduleRestore(context, endTime)
                    )
                }
            }

            "cancelScheduledRestore" -> {
                SilentAlarmScheduler.cancelRestore(context)
                result.success(true)
            }

            "refreshPrayerSchedule" -> {
                result.success(PrayerAlarmScheduler.refresh(context))
            }

            "canScheduleExactAlarms" -> {
                result.success(SilentAlarmScheduler.canScheduleExactAlarms(context))
            }

            "openExactAlarmSettings" -> {
                SilentAlarmScheduler.openExactAlarmSettings(context)
                result.success(null)
            }

            "cancelTimerNotification" -> {
                SakinaNotifications.cancelTimer(context)
                result.success(true)
            }

            "testPrayerSilence" -> {
                val prefs = SakinaPrefs.get(context)
                val now = System.currentTimeMillis()
                val activeBefore = prefs.getLong(
                    SakinaPrefs.KEY_END_TIME,
                    0L
                ) > now
                val testEnd = now + 10_000L

                val started = SakinaSilence.start(context, prefs, testEnd)
                if (started && !activeBefore) {
                    SakinaNotifications.showTimer(
                        context,
                        "Test prayer silence",
                        "Sound returns in 10 seconds"
                    )
                }
                result.success(started)
            }

            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
