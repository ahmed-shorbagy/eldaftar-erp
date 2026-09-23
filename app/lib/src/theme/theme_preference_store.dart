import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ThemePreferenceStore {
  Future<String?> read();

  Future<void> write(String value);
}

class SharedPreferencesThemeStore implements ThemePreferenceStore {
  SharedPreferencesThemeStore(this._preferences);

  static const storageKey = 'theme_mode';

  final SharedPreferences _preferences;

  @override
  Future<String?> read() async => _preferences.getString(storageKey);

  @override
  Future<void> write(String value) => _preferences.setString(storageKey, value);
}
