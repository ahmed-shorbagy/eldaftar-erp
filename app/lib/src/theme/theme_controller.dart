import 'package:flutter/material.dart';

import 'theme_preference_store.dart';

class ThemeController extends ChangeNotifier {
  ThemeController({
    ThemePreferenceStore? store,
    ThemeMode initial = ThemeMode.system,
  }) : _store = store,
       _mode = initial;

  final ThemePreferenceStore? _store;
  ThemeMode _mode;

  ThemeMode get mode => _mode;

  Future<void> load() async {
    final stored = await _store?.read();
    _mode = _decode(stored);
    notifyListeners();
  }

  Future<void> toggle(Brightness resolvedBrightness) async {
    _mode = resolvedBrightness == Brightness.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    notifyListeners();
    await _store?.write(_mode.name);
  }

  static ThemeMode _decode(String? stored) {
    return switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}
