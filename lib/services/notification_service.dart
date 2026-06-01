import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static const _channelId = 'silent_timer_channel';
  static const _notifId = 1;

  static Future<void> init() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);

    const androidChannel = AndroidNotificationChannel(
      _channelId,
      'Silent Timer',
      description: 'Shows active silent timer',
      importance: Importance.low,
    );
      await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  static Future<void> showTimerNotification(int remainingSeconds) async {
    final m = remainingSeconds ~/ 60;
    final s = remainingSeconds % 60;
    final timeStr =
        '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

    const details = AndroidNotificationDetails(
      _channelId,
      'Silent Timer',
      channelDescription: 'Shows active silent timer',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      onlyAlertOnce: true,
      icon: '@mipmap/ic_launcher',
    );

    await _plugin.show(
      _notifId,
      '🔇 Phone is silenced',
      'Restoring sound in $timeStr',
      const NotificationDetails(android: details),
    );
  }

  static Future<void> showRestoredNotification() async {
    const details = AndroidNotificationDetails(
      _channelId,
      'Silent Timer',
      channelDescription: 'Shows active silent timer',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@mipmap/ic_launcher',
    );
    await _plugin.show(
      _notifId,
      '🔔 Sound restored',
      'Your phone is back to normal.',
      const NotificationDetails(android: details),
    );
  }

  static Future<void> cancel() async {
    await _plugin.cancel(_notifId);
  }
}