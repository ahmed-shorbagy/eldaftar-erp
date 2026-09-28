import 'package:shared_preferences/shared_preferences.dart';

import '../application/onboarding_store.dart';

class SharedPreferencesOnboardingStore implements OnboardingStore {
  const SharedPreferencesOnboardingStore(this.preferences);

  final SharedPreferences preferences;

  static const _prefix = 'onboarding_v1_';

  @override
  Future<bool> isComplete(String path) async =>
      preferences.getBool('$_prefix${path}_complete') ?? false;

  @override
  Future<int> readStep(String path) async =>
      preferences.getInt('$_prefix${path}_step') ?? 0;

  @override
  Future<void> saveStep(String path, int step) async {
    await preferences.setInt('$_prefix${path}_step', step);
  }

  @override
  Future<void> markComplete(String path) async {
    await preferences.setBool('$_prefix${path}_complete', true);
  }
}
