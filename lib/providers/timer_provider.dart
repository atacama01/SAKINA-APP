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

  Future<bool> start(int minutes) async {
    final int previousMode = state.status == TimerStatus.running
        ? state.previousRingerMode
        : await SilentService.getCurrentMode();

    _ticker?.cancel();
    _ticker = null;

    final success = await SilentService.enableSilent();
    if (!success) return false;

    await SilentService.cancelScheduledRestore();

    final endTime = DateTime.now()
        .add(Duration(minutes: minutes))
        .millisecondsSinceEpoch;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('end_time', endTime);
    await prefs.setInt('previous_mode', previousMode);

    state = TimerState(
      status: TimerStatus.running,
      remainingSeconds: minutes * 60,
      previousRingerMode: previousMode,
    );

    _tick();
    return true;
  }

  void _tick() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (state.remainingSeconds <= 1) {
        await _finish();
      } else {
        final remaining = state.remainingSeconds - 1;
        state = state.copyWith(remainingSeconds: remaining);
        await NotificationService.showTimerNotification(remaining);
      }
    });
  }

  Future<void> _finish() async {
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
  }

  /// Called on app open — resumes any active timer from SharedPreferences.
  Future<void> resumeIfActive() async {
    final prefs = await SharedPreferences.getInstance();
    final endTime = prefs.getInt('end_time');
    final previousMode = prefs.getInt('previous_mode');

    if (endTime == null || previousMode == null) return;

    final remaining =
        (endTime - DateTime.now().millisecondsSinceEpoch) ~/ 1000;

    if (remaining <= 0) {
      await SilentService.restoreMode(previousMode);
      await prefs.remove('end_time');
      await prefs.remove('previous_mode');
      return;
    }

    await SilentService.cancelScheduledRestore();

    state = TimerState(
      status: TimerStatus.running,
      remainingSeconds: remaining,
      previousRingerMode: previousMode,
    );
    _tick();
  }

  /// Called every time app comes to foreground.
  /// Handles ALL cases: tile started, tile stopped, or tile replaced timer.
  Future<void> syncState() async {
    final prefs = await SharedPreferences.getInstance();
    final endTime = prefs.getInt('end_time');
    final previousMode = prefs.getInt('previous_mode');

    final now = DateTime.now().millisecondsSinceEpoch;

    // Case 1: SharedPreferences has an active timer
    if (endTime != null && previousMode != null && endTime > now) {
      final remaining = (endTime - now) ~/ 1000;

      // Case 1a: Dart timer is already running for the same session — just
      // correct the remaining seconds in case of clock drift, no restart needed.
      if (state.status == TimerStatus.running) {
        // Only restart ticker if the end time differs significantly (tile
        // replaced the timer while app was backgrounded).
        final dartEndEstimate =
            now + (state.remainingSeconds * 1000);
        final drift = (dartEndEstimate - endTime).abs();

        if (drift > 5000) {
          // Tile started a NEW timer while app was in background — replace.
          _ticker?.cancel();
          _ticker = null;
          await SilentService.cancelScheduledRestore();

          state = TimerState(
            status: TimerStatus.running,
            remainingSeconds: remaining,
            previousRingerMode: previousMode,
          );
          _tick();
        }
        // else: same timer, minor drift — leave it running as-is.
        return;
      }

      // Case 1b: Dart timer was idle but tile started one — pick it up.
      _ticker?.cancel();
      _ticker = null;
      await SilentService.cancelScheduledRestore();

      state = TimerState(
        status: TimerStatus.running,
        remainingSeconds: remaining,
        previousRingerMode: previousMode,
      );
      _tick();
      return;
    }

    // Case 2: SharedPreferences is empty but Dart thinks timer is running
    // → tile stopped it externally.
    if (state.status == TimerStatus.running &&
        (endTime == null || (endTime != null && endTime <= now))) {
      _ticker?.cancel();
      _ticker = null;
      await NotificationService.cancel();
      state = const TimerState(status: TimerStatus.idle);

      // Clean up expired entry if it exists
      if (endTime != null) {
        await prefs.remove('end_time');
        await prefs.remove('previous_mode');
      }
    }

    // Case 3: Both idle — nothing to do.
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

final timerProvider =
    StateNotifierProvider<TimerNotifier, TimerState>((ref) => TimerNotifier());