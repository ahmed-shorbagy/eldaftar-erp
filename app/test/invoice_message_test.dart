import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:eldafttar/src/features/invoice_message/domain/message_template.dart';
import 'package:eldafttar/src/features/invoice_message/domain/synthetic_message.dart';
import 'package:eldafttar/src/features/invoice_message/application/message_contract.dart';
import 'package:eldafttar/src/features/invoice_message/application/message_gateway.dart';
import 'package:eldafttar/src/features/invoice_message/application/message_flow.dart';
import 'package:eldafttar/src/features/invoice_message/application/message_handoff.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';

const messageUser = 'a1111111-1111-4111-8111-111111111111';
const messageShop = 'a1222222-2222-4222-8222-222222222222';
const messageKey = 'a1555555-5555-4555-8555-555555555555';
const messageOperation = '11111111-1111-4111-8111-111111111111';
Map<String, Object?> clone(Map<String, Object?> value) =>
    jsonDecode(jsonEncode(value)) as Map<String, Object?>;

class MessageFake implements InvoiceMessageGateway {
  Object? session = 'epoch1';
  int revision = 0, sends = 0, reads = 0, statuses = 0;
  bool writable = true, unknown = false, absent = true;
  String? template;
  String? error;
  Map<String, Object?> operation = syntheticMessageOperation();
  MessageReceipt? receipt;
  Future<void> Function()? beforeSource, beforeRead, beforeSend;
  final sent = <Map<String, Object?>>[];
  MessageProfile get profile => MessageProfile(
    shop: messageShop,
    revision: revision,
    template: template,
    canWrite: writable,
    zone: operation['time_zone'] as String,
    atUtc: revision == 0 ? null : '2026-10-18T07:30:00Z',
    atShop: revision == 0 ? null : '2026-10-18T10:30:00',
  );
  @override
  Object? messageSession(String user) => user == messageUser ? session : null;
  @override
  Future<MessageProfile> readMessage(String user, String shop) async {
    await beforeRead?.call();
    if (error != null) throw MessageGatewayException(error);
    return profile;
  }

  @override
  Future<MessageReview> reviewMessage(
    String user,
    String shop,
    Map<String, Object?> p,
  ) async => MessageReview(
    !writable
        ? 'expired'
        : p['expected_revision'] != '$revision'
        ? 'stale'
        : 'ready',
    revision,
    writable,
  );
  @override
  Future<MessageSource> readMessageSource(
    String user,
    String shop,
    String op,
  ) async {
    reads++;
    await beforeSource?.call();
    if (error != null) throw MessageGatewayException(error);
    return MessageSource(profile, clone(operation));
  }

  @override
  Future<MessageTransport> sendMessage(
    String user,
    String shop,
    Map<String, Object?> body,
  ) async {
    sends++;
    sent.add(clone(body));
    await beforeSend?.call();
    if (error != null) return MessageTransport(error: error);
    if (unknown) return const MessageTransport();
    final payload = Map<String, Object?>.from(body['p_payload'] as Map);
    if (payload['expected_revision'] != '$revision') {
      return const MessageTransport(error: 'stale_message');
    }
    revision++;
    template = payload['template'] as String?;
    receipt = MessageReceipt(
      shop: shop,
      key: body['p_idempotency_key'] as String,
      actor: user,
      payload: payload,
      revision: revision,
      at: '2026-10-18T07:30:00Z',
    );
    absent = false;
    return MessageTransport(receipt: receipt);
  }

  @override
  Future<MessageTransport> messageStatus(
    String user,
    String shop,
    Map<String, Object?> body,
  ) async {
    statuses++;
    return MessageTransport(
      receipt: receipt,
      absent: receipt == null && absent,
      error: error,
    );
  }
}

class MessageLocker implements FinancialCommandLocker {
  PendingFinancialCommand? command;
  bool failClear = false;
  @override
  Future<PendingFinancialCommand?> read(String u, String s) async => command;
  @override
  Future<void> save(String u, String s, PendingFinancialCommand c) async {
    if (command != null &&
        (command!.key != c.key ||
            canonicalMessageJson(command!.body) !=
                canonicalMessageJson(c.body))) {
      throw StateError('occupied');
    }
    command = c;
  }

  @override
  Future<void> clear(String u, String s, String key) async {
    if (failClear) throw StateError('disk');
    if (command?.key == key) command = null;
  }
}

class MessageLauncherFake implements MessageLauncher {
  final uris = <Uri>[];
  MessageLaunch result = MessageLaunch.opened;
  @override
  Future<MessageLaunch> launch(Uri uri) async {
    uris.add(uri);
    return result;
  }
}

void main() {
  test(
    'server-local operation time crosses UTC midnight/month without a Cairo or device fallback',
    () {
      final source = syntheticMessageOperation()
        ..['time_zone'] = 'Asia/Riyadh'
        ..['occurred_at'] = '2026-10-31T23:30:00Z'
        ..['occurred_at_shop'] = '2026-11-01T02:30:00';
      expect(messageValues(source)['operation_time'], '1 نوفمبر 2026، 02:30');
      source.remove('occurred_at_shop');
      source['occurred_at_cairo'] = '2026-11-01T01:30:00';
      expect(() => messageValues(source), throwsA(isA<MessageValidation>()));
      expect(MessageTemplate.parse('\t\u00a0').custom, isNull);
      for (final raw in ['\r', 'x\r', '\rx']) {
        expect(
          () => MessageTemplate.parse(raw),
          throwsA(isA<MessageValidation>()),
        );
      }
    },
  );
  test(
    'default, CRLF, whitespace reset, and one-pass escaped nonrecursive values',
    () {
      expect(MessageTemplate.parse(null).text, defaultInvoiceMessage);
      expect(MessageTemplate.parse(' \n\u00a0 ').custom, isNull);
      expect(MessageTemplate.parse(' x\r\ny ').text, 'x\ny');
      final op = syntheticMessageOperation();
      (op['payload'] as Map)['customer_name'] = '{total}';
      expect(
        MessageTemplate.parse('{{sequence}} {customer_name}').render(op),
        '{sequence} {total}',
      );
    },
  );
  test(
    'sale acceptance and every allowed token; five karats sum exact milligrams',
    () {
      final op = syntheticMessageOperation();
      final values = messageValues(op);
      expect(values['sequence'], '73');
      expect(values['kind'], 'بيع');
      expect(values['total'], '1,234.50');
      expect(values['grams_18'], '3.705');
      expect(values['item_count'], '2');
      expect(values['paid'], '');
      expect(values['obligation'], '');
      expect(values['operation_time'], '18 أكتوبر 2026، 10:30');
      expect(values.keys.toSet(), messageTokens.keys.toSet());
      (op['payload'] as Map)['items'] = [
        for (final k in [14, 18, 21, 22, 24]) ...[
          {'karat': k, 'milligrams': '9007199254740993'},
          {'karat': k, 'milligrams': '7'},
        ],
      ];
      for (final k in [14, 18, 21, 22, 24]) {
        expect(messageValues(op)['grams_$k'], '9007199254741.000');
      }
    },
  );
  test(
    'purchase uses original tenders and obligation, ignores live remaining and pricing',
    () {
      final op = syntheticMessageOperation()..['kind'] = 'purchase';
      final body = op['payload'] as Map<String, Object?>;
      body.addAll({
        'version': 2,
        'kind': 'purchase',
        'total_piastres': '200000',
        'purchase_obligation_piastres': '100000',
        'purchase_payable_remaining_piastres': '50000',
        'customer_name': null,
        'pricing': {'arbitrary': 'ignored'},
        'tenders': [
          {'piastres': '75000'},
          {'piastres': '25000'},
        ],
      });
      expect(messageValues(op)['paid'], '1,000');
      expect(messageValues(op)['obligation'], '1,000');
      expect(messageValues(op)['customer_name'], '');
      body['tenders'] = [];
      body.remove('purchase_obligation_piastres');
      body['items'] = [];
      expect(messageValues(op)['paid'], '');
      expect(messageValues(op)['obligation'], '');
      expect(messageValues(op)['item_count'], '0');
    },
  );
  test(
    'grammar, disallowed controls, malformed UTF16 and all bounds reject without truncation',
    () {
      for (final text in [
        '{remaining}',
        '{total',
        '{}',
        '{a{total}}',
        '}',
        '{TOTAL}',
        '{total }',
        'a\rb',
        'a\tb',
        '\u0000',
        '\u061c',
        '\u202e',
        '\u2066',
        '\ud800',
        '\udc00',
      ]) {
        expect(
          () => MessageTemplate.parse(text),
          throwsA(isA<MessageValidation>()),
          reason: text,
        );
      }
      expect(MessageTemplate.parse('😀' * 400).text.runes.length, 400);
      expect(
        () => MessageTemplate.parse('😀' * 401),
        throwsA(isA<MessageValidation>()),
      );
      expect(
        MessageTemplate.parse(List.filled(9, 'x').join('\n')).text,
        isNotEmpty,
      );
      expect(
        () => MessageTemplate.parse(List.filled(10, 'x').join('\n')),
        throwsA(isA<MessageValidation>()),
      );
      final op = syntheticMessageOperation();
      (op['payload'] as Map)['customer_name'] = 'a' * 200;
      expect(
        () => MessageTemplate.parse('{customer_name}' * 3).render(op),
        throwsA(isA<MessageValidation>()),
      );
      expect(
        () => messageWhatsappUri('ع' * 300, '01011111111'),
        throwsA(isA<MessageValidation>()),
      );
      expect(
        () => messageWhatsappUri('a' * 501, '01011111111'),
        throwsA(isA<MessageValidation>()),
      );
      expect(
        messageWhatsappUri('a' * 500, '01011111111').queryParameters['text'],
        'a' * 500,
      );
    },
  );
  test(
    'malformed required values and substituted controls fail closed even default body',
    () {
      for (final key in [
        'shop_name',
        'time_zone',
        'occurred_at',
        'occurred_at_shop',
        'shop_sequence',
      ]) {
        final op = syntheticMessageOperation()..remove(key);
        expect(
          () => MessageTemplate.parse(null).render(op),
          throwsA(isA<MessageValidation>()),
        );
      }
      for (final patch in [
        {'items': null},
        {'total_piastres': '1.2'},
        {'customer_name': 'x\u202ey'},
        {
          'items': [
            {'karat': 18, 'milligrams': '9223372036854775807'},
            {'karat': 18, 'milligrams': '1'},
          ],
        },
        {
          'items': [
            {'karat': 23, 'milligrams': '1'},
          ],
        },
      ]) {
        final op = syntheticMessageOperation();
        (op['payload'] as Map).addAll(patch);
        expect(
          () => MessageTemplate.parse(null).render(op),
          throwsA(isA<MessageValidation>()),
        );
      }
      final op = syntheticMessageOperation()
        ..['occurred_at_shop'] = '2026-02-30T10:30:00';
      expect(() => messageValues(op), throwsA(isA<MessageValidation>()));
    },
  );
  test('Egyptian snapshot normalization preserves legacy rules only', () {
    for (final phone in [
      '01011111111',
      '+201011111111',
      '201011111111',
      '(010) 1111-1111',
    ]) {
      expect(messageEgyptianPhone(phone), '201011111111');
    }
    for (final phone in [null, '', '+966501234567', 'abc', '0111111']) {
      expect(
        () => messageWhatsappUri('x', phone),
        throwsA(isA<MessageValidation>()),
      );
    }
  });
  test(
    'frozen request survives unknown, crash restoration, original retry and cleanup failure',
    () async {
      final g = MessageFake()..unknown = true;
      final locker = MessageLocker();
      final flow = InvoiceMessageFlow(g, locker);
      final payload = messagePayload(0, 'نص {total}');
      final outcome = await flow.submit(
        messageUser,
        messageShop,
        messageKey,
        payload,
        canWrite: true,
      );
      expect(outcome.pending, isNotNull);
      expect(locker.command, isNotNull);
      payload['template'] = 'mutated';
      expect(
        (locker.command!.body['p_payload'] as Map)['template'],
        'نص {total}',
      );
      g.unknown = false;
      locker.failClear = true;
      final recovered = await InvoiceMessageFlow(g, locker).reconcile(
        messageUser,
        messageShop,
        locker.command!,
        canWrite: true,
        retry: true,
      );
      expect(recovered.receipt, isNotNull);
      expect(recovered.pending, isNotNull);
      expect(g.sends, 2);
      expect(canonicalMessageJson(g.sent[0]), canonicalMessageJson(g.sent[1]));
      locker.failClear = false;
      g.writable = false;
      final finalResult = await flow.reconcile(
        messageUser,
        messageShop,
        locker.command!,
        canWrite: false,
        retry: true,
      );
      expect(finalResult.receipt, isNotNull);
      expect(locker.command, isNull);
      expect(g.sends, 2);
    },
  );
  test(
    'foreign pending, expired, session changes, mismatched receipt never clear original',
    () async {
      final g = MessageFake();
      final locker = MessageLocker()
        ..command = const PendingFinancialCommand(
          key: 'other',
          kind: 'future_kind',
          body: {'opaque': 'bytes'},
        );
      final flow = InvoiceMessageFlow(g, locker);
      expect(
        (await flow.submit(
          messageUser,
          messageShop,
          messageKey,
          messagePayload(0, null),
          canWrite: true,
        )).error,
        'other_pending',
      );
      expect(locker.command!.body, {'opaque': 'bytes'});
      expect(g.sends, 0);
      locker.command = null;
      expect(
        (await flow.submit(
          messageUser,
          messageShop,
          messageKey,
          messagePayload(0, null),
          canWrite: false,
        )).error,
        'shop_not_active',
      );
      g.beforeSend = () async {
        g.session = 'epoch2';
      };
      expect(
        (await flow.submit(
          messageUser,
          messageShop,
          messageKey,
          messagePayload(0, null),
          canWrite: true,
        )).error,
        'discarded',
      );
      expect(locker.command, isNotNull);
    },
  );
  test(
    'handoff rechecks template, operation, identity, zone, phone; no write or confirmation port',
    () async {
      for (final change in [
        'template',
        'shop_name',
        'time_zone',
        'customer_phone',
        'total_piastres',
      ]) {
        final g = MessageFake();
        final launch = MessageLauncherFake();
        final flow = MessageHandoff(g, launch);
        final before = await flow.prepare(
          messageUser,
          messageShop,
          messageOperation,
        );
        switch (change) {
          case 'template':
            g.revision++;
            g.template = 'نص {total}';
          case 'shop_name':
            g.operation['shop_name'] = 'اسم جديد';
          case 'time_zone':
            g.operation['time_zone'] = 'Asia/Riyadh';
            g.operation['occurred_at_shop'] = '2026-10-18T11:30:00';
          case 'customer_phone':
            (g.operation['payload'] as Map)['customer_phone'] = '01022222222';
          default:
            (g.operation['payload'] as Map)['total_piastres'] = '100';
        }
        final result = await flow.open(
          messageUser,
          messageShop,
          messageOperation,
          before,
        );
        expect(result.error, 'stale', reason: change);
        expect(result.updated, isNotNull);
        expect(launch.uris, isEmpty);
        expect(
          (await flow.open(
            messageUser,
            messageShop,
            messageOperation,
            result.updated!,
          )).launch,
          MessageLaunch.opened,
        );
        expect(launch.uris.length, 1);
        expect(g.sends, 0);
        expect(g.statuses, 0);
      }
    },
  );
  test('launcher results and account/token loss never claim sending', () async {
    final g = MessageFake();
    final launcher = MessageLauncherFake();
    final flow = MessageHandoff(g, launcher);
    for (final result in MessageLaunch.values) {
      launcher.result = result;
      final p = await flow.prepare(messageUser, messageShop, messageOperation);
      expect(
        (await flow.open(messageUser, messageShop, messageOperation, p)).launch,
        result,
      );
    }
    final p = await flow.prepare(messageUser, messageShop, messageOperation);
    g.session = 'epoch2';
    expect(
      (await flow.open(messageUser, messageShop, messageOperation, p)).error,
      'discarded',
    );
    final count = launcher.uris.length;
    g.beforeSource = () async {
      g.session = 'epoch3';
    };
    expect(
      () => flow.prepare(messageUser, messageShop, messageOperation),
      throwsA(isA<MessageGatewayException>()),
    );
    expect(launcher.uris.length, count);
  });
}
