import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/invoice_message/application/message_contract.dart';
import 'package:eldafttar/src/features/invoice_message/application/message_gateway.dart';
import 'package:eldafttar/src/features/invoice_message/application/message_flow.dart';
import 'package:eldafttar/src/features/invoice_message/data/message_codec.dart';
import 'package:eldafttar/src/features/invoice_message/domain/synthetic_message.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_sync.dart';
import 'invoice_message_test.dart';

Map<String, Object?> profileJson({int revision = 0}) => {
  'version': 1,
  'shop_id': messageShop,
  'revision': '$revision',
  'template': null,
  'can_write': true,
  'time_zone': 'Africa/Cairo',
  'created_at': revision == 0 ? null : '2026-10-18T07:30:00Z',
  'created_at_shop': revision == 0 ? null : '2026-10-18T10:30:00',
};
Map<String, Object?> receiptJson(Map<String, Object?> payload) => {
  'version': 1,
  'shop_id': messageShop,
  'revision': '1',
  'template': payload['template'],
  'key': messageKey,
  'kind': invoiceMessageKind,
  'payload': payload,
  'actor_user_id': messageUser,
  'at': '2026-10-18T07:30:00Z',
  'replayed': false,
  'cash_piastres': '0',
  'gold_milligrams': '0',
  'stock_milligrams': '0',
  'invoice_effect': false,
  'dispatch_effect': false,
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'HTTP timeout after commit reconciles original receipt without a second save',
    () async {
      final held = Completer<void>();
      var sends = 0, statuses = 0;
      final payload = messagePayload(0, 'نص {total}');
      final locker = MessageLocker();
      http.Response result() => http.Response.bytes(
        utf8.encode(jsonEncode(receiptJson(payload))),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
      final gateway = HttpOpeningGateway(
        client: MockClient((r) async {
          if (r.url.pathSegments.last == 'post_invoice_message_v1') {
            sends++;
            await held.future;
            return result();
          }
          if (r.url.pathSegments.last == 'get_invoice_message_status_v1') {
            statuses++;
            return http.Response.bytes(
              utf8.encode(
                jsonEncode({
                  'status': 'completed',
                  'result': receiptJson(payload),
                }),
              ),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          throw StateError('unexpected RPC');
        }),
        supabaseUrl: 'https://synthetic.test',
        publishableKey: 'public',
        accessToken: () => 'epoch',
        currentUserId: () => messageUser,
        timeout: const Duration(milliseconds: 20),
      );
      final outcome = await InvoiceMessageFlow(
        gateway,
        locker,
      ).submit(messageUser, messageShop, messageKey, payload, canWrite: true);
      expect(outcome.receipt, isNotNull);
      expect(outcome.pending, isNull);
      expect(locker.command, isNull);
      expect(sends, 1);
      expect(statuses, 1);
      held.complete();
    },
  );
  test(
    'HTTP read/review/save/status/source only use narrow metadata RPCs and actual body',
    () async {
      final calls = <http.Request>[];
      final payload = messagePayload(0, 'نص {total}');
      final client = MockClient((r) async {
        calls.add(r);
        final result = switch (r.url.pathSegments.last) {
          'get_invoice_message_v1' => profileJson(),
          'review_invoice_message_v1' => {
            'status': 'ready',
            'current_revision': '0',
            'can_write': true,
            'normalized': payload,
          },
          'post_invoice_message_v1' => receiptJson(payload),
          'get_invoice_message_status_v1' => {
            'status': 'completed',
            'result': receiptJson(payload),
          },
          'get_invoice_message_source_v1' => {
            ...syntheticMessageOperation(),
            'version': 1,
            'shop_id': messageShop,
            'content_sha256': 'a' * 64,
            'message': profileJson(),
          },
          _ => throw StateError('unexpected RPC'),
        };
        return http.Response(
          jsonEncode(result),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final g = HttpOpeningGateway(
        client: client,
        supabaseUrl: 'https://synthetic.test',
        publishableKey: 'public',
        accessToken: () => 'epoch',
        currentUserId: () => messageUser,
      );
      expect(parseMessageProfile(profileJson(), messageShop).revision, 0);
      expect(
        parseMessageSource(
          {
            ...syntheticMessageOperation(),
            'version': 1,
            'shop_id': messageShop,
            'content_sha256': 'a' * 64,
            'message': profileJson(),
          },
          messageShop,
          messageOperation,
        ).operation['shop_sequence'],
        '73',
      );
      expect((await g.readMessage(messageUser, messageShop)).revision, 0);
      expect(
        (await g.reviewMessage(messageUser, messageShop, payload)).status,
        'ready',
      );
      final envelope = {'p_idempotency_key': messageKey, 'p_payload': payload};
      expect(
        (await g.sendMessage(
          messageUser,
          messageShop,
          envelope,
        )).receipt!.revision,
        1,
      );
      expect(
        (await g.messageStatus(
          messageUser,
          messageShop,
          envelope,
        )).receipt!.payload,
        payload,
      );
      expect(
        (await g.readMessageSource(
          messageUser,
          messageShop,
          messageOperation,
        )).operation['shop_sequence'],
        '73',
      );
      expect(calls.length, 5);
      expect(jsonDecode(calls[2].body), envelope);
      expect(jsonDecode(calls[3].body), envelope);
      expect(
        calls.every((r) => r.headers['authorization'] == 'Bearer epoch'),
        isTrue,
      );
    },
  );
  test(
    'late HTTP token/account changes discarded, timeout unknown and stale error retained',
    () async {
      var token = 'epoch', user = messageUser;
      final held = Completer<void>();
      var mode = 'held';
      final g = HttpOpeningGateway(
        client: MockClient((r) async {
          if (mode == 'held') {
            await held.future;
            return http.Response(jsonEncode(profileJson()), 200);
          }
          if (mode == 'stale') {
            return http.Response(jsonEncode({'message': 'stale_message'}), 400);
          }
          return http.Response('unavailable', 503);
        }),
        supabaseUrl: 'https://synthetic.test',
        publishableKey: 'public',
        accessToken: () => token,
        currentUserId: () => user,
      );
      final future = g.readMessage(messageUser, messageShop);
      token = 'epoch2';
      held.complete();
      await expectLater(future, throwsA(isA<MessageGatewayException>()));
      mode = 'stale';
      final envelope = {
        'p_idempotency_key': messageKey,
        'p_payload': messagePayload(0, null),
      };
      expect(
        (await g.sendMessage(messageUser, messageShop, envelope)).error,
        'stale_message',
      );
      mode = '503';
      expect(
        (await g.sendMessage(messageUser, messageShop, envelope)).receipt,
        isNull,
      );
      user = 'other';
      await expectLater(
        g.readMessage(messageUser, messageShop),
        throwsA(isA<MessageGatewayException>()),
      );
    },
  );
  test(
    'codec denies other shop, unsupported version, wrong zone and financial effects',
    () {
      expect(
        () => parseMessageProfile({
          ...profileJson(),
          'shop_id': 'other',
        }, messageShop),
        throwsFormatException,
      );
      expect(
        () =>
            parseMessageProfile({...profileJson(), 'version': 2}, messageShop),
        throwsFormatException,
      );
      expect(
        () => parseMessageReceipt({
          ...receiptJson(messagePayload(0, null)),
          'dispatch_effect': true,
        }),
        throwsFormatException,
      );
      expect(
        () => parseMessageSource(
          {
            ...syntheticMessageOperation(),
            'version': 1,
            'shop_id': messageShop,
            'content_sha256': 'a' * 64,
            'message': {...profileJson(), 'time_zone': 'Asia/Riyadh'},
          },
          messageShop,
          messageOperation,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'secure locker preserves exact unrelated and unknown bytes and restores original message',
    () async {
      SharedPreferences.setMockInitialValues({});
      final key = 'pending_financial_${messageUser}_$messageShop';
      const foreign =
          '{"key":"a1555555-5555-4555-8555-555555555555", "kind":"future_kind", "body":{"opaque":"unchanged"}}';
      FlutterSecureStorage.setMockInitialValues({key: foreign});
      const storage = FlutterSecureStorage();
      final store = PendingFinancialCommands(storage: storage);
      await expectLater(
        store.read(messageUser, messageShop),
        throwsFormatException,
      );
      final message = PendingFinancialCommand(
        key: messageKey,
        kind: invoiceMessageKind,
        body: {
          'p_idempotency_key': messageKey,
          'p_payload': messagePayload(0, 'نص {total}'),
        },
      );
      await expectLater(
        store.save(messageUser, messageShop, message),
        throwsFormatException,
      );
      expect(await storage.read(key: key), foreign);
      FlutterSecureStorage.setMockInitialValues({});
      await store.save(messageUser, messageShop, message);
      expect(
        canonicalMessageJson(
          (await store.read(messageUser, messageShop))!.body,
        ),
        canonicalMessageJson(message.body),
      );
      final before = await storage.read(key: key);
      await expectLater(
        store.save(
          messageUser,
          messageShop,
          PendingFinancialCommand(
            key: messageKey,
            kind: invoiceMessageKind,
            body: {
              'p_idempotency_key': messageKey,
              'p_payload': messagePayload(0, 'changed'),
            },
          ),
        ),
        throwsStateError,
      );
      expect(await storage.read(key: key), before);
    },
  );
  test(
    'message and appearance revisions invalidate separately and reconnect catches up',
    () {
      const old = ShopSyncSnapshot(
        shopId: messageShop,
        revision: 1,
        appearanceRevision: 1,
        messageRevision: 1,
      );
      const next = ShopSyncSnapshot(
        shopId: messageShop,
        revision: 2,
        appearanceRevision: 1,
        messageRevision: 2,
      );
      expect(next.changedFrom(old), {ShopSyncScope.message});
      expect(next.asCatchUp().messageRevision, 2);
      expect(next.asCatchUp().forceRefresh, isTrue);
    },
  );
}
