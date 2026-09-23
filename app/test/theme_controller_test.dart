import 'package:eldafttar/src/theme/theme_controller.dart';
import 'package:eldafttar/src/theme/theme_preference_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryThemePreferenceStore implements ThemePreferenceStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

void main() {
  test('unknown or empty preference follows the system', () async {
    final store = MemoryThemePreferenceStore()..value = 'nope';
    final controller = ThemeController(store: store);

    await controller.load();

    expect(controller.mode, ThemeMode.system);
  });

  test('loads a persisted light or dark choice', () async {
    final store = MemoryThemePreferenceStore()..value = 'dark';
    final controller = ThemeController(store: store);

    await controller.load();
    expect(controller.mode, ThemeMode.dark);

    store.value = 'light';
    await controller.load();
    expect(controller.mode, ThemeMode.light);
  });

  test('toggle persists the opposite of the resolved brightness', () async {
    final store = MemoryThemePreferenceStore();
    final controller = ThemeController(store: store);

    await controller.toggle(Brightness.light);
    expect(controller.mode, ThemeMode.dark);
    expect(store.value, 'dark');

    await controller.toggle(Brightness.dark);
    expect(controller.mode, ThemeMode.light);
    expect(store.value, 'light');
  });
}
