import 'package:eldafttar/src/features/onboarding/data/shared_preferences_onboarding_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('skipped guide resumes its step after store recreation', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final first = SharedPreferencesOnboardingStore(preferences);
    expect(await first.isComplete('auth_signin'), isFalse);
    await first.saveStep('auth_signin', 2);

    final reopened = SharedPreferencesOnboardingStore(
      await SharedPreferences.getInstance(),
    );
    expect(await reopened.readStep('auth_signin'), 2);
    expect(await reopened.readStep('auth_signup'), 0);
    expect(await reopened.isComplete('auth_signin'), isFalse);
    await reopened.markComplete('auth_signin');
    expect(await first.isComplete('auth_signin'), isTrue);
    expect(await first.isComplete('auth_signup'), isFalse);
  });
}
