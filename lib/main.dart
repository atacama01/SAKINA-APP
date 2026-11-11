import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/theme_provider.dart';
import 'providers/timer_provider.dart';
import 'screens/home_screen.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final initialTheme =
      themeModeFromName(prefs.getString(themeModePreferenceKey));
  runApp(
    ProviderScope(
      overrides: [
        themeModeProvider
            .overrideWith((ref) => ThemeModeNotifier(initialTheme)),
      ],
      child: const SilentTimerApp(),
    ),
  );
}

class SilentTimerApp extends ConsumerWidget {
  const SilentTimerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'Silent Timer',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A6FA5),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A6FA5),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AppEntry(),
    );
  }
}

class AppEntry extends ConsumerStatefulWidget {
  const AppEntry({super.key});

  @override
  ConsumerState<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends ConsumerState<AppEntry> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await ref.read(timerProvider.notifier).resumeIfActive();
    if (mounted) setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }
    return const HomeScreen();
  }
}