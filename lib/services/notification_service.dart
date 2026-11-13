import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'silent_timer_channel';
  static const _notifId = 1;
  static const _restoredNotifId = 2;
  static const _smallIcon = 'ic_stat_sakina';

  static Future<void> init() async {
    const android = AndroidInitializationSettings(_smallIcon);
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);

    const androidChannel = AndroidNotificationChannel(
      _channelId,
      'Silent Timer',
      description: 'Shows the active silent timer and prayer silence',
      importance: Importance.low,
      playSound: false,
      enableVibration: false,
      showBadge: false,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  static Future<bool> requestPermission() async {
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return true;
      return await android.requestNotificationsPermission() ?? true;
    } catch (_) {
      return true;
    }
  }

  static Future<void> showTimerNotification(int remainingSeconds) async {
    final m = remainingSeconds ~/ 60;
    final s = remainingSeconds % 60;
    final timeStr =
        '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

    const details = AndroidNotificationDetails(
      _channelId,
      'Silent Timer',
      channelDescription: 'Shows the active silent timer and prayer silence',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
      visibility: NotificationVisibility.public,
      icon: _smallIcon,
    );

    try {
      await _plugin.show(
        _notifId,
        'Phone is silenced',
        'Restoring sound in $timeStr',
        const NotificationDetails(android: details),
      );
    } catch (error) {
      // Notification problems must not interrupt a running timer.
      debugPrint('Could not update the timer notification: $error');
    }
  }

  static Future<void> showRestoredNotification() async {
    const details = AndroidNotificationDetails(
      _channelId,
      'Silent Timer',
      channelDescription: 'Shows the active silent timer and prayer silence',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: false,
      autoCancel: true,
      onlyAlertOnce: true,
      playSound: false,
      enableVibration: false,
      timeoutAfter: 7000,
      icon: _smallIcon,
    );
    // Use a separate id so the periodic timer sync cannot cancel the brief
    // confirmation message.
    try {
      await _plugin.cancel(_notifId);
      await _plugin.show(
        _restoredNotifId,
        'Sound restored',
        'Your phone is back to normal.',
        const NotificationDetails(android: details),
      );
    } catch (error) {
      // Finishing the timer (and clearing its persisted state) must not
      // depend on the notification plugin succeeding.
      debugPrint('Could not show the restored notification: $error');
    }
  }

  static Future<void> cancel() async {
    try {
      await _plugin.cancel(_notifId);
    } catch (error) {
      debugPrint('Could not cancel the timer notification: $error');
    }
  }
}
