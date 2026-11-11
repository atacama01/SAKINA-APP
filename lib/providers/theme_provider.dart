import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const themeModePreferenceKey = 'theme_mode';

/// Reads a stored theme mode. Anything missing or unknown falls back to
/// following the system setting.
ThemeMode themeModeFromName(String? name) {
  return ThemeMode.values.firstWhere(
    (mode) => mode.name == name,
    orElse: () => ThemeMode.system,
  );
}

/// Cycles system → light → dark → system. The first tap therefore moves away
/// from the current system appearance only when the user asks for it.
ThemeMode nextThemeMode(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => ThemeMode.light,
    ThemeMode.light => ThemeMode.dark,
    ThemeMode.dark => ThemeMode.system,
  };
}

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier([super.initial = ThemeMode.system]);

  Future<void> cycle() async {
    final next = nextThemeMode(state);
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(themeModePreferenceKey, next.name);
    } catch (_) {
      // The theme still applies for this session if persistence fails.
    }
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});
