import 'dart:convert';

import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'purchase cash settlement posts its target and exact piastres',
    () async {
      const purchase = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
      const key = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
      final gateway = HttpOpeningGateway(
        client: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/settle_purchase_cash_payable');
          expect(jsonDecode(request.body), {
            'p_idempotency_key': key,
            'p_purchase_operation_id': purchase,
            'p_tenders': [
              {'method': 'cash', 'piastres': '2000000'},
            ],
          });
          return http.Response(
            jsonEncode({
              'ok': true,
              'operation_id': 'dddddddd-dddd-4ddd-8ddd-dddddddddddd',
              'replayed': false,
              'remaining_piastres': '2000000',
            }),
            200,
          );
        }),
        supabaseUrl: 'https://example.test',
        publishableKey: 'test',
        accessToken: () => 'token',
        currentUserId: () => 'owner-a',
      );
      final result = await gateway.settlePurchaseCash(
        callerUserId: 'owner-a',
        idempotencyKey: key,
        purchaseOperationId: purchase,
        tenders: [
          {'method': 'cash', 'piastres': '2000000'},
        ],
      );
      expect(result, isA<FinancialCommitted>());
    },
  );
}
