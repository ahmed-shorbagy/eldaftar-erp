import 'package:eldafttar/src/features/shop_accounts/data/supabase_shop_sync_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'cancelling one production watch leaves another Supabase channel subscribed',
    () async {
      final client = SupabaseClient(
        'http://127.0.0.1:9',
        'unit-test-publishable',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final gateway = SupabaseShopSyncGateway(client);
      final first = gateway
          .watch(
            shopId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            userId: 'owner',
          )
          .listen((_) {});
      final second = gateway
          .watch(
            shopId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
            userId: 'owner',
          )
          .listen((_) {});
      try {
        expect(client.getChannels(), hasLength(2));
        await first.cancel();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(client.getChannels(), hasLength(1));
        await second.cancel();
        await gateway.close();
        expect(client.getChannels(), isEmpty);
      } finally {
        await first.cancel();
        await second.cancel();
        await gateway.close();
        await client.dispose();
      }
    },
  );
}
