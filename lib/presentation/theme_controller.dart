import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme is locked to light for now (dark UI deferred).
class ThemeController extends ChangeNotifier {
  static const _kMode = 'theme_mode';

  ThemeMode mode = ThemeMode.light;
  bool ready = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    // Force light; clear any previously saved dark/system preference.
    await prefs.setString(_kMode, 'light');
    mode = ThemeMode.light;
    ready = true;
    notifyListeners();
  }

  bool isDark(BuildContext context) => false;

  Future<void> toggle(BuildContext context) async {
    await setMode(ThemeMode.light);
  }

  Future<void> setMode(ThemeMode next) async {
    mode = ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kMode, 'light');
  }
}
