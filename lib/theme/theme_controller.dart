import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The admin's light/dark/system theme choice, saved on the device.
/// [IsdaSafeAdminApp] listens to it for `MaterialApp.themeMode`; Settings
/// writes it through [setThemeMode].
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final instance = ThemeController._();

  static const _prefsKey = 'theme_mode';

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  /// Restores the saved choice; call once at startup.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_prefsKey);
      final restored = ThemeMode.values
          .where((m) => m.name == stored)
          .firstOrNull;
      if (restored != null && restored != _themeMode) {
        _themeMode = restored;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('ThemeController: load error $e');
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, mode.name);
  }
}
