import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silent_timer/models/prayer_settings.dart';
import 'package:silent_timer/models/prayer_time.dart';
import 'package:silent_timer/providers/theme_provider.dart';
import 'package:silent_timer/services/prayer_service.dart';

void main() {
  group('Theme mode', () {
    test('defaults to system and cycles system -> light -> dark', () {
      expect(themeModeFromName(null), ThemeMode.system);
      expect(nextThemeMode(ThemeMode.system), ThemeMode.light);
      expect(nextThemeMode(ThemeMode.light), ThemeMode.dark);
      expect(nextThemeMode(ThemeMode.dark), ThemeMode.system);
    });
  });

  group('PrayerSettings', () {
    test('defaults match the requested iqamah schedule', () {
      final settings = PrayerSettings.defaults();

      expect(settings.enabled, isFalse);
      expect(settings.ruleFor(PrayerName.fajr).iqamahDelayMinutes, 20);
      expect(settings.ruleFor(PrayerName.dhuhr).iqamahDelayMinutes, 15);
      expect(settings.ruleFor(PrayerName.asr).iqamahDelayMinutes, 15);
      expect(settings.ruleFor(PrayerName.maghrib).iqamahDelayMinutes, 7);
      expect(settings.ruleFor(PrayerName.isha).iqamahDelayMinutes, 15);

      for (final prayer in PrayerName.values) {
        expect(
          settings.ruleFor(prayer).silenceDurationMinutes,
          20,
          reason: '${prayer.label} should default to 20 minutes of silence',
        );
      }
    });

    test('round-trips through JSON without losing rules', () {
      final settings = PrayerSettings.defaults().copyWith(
        enabled: true,
        city: 'Casablanca',
        country: 'Morocco',
        rules: {
          ...PrayerSettings.defaults().rules,
          PrayerName.maghrib: const PrayerRule(
            enabled: false,
            iqamahDelayMinutes: 9,
            silenceDurationMinutes: 25,
          ),
        },
      );

      final restored = PrayerSettings.fromJsonString(settings.toJsonString());

      expect(restored.enabled, isTrue);
      expect(restored.city, 'Casablanca');
      expect(restored.country, 'Morocco');
      expect(restored.ruleFor(PrayerName.maghrib).enabled, isFalse);
      expect(restored.ruleFor(PrayerName.maghrib).iqamahDelayMinutes, 9);
      expect(restored.ruleFor(PrayerName.maghrib).silenceDurationMinutes, 25);
      expect(restored.ruleFor(PrayerName.fajr).iqamahDelayMinutes, 20);
    });
  });

  group('AlAdhan parsing', () {
    test('converts calendar timings into local DateTime values', () {
      final times = PrayerService.parseCalendarResponse({
        'data': [
          {
            'date': {
              'gregorian': {'date': '01-01-2026'},
            },
            'timings': {
              'Fajr': '05:30 (CET)',
              'Dhuhr': '12:45',
              'Asr': '15:10',
              'Maghrib': '17:30',
              'Isha': '19:00',
            },
          },
        ],
      });

      expect(times, hasLength(5));
      expect(times.first.prayer, PrayerName.fajr);
      expect(times.first.adhan, DateTime(2026, 1, 1, 5, 30));
      expect(
        times.firstWhere((time) => time.prayer == PrayerName.isha).adhan,
        DateTime(2026, 1, 1, 19, 0),
      );
    });
  });

  group('Prayer occurrences', () {    test('silence starts after iqamah and lasts the configured duration', () {
      final settings = PrayerSettings.defaults().copyWith(
        enabled: true,
        city: 'Casablanca',
        country: 'Morocco',
      );
      final adhan = DateTime(2026, 1, 1, 5, 0);
      final cache = PrayerCache(
        source: settings.sourceKey,
        fetchedAt: adhan,
        times: [
          PrayerTime(prayer: PrayerName.fajr, adhan: adhan),
        ],
      );

      final occurrence = occurrenceFor(
        cache.times.single,
        settings.ruleFor(PrayerName.fajr),
      );

      expect(
        occurrence.silenceStart,
        adhan.add(const Duration(minutes: 20)),
      );
      expect(
        occurrence.silenceEnd,
        adhan.add(const Duration(minutes: 40)),
      );
      expect(
        nextOccurrence(settings, cache, adhan)?.prayer,
        PrayerName.fajr,
      );
      expect(
        currentOccurrence(
          settings,
          cache,
          adhan.add(const Duration(minutes: 25)),
        )?.prayer,
        PrayerName.fajr,
      );
    });

    test('disabled prayers are skipped', () {
      final settings = PrayerSettings.defaults().copyWith(
        enabled: true,
        city: 'Casablanca',
        country: 'Morocco',
        rules: {
          ...PrayerSettings.defaults().rules,
          PrayerName.fajr: PrayerRule.defaultsFor(PrayerName.fajr)
              .copyWith(enabled: false),
        },
      );
      final adhan = DateTime(2026, 1, 1, 5, 0);
      final cache = PrayerCache(
        source: settings.sourceKey,
        fetchedAt: adhan,
        times: [
          PrayerTime(prayer: PrayerName.fajr, adhan: adhan),
        ],
      );

      expect(nextOccurrence(settings, cache, adhan), isNull);
      expect(currentOccurrence(settings, cache, adhan), isNull);
    });
  });
}
