package com.silent_timer.silent_timer

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
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
        val notif = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

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

            "cancelScheduledRestore" -> {
                try {
                    val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                    val intent = Intent(context, SilentRestoreReceiver::class.java)
                    val pi = PendingIntent.getBroadcast(
                        context,
                        SilentTimerTileService.ALARM_REQUEST_CODE,
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    alarm.cancel(pi)
                    result.success(true)
                } catch (e: Exception) {
                    result.error("FAILED", e.message, null)
                }
            }

            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}