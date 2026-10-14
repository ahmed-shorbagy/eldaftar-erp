import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/debts/application/debt_gateway.dart';
import 'package:eldafttar/src/features/debts/application/debt_statement_gateway.dart';
import 'package:eldafttar/src/features/debts/application/debt_statement_flow.dart';
import 'package:eldafttar/src/features/debts/data/debt_statement_codec.dart';
import 'package:eldafttar/src/features/debts/domain/debt_rules.dart';
import 'package:eldafttar/src/features/debts/domain/debt_statement.dart';
import 'package:eldafttar/src/features/debts/presentation/debt_statement_pdf.dart';
import 'debt_statement_fixtures.dart';

class StatementFake implements DebtStatementGateway {
  Object? session = 'token';
  Map<String, Object?> data = statementFixture();
  Future<DebtStatement> Function()? read;
  int reads = 0;
  @override
  Object? statementSession(String _) => session;
  @override
  Future<DebtStatement> readStatement({
    required String callerUserId,
    required String shopId,
    required DebtSourceKind sourceKind,
    required String sourceId,
  }) async {
    reads++;
    return read != null ? await read!() : parseDebtStatement(data);
  }
}

class StatementPlatformFake implements DebtStatementPlatform {
  StatementCapabilities caps = const StatementCapabilities(
    save: true,
    share: true,
    print: true,
  );
  StatementOutcome outcome = StatementOutcome.handedOff;
  int calls = 0;
  Uint8List? received;
  Future<StatementOutcome> Function(bool Function())? open;
  @override
  Future<StatementCapabilities> capabilities() async => caps;
  @override
  Future<StatementOutcome> handoff(
    StatementAction action,
    Uint8List bytes, {
    required bool Function() stillAuthorized,
  }) async {
    calls++;
    received = bytes;
    return open != null ? open!(stillAuthorized) : outcome;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final source in DebtSourceKind.values) {
    for (final karat
        in source == DebtSourceKind.purchaseCashPayable
            ? <int?>[null]
            : <int?>[null, 14, 18, 21, 22, 24]) {
      if (source == DebtSourceKind.goldObligation && karat == null) continue;
      test(
        'validated $source $karat retains exact unit and complete history',
        () {
          final s = parseDebtStatement(
            statementFixture(
              source: source,
              unit: karat == null ? 'money' : 'gold',
              karat: karat,
              archived: true,
            ),
          );
          expect(s.original, s.settled + s.cancelled + s.remaining);
          expect(s.history.length, 3);
          if (karat != null) {
            expect(statementAmount(s, s.remaining), contains('10.005'));
          }
        },
      );
    }
  }
  for (final direction in ['shop_owes', 'owed_to_shop']) {
    test('standalone direction $direction and empty history settlement', () {
      final s = parseDebtStatement(
        statementFixture(direction: direction, payments: 0),
      );
      expect(s.settled, BigInt.zero);
      expect(s.contactPhone, isNull);
    });
  }
  test('cancellation differs from actual payment', () {
    final s = parseDebtStatement(
      statementFixture(
        source: DebtSourceKind.purchaseCashPayable,
        cancel: true,
      ),
    );
    expect(s.settled, BigInt.one);
    expect(s.cancelled, BigInt.from(100));
  });
  for (final mutation in <String, void Function(Map<String, Object?>)>{
    'incomplete': (j) => j['history_complete'] = false,
    'wrong count': (j) => j['history_count'] = 0,
    'missing origin': (j) => (j['history'] as List).removeAt(0),
    'floating amount': (j) => j['remaining_amount'] = 100.5,
    'wrong invariants': (j) => j['settled_amount'] = '2',
    'missing cancelled': (j) => j.remove('cancelled_amount'),
    'future event': (j) =>
        ((j['history'] as List).last as Map)['at'] = '2027-01-01T00:00:00Z',
    'missing actor': (j) =>
        ((j['history'] as List).last as Map).remove('actor_user_id'),
    'duplicate operation': (j) {
      final rows = j['history'] as List;
      rows.last['operation_id'] = rows.first['operation_id'];
    },
    'missing settlement evidence': (j) =>
        ((j['history'] as List).last as Map)['amount'] = '0',
    'mixed unit': (j) => j['karat'] = 18,
    'unknown event': (j) =>
        ((j['history'] as List).last as Map)['event_type'] = 'unknown',
  }.entries) {
    test('rejects ${mutation.key}', () {
      final j = statementFixture(source: DebtSourceKind.purchaseCashPayable);
      mutation.value(j);
      expect(() => parseDebtStatement(j), throwsA(isA<FormatException>()));
    });
  }
  test('long complete evidence retains every exact payment and origin', () {
    final s = parseDebtStatement(statementFixture(payments: 400));
    expect(s.history.length, 401);
    expect(s.settled, BigInt.from(400));
  });
  for (final name in ['money', 'gold', 'long-money', 'long-gold']) {
    test('actual Cairo A4 PDF fixture $name', () async {
      final j = statementFixture(
        unit: name.contains('gold') ? 'gold' : 'money',
        karat: name.contains('gold') ? 22 : null,
        payments: name.startsWith('long') ? 120 : 1,
      );
      if (name.startsWith('long')) {
        for (final e in j['history'] as List) {
          e['reason'] =
              'بيانات اصطناعية ذات نص عربي طويل مختلط ABC 123 لفحص التفاف السطور وعدم فقد أي سجل. ' *
              3;
        }
      }
      final bytes = await buildDebtStatementPdf(parseDebtStatement(j));
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      final file = File('build/debt-statement/$name.pdf');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    });
  }
  late StatementFake g;
  late StatementPlatformFake p;
  late DebtStatementFlow f;
  setUp(() {
    g = StatementFake();
    p = StatementPlatformFake();
    f = DebtStatementFlow(
      gateway: g,
      platform: p,
      render: (_) async => Uint8List.fromList(utf8.encode('%PDF synthetic')),
      userId: statementUser,
      shopId: statementShop,
      sourceKind: DebtSourceKind.standalone,
      sourceId: statementSourceId,
      canRead: () => true,
    );
  });
  test(
    'fresh reads before exact reviewed-byte handoff and duplicate prevention',
    () async {
      expect(await f.prepare(), StatementOutcome.prepared);
      final bytes = f.bytes;
      expect(
        await f.handoff(StatementAction.share),
        StatementOutcome.handedOff,
      );
      expect(g.reads, 2);
      expect(identical(p.received, bytes), true);
      final blocked = Completer<DebtStatement>();
      g.read = () => blocked.future;
      final pending = f.handoff(StatementAction.save);
      expect(await f.handoff(StatementAction.share), StatementOutcome.busy);
      blocked.complete(parseDebtStatement(g.data));
      await pending;
    },
  );
  for (final change in ['freshness', 'token', 'logout', 'sync']) {
    test('$change invalidates bytes and never hands off', () async {
      await f.prepare();
      final bytes = f.bytes!;
      switch (change) {
        case 'freshness':
          g.data['freshness'] = 'b' * 64;
        case 'token':
          g.session = 'new';
        case 'logout':
          g.session = null;
        case 'sync':
          f.invalidate();
      }
      expect(await f.handoff(StatementAction.save), StatementOutcome.stale);
      expect(p.calls, 0);
      expect(bytes.every((b) => b == 0), true);
    });
  }
  test('late generation after access loss scrubs renderer bytes', () async {
    final pending = Completer<DebtStatement>();
    g.read = () => pending.future;
    final result = f.prepare();
    g.session = null;
    pending.complete(parseDebtStatement(g.data));
    expect(await result, StatementOutcome.stale);
    expect(f.bytes, isNull);
  });
  test('read or generation failure has no handoff effect', () async {
    g.read = () async => throw const DebtReadException('forbidden');
    expect(await f.prepare(), StatementOutcome.failed);
    expect(p.calls, 0);
    expect(f.bytes, isNull);
  });
  for (final outcome in [
    StatementOutcome.saved,
    StatementOutcome.cancelled,
    StatementOutcome.failed,
    StatementOutcome.handedOff,
  ]) {
    test('adapter outcome $outcome stays distinct', () async {
      await f.prepare();
      p.outcome = outcome;
      expect(await f.handoff(StatementAction.save), outcome);
    });
  }
  test('unavailable platform action never opens', () async {
    await f.prepare();
    p.caps = const StatementCapabilities();
    expect(
      await f.handoff(StatementAction.print),
      StatementOutcome.unavailable,
    );
    expect(p.calls, 0);
  });
  test('late handoff access loss discarded', () async {
    await f.prepare();
    p.open = (guard) async {
      g.session = null;
      expect(guard(), false);
      return StatementOutcome.saved;
    };
    expect(await f.handoff(StatementAction.save), StatementOutcome.stale);
    expect(f.bytes, isNull);
  });
  for (final change in ['none', 'shop', 'source', 'token', 'account']) {
    test(
      'HTTP statement read checks $change without posting any command',
      () async {
        var user = statementUser, token = 'token';
        var calls = 0;
        final client = MockClient((r) async {
          calls++;
          expect(r.url.path, '/rest/v1/rpc/get_debt_statement_v1');
          expect(jsonDecode(r.body), {
            'p_source_kind': 'standalone',
            'p_source_id': statementSourceId,
          });
          final j = statementFixture();
          if (change == 'shop') j['shop_id'] = statementUser;
          if (change == 'source') j['source_id'] = statementUser;
          if (change == 'token') token = 'new';
          if (change == 'account') user = statementShop;
          return http.Response(
            jsonEncode(j),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });
        final gateway = HttpOpeningGateway(
          client: client,
          supabaseUrl: 'https://example.test',
          publishableKey: 'public-test',
          accessToken: () => token,
          currentUserId: () => user,
        );
        final result = gateway.readStatement(
          callerUserId: statementUser,
          shopId: statementShop,
          sourceKind: DebtSourceKind.standalone,
          sourceId: statementSourceId,
        );
        if (change == 'none') {
          expect((await result).shopId, statementShop);
        } else {
          await expectLater(result, throwsA(isA<DebtReadException>()));
        }
        expect(calls, 1);
      },
    );
  }
}
