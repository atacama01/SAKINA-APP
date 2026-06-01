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
}