import 'dart:convert';

import 'prayer_settings.dart';

class PrayerTime {
  final PrayerName prayer;
  final DateTime adhan;

  const PrayerTime({required this.prayer, required this.adhan});

  Map<String, dynamic> toJson() => {
        'prayer': prayer.key,
        'ts': adhan.millisecondsSinceEpoch,
      };

  factory PrayerTime.fromJson(Map<String, dynamic> json) {
    final prayer = prayerNameFromKey(json['prayer'] as String?);
    if (prayer == null) {
      throw const FormatException('Unknown prayer');
    }
    return PrayerTime(
      prayer: prayer,
      adhan: DateTime.fromMillisecondsSinceEpoch(
        (json['ts'] as num).toInt(),
      ),
    );
  }
}

class PrayerCache {
  final String source;
  final DateTime fetchedAt;
  final List<PrayerTime> times;

  const PrayerCache({
    required this.source,
    required this.fetchedAt,
    required this.times,
  });

  DateTime? get lastTime {
    if (times.isEmpty) return null;
    return times
        .map((entry) => entry.adhan)
        .reduce((a, b) => a.isAfter(b) ? a : b);
  }

  bool covers(DateTime moment) {
    final last = lastTime;
    return last != null && last.isAfter(moment);
  }

  List<PrayerTime> forDate(DateTime date) {
    return times
        .where((entry) =>
            entry.adhan.year == date.year &&
            entry.adhan.month == date.month &&
            entry.adhan.day == date.day)
        .toList()
      ..sort((a, b) => a.adhan.compareTo(b.adhan));
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'source': source,
        'fetchedAt': fetchedAt.millisecondsSinceEpoch,
        'times': times.map((entry) => entry.toJson()).toList(),
      };

  String toJsonString() => jsonEncode(toJson());

  factory PrayerCache.fromJson(Map<String, dynamic> json) {
    final rawTimes = json['times'];
    if (rawTimes is! List) {
      throw const FormatException('Prayer cache has no times');
    }

    final times = <PrayerTime>[];
    for (final raw in rawTimes) {
      if (raw is Map<String, dynamic>) {
        try {
          times.add(PrayerTime.fromJson(raw));
        } on FormatException {
          // Ignore malformed entries and keep the rest of the cache.
        }
      }
    }
    times.sort((a, b) => a.adhan.compareTo(b.adhan));

    return PrayerCache(
      source: json['source'] as String? ?? '',
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(
        (json['fetchedAt'] as num?)?.toInt() ?? 0,
      ),
      times: times,
    );
  }

  factory PrayerCache.fromJsonString(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return PrayerCache.fromJson(decoded);
    }
    throw const FormatException('Invalid prayer cache');
  }
}

class PrayerOccurrence {
  final PrayerName prayer;
  final DateTime adhan;
  final DateTime silenceStart;
  final DateTime silenceEnd;

  const PrayerOccurrence({
    required this.prayer,
    required this.adhan,
    required this.silenceStart,
    required this.silenceEnd,
  });

  bool get usesSameDay =>
      silenceStart.year == adhan.year &&
      silenceStart.month == adhan.month &&
      silenceStart.day == adhan.day;

  bool isActiveAt(DateTime now) {
    return !now.isBefore(silenceStart) && now.isBefore(silenceEnd);
  }
}

PrayerOccurrence occurrenceFor(
  PrayerTime time,
  PrayerRule rule,
) {
  final start = time.adhan.add(Duration(minutes: rule.iqamahDelayMinutes));
  return PrayerOccurrence(
    prayer: time.prayer,
    adhan: time.adhan,
    silenceStart: start,
    silenceEnd:
        start.add(Duration(minutes: rule.silenceDurationMinutes)),
  );
}

List<PrayerOccurrence> occurrencesForDate(
  PrayerSettings settings,
  PrayerCache cache,
  DateTime date,
) {
  return cache
      .forDate(date)
      .map((time) => occurrenceFor(time, settings.ruleFor(time.prayer)))
      .toList()
    ..sort((a, b) => a.silenceStart.compareTo(b.silenceStart));
}

PrayerOccurrence? nextOccurrence(
  PrayerSettings settings,
  PrayerCache? cache,
  DateTime now,
) {
  if (!settings.enabled || cache == null) return null;

  PrayerOccurrence? next;
  for (final time in cache.times) {
    final rule = settings.ruleFor(time.prayer);
    if (!rule.enabled) continue;

    final occurrence = occurrenceFor(time, rule);
    if (!occurrence.silenceStart.isAfter(now)) continue;

    if (next == null ||
        occurrence.silenceStart.isBefore(next.silenceStart)) {
      next = occurrence;
    }
  }
  return next;
}

PrayerOccurrence? currentOccurrence(
  PrayerSettings settings,
  PrayerCache? cache,
  DateTime now,
) {
  if (!settings.enabled || cache == null) return null;

  for (final time in cache.times) {
    final rule = settings.ruleFor(time.prayer);
    if (!rule.enabled) continue;

    final occurrence = occurrenceFor(time, rule);
    if (occurrence.isActiveAt(now)) return occurrence;
  }
  return null;
}

class PrayerStatus {
  final PrayerSettings settings;
  final PrayerCache? cache;
  final bool cacheMatchesSource;
  final PrayerOccurrence? next;
  final PrayerOccurrence? current;

  const PrayerStatus({
    required this.settings,
    required this.cache,
    required this.cacheMatchesSource,
    required this.next,
    required this.current,
  });

  bool get hasUsableSchedule {
    return cache != null &&
        cacheMatchesSource &&
        (cache!.lastTime?.isAfter(DateTime.now()) ?? false);
  }
}
