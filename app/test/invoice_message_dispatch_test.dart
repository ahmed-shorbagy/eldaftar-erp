import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_operation_screen.dart';
import 'package:eldafttar/src/features/invoice_message/domain/synthetic_message.dart';
import 'customer_widget_test.dart' show customerHost, size;
import 'invoice_message_test.dart';
import 'invoice_message_http_test.dart' show profileJson;
import 'invoice_message_widget_test.dart' show tapMessage;

void main() {
  testWidgets(
    'operation handoff cannot confirm dispatch; separate owner action sends no body or phone',
    (t) async {
      size(t);
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      var confirmed = false;
      final calls = <http.Request>[], launcher = MessageLauncherFake();
      final source = {
        ...syntheticMessageOperation(),
        'version': 1,
        'shop_id': messageShop,
        'actor_display_name': 'مالك تجريبي',
        'occurred_at_cairo': '2026-10-18T10:30:00',
        'content_sha256': 'a' * 64,
        'message': profileJson(),
      };
      final gateway = HttpOpeningGateway(
        client: MockClient((r) async {
          calls.add(r);
          Object? result;
          switch (r.url.pathSegments.last) {
            case 'get_daily_ledger_operation':
              result = source;
            case 'get_invoice_dispatch_state':
              result = {
                'operation_id': messageOperation,
                'status': confirmed ? 'owner_confirmed' : 'unconfirmed',
                if (confirmed) 'confirmed_at': '2026-10-18T07:40:00Z',
              };
            case 'get_invoice_message_source_v1':
              result = source;
            case 'get_invoice_brand_source_v1':
              return http.Response('{"code":"PGRST202"}', 404);
            case 'get_invoice_presentations_v1':
              result = {
                'version': 1,
                'shop_id': messageShop,
                'operation_id': messageOperation,
                'can_write': true,
                'items': [],
              };
            case 'confirm_invoice_whatsapp_send':
              confirmed = true;
              result = {
                'ok': true,
                'operation_id': messageOperation,
                'replayed': false,
              };
            default:
              fail('Unexpected RPC ${r.url.pathSegments.last}');
          }
          return http.Response.bytes(
            utf8.encode(jsonEncode(result)),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        supabaseUrl: 'https://synthetic.test',
        publishableKey: 'public',
        accessToken: () => 'epoch',
        currentUserId: () => messageUser,
      );
      await t.pumpWidget(
        customerHost(
          FinancialOperationScreen(
            gateway: gateway,
            userId: messageUser,
            shopId: messageShop,
            canRead: () => true,
            canWrite: () => true,
            messageLauncher: launcher,
            pdfShare: (bytes, name) async => true,
            line: const LedgerFeedLine(
              kind: 'sale',
              labelAr: 'بيع',
              operationId: messageOperation,
              actorDisplayName: 'مالك تجريبي',
              occurredAt: '2026-10-18T07:30:00Z',
              occurredAtCairo: '2026-10-18T10:30:00',
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('فتح رسالة واتساب'), findsNothing);
      expect(find.text('تأكيد الإرسال بعد إرساله'), findsNothing);
      await tapMessage(t, find.text('مشاركة مستند PDF عبر واتساب'));
      expect(find.text('إرسال الفاتورة'), findsOneWidget);
      expect(confirmed, isFalse);
      expect(launcher.uris, isEmpty);
      await tapMessage(t, find.byKey(const Key('invoice-pdf-share')));
      await tapMessage(t, find.byKey(const Key('invoice-pdf-legacy-share')));
      expect(confirmed, isFalse);
      expect(
        calls.where(
          (r) => r.url.pathSegments.last == 'confirm_invoice_whatsapp_send',
        ),
        isEmpty,
      );
      await tapMessage(t, find.byKey(const Key('invoice-pdf-confirm')));
      expect(confirmed, isTrue);
      expect(
        find.text('أكد المالك إرسال الفاتورة عبر واتساب.'),
        findsOneWidget,
      );
      final body =
          jsonDecode(
                calls
                    .singleWhere(
                      (r) =>
                          r.url.pathSegments.last ==
                          'confirm_invoice_whatsapp_send',
                    )
                    .body,
              )
              as Map;
      expect(body.keys.toSet(), {'p_operation_id', 'p_idempotency_key'});
      expect(body['p_operation_id'], messageOperation);
      expect(
        calls.every((r) => !r.url.pathSegments.last.startsWith('post_')),
        isTrue,
      );
      expect(find.text('مشاركة مستند PDF عبر واتساب'), findsOneWidget);
    },
  );
}
