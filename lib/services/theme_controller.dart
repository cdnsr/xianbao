import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persisted day/night preference for the app.
///
/// Defaults to [ThemeMode.system] until the user taps the toggle in the
/// home drawer, after which the explicit choice wins.
class ThemeController extends ChangeNotifier {
  static const String _prefsKey = 'theme_mode_v1';

  ThemeMode _mode = ThemeMode.system;

  ThemeMode get mode => _mode;

  bool get isFollowingSystem => _mode == ThemeMode.system;

  /// Load the saved preference. Never throws; falls back to system.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _mode = _decode(prefs.getString(_prefsKey));
    } catch (_) {
      _mode = ThemeMode.system;
    }
    notifyListeners();
  }

  /// Flip to the opposite of [current] and persist the explicit choice.
  Future<void> toggle(Brightness current) {
    return setMode(
      current == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }

  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _encode(mode));
    } catch (_) {
      // Preference persistence must never break the UI.
    }
  }

  static ThemeMode _decode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
