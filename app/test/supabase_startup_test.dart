import 'package:eldafttar/src/config/supabase_public_config.dart';
import 'package:eldafttar/src/config/supabase_startup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not initialize when either public value is absent', () async {
    final calls = <List<String>>[];

    Future<void> start(String url, String publishableKey) async {
      calls.add([url, publishableKey]);
    }

    expect(
      await prepareSupabase(
        const SupabasePublicConfig(url: '', publishableKey: ''),
        start,
      ),
      SupabaseStartupStatus.missingConfiguration,
    );
    expect(
      await prepareSupabase(
        const SupabasePublicConfig(
          url: 'https://example.supabase.co',
          publishableKey: ' ',
        ),
        start,
      ),
      SupabaseStartupStatus.missingConfiguration,
    );
    expect(
      await prepareSupabase(
        const SupabasePublicConfig(url: ' ', publishableKey: 'public-key'),
        start,
      ),
      SupabaseStartupStatus.missingConfiguration,
    );
    expect(calls, isEmpty);
  });

  test('initializes once with both trimmed public values', () async {
    final calls = <List<String>>[];

    final status = await prepareSupabase(
      const SupabasePublicConfig(
        url: ' https://example.supabase.co ',
        publishableKey: ' public-key ',
      ),
      (url, publishableKey) async {
        calls.add([url, publishableKey]);
      },
    );

    expect(status, SupabaseStartupStatus.ready);
    expect(calls, [
      ['https://example.supabase.co', 'public-key'],
    ]);
  });

  test('reports failure without exposing the initializer error', () async {
    final status = await prepareSupabase(
      const SupabasePublicConfig(
        url: 'https://example.supabase.co',
        publishableKey: 'public-key',
      ),
      (url, publishableKey) async {
        throw StateError('secret $publishableKey');
      },
    );

    expect(status, SupabaseStartupStatus.failed);
  });
}
