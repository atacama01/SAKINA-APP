import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/silent_service.dart';
import '../services/notification_service.dart';

enum TimerStatus { idle, running }

class TimerState {
  final TimerStatus status;
  final int remainingSeconds;
  final int previousRingerMode;

  const TimerState({
    this.status = TimerStatus.idle,
    this.remainingSeconds = 0,
    this.previousRingerMode = 2,
  });

  TimerState copyWith({
    TimerStatus? status,
    int? remainingSeconds,
    int? previousRingerMode,
  }) =>
      TimerState(
        status: status ?? this.status,
        remainingSeconds: remainingSeconds ?? this.remainingSeconds,
        previousRingerMode: previousRingerMode ?? this.previousRingerMode,
      );
}

class TimerNotifier extends StateNotifier<TimerState> {
  TimerNotifier() : super(const TimerState());

  Timer? _ticker;
  int _session = 0;

  Future<bool> start(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final activeEndTime = prefs.getInt('end_time');
    final storedPreviousMode = prefs.getInt('previous_mode');

    // If a timer (or a prayer silence) is already active, keep the original
    // ringer mode instead of saving "silent" as the mode to restore.
    final int previousMode;
    if (activeEndTime != null &&
        activeEndTime > now &&
        storedPreviousMode != null) {
      previousMode = storedPreviousMode;
    } else if (state.status == TimerStatus.running) {
      previousMode = state.previousRingerMode;
    } else {
      previousMode = await SilentService.getCurrentMode();
    }

    _ticker?.cancel();
    _ticker = null;

    final success = await SilentService.enableSilent();
    if (!success) return false;

    final endTime = DateTime.now()
        .add(Duration(minutes: minutes))
        .millisecondsSinceEpoch;

    await prefs.setInt('end_time', endTime);
    await prefs.setInt('previous_mode', previousMode);

    _session++;
    state = TimerState(
      status: TimerStatus.running,
      remainingSeconds: minutes * 60,
      previousRingerMode: previousMode,
    );

    await SilentService.cancelScheduledRestore();
    await SilentService.scheduleRestore(endTime);

    _tick();
    return true;
  }

  void _tick() {
    _ticker?.cancel();
    final session = _session;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (session != _session) return;
      if (state.remainingSeconds <= 1) {
        await _finish();
      } else {
        final remaining = state.remainingSeconds - 1;
        state = state.copyWith(remainingSeconds: remaining);
        if (session == _session && state.status == TimerStatus.running) {
          await NotificationService.showTimerNotification(remaining);
        }
      }
    });
  }

  Future<void> _finish() async {
    _session++;
    _ticker?.cancel();
    _ticker = null;

    final mode = state.previousRingerMode;
    state = const TimerState(status: TimerStatus.idle);

    await SilentService.restoreMode(mode);
    await SilentService.cancelScheduledRestore();
    await NotificationService.showRestoredNotification();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('end_time');
    await prefs.remove('previous_mode');
  }

  Future<void> stop() async {
    if (state.status == TimerStatus.idle) return;

    _session++;
    _ticker?.cancel();
    _ticker = null;

    final mode = state.previousRingerMode;
    state = const TimerState(status: TimerStatus.idle);

    await SilentService.restoreMode(mode);
    await SilentService.cancelScheduledRestore();
    await NotificationService.cancel();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('end_time');
    await prefs.remove('previous_mode');
  }

  Future<void> addMinutes(int minutes) async {
    if (state.status != TimerStatus.running) return;
    state =
        state.copyWith(remainingSeconds: state.remainingSeconds + minutes * 60);

    final prefs = await SharedPreferences.getInstance();
    final endTime = prefs.getInt('end_time');
    if (endTime != null) {
      final newEndTime = endTime + minutes * 60 * 1000;
      await prefs.setInt('end_time', newEndTime);
      await SilentService.cancelScheduledRestore();
      await SilentService.scheduleRestore(newEndTime);
    }
  }

  /// Called on app open — resumes any active timer from SharedPreferences.
  Future<void> resumeIfActive() async {
    final prefs = await SharedPreferences.getInstance();
    // Native components (prayer alarms, Quick Settings tile) update the same
    // preferences file. Refresh the Dart cache before trusting it.
    await prefs.reload();
    final endTime = prefs.getInt('end_time');
    final previousMode = prefs.getInt('previous_mode');

    if (endTime == null || previousMode == null) {
      await NotificationService.cancel();
      return;
    }

    final remaining =
        (endTime - DateTime.now().millisecondsSinceEpoch) ~/ 1000;

    if (remaining <= 0) {
      await SilentService.restoreMode(previousMode);
      await SilentService.cancelScheduledRestore();
      await NotificationService.cancel();
      await prefs.remove('end_time');
      await prefs.remove('previous_mode');
      return;
    }

    // Keep the native restore alarm in sync. This also restores the timer when
    // the Flutter process is killed while the app is in the background.
    await SilentService.scheduleRestore(endTime);

    _session++;
    state = TimerState(
      status: TimerStatus.running,
      remainingSeconds: remaining,
      previousRingerMode: previousMode,
    );
    _tick();
  }

  /// Called every time app comes to foreground.
  /// Handles ALL cases: prayer start, tile started, tile stopped, or tile
  /// replaced timer.
  Future<void> syncState() async {
    final prefs = await SharedPreferences.getInstance();
    // The tile and native prayer receivers write to the shared preferences
    // file directly, so drop the Dart cache before reading the timer state.
    await prefs.reload();
    final endTime = prefs.getInt('end_time');
    final previousMode = prefs.getInt('previous_mode');

    final now = DateTime.now().millisecondsSinceEpoch;

    // Case 1: SharedPreferences has an active timer
    if (endTime != null && previousMode != null && endTime > now) {
      final remaining = (endTime - now) ~/ 1000;

      // Case 1a: Dart timer is already running for the same session — just
      // correct the remaining seconds in case of clock drift, no restart needed.
      if (state.status == TimerStatus.running) {
        final dartEndEstimate =
            now + (state.remainingSeconds * 1000);
        final drift = (dartEndEstimate - endTime).abs();

        if (drift > 5000) {
          // A new timer (tile or prayer) replaced the timer while the app was
          // in the background.
          _session++;
          _ticker?.cancel();
          _ticker = null;

          state = TimerState(
            status: TimerStatus.running,
            remainingSeconds: remaining,
            previousRingerMode: previousMode,
          );
          await SilentService.scheduleRestore(endTime);
          _tick();
        }
        // else: same timer, minor drift — leave it running as-is.
        return;
      }

      // Case 1b: Dart timer was idle but a native path started one.
      _session++;
      _ticker?.cancel();
      _ticker = null;

      state = TimerState(
        status: TimerStatus.running,
        remainingSeconds: remaining,
        previousRingerMode: previousMode,
      );
      await SilentService.scheduleRestore(endTime);
      _tick();
      return;
    }

    // Case 2: SharedPreferences is empty but Dart thinks timer is running
    // → tile or native restore stopped it externally.
    if (state.status == TimerStatus.running &&
        (endTime == null || endTime <= now)) {
      _session++;
      _ticker?.cancel();
      _ticker = null;
      await SilentService.cancelScheduledRestore();
      await NotificationService.cancel();
      state = const TimerState(status: TimerStatus.idle);

      // Clean up expired entry if it exists
      if (endTime != null) {
        await prefs.remove('end_time');
        await prefs.remove('previous_mode');
      }
      return;
    }

    // Case 3: Both idle. Make sure a stale ongoing notification is gone.
    if (state.status == TimerStatus.idle) {
      await NotificationService.cancel();
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

final timerProvider =
    StateNotifierProvider<TimerNotifier, TimerState>((ref) => TimerNotifier());
