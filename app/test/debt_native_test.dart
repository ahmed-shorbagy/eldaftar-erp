import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eldafttar/src/features/debts/application/debt_native_contract.dart';
import 'package:eldafttar/src/features/debts/application/debt_native_flow.dart';
import 'package:eldafttar/src/features/debts/application/debt_native_gateway.dart';
import 'package:eldafttar/src/features/debts/application/debt_reminder_coordinator.dart';
import 'package:eldafttar/src/features/debts/application/debt_reminder_device.dart';
import 'package:eldafttar/src/features/debts/application/debt_gateway.dart';
import 'package:eldafttar/src/features/debts/data/debt_native_codec.dart';
import 'package:eldafttar/src/features/debts/data/debt_reminder_device_store.dart';
import 'package:eldafttar/src/features/debts/domain/debt_rules.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'debt_due_fixtures.dart';
import 'debt_native_fixtures.dart';
import 'repair_command_flow_test.dart' show MemoryLocker;

PendingFinancialCommand nativeCommand(FakeNative g) => PendingFinancialCommand(
  key: dueKey,
  kind: debtNativeKind,
  body: {
    'p_idempotency_key': dueKey,
    'p_payload': parseDebtNativeDetail(g.data).row.payload('16:00'),
  },
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final source in DebtSourceKind.values) {
    for (final direction
        in source == DebtSourceKind.standalone
            ? ['shop_owes', 'owed_to_shop']
            : ['shop_owes']) {
      for (final karat
          in source == DebtSourceKind.purchaseCashPayable
              ? <int?>[null]
              : source == DebtSourceKind.goldObligation
              ? <int?>[14, 18, 21, 22, 24]
              : <int?>[null, 14, 18, 21, 22, 24]) {
        test('native exact source $source $direction $karat', () {
          final r = parseDebtNativeDetail(
            nativeFixture(
              source: source.wire,
              direction: direction,
              karat: karat,
            ),
          );
          expect(r.row.due.summary.remaining, BigInt.from(10005));
          expect(r.row.due.summary.karat, karat);
        });
      }
    }
  }
  for (final time in ['00:00', '23:59', '16:05']) {
    test('HH:mm accepts $time', () => expect(validReminderTime(time), isTrue));
  }
  for (final time in [
    '24:00',
    '12:60',
    '1:00',
    '12:00:00',
    '',
    ' 12:00',
    '١٢:٠٠',
  ]) {
    test('HH:mm rejects $time', () => expect(validReminderTime(time), isFalse));
  }
  test(
    'old dates and inactive intent remain readable without native trigger',
    () {
      for (final data in [
        nativeFixture(time: null, version: 0),
        nativeFixture(date: null),
        nativeFixture(state: 'archived'),
        nativeFixture(remaining: '0'),
        nativeFixture(valid: false),
      ]) {
        expect(() => parseDebtNativeDetail(data), returnsNormally);
      }
    },
  );
  test('malformed native audit/trigger/money fail closed', () {
    for (final edit in <Map<String, Object?>>[
      {'native_version': '2'},
      {'native_updated_at': 'bad'},
      {'native_actor_user_id': 'bad'},
      {'native_freshness': 'bad'},
      {'trigger_at': null},
      {'remaining_amount': '1.5'},
      {'time_valid': false},
      {'native_history': []},
      {'reminder_time': '24:00'},
    ]) {
      expect(
        () => parseDebtNativeDetail({...nativeFixture(), ...edit}),
        throwsFormatException,
      );
    }
  });
  test(
    'metadata timeout/restart preserves command; local scheduling never sends metadata',
    () async {
      final g = FakeNative()..unknown = true, store = MemoryLocker();
      final c = nativeCommand(g);
      final out = await DebtNativeFlow(g, store).submit(
        dueUser,
        dueShop,
        dueKey,
        c.body['p_payload'] as Map<String, Object?>,
        canWrite: true,
      );
      expect(out.pending, isNotNull);
      expect(store.stored?.body, c.body);
      g.statusOverride = (c) async => DebtNativeTransport(
        receipt: parseDebtNativeReceipt(nativeReceipt(c)),
      );
      final resumed = await DebtNativeFlow(g, store).reconcile(
        dueUser,
        dueShop,
        store.stored!,
        retry: true,
        canWrite: false,
      );
      expect(resumed.receipt, isNotNull);
      expect(store.stored, isNull);
      expect(g.sent.length, 1);
    },
  );
  test(
    'late token and malformed receipts retain original native command',
    () async {
      for (final change in [false, true]) {
        final g = FakeNative(), store = MemoryLocker();
        g.sendOverride = (c) async {
          if (change) g.session = 'other';
          return DebtNativeTransport(
            receipt: parseDebtNativeReceipt({
              ...nativeReceipt(c),
              'source_id': dueShop,
            }),
          );
        };
        final out = await DebtNativeFlow(g, store).submit(
          dueUser,
          dueShop,
          dueKey,
          parseDebtNativeDetail(g.data).row.payload(null),
          canWrite: true,
        );
        expect(out.pending, isNotNull);
        expect(store.stored, isNotNull);
      }
    },
  );
  test(
    'secure manifest and locker survive restart; unknown foreign bytes preserved',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      final s = const SecureDeviceReminderStore(),
          m = await const SecureDeviceReminderStore().load();
      await s.save(
        DeviceReminderManifest(
          installation: m.installation,
          userId: dueUser,
          shopId: dueShop,
          enabled: true,
        ),
      );
      expect((await const SecureDeviceReminderStore().load()).enabled, isTrue);
      const locker = PendingFinancialCommands();
      final c = nativeCommand(FakeNative());
      await locker.save(dueUser, dueShop, c);
      expect(
        (await const PendingFinancialCommands().read(dueUser, dueShop))!.body,
        c.body,
      );
      await locker.clear(dueUser, dueShop, dueKey);
      const storage = FlutterSecureStorage(),
          raw =
              '{"key":"a4444444-4444-4444-8444-444444444444","kind":"future","body":{"original":true}}';
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
  test(
    'secure tap routes allow old and new tokens for one stable OS ID',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      const s = SecureDeviceReminderStore();
      final a = DeviceReminderRequest(
        id: 0x40000001,
        token: dueKey,
        sourceKind: 'standalone',
        sourceId: dueSourceId,
        fingerprint: dueHash,
        at: DateTime.utc(2026, 10, 14),
      );
      final b = DeviceReminderRequest(
        id: a.id,
        token: dueShop,
        sourceKind: a.sourceKind,
        sourceId: a.sourceId,
        fingerprint: dueHash,
        at: DateTime.utc(2026, 10, 15),
      );
      await s.save(
        DeviceReminderManifest(
          installation: dueKey,
          userId: dueUser,
          shopId: dueShop,
          requests: [b],
          routes: [a, b],
        ),
      );
      final m = await const SecureDeviceReminderStore().load();
      expect(m.routes.length, 2);
      expect(m.requests.single.id, a.id);
      expect(m.routes.map((r) => r.token), [dueKey, dueShop]);
    },
  );
  for (final code in [
    'stale_native',
    'due_date_required',
    'unresolved_wall_time',
    'invalid_time',
  ]) {
    test('HTTP definite native rejection $code is recoverable', () async {
      final gateway = HttpOpeningGateway(
        client: MockClient(
          (r) async => http.Response(jsonEncode({'message': code}), 400),
        ),
        supabaseUrl: 'https://example.supabase.co',
        publishableKey: 'public-test',
        accessToken: () => 'token',
        currentUserId: () => dueUser,
      );
      final store = MemoryLocker(), c = nativeCommand(FakeNative());
      final out = await DebtNativeFlow(gateway, store).submit(
        dueUser,
        dueShop,
        dueKey,
        c.body['p_payload'] as Map<String, Object?>,
        canWrite: true,
      );
      expect(out.error, code);
      expect(out.pending, isNull);
      expect(store.stored, isNull);
    });
  }
  test('HTTP review gap/fold preserves typed error', () async {
    final gateway = HttpOpeningGateway(
      client: MockClient(
        (_) async => http.Response('{"message":"unresolved_wall_time"}', 400),
      ),
      supabaseUrl: 'https://example.supabase.co',
      publishableKey: 'public-test',
      accessToken: () => 'token',
      currentUserId: () => dueUser,
    );
    await expectLater(
      gateway.reviewNative(
        userId: dueUser,
        shopId: dueShop,
        sourceKind: DebtSourceKind.standalone,
        sourceId: dueSourceId,
        time: '01:30',
      ),
      throwsA(
        isA<DebtReadException>().having(
          (e) => e.code,
          'code',
          'unresolved_wall_time',
        ),
      ),
    );
  });
  group('durable device reconciliation', () {
    late FakeNative g;
    late MemoryDeviceStore store;
    late FakeNotificationPort port;
    late FakeReminderClock clock;
    late DebtReminderCoordinator c;
    setUp(() async {
      g = FakeNative();
      store = MemoryDeviceStore();
      port = FakeNotificationPort();
      clock = FakeReminderClock();
      c = DebtReminderCoordinator(
        gateway: g,
        store: store,
        port: port,
        clock: clock,
      );
      await c.bind(dueUser, dueShop);
    });
    test(
      'default disabled no permission; explicit enable registers once, repeat/restart reuses',
      () async {
        expect(port.permissionRequests, 0);
        expect(port.registrations, isEmpty);
        await c.enable();
        expect(port.permissionRequests, 1);
        expect(port.pending.length, 1);
        expect(c.report.state, DeviceReminderState.registered);
        final id = port.pending.single;
        await c.reconcile();
        expect(port.registrations.length, 1);
        c = DebtReminderCoordinator(
          gateway: g,
          store: store,
          port: port,
          clock: clock,
        );
        await c.bind(dueUser, dueShop);
        expect(port.pending.single, id);
        expect(port.registrations.length, 1);
        expect(g.sent, isEmpty);
      },
    );
    for (final permission in [
      ReminderPermission.denied,
      ReminderPermission.unsupported,
    ]) {
      test(
        'permission $permission no schedule, recovery and revoke cancel',
        () async {
          port.allowed = permission;
          await c.enable();
          expect(port.pending, isEmpty);
          expect(
            c.report.state,
            permission == ReminderPermission.denied
                ? DeviceReminderState.permissionDenied
                : DeviceReminderState.unsupported,
          );
          port.allowed = ReminderPermission.allowed;
          await c.reconcile();
          expect(port.pending.length, 1);
          port.allowed = permission;
          await c.reconcile();
          expect(port.pending, isEmpty);
          expect(g.sent, isEmpty);
        },
      );
    }
    test(
      'disable needs no backend or active entitlement and preserves shared date/time',
      () async {
        await c.enable();
        g.error = 'shop_not_active';
        final before = Map.of(g.data);
        await c.disable();
        expect(port.pending, isEmpty);
        expect(c.enabled, isFalse);
        expect(g.data, before);
      },
    );
    test(
      'unknown schedule reply/crash retries same identity without duplicates',
      () async {
        port.replaceOverride = (_) async =>
            throw StateError('timeout-after-OS-write');
        await c.enable();
        final id = port.pending.single;
        expect(c.report.state, DeviceReminderState.failed);
        expect(store.value.requests.single.applied, isFalse);
        port.replaceOverride = null;
        c = DebtReminderCoordinator(
          gateway: g,
          store: store,
          port: port,
          clock: clock,
        );
        await c.bind(dueUser, dueShop);
        expect(port.pending, {id});
        expect(port.registrations.length, 2);
        expect(store.value.requests.single.applied, isTrue);
        expect(g.sent, isEmpty);
      },
    );
    test('unknown cancel persists durable cancellation until retry', () async {
      await c.enable();
      port.cancelOverride = (_) async {};
      await c.disable();
      expect(c.report.state, DeviceReminderState.failed);
      expect(store.value.requests, isNotEmpty);
      port.cancelOverride = null;
      await c.reconcile();
      expect(port.pending, isEmpty);
      expect(store.value.requests, isEmpty);
    });
    test(
      'source removal/full settle/archive/date clear reconciles cancellation',
      () async {
        await c.enable();
        g.rows = [];
        await c.reconcile();
        expect(port.pending, isEmpty);
        expect(store.value.requests, isEmpty);
        expect(g.sent, isEmpty);
      },
    );
    test(
      'date/zone/partial remaining changes replace same identity; reboot loss reregisters once',
      () async {
        await c.enable();
        final id = port.pending.single;
        g.rows = [
          {
            ...nativeFixture(remaining: '9000'),
            'native_freshness': List.filled(64, 'b').join(),
          },
        ];
        await c.reconcile();
        expect(port.pending, {id});
        expect(port.registrations.length, 2);
        port.pending.clear();
        await c.reconcile();
        expect(port.registrations.length, 3);
        await c.reconcile();
        expect(port.registrations.length, 3);
      },
    );
    test(
      'past, invalid DST, horizon, 32 capacity are all explicit without truncation',
      () async {
        g.rows = [
          for (var i = 0; i < 36; i++)
            {
              ...nativeFixture(
                trigger: i == 0
                    ? '2026-10-14T11:00:00Z'
                    : i == 1
                    ? '2026-11-14T12:00:01Z'
                    : '2026-10-14T13:00:00Z',
                valid: i != 2,
              ),
              'source_id':
                  'a3333333-3333-4333-8333-${i.toString().padLeft(12, '0')}',
              'debt_key':
                  'standalone:a3333333-3333-4333-8333-${i.toString().padLeft(12, '0')}',
            },
        ];
        await c.enable();
        expect(port.pending.length, 32);
        expect(c.report.rows.length, 36);
        expect(
          c.report.rows.values
              .where((s) => s == DeviceReminderState.missed)
              .length,
          1,
        );
        expect(
          c.report.rows.values
              .where((s) => s == DeviceReminderState.outsideHorizon)
              .length,
          1,
        );
        expect(
          c.report.rows.values
              .where((s) => s == DeviceReminderState.invalidTime)
              .length,
          1,
        );
        expect(
          c.report.rows.values
              .where((s) => s == DeviceReminderState.capacity)
              .length,
          1,
        );
      },
    );
    test('complete paging stale cursor stops before OS work', () async {
      g.pageOverride = (cursor) async => parseDebtNativePage(
        nativePage(
          [nativeFixture()],
          total: 2,
          cursor: cursor == null ? 'next' : null,
          hash: cursor == null ? dueHash : List.filled(64, 'b').join(),
          offset: cursor == null ? 0 : 1,
        ),
      );
      await c.enable();
      expect(port.registrations, isEmpty);
      expect(c.report.state, DeviceReminderState.stale);
      expect(g.pages, [null, 'next']);
    });
    test('complete 120-source set is read before capacity selection', () async {
      final all = [
        for (var i = 0; i < 120; i++)
          {
            ...nativeFixture(),
            'source_id':
                'a3333333-3333-4333-8333-${i.toString().padLeft(12, '0')}',
          },
      ];
      g.pageOverride = (cursor) async {
        final offset = cursor == null ? 0 : int.parse(cursor),
            end = (offset + 50).clamp(0, all.length);
        return parseDebtNativePage(
          nativePage(
            all.sublist(offset, end),
            offset: offset,
            total: all.length,
            cursor: end == all.length ? null : '$end',
          ),
        );
      };
      await c.enable();
      expect(g.pages, [null, '50', '100', null]);
      expect(c.report.rows.length, 120);
      expect(port.pending.length, 32);
      expect(
        c.report.rows.values
            .where((s) => s == DeviceReminderState.capacity)
            .length,
        88,
      );
    });
    test(
      'strict scheduler contract rejects data fields and missing nullable trigger',
      () {
        final page = nativePage([nativeFixture(valid: false)]),
            entry =
                (nativePage([nativeFixture(valid: false)])['items'] as List)
                        .single
                    as Map;
        final bad = Map<String, Object?>.from(entry)..remove('trigger_at');
        bad['party_name'] = 'private';
        expect(
          () => parseDebtNativePage({
            ...page,
            'items': [bad],
          }),
          throwsFormatException,
        );
      },
    );
    test('delayed snapshot does not advance server time twice', () async {
      g.rows = [nativeFixture(trigger: '2026-10-14T12:00:30Z')];
      g.pageOverride = (cursor) async {
        clock.elapsedTime = const Duration(seconds: 60);
        return parseDebtNativePage(nativePage(g.rows));
      };
      await c.enable();
      expect(port.pending.length, 1);
      expect(c.report.rows.values.single, DeviceReminderState.registered);
    });
    test('device clock mismatch does not change server due status', () async {
      clock.now = clock.now.add(const Duration(hours: 1));
      await c.enable();
      expect(c.report.state, DeviceReminderState.clockMismatch);
      expect(port.pending, isEmpty);
      expect(g.data['due_state'], 'today');
    });
    test(
      'fired notification tap survives missed cleanup and requires fresh source read',
      () async {
        await c.enable();
        final token = store.value.requests.single.token;
        g.rows = [];
        await c.reconcile();
        expect(store.value.requests, isEmpty);
        expect(store.value.routes.single.token, token);
        port.tap!(token);
        await c
            .dismissTap(); // Drain tap callback, then set again to exercise persisted route.
        port.tap!(token);
        await c.reconcile();
        final detail = await c.readTap();
        expect(detail, isNotNull);
        expect(g.detailReads, 1);
        await c.bind(null, null);
        expect(await c.readTap(), isNull);
        expect(store.value.routes, isEmpty);
      },
    );
    test('account change during OS reply cancels late registration', () async {
      final started = Completer<void>(), release = Completer<void>();
      port.replaceOverride = (_) async {
        started.complete();
        await release.future;
      };
      final enabling = c.enable();
      await started.future;
      final logout = c.bind(null, null);
      release.complete();
      await enabling;
      await logout;
      expect(port.pending, isEmpty);
      expect(store.value.enabled, isFalse);
      expect(store.value.requests, isEmpty);
    });
    test(
      'offline stale data retains generic existing request; revoked read cancels',
      () async {
        await c.enable();
        g.error = 'read';
        await c.reconcile();
        expect(c.report.state, DeviceReminderState.stale);
        expect(port.pending.length, 1);
        g.error = 'forbidden';
        await c.reconcile();
        expect(port.pending, isEmpty);
      },
    );
  });
}
