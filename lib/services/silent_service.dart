import 'package:flutter/services.dart';

class SilentService {
  static const _channel = MethodChannel('silent_timer/audio');

  static Future<int> getCurrentMode() async {
    try {
      return await _channel.invokeMethod<int>('getCurrentMode') ?? 2;
    } catch (_) {
      return 2;
    }
  }

  static Future<bool> enableSilent() async {
    try {
      return await _channel.invokeMethod<bool>('enableSilent') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> restoreMode(int mode) async {
    try {
      await _channel.invokeMethod('restoreMode', {'mode': mode});
    } catch (_) {}
  }

  static Future<bool> hasDndPermission() async {
    try {
      return await _channel.invokeMethod<bool>('hasDndPermission') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openDndSettings() async {
    try {
      await _channel.invokeMethod('openDndSettings');
    } catch (_) {}
  }

  static Future<void> cancelScheduledRestore() async {
    try {
      await _channel.invokeMethod('cancelScheduledRestore');
    } catch (_) {}
  }

  static Future<bool> scheduleRestore(int endTimeMs) async {
    try {
      return await _channel.invokeMethod<bool>(
            'scheduleRestore',
            {'endTime': endTimeMs},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> refreshPrayerSchedule() async {
    try {
      return await _channel.invokeMethod<bool>('refreshPrayerSchedule') ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> canScheduleExactAlarms() async {
    try {
      return await _channel.invokeMethod<bool>('canScheduleExactAlarms') ??
          true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> openExactAlarmSettings() async {
    try {
      await _channel.invokeMethod('openExactAlarmSettings');
    } catch (_) {}
  }

  static Future<bool> testPrayerSilence() async {
    try {
      return await _channel.invokeMethod<bool>('testPrayerSilence') ?? false;
    } catch (_) {
      return false;
    }
  }
}