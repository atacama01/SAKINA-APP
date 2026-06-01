package com.silent_timer.silent_timer

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioManager

class SilentRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val prefs = context.getSharedPreferences(
            "FlutterSharedPreferences", Context.MODE_PRIVATE)
        val endTime = prefs.getLong("flutter.end_time", 0L)
        if (endTime > 0) {
            val mode = prefs.getLong("flutter.previous_mode", 2L).toInt()
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            audio.ringerMode = mode
            prefs.edit()
                .remove("flutter.end_time")
                .remove("flutter.previous_mode")
                .apply()
        }
    }
}