import 'dart:convert';

import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const userId = 'd1111111-1111-4111-8111-111111111111';
const shopId = 'd1222222-2222-4222-8222-222222222222';
const key = 'd3000000-0000-4000-8000-000000000202';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('a debt command round-trips and a changed body is rejected', () async {
    const store = PendingFinancialCommands();
    const command = PendingFinancialCommand(
      key: key,
      kind: 'debt_declare',
      body: {
        'p_idempotency_key': key,
        'p_payload': {
          'version': 1,
          'kind': 'debt_declare',
          'direction': 'shop_owes',
          'unit': 'money',
          'karat': null,
          'amount': '1500',
          'party_name': 'طرف',
          'contact_phone': '',
          'reason': 'سبب تاريخي',
          'external_reference': null,
        },
      },
    );
    await store.save(userId, shopId, command);
    final read = await store.read(userId, shopId);
    expect(read?.kind, 'debt_declare');
    expect(read?.body, command.body);

    final storage = const FlutterSecureStorage();
    await storage.write(
      key: 'pending_financial_${userId}_$shopId',
      value: jsonEncode({
        'key': key,
        'kind': 'debt_declare',
        'body': {
          'p_idempotency_key': key,
          'p_payload': {'version': 1, 'kind': 'debt_declare'},
        },
      }),
    );
    expect(
      PendingFinancialCommands(storage: storage).read(userId, shopId),
      throwsFormatException,
    );
  });
}
