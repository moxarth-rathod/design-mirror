/// DesignMirror AI — Preferences Service
///
/// Persists user-facing settings (theme mode, dimension unit) to
/// SharedPreferences so they survive app restarts.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/units.dart';

class PreferencesService {
  static const _keyThemeMode = 'theme_mode';
  static const _keyDimensionUnit = 'dimension_unit';

  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final themeIndex = prefs.getInt(_keyThemeMode);
    if (themeIndex != null && themeIndex < ThemeMode.values.length) {
      themeMode.value = ThemeMode.values[themeIndex];
    }

    final unitIndex = prefs.getInt(_keyDimensionUnit);
    if (unitIndex != null && unitIndex < DimensionUnit.values.length) {
      DimensionFormatter.currentUnit.value = DimensionUnit.values[unitIndex];
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyThemeMode, mode.index);
  }

  Future<void> setDimensionUnit(DimensionUnit unit) async {
    DimensionFormatter.currentUnit.value = unit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyDimensionUnit, unit.index);
  }
}
