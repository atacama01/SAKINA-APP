import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/preset_model.dart';
import '../providers/timer_provider.dart';
import '../services/silent_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  int _tilePresetMinutes = 30;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTilePreset();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycle) {
    if (lifecycle == AppLifecycleState.resumed) {
      // Full sync every time app comes to foreground.
      // This catches: tile started, tile stopped, tile replaced timer.
      ref.read(timerProvider.notifier).syncState();
      _loadTilePreset();
    }
  }

  Future<void> _loadTilePreset() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _tilePresetMinutes = prefs.getInt('tile_preset_minutes') ?? 30;
      });
    }
  }

  Future<void> _saveTilePreset(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('tile_preset_minutes', minutes);
    if (mounted) setState(() => _tilePresetMinutes = minutes);
  }

  Future<void> _startTimer(int minutes) async {
    final hasPerm = await SilentService.hasDndPermission();
    if (!mounted) return;
    if (!hasPerm) {
      _showDndDialog();
      return;
    }
    await ref.read(timerProvider.notifier).start(minutes);
  }

  Future<void> _stopTimer() async {
    if (_stopping) return;
    if (mounted) setState(() => _stopping = true);
    await ref.read(timerProvider.notifier).stop();
    if (mounted) setState(() => _stopping = false);
  }

  void _showDndDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'Silent Timer needs Do Not Disturb access.\n\n'
          'Tap "Open Settings", find Silent Timer, and enable it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await SilentService.openDndSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _showTilePresetSheet() {
    int temp = _tilePresetMinutes;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(children: [
                Icon(Icons.tune, size: 20),
                SizedBox(width: 8),
                Text('Tile Preset',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 8),
              Text(
                'The QS tile will silence your phone for this duration instantly.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 20),
              Center(
                child: Text(
                  _formatDuration(temp),
                  style: const TextStyle(
                      fontSize: 48, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [15, 20, 30, 40, 45, 60, 90, 120].map((m) {
                  return ChoiceChip(
                    label: Text(_formatDuration(m)),
                    selected: temp == m,
                    onSelected: (_) => setSheet(() => temp = m),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton.filledTonal(
                    onPressed:
                        temp > 5 ? () => setSheet(() => temp -= 5) : null,
                    icon: const Icon(Icons.remove),
                  ),
                  const SizedBox(width: 12),
                  Text('±5 min',
                      style: TextStyle(color: Colors.grey[600])),
                  const SizedBox(width: 12),
                  IconButton.filledTonal(
                    onPressed:
                        temp < 480 ? () => setSheet(() => temp += 5) : null,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _saveTilePreset(temp);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                        'Tile preset set to ${_formatDuration(temp)}'),
                    behavior: SnackBarBehavior.floating,
                  ));
                },
                style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52)),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCustomTimer() {
    int hours = 0;
    int minutes = 30;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Custom Timer',
                style:
                    TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _TimeSpinner(
                    label: 'Hours',
                    max: 23,
                    onChanged: (v) => hours = v),
                const SizedBox(width: 32),
                _TimeSpinner(
                    label: 'Minutes',
                    max: 59,
                    initial: 30,
                    onChanged: (v) => minutes = v),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                final total = hours * 60 + minutes;
                if (total > 0) _startTimer(total);
              },
              icon: const Icon(Icons.timer),
              label: const Text('Start'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52)),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  String _formatSeconds(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final timerState = ref.watch(timerProvider);
    final isRunning = timerState.status == TimerStatus.running;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Silent Timer',
            style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Tile preset',
            icon: const Icon(Icons.tune),
            onPressed: _showTilePresetSheet,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          children: [

            // ── Banner ───────────────────────────────────────────
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: isRunning
                  ? _ActiveBanner(
                      key: const ValueKey('active'),
                      timeStr: _formatSeconds(timerState.remainingSeconds),
                      stopping: _stopping,
                      onStop: _stopTimer,
                      onAdd: (m) =>
                          ref.read(timerProvider.notifier).addMinutes(m),
                      colors: colors,
                    )
                  : _IdleBanner(
                      key: const ValueKey('idle'),
                      text:
                          'Tile preset: ${_formatDuration(_tilePresetMinutes)} — tap ⚙ to change',
                      colors: colors,
                    ),
            ),

            const SizedBox(height: 24),

            Text('Quick Presets',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: PresetModel.defaults
                  .map((p) =>
                      _PresetCard(preset: p, onTap: () => _startTimer(p.minutes)))
                  .toList(),
            ),

            const SizedBox(height: 24),

            Text('Quick Durations',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [15, 30, 60, 120].map((min) {
                return FilledButton.tonal(
                  onPressed: () => _startTimer(min),
                  child: Text(min < 60 ? '$min min' : '${min ~/ 60}h'),
                );
              }).toList(),
            ),

            const SizedBox(height: 32),

            FilledButton.icon(
              onPressed: _showCustomTimer,
              icon: const Icon(Icons.timer),
              label: const Text('Custom Timer'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Widgets ─────────────────────────────────────────────────────────

class _ActiveBanner extends StatelessWidget {
  final String timeStr;
  final bool stopping;
  final VoidCallback onStop;
  final ValueChanged<int> onAdd;
  final ColorScheme colors;

  const _ActiveBanner({
    super.key,
    required this.timeStr,
    required this.stopping,
    required this.onStop,
    required this.onAdd,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.volume_off,
                  size: 18, color: colors.onErrorContainer),
              const SizedBox(width: 8),
              Text('Phone is silenced',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colors.onErrorContainer)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            timeStr,
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.bold,
              color: colors.onErrorContainer,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          Text('remaining',
              style: TextStyle(
                  fontSize: 12,
                  color: colors.onErrorContainer.withOpacity(0.7))),
          const SizedBox(height: 12),
          Row(
            children: [
              ...[5, 10, 15].map((m) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: OutlinedButton(
                      onPressed: () => onAdd(m),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.onErrorContainer,
                        side: BorderSide(
                            color:
                                colors.onErrorContainer.withOpacity(0.4)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text('+${m}m',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  )),
              const Spacer(),
              FilledButton(
                onPressed: stopping ? null : onStop,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: stopping
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Stop'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IdleBanner extends StatelessWidget {
  final String text;
  final ColorScheme colors;

  const _IdleBanner(
      {super.key, required this.text, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.title_outlined,
              color: colors.onSecondaryContainer, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    color: colors.onSecondaryContainer, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _PresetCard extends StatelessWidget {
  final PresetModel preset;
  final VoidCallback onTap;

  const _PresetCard({required this.preset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final h = preset.minutes ~/ 60;
    final m = preset.minutes % 60;
    final label = h > 0 ? (m > 0 ? '${h}h ${m}m' : '${h}h') : '${m}m';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: colors.primaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(preset.icon, style: const TextStyle(fontSize: 24)),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(preset.name,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colors.onPrimaryContainer)),
                Text(label,
                    style: TextStyle(
                        fontSize: 12, color: colors.onPrimaryContainer)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeSpinner extends StatefulWidget {
  final String label;
  final int max;
  final int initial;
  final ValueChanged<int> onChanged;

  const _TimeSpinner({
    required this.label,
    required this.max,
    this.initial = 0,
    required this.onChanged,
  });

  @override
  State<_TimeSpinner> createState() => _TimeSpinnerState();
}

class _TimeSpinnerState extends State<_TimeSpinner> {
  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(widget.label,
            style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton.filled(
              onPressed: _value > 0
                  ? () {
                      setState(() => _value--);
                      widget.onChanged(_value);
                    }
                  : null,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 48,
              child: Text(
                _value.toString().padLeft(2, '0'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton.filled(
              onPressed: _value < widget.max
                  ? () {
                      setState(() => _value++);
                      widget.onChanged(_value);
                    }
                  : null,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}