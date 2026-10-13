import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_sync.dart';
import 'customer_fixtures.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  test(
    'secure customer envelope survives restart and another payload cannot overwrite it',
    () async {
      const first = PendingFinancialCommands();
      await first.save('owner', 'shop', createCustomerCommand());
      final restored = await const PendingFinancialCommands().read(
        'owner',
        'shop',
      );
      expect(restored!.body, createCustomerCommand().body);
      final p = createCustomerPayload()..['display_name'] = 'اسم آخر';
      expect(
        () => first.save(
          'owner',
          'shop',
          PendingFinancialCommand(
            key: commandKey,
            kind: 'customer_create',
            body: {'p_idempotency_key': commandKey, 'p_payload': p},
          ),
        ),
        throwsStateError,
      );
      expect((await first.read('owner', 'shop'))!.body, restored.body);
      expect(await first.read('other', 'shop'), isNull);
      await first.clear('owner', 'shop', 'wrong-key');
      expect(await first.read('owner', 'shop'), isNotNull);
    },
  );
  test(
    'customer revision alone invalidates customer routes and survives catch-up',
    () {
      const before = ShopSyncSnapshot(
        shopId: 'shop',
        revision: 1,
        customerRevision: 1,
      );
      const next = ShopSyncSnapshot(
        shopId: 'shop',
        revision: 2,
        customerRevision: 2,
      );
      expect(next.changedFrom(before), {ShopSyncScope.customer});
      expect(next.asCatchUp().customerRevision, 2);
      expect(next.asCatchUp().forceRefresh, isTrue);
    },
  );
}
