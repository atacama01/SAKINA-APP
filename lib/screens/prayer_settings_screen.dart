import 'dart:async';

import 'package:flutter/material.dart';

import '../models/prayer_settings.dart';
import '../models/prayer_time.dart';
import '../services/notification_service.dart';
import '../services/prayer_service.dart';
import '../services/silent_service.dart';

class PrayerSettingsScreen extends StatefulWidget {
  const PrayerSettingsScreen({super.key});

  @override
  State<PrayerSettingsScreen> createState() => _PrayerSettingsScreenState();
}

class _PrayerSettingsScreenState extends State<PrayerSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cityController = TextEditingController();
  final _countryController = TextEditingController();

  PrayerSettings _settings = PrayerSettings.defaults();
  PrayerCache? _cache;
  bool _loading = true;
  bool _saving = false;
  bool _locating = false;
  bool _exactAlarmsAllowed = true;
  String? _error;
  String? _warning;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _cityController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final settings = await PrayerService.loadSettings();
    final cache = await PrayerService.loadCache();
    final exactAlarms = await SilentService.canScheduleExactAlarms();

    if (!mounted) return;
    _cityController.text = settings.city;
    _countryController.text = settings.country;
    setState(() {
      _settings = settings;
      _cache = cache;
      _exactAlarmsAllowed = exactAlarms;
      _loading = false;
    });
  }

  PrayerSettings get _editedSettings {
    return _settings.copyWith(
      city: _cityController.text.trim(),
      country: _countryController.text.trim(),
    );
  }

  List<PrayerOccurrence> get _todayPreview {
    final cache = _cache;
    if (cache == null) return const [];
    return occurrencesForDate(
      _editedSettings,
      cache,
      DateTime.now(),
    );
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });

    try {
      final position = await PrayerLocationService.getCurrentLocation();
      if (!mounted) return;
      setState(() {
        _settings = _settings.copyWith(
          locationMode: PrayerLocationMode.coordinates,
          latitude: position.latitude,
          longitude: position.longitude,
        );
        _locating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Location captured. Tap Save & refresh to update times.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on LocationException catch (e) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _locating = false;
        _error = 'Could not get your location. You can use manual city instead.';
      });
    }
  }

  Future<void> _saveAndRefresh() async {
    final valid = _formKey.currentState?.validate() ?? true;
    if (!valid) return;

    final settings = _editedSettings;
    if (settings.enabled && !settings.isConfigured) {
      setState(() {
        _error = settings.locationMode == PrayerLocationMode.city
            ? 'Enter a city and country, or use your current location.'
            : 'Use your current location before enabling prayer mode.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
      _warning = null;
    });

    if (settings.enabled) {
      await NotificationService.requestPermission();
    }

    final result = await PrayerService.sync(settings, forceRefresh: true);
    if (!mounted) return;

    setState(() {
      _settings = result.settings;
      _cache = result.cache ?? _cache;
      _saving = false;
      _error = result.error;
      _warning = result.warning;
    });

    if (result.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.refreshed
                ? 'Prayer times updated and schedule refreshed.'
                : 'Prayer settings saved.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _testSilence() async {
    final hasDnd = await SilentService.hasDndPermission();
    if (!mounted) return;
    if (!hasDnd) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enable Do Not Disturb access first.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await NotificationService.requestPermission();
    final started = await SilentService.testPrayerSilence();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          started
              ? 'Test started — your phone will be silent for 10 seconds.'
              : 'Could not start the test. Check DND access.',
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _allowExactAlarms() async {
    await SilentService.openExactAlarmSettings();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final allowed = await SilentService.canScheduleExactAlarms();
    if (mounted) setState(() => _exactAlarmsAllowed = allowed);
  }

  String _time(BuildContext context, DateTime dateTime) {
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(dateTime),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Prayer Mode',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  children: [
                    _buildIntroCard(colors),
                    const SizedBox(height: 16),

                    if (!_exactAlarmsAllowed) ...[
                      _buildExactAlarmBanner(colors),
                      const SizedBox(height: 12),
                    ],

                    if (_error != null) ...[
                      _MessageCard(
                        message: _error!,
                        icon: Icons.error_outline,
                        color: colors.errorContainer,
                        foreground: colors.onErrorContainer,
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (_warning != null) ...[
                      _MessageCard(
                        message: _warning!,
                        icon: Icons.info_outline,
                        color: colors.secondaryContainer,
                        foreground: colors.onSecondaryContainer,
                      ),
                      const SizedBox(height: 12),
                    ],

                    Card(
                      child: SwitchListTile(
                        title: const Text(
                          'Automatic prayer silence',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: const Text(
                          'Silence your phone after iqamah for the prayers '
                          'you select below.',
                        ),
                        value: _settings.enabled,
                        onChanged: (value) {
                          setState(() {
                            _settings = _settings.copyWith(enabled: value);
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    _sectionTitle(context, 'Location'),
                    const SizedBox(height: 8),
                    SegmentedButton<PrayerLocationMode>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: PrayerLocationMode.city,
                          label: Text('City'),
                          icon: Icon(Icons.location_city),
                        ),
                        ButtonSegment(
                          value: PrayerLocationMode.coordinates,
                          label: Text('My location'),
                          icon: Icon(Icons.my_location),
                        ),
                      ],
                      selected: {_settings.locationMode},
                      onSelectionChanged: (selection) {
                        setState(() {
                          _settings = _settings.copyWith(
                            locationMode: selection.first,
                          );
                        });
                      },
                    ),
                    const SizedBox(height: 12),

                    if (_settings.locationMode == PrayerLocationMode.city) ...[
                      TextFormField(
                        controller: _cityController,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'City',
                          hintText: 'e.g. Casablanca',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.location_city),
                        ),
                        validator: (value) {
                          if (!_settings.enabled) return null;
                          if (value == null || value.trim().isEmpty) {
                            return 'Enter your city';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _countryController,
                        textInputAction: TextInputAction.done,
                        decoration: const InputDecoration(
                          labelText: 'Country',
                          hintText: 'e.g. Morocco',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.public),
                        ),
                        validator: (value) {
                          if (!_settings.enabled) return null;
                          if (value == null || value.trim().isEmpty) {
                            return 'Enter your country';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tip: choose the city you are actually in so the '
                        'times match your phone timezone.',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ] else ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _settings.latitude == null
                                    ? 'No location captured yet'
                                    : 'Lat ${_settings.latitude!.toStringAsFixed(4)}, '
                                        'Lon ${_settings.longitude!.toStringAsFixed(4)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Your coordinates are saved on this device and '
                                'sent to AlAdhan only when fetching prayer times.',
                                style: TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 12),
                              FilledButton.tonalIcon(
                                onPressed: _locating ? null : _useCurrentLocation,
                                icon: _locating
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : const Icon(Icons.my_location),
                                label: Text(
                                  _locating
                                      ? 'Getting location…'
                                      : 'Use my current location',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),
                    _sectionTitle(context, 'Calculation'),
                    const SizedBox(height: 8),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Calculation method',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calculate_outlined),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: _settings.method,
                          items: [
                            ...prayerCalculationMethods.map(
                              (method) => DropdownMenuItem(
                                value: method.id,
                                child: Text(method.name),
                              ),
                            ),
                            if (!prayerCalculationMethods
                                .any((m) => m.id == _settings.method))
                              DropdownMenuItem(
                                value: _settings.method,
                                child: Text('Method ${_settings.method}'),
                              ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _settings = _settings.copyWith(method: value);
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Asr calculation',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.schedule),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          isExpanded: true,
                          value: _settings.school,
                          items: const [
                            DropdownMenuItem(
                              value: 0,
                              child: Text('Standard (Shafi, Maliki, Hanbali)'),
                            ),
                            DropdownMenuItem(
                              value: 1,
                              child: Text('Hanafi'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _settings = _settings.copyWith(school: value);
                            });
                          },
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    _sectionTitle(context, 'Prayer window'),
                    const SizedBox(height: 4),
                    Text(
                      'The iqamah delay is added to the adhan time. The phone '
                      'then stays silent for the duration you choose.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 10),

                    for (final prayer in PrayerName.values) ...[
                      _PrayerRuleCard(
                        prayer: prayer,
                        rule: _settings.ruleFor(prayer),
                        onChanged: (rule) {
                          setState(() {
                            _settings = _settings.copyWith(
                              rules: {
                                ..._settings.rules,
                                prayer: rule,
                              },
                            );
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                    ],

                    const SizedBox(height: 10),
                    _buildTodayPreview(context, colors),

                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _saving ? null : _saveAndRefresh,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _saving ? 'Saving & fetching…' : 'Save & refresh',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _testSilence,
                      icon: const Icon(Icons.timer_outlined),
                      label: const Text('Test auto-silence for 10 seconds'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Prayer times are provided by the free AlAdhan API. '
                      'No account or API key is required. Only your city or '
                      'coordinates are sent when refreshing. Times are cached '
                      'on this device and work offline afterward.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w600),
    );
  }

  Widget _buildIntroCard(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.mosque, color: colors.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Sakina can silence your phone at iqamah automatically. '
              'Set each prayer exactly how you want it.',
              style: TextStyle(
                color: colors.onPrimaryContainer,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExactAlarmBanner(ColorScheme colors) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.alarm, color: colors.onSecondaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Exact alarms are disabled. Prayer silencing may be delayed.',
              style: TextStyle(
                fontSize: 12,
                color: colors.onSecondaryContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: _allowExactAlarms,
            child: const Text('Allow'),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayPreview(BuildContext context, ColorScheme colors) {
    final occurrences = _todayPreview;
    final cache = _cache;
    final cacheMatches =
        cache != null && cache.source == _editedSettings.sourceKey;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.today, size: 18, color: colors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Today',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (occurrences.isEmpty)
              Text(
                'No saved prayer times for today. Save & refresh to fetch them.',
                style: TextStyle(
                  fontSize: 12,
                  color: colors.onSurfaceVariant,
                ),
              )
            else ...[
              for (final occurrence in occurrences)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(
                          occurrence.prayer.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        _time(context, occurrence.adhan),
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward, size: 12),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _settings.ruleFor(occurrence.prayer).enabled
                              ? 'silent ${_time(context, occurrence.silenceStart)}'
                                  '–${_time(context, occurrence.silenceEnd)}'
                              : 'disabled',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!cacheMatches)
                Text(
                  'These are saved times from a previous location or method. '
                  'Save & refresh to update them.',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.error,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color color;
  final Color foreground;

  const _MessageCard({
    required this.message,
    required this.icon,
    required this.color,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

class _PrayerRuleCard extends StatelessWidget {
  final PrayerName prayer;
  final PrayerRule rule;
  final ValueChanged<PrayerRule> onChanged;

  const _PrayerRuleCard({
    required this.prayer,
    required this.rule,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                prayer.label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Switch(
                value: rule.enabled,
                onChanged: (value) => onChanged(
                  rule.copyWith(enabled: value),
                ),
              ),
            ],
          ),
          if (rule.enabled) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Silence starts after adhan',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                _MinuteStepper(
                  value: rule.iqamahDelayMinutes,
                  min: 0,
                  max: 120,
                  onChanged: (value) => onChanged(
                    rule.copyWith(iqamahDelayMinutes: value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Silence duration',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                _MinuteStepper(
                  value: rule.silenceDurationMinutes,
                  min: 1,
                  max: 180,
                  onChanged: (value) => onChanged(
                    rule.copyWith(silenceDurationMinutes: value),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _MinuteStepper extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _MinuteStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: value > min ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_circle_outline, size: 20),
        ),
        SizedBox(
          width: 58,
          child: Text(
            '$value min',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFeatures: [FontFeature.tabularFigures()],
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: value < max ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_circle_outline, size: 20),
        ),
      ],
    );
  }
}
