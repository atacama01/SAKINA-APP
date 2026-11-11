import 'dart:convert';

enum PrayerName { fajr, dhuhr, asr, maghrib, isha }

extension PrayerNameInfo on PrayerName {
  String get key => name;

  String get apiKey => switch (this) {
        PrayerName.fajr => 'Fajr',
        PrayerName.dhuhr => 'Dhuhr',
        PrayerName.asr => 'Asr',
        PrayerName.maghrib => 'Maghrib',
        PrayerName.isha => 'Isha',
      };

  String get label => switch (this) {
        PrayerName.fajr => 'Fajr',
        PrayerName.dhuhr => 'Dhuhr',
        PrayerName.asr => 'Asr',
        PrayerName.maghrib => 'Maghrib',
        PrayerName.isha => 'Isha',
      };
}

PrayerName? prayerNameFromKey(String? key) {
  for (final prayer in PrayerName.values) {
    if (prayer.key == key) return prayer;
  }
  return null;
}

enum PrayerLocationMode { city, coordinates }

class PrayerRule {
  final bool enabled;
  final int iqamahDelayMinutes;
  final int silenceDurationMinutes;

  const PrayerRule({
    this.enabled = true,
    required this.iqamahDelayMinutes,
    required this.silenceDurationMinutes,
  });

  static PrayerRule defaultsFor(PrayerName prayer) {
    final delay = switch (prayer) {
      PrayerName.fajr => 20,
      PrayerName.dhuhr => 15,
      PrayerName.asr => 15,
      PrayerName.maghrib => 7,
      PrayerName.isha => 15,
    };
    return PrayerRule(
      iqamahDelayMinutes: delay,
      silenceDurationMinutes: 20,
    );
  }

  PrayerRule copyWith({
    bool? enabled,
    int? iqamahDelayMinutes,
    int? silenceDurationMinutes,
  }) {
    return PrayerRule(
      enabled: enabled ?? this.enabled,
      iqamahDelayMinutes:
          iqamahDelayMinutes ?? this.iqamahDelayMinutes,
      silenceDurationMinutes:
          silenceDurationMinutes ?? this.silenceDurationMinutes,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'delay': iqamahDelayMinutes,
        'duration': silenceDurationMinutes,
      };

  factory PrayerRule.fromJson(Map<String, dynamic> json, PrayerName prayer) {
    final fallback = defaultsFor(prayer);
    return PrayerRule(
      enabled: json['enabled'] as bool? ?? fallback.enabled,
      iqamahDelayMinutes: (json['delay'] as num?)?.toInt() ??
          fallback.iqamahDelayMinutes,
      silenceDurationMinutes: (json['duration'] as num?)?.toInt() ??
          fallback.silenceDurationMinutes,
    );
  }
}

class PrayerSettings {
  final bool enabled;
  final PrayerLocationMode locationMode;
  final String city;
  final String country;
  final double? latitude;
  final double? longitude;
  final int method;
  final int school;
  final Map<PrayerName, PrayerRule> rules;

  const PrayerSettings({
    required this.enabled,
    required this.locationMode,
    required this.city,
    required this.country,
    required this.latitude,
    required this.longitude,
    required this.method,
    required this.school,
    required this.rules,
  });

  factory PrayerSettings.defaults() {
    return PrayerSettings(
      enabled: false,
      locationMode: PrayerLocationMode.city,
      city: '',
      country: '',
      latitude: null,
      longitude: null,
      method: 3,
      school: 0,
      rules: {
        for (final prayer in PrayerName.values)
          prayer: PrayerRule.defaultsFor(prayer),
      },
    );
  }

  bool get isConfigured {
    if (locationMode == PrayerLocationMode.city) {
      return city.trim().isNotEmpty && country.trim().isNotEmpty;
    }
    return latitude != null && longitude != null;
  }

  String get displayLocation {
    if (locationMode == PrayerLocationMode.coordinates) {
      return 'Current location';
    }
    final parts = [city.trim(), country.trim()]
        .where((part) => part.isNotEmpty)
        .toList();
    return parts.isEmpty ? 'No location set' : parts.join(', ');
  }

  String get sourceKey {
    final location = switch (locationMode) {
      PrayerLocationMode.city =>
        'city|${city.trim().toLowerCase()}|${country.trim().toLowerCase()}',
      PrayerLocationMode.coordinates =>
        'coords|${(latitude ?? 0).toStringAsFixed(3)}|'
            '${(longitude ?? 0).toStringAsFixed(3)}',
    };
    return '$location|$method|$school';
  }

  PrayerRule ruleFor(PrayerName prayer) {
    return rules[prayer] ?? PrayerRule.defaultsFor(prayer);
  }

  PrayerSettings copyWith({
    bool? enabled,
    PrayerLocationMode? locationMode,
    String? city,
    String? country,
    double? latitude,
    double? longitude,
    int? method,
    int? school,
    Map<PrayerName, PrayerRule>? rules,
  }) {
    return PrayerSettings(
      enabled: enabled ?? this.enabled,
      locationMode: locationMode ?? this.locationMode,
      city: city ?? this.city,
      country: country ?? this.country,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      method: method ?? this.method,
      school: school ?? this.school,
      rules: rules ?? this.rules,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'locationMode': locationMode.name,
        'city': city,
        'country': country,
        'latitude': latitude,
        'longitude': longitude,
        'method': method,
        'school': school,
        'rules': {
          for (final entry in rules.entries)
            entry.key.key: entry.value.toJson(),
        },
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

  String toJsonString() => jsonEncode(toJson());

  factory PrayerSettings.fromJson(Map<String, dynamic> json) {
    final fallback = PrayerSettings.defaults();
    final rulesJson = json['rules'];
    final rules = <PrayerName, PrayerRule>{};

    for (final prayer in PrayerName.values) {
      final raw = rulesJson is Map ? rulesJson[prayer.key] : null;
      rules[prayer] = raw is Map<String, dynamic>
          ? PrayerRule.fromJson(raw, prayer)
          : PrayerRule.defaultsFor(prayer);
    }

    final locationMode = PrayerLocationMode.values.firstWhere(
      (mode) => mode.name == json['locationMode'],
      orElse: () => fallback.locationMode,
    );

    return PrayerSettings(
      enabled: json['enabled'] as bool? ?? fallback.enabled,
      locationMode: locationMode,
      city: json['city'] as String? ?? fallback.city,
      country: json['country'] as String? ?? fallback.country,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      method: (json['method'] as num?)?.toInt() ?? fallback.method,
      school: (json['school'] as num?)?.toInt() ?? fallback.school,
      rules: rules,
    );
  }

  factory PrayerSettings.fromJsonString(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return PrayerSettings.fromJson(decoded);
    }
    return PrayerSettings.defaults();
  }
}

class PrayerCalculationMethod {
  final int id;
  final String name;

  const PrayerCalculationMethod(this.id, this.name);
}

const prayerCalculationMethods = <PrayerCalculationMethod>[
  PrayerCalculationMethod(3, 'Muslim World League (MWL)'),
  PrayerCalculationMethod(2, 'ISNA — North America'),
  PrayerCalculationMethod(4, 'Umm Al-Qura — Makkah'),
  PrayerCalculationMethod(5, 'Egyptian General Authority'),
  PrayerCalculationMethod(1, 'University of Karachi'),
  PrayerCalculationMethod(21, 'Morocco'),
  PrayerCalculationMethod(19, 'Algeria'),
  PrayerCalculationMethod(18, 'Tunisia'),
  PrayerCalculationMethod(13, 'Diyanet — Turkey'),
  PrayerCalculationMethod(20, 'KEMENAG — Indonesia'),
  PrayerCalculationMethod(17, 'JAKIM — Malaysia'),
  PrayerCalculationMethod(8, 'Gulf Region'),
  PrayerCalculationMethod(9, 'Kuwait'),
  PrayerCalculationMethod(10, 'Qatar'),
  PrayerCalculationMethod(16, 'Dubai'),
  PrayerCalculationMethod(23, 'Jordan'),
  PrayerCalculationMethod(12, 'France'),
  PrayerCalculationMethod(7, 'Tehran — Iran'),
  PrayerCalculationMethod(11, 'Singapore'),
  PrayerCalculationMethod(14, 'Russia'),
  PrayerCalculationMethod(15, 'Moonsighting Committee'),
  PrayerCalculationMethod(22, 'Lisbon'),
];
