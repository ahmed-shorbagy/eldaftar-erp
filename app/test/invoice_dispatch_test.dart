import 'dart:convert';

import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_operation_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _operation = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const _key = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

HttpOpeningGateway _gateway(MockClient client) => HttpOpeningGateway(
  client: client,
  supabaseUrl: 'https://example.test',
  publishableKey: 'publishable-key',
  accessToken: () => 'access-token',
  currentUserId: () => 'owner-a',
);

void main() {
  test(
    'Egyptian WhatsApp number is normalized without changing its digits',
    () {
      expect(whatsappPhone('01012345678'), '201012345678');
      expect(whatsappPhone('+201012345678'), '201012345678');
      expect(whatsappPhone('201012345678'), '201012345678');
      expect(whatsappPhone('01123'), isNull);
    },
  );

  test(
    'opening a handoff does not create a confirmed dispatch state',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/rest/v1/rpc/get_invoice_dispatch_state');
        expect(jsonDecode(request.body), {'p_operation_id': _operation});
        return http.Response(
          jsonEncode({'operation_id': _operation, 'status': 'unconfirmed'}),
          200,
        );
      });
      final state = await _gateway(
        client,
      ).dispatchState(callerUserId: 'owner-a', operationId: _operation);
      expect(state.ownerConfirmed, isFalse);
      expect(state.confirmedAt, isNull);
    },
  );

  test(
    'owner confirmation uses a scoped idempotency key and reads UTC time',
    () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/confirm_invoice_whatsapp_send')) {
          expect(jsonDecode(request.body), {
            'p_operation_id': _operation,
            'p_idempotency_key': _key,
          });
          return http.Response(
            jsonEncode({
              'ok': true,
              'operation_id': _operation,
              'replayed': false,
            }),
            200,
          );
        }
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'operation_id': _operation,
              'status': 'owner_confirmed',
              'confirmed_at': '2026-09-29T06:00:00+00:00',
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final gateway = _gateway(client);
      final result = await gateway.confirmWhatsappSend(
        callerUserId: 'owner-a',
        operationId: _operation,
        idempotencyKey: _key,
      );
      expect(result, isA<FinancialCommitted>());
      final state = await gateway.dispatchState(
        callerUserId: 'owner-a',
        operationId: _operation,
      );
      expect(state.ownerConfirmed, isTrue);
      expect(state.confirmedAt, DateTime.utc(2026, 9, 29, 6));
    },
  );
  test(
    'pending invoice page preserves the server cursor and operation identity',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/rest/v1/rpc/get_pending_invoice_sends');
        expect(jsonDecode(request.body), {'p_before_sequence': 80});
        return http.Response.bytes(
          utf8.encode(
            jsonEncode({
              'items': [
                {
                  'operation_id': _operation,
                  'kind': 'sale',
                  'shop_sequence': '79',
                  'occurred_at_cairo': '2026-09-29T09:00:00',
                  'customer_name': 'عميل تجريبي',
                },
              ],
              'next_before_sequence': 79,
            }),
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final page = await _gateway(
        client,
      ).pendingInvoiceSends(callerUserId: 'owner-a', beforeSequence: 80);
      expect(page.items.single.operationId, _operation);
      expect(page.items.single.customerName, 'عميل تجريبي');
      expect(page.nextBeforeSequence, 79);
    },
  );
}
