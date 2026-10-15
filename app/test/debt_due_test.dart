import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:eldafttar/src/features/debts/domain/debt_calendar_date.dart';
import 'package:eldafttar/src/features/debts/domain/debt_rules.dart';
import 'package:eldafttar/src/features/debts/application/debt_due_contract.dart';
import 'package:eldafttar/src/features/debts/application/debt_due_flow.dart';
import 'package:eldafttar/src/features/debts/application/debt_due_gateway.dart';
import 'package:eldafttar/src/features/debts/data/debt_due_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'debt_due_fixtures.dart';
import 'repair_command_flow_test.dart' show MemoryLocker;
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionSaveLocker extends MemoryLocker {
  SessionSaveLocker(this.gateway);
  final FakeDue gateway;
  @override
  Future<void> save(String user, String shop, PendingFinancialCommand c) async {
    await super.save(user, shop, c);
    gateway.session = 'changed-during-save';
  }
}

PendingFinancialCommand command(Map<String, Object?> p) =>
    PendingFinancialCommand(
      key: dueKey,
      kind: debtDueKind,
      body: {'p_idempotency_key': dueKey, 'p_payload': p},
    );
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'unknown send then access loss during status never clears original',
    () async {
      final g = FakeDue()..unknown = true;
      g.statusOverride = (_) async =>
          const DebtDueTransport(error: 'shop_unavailable');
      final store = MemoryLocker();
      final r = await DebtDueFlow(
        g,
        store,
      ).submit(dueUser, dueShop, dueKey, g.payload(), canWrite: true);
      expect(r.pending, isNotNull);
      expect(store.stored?.key, dueKey);
    },
  );
  test(
    'session changes during saved envelope creation prevent first send',
    () async {
      final g = FakeDue();
      final store = SessionSaveLocker(g);
      final r = await DebtDueFlow(
        g,
        store,
      ).submit(dueUser, dueShop, dueKey, g.payload(), canWrite: true);
      expect(r.pending, isNotNull);
      expect(g.sent, isEmpty);
      expect(store.stored?.key, dueKey);
    },
  );
  test('session changes after absent status prevent resend', () async {
    final g = FakeDue();
    g.statusOverride = (_) async {
      g.session = 'changed-during-status';
      return const DebtDueTransport(absent: true);
    };
    final store = MemoryLocker()..stored = command(g.payload());
    final r = await DebtDueFlow(
      g,
      store,
    ).reconcile(dueUser, dueShop, store.stored!, retry: true, canWrite: true);
    expect(r.pending, isNotNull);
    expect(g.sent, isEmpty);
  });
  test(
    'cleanup failure retains confirmed receipt and blocking original',
    () async {
      final g = FakeDue();
      final store = MemoryLocker()..clearError = StateError('storage');
      final r = await DebtDueFlow(
        g,
        store,
      ).submit(dueUser, dueShop, dueKey, g.payload(), canWrite: true);
      expect(r.receipt, isNotNull);
      expect(r.pending, isNotNull);
      expect(r.error, 'storage');
    },
  );
  test(
    'secure recovery across instances preserves exact due envelope and foreign unknown bytes',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      const locker = PendingFinancialCommands();
      final c = command(FakeDue().payload());
      await locker.save(dueUser, dueShop, c);
      expect(
        canonicalDueJson(
          (await const PendingFinancialCommands().read(dueUser, dueShop))!.body,
        ),
        canonicalDueJson(c.body),
      );
      await expectLater(
        locker.save(
          dueUser,
          dueShop,
          command({...FakeDue().payload(), 'due_date': '2027-01-01'}),
        ),
        throwsStateError,
      );
      await locker.clear(dueUser, dueShop, dueKey);
      const storage = FlutterSecureStorage();
      const raw =
          '{"key":"a4444444-4444-4444-8444-444444444444","kind":"unknown_future","body":{"p_payload":{"private":"original"}}}';
      await storage.write(
        key: 'pending_financial_${dueUser}_$dueShop',
        value: raw,
      );
      await expectLater(
        locker.save(dueUser, dueShop, c),
        throwsFormatException,
      );
      expect(
        await storage.read(key: 'pending_financial_${dueUser}_$dueShop'),
        raw,
      );
    },
  );
  for (final date in ['0001-01-01', '2000-02-29', '2024-02-29', '9999-12-31']) {
    test(
      'calendar accepts $date',
      () => expect(DebtCalendarDate.parse(date)?.wire, date),
    );
  }
  for (final date in [
    '0000-01-01',
    '1900-02-29',
    '2023-02-29',
    '2024-04-31',
    '2024-13-01',
    '2024-00-10',
    '2024-2-09',
    'today',
    '2024-02-29T01:00:00Z',
  ]) {
    test(
      'calendar rejects $date',
      () => expect(DebtCalendarDate.parse(date), isNull),
    );
  }
  for (final source in DebtSourceKind.values) {
    for (final karat
        in source == DebtSourceKind.purchaseCashPayable
            ? <int?>[null]
            : <int?>[null, 14, 18, 21, 22, 24]) {
      if (source == DebtSourceKind.goldObligation && karat == null) continue;
      test('exact source unit $source $karat', () {
        final d = parseDebtDueDetail(
          dueFixture(source: source.wire, karat: karat),
        );
        expect(d.row.summary.remaining, BigInt.from(10005));
        expect(d.row.summary.karat, karat);
      });
    }
  }
  for (final direction in ['shop_owes', 'owed_to_shop']) {
    for (final date in <String?>[
      null,
      '2026-10-13',
      '2026-10-14',
      '2026-10-15',
    ]) {
      test('$direction date $date has truthful server classification', () {
        final d = parseDebtDueDetail(
          dueFixture(direction: direction, date: date),
        );
        expect(
          d.row.state,
          date == null
              ? null
              : date == '2026-10-13'
              ? 'overdue'
              : date == '2026-10-14'
              ? 'today'
              : 'upcoming',
        );
      });
    }
  }
  for (final state in ['archived', 'settled', 'cancelled']) {
    test('closed $state retains readable metadata', () {
      final d = parseDebtDueDetail(
        dueFixture(
          state: state,
          remaining: state == 'archived' ? '10005' : '0',
        ),
      );
      expect(d.canSchedule, false);
      expect(d.row.date!.wire, '2026-10-14');
      expect(d.row.state, 'inactive');
    });
  }
  for (final mutation in <String, void Function(Map<String, Object?>)>{
    'device classification': (j) => j['due_state'] = 'overdue',
    'invalid date': (j) => j['due_date'] = '2023-02-29',
    'malformed amount': (j) => j['remaining_amount'] = 10.005,
    'missing actor': (j) => j['actor_user_id'] = null,
    'false version': (j) => j['due_version'] = '0',
    'missing history': (j) => j['metadata_history'] = [],
    'wrong history date': (j) =>
        (j['metadata_history'] as List).first['new_date'] = '2026-10-15',
    'bad UTC': (j) => j['snapshot_at'] = '2026-10-14T12:00:00',
  }.entries) {
    test('rejects ${mutation.key}', () {
      final j = FakeDue().clone();
      mutation.value(j);
      expect(() => parseDebtDueDetail(j), throwsFormatException);
    });
  }
  test('locker envelope validates dates, exact version and full payload', () {
    final c = command(FakeDue().payload());
    expect(matchesDebtDueEnvelope(c.key, c.kind, c.body), true);
    final p = {...FakeDue().payload(), 'extra': true};
    expect(matchesDebtDueEnvelope(c.key, c.kind, command(p).body), false);
    expect(
      matchesDebtDueEnvelope(
        c.key,
        c.kind,
        command({
          ...FakeDue().payload(),
          'expected_due_version': '9223372036854775808',
        }).body,
      ),
      false,
    );
  });
  test(
    'unknown, restart, replay retains the exact original envelope',
    () async {
      final g = FakeDue()..unknown = true;
      final store = MemoryLocker();
      final flow = DebtDueFlow(g, store);
      final p = g.payload();
      final first = await flow.submit(
        dueUser,
        dueShop,
        dueKey,
        p,
        canWrite: true,
      );
      expect(first.pending, isNotNull);
      final body = canonicalDueJson(store.stored!.body);
      p['due_date'] = '2027-01-01';
      g.unknown = false;
      final again = await flow.reconcile(
        dueUser,
        dueShop,
        store.stored!,
        retry: true,
        canWrite: true,
      );
      expect(again.receipt?.date, isNull);
      expect(canonicalDueJson(g.sent.last.body), body);
      expect(store.stored, isNull);
    },
  );
  test('foreign pending blocks metadata save and stays untouched', () async {
    final g = FakeDue();
    final foreign = PendingFinancialCommand(
      key: 'a5555555-5555-4555-8555-555555555555',
      kind: 'sale',
      body: {
        'p_payload': {'kind': 'sale'},
      },
    );
    final store = MemoryLocker()..stored = foreign;
    final r = await DebtDueFlow(
      g,
      store,
    ).submit(dueUser, dueShop, dueKey, g.payload(), canWrite: true);
    expect(r.error, 'other_pending');
    expect(identical(store.stored, foreign), true);
    expect(g.sent, isEmpty);
  });
  test(
    'expired owners reconcile confirmed request but never resend absent',
    () async {
      final g = FakeDue();
      final store = MemoryLocker()..stored = command(g.payload());
      final flow = DebtDueFlow(g, store);
      final r = await flow.reconcile(
        dueUser,
        dueShop,
        store.stored!,
        retry: true,
        canWrite: false,
      );
      expect(r.pending, isNotNull);
      expect(g.sent, isEmpty);
      g.statusOverride = (c) async =>
          DebtDueTransport(receipt: parseDebtDueReceipt(dueReceipt(c)));
      final saved = await flow.reconcile(
        dueUser,
        dueShop,
        store.stored!,
        retry: true,
        canWrite: false,
      );
      expect(saved.receipt, isNotNull);
      expect(store.stored, isNull);
    },
  );
  for (final field in [
    'payload',
    'actor_user_id',
    'shop_id',
    'source_id',
    'due_version',
  ]) {
    test('mismatched receipt $field preserves pending', () async {
      final g = FakeDue();
      g.sendOverride = (c) async {
        final j = dueReceipt(c);
        j[field] = switch (field) {
          'payload' => {...g.payload(), 'due_date': '2027-01-01'},
          'due_version' => '99',
          _ => 'a9999999-9999-4999-8999-999999999999',
        };
        return DebtDueTransport(receipt: parseDebtDueReceipt(j));
      };
      final store = MemoryLocker();
      final r = await DebtDueFlow(
        g,
        store,
      ).submit(dueUser, dueShop, dueKey, g.payload(), canWrite: true);
      expect(r.pending, isNotNull);
      expect(store.stored?.key, dueKey);
    });
  }
  test('late token change preserves original request', () async {
    final g = FakeDue();
    g.sendOverride = (c) async {
      g.session = 'new-token';
      return DebtDueTransport(receipt: parseDebtDueReceipt(dueReceipt(c)));
    };
    final store = MemoryLocker();
    final r = await DebtDueFlow(
      g,
      store,
    ).submit(dueUser, dueShop, dueKey, g.payload(), canWrite: true);
    expect(r.pending, isNotNull);
    expect(store.stored?.key, dueKey);
  });
  test('malformed paging never claims empty or complete', () {
    expect(
      () => parseDebtReminderPage(duePageFixture(rows: [], total: 1)),
      throwsFormatException,
    );
    expect(
      () => parseDebtReminderPage(duePageFixture(total: 2)),
      throwsFormatException,
    );
    expect(
      () => parseDebtReminderPage(
        duePageFixture(rows: [dueFixture(), dueFixture()]),
      ),
      throwsFormatException,
    );
  });
  for (final operation in ['read', 'list', 'send', 'status']) {
    for (final changed in ['token', 'account', 'logout']) {
      test('HTTP $operation discards late $changed reply', () async {
        var token = 'token';
        String? user = dueUser;
        final c = command(FakeDue().payload());
        final gate = HttpOpeningGateway(
          client: MockClient((request) async {
            if (changed == 'token') {
              token = 'new';
            } else {
              user = changed == 'logout' ? null : 'other';
            }
            final Object j = operation == 'read'
                ? dueFixture()
                : operation == 'list'
                ? duePageFixture()
                : operation == 'send'
                ? dueReceipt(c)
                : {'status': 'completed', 'result': dueReceipt(c)};
            return http.Response(jsonEncode(j), 200);
          }),
          supabaseUrl: 'https://example.test',
          publishableKey: 'public',
          accessToken: () => token,
          currentUserId: () => user,
        );
        if (operation == 'read') {
          await expectLater(
            gate.readDue(
              userId: dueUser,
              shopId: dueShop,
              sourceKind: DebtSourceKind.standalone,
              sourceId: dueSourceId,
            ),
            throwsA(isA<Exception>()),
          );
        } else if (operation == 'list') {
          await expectLater(
            gate.readReminders(
              userId: dueUser,
              shopId: dueShop,
              query: '',
              filter: 'all',
              cursor: null,
            ),
            throwsA(isA<Exception>()),
          );
        } else {
          final t = operation == 'send'
              ? await gate.sendDue(userId: dueUser, shopId: dueShop, command: c)
              : await gate.dueStatus(
                  userId: dueUser,
                  shopId: dueShop,
                  command: c,
                );
          expect(t.receipt, isNull);
        }
      });
    }
  }
  test(
    'HTTP status checks exact original payload and malformed wrapper',
    () async {
      final c = command(FakeDue().payload());
      late http.Request captured;
      final gate = HttpOpeningGateway(
        client: MockClient((r) async {
          captured = r;
          return http.Response(
            jsonEncode({
              'status': 'completed',
              'result': dueReceipt(c),
              'extra': true,
            }),
            200,
          );
        }),
        supabaseUrl: 'https://example.test',
        publishableKey: 'public',
        accessToken: () => 'token',
        currentUserId: () => dueUser,
      );
      final t = await gate.dueStatus(
        userId: dueUser,
        shopId: dueShop,
        command: c,
      );
      expect(
        canonicalDueJson(jsonDecode(captured.body)),
        canonicalDueJson(c.body),
      );
      expect(t.receipt, isNull);
    },
  );
}
