import 'dart:async';
import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/prayer_settings.dart';
import '../models/prayer_time.dart';
import 'silent_service.dart';

class PrayerSyncResult {
  final PrayerSettings settings;
  final PrayerCache? cache;
  final bool refreshed;
  final String? warning;
  final String? error;

  const PrayerSyncResult({
    required this.settings,
    required this.cache,
    required this.refreshed,
    this.warning,
    this.error,
  });

  bool get success => error == null;
}

class PrayerService {
  static const _settingsKey = 'prayer_config';
  static const _cacheKey = 'prayer_cache';
  static const _freshFor = Duration(days: 7);
  static const _minimumCoverage = Duration(days: 2);

  static Future<PrayerSyncResult>? _syncInFlight;
  static DateTime? _lastSyncAttempt;

  static Future<PrayerSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null || raw.isEmpty) return PrayerSettings.defaults();

    try {
      return PrayerSettings.fromJsonString(raw);
    } catch (_) {
      return PrayerSettings.defaults();
    }
  }

  static Future<void> saveSettings(PrayerSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, settings.toJsonString());
  }

  static Future<PrayerCache?> loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      return PrayerCache.fromJsonString(raw);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveCache(PrayerCache cache) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_cacheKey, cache.toJsonString());
  }

  static Future<PrayerStatus> status() async {
    final settings = await loadSettings();
    final cache = await loadCache();
    final now = DateTime.now();
    final matches = cache != null && cache.source == settings.sourceKey;

    return PrayerStatus(
      settings: settings,
      cache: cache,
      cacheMatchesSource: matches,
      next: matches ? nextOccurrence(settings, cache, now) : null,
      current: matches ? currentOccurrence(settings, cache, now) : null,
    );
  }

  /// Called on app start / resume. Refreshes the cached times if needed and
  /// asks the native side to rebuild the alarm schedule.
  static Future<PrayerSyncResult> ensureSchedule({
    bool forceRefresh = false,
  }) async {
    final settings = await loadSettings();

    final lastAttempt = _lastSyncAttempt;
    final recentlyChecked = lastAttempt != null &&
        DateTime.now().difference(lastAttempt) < const Duration(minutes: 2);
    if (!forceRefresh && recentlyChecked && _syncInFlight == null) {
      await SilentService.refreshPrayerSchedule();
      final cache = await loadCache();
      final matches = cache != null && cache.source == settings.sourceKey;
      return PrayerSyncResult(
        settings: settings,
        cache: matches ? cache : null,
        refreshed: false,
      );
    }

    return sync(settings, forceRefresh: forceRefresh);
  }

  static Future<PrayerSyncResult> sync(
    PrayerSettings settings, {
    bool forceRefresh = false,
  }) async {
    final inFlight = _syncInFlight;
    if (inFlight != null) return inFlight;

    final future = _sync(settings, forceRefresh: forceRefresh);
    _syncInFlight = future;
    try {
      return await future;
    } finally {
      _syncInFlight = null;
      _lastSyncAttempt = DateTime.now();
    }
  }

  static Future<PrayerSyncResult> _sync(
    PrayerSettings settings, {
    required bool forceRefresh,
  }) async {
    await saveSettings(settings);

    final now = DateTime.now();
    final existing = await loadCache();
    final existingMatches =
        existing != null && existing.source == settings.sourceKey;

    PrayerCache? cache = existingMatches ? existing : null;
    var refreshed = false;
    String? warning;
    String? error;

    if (settings.enabled &&
        (forceRefresh ||
            !existingMatches ||
            _needsRefresh(existing, now))) {
      try {
        final fetched = await _fetchCalendar(settings);
        await saveCache(fetched);
        cache = fetched;
        refreshed = true;
      } catch (e) {
        if (cache == null) {
          error = _friendlyError(e);
        } else {
          warning =
              'Could not refresh prayer times. Using saved times. '
              '${_friendlyError(e)}';
        }
      }
    }

    await SilentService.refreshPrayerSchedule();

    return PrayerSyncResult(
      settings: settings,
      cache: cache,
      refreshed: refreshed,
      warning: warning,
      error: error,
    );
  }

  static bool _needsRefresh(PrayerCache? cache, DateTime now) {
    if (cache == null) return true;

    if (now.difference(cache.fetchedAt) > _freshFor) return true;

    final last = cache.lastTime;
    if (last == null) return true;
    if (last.isBefore(now.add(_minimumCoverage))) return true;

    return false;
  }

  static Future<PrayerCache> _fetchCalendar(PrayerSettings settings) async {
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1);

    final months = <DateTime>[
      DateTime(now.year, now.month),
      DateTime(nextMonth.year, nextMonth.month),
    ];

    final results = await Future.wait(
      months.map((month) => _fetchMonth(settings, month)),
    );

    final times = results.expand((entries) => entries).toList()
      ..sort((a, b) => a.adhan.compareTo(b.adhan));

    final deduped = <String, PrayerTime>{};
    for (final time in times) {
      final key = '${time.adhan.millisecondsSinceEpoch}|${time.prayer.key}';
      deduped[key] = time;
    }

    final sorted = deduped.values.toList()
      ..sort((a, b) => a.adhan.compareTo(b.adhan));

    return PrayerCache(
      source: settings.sourceKey,
      fetchedAt: DateTime.now(),
      times: sorted,
    );
  }

  static Future<List<PrayerTime>> _fetchMonth(
    PrayerSettings settings,
    DateTime month,
  ) async {
    final params = <String, String>{
      'method': settings.method.toString(),
      'school': settings.school.toString(),
    };

    final Uri uri;
    if (settings.locationMode == PrayerLocationMode.city) {
      params['city'] = settings.city.trim();
      params['country'] = settings.country.trim();
      uri = Uri.https(
        'api.aladhan.com',
        '/v1/calendarByCity/${month.year}/${month.month}',
        params,
      );
    } else {
      params['latitude'] = settings.latitude!.toStringAsFixed(6);
      params['longitude'] = settings.longitude!.toStringAsFixed(6);
      uri = Uri.https(
        'api.aladhan.com',
        '/v1/calendar/${month.year}/${month.month}',
        params,
      );
    }

    final response = await http.get(
      uri,
      headers: const {
        'Accept': 'application/json',
        'User-Agent': 'Sakina/1.1 (SAKINA-APP)',
      },
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode != 200) {
      throw PrayerApiException(
        'Prayer service returned HTTP ${response.statusCode}.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const PrayerApiException('Unexpected prayer service response.');
    }

    return parseCalendarResponse(decoded);
  }

  static List<PrayerTime> parseCalendarResponse(
    Map<String, dynamic> response,
  ) {
    final data = response['data'];
    if (data is! List) {
      throw const PrayerApiException(
        'Prayer service response has no prayer times.',
      );
    }

    final times = <PrayerTime>[];
    for (final day in data) {
      if (day is! Map<String, dynamic>) continue;

      final date = day['date'];
      final gregorian = date is Map<String, dynamic> ? date['gregorian'] : null;
      final rawDate =
          gregorian is Map<String, dynamic> ? gregorian['date'] : null;
      final timings = day['timings'];
      if (rawDate is! String || timings is! Map<String, dynamic>) continue;

      final dateParts = rawDate.split('-');
      if (dateParts.length != 3) continue;
      final dayNumber = int.tryParse(dateParts[0]);
      final monthNumber = int.tryParse(dateParts[1]);
      final yearNumber = int.tryParse(dateParts[2]);
      if (dayNumber == null || monthNumber == null || yearNumber == null) {
        continue;
      }

      for (final prayer in PrayerName.values) {
        final rawTime = timings[prayer.apiKey];
        if (rawTime is! String) continue;

        final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(rawTime.trim());
        if (match == null) continue;

        final hour = int.parse(match.group(1)!);
        final minute = int.parse(match.group(2)!);
        if (hour > 23 || minute > 59) continue;

        times.add(
          PrayerTime(
            prayer: prayer,
            adhan: DateTime(
              yearNumber,
              monthNumber,
              dayNumber,
              hour,
              minute,
            ),
          ),
        );
      }
    }

    if (times.isEmpty) {
      throw const PrayerApiException(
        'No prayer times were found for that location.',
      );
    }

    return times;
  }

  static String _friendlyError(Object error) {
    if (error is PrayerApiException) return error.message;
    if (error is TimeoutException) {
      return 'The prayer service timed out. Check your internet connection.';
    }
    return 'Could not load prayer times. Check your internet connection.';
  }
}

class PrayerApiException implements Exception {
  final String message;

  const PrayerApiException(this.message);

  @override
  String toString() => message;
}

class LocationException implements Exception {
  final String message;

  const LocationException(this.message);

  @override
  String toString() => message;
}

class PrayerLocationService {
  static Future<Position> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException(
        'Location services are disabled. Turn them on, or use manual city.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw const LocationException(
        'Location permission was denied. You can still use manual city.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Location permission is permanently denied. Open app settings to '
        'allow it, or use manual city.',
      );
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (_) {
      // The fused provider needs Google Play services and can time out on
      // emulators or de-Googled devices. Fall back to the platform location
      // manager, which also works with GPS-only hardware.
      return Geolocator.getCurrentPosition(
        locationSettings: AndroidSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 20),
          forceLocationManager: true,
        ),
      );
    }
  }
}
