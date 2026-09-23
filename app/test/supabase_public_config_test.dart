import 'package:eldafttar/src/config/supabase_public_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('both public values are required', () {
    expect(
      const SupabasePublicConfig(url: '', publishableKey: '').isComplete,
      isFalse,
    );
    expect(
      const SupabasePublicConfig(
        url: 'https://example.supabase.co',
        publishableKey: '',
      ).isComplete,
      isFalse,
    );
    expect(
      const SupabasePublicConfig(
        url: '',
        publishableKey: 'public-key',
      ).isComplete,
      isFalse,
    );
    expect(
      const SupabasePublicConfig(url: '   ', publishableKey: '   ').isComplete,
      isFalse,
    );
    expect(
      const SupabasePublicConfig(
        url: ' https://example.supabase.co ',
        publishableKey: ' public-key ',
      ).isComplete,
      isTrue,
    );
  });

  test('values are trimmed before use', () {
    const config = SupabasePublicConfig(
      url: ' https://example.supabase.co ',
      publishableKey: ' public-key ',
    );

    expect(config.trimmedUrl, 'https://example.supabase.co');
    expect(config.trimmedPublishableKey, 'public-key');
  });
}
