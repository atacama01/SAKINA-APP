package com.silent_timer.silent_timer

import android.content.Context
import android.content.SharedPreferences

/**
 * Shared keys between the Flutter layer and the native background components.
 *
 * Flutter's shared_preferences Android backend stores every key in the
 * "FlutterSharedPreferences" file with a "flutter." prefix.
 */
object SakinaPrefs {
    private const val FILE_NAME = "FlutterSharedPreferences"

    const val KEY_END_TIME = "flutter.end_time"
    const val KEY_PREVIOUS_MODE = "flutter.previous_mode"
    const val KEY_TILE_PRESET_MINUTES = "flutter.tile_preset_minutes"
    const val KEY_PRAYER_CONFIG = "flutter.prayer_config"
    const val KEY_PRAYER_CACHE = "flutter.prayer_cache"

    fun get(context: Context): SharedPreferences =
        context.getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE)
}
