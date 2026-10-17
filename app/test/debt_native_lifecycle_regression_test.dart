import 'dart:async';
import 'package:eldafttar/src/features/debts/application/debt_reminder_coordinator.dart';
import 'package:eldafttar/src/features/debts/application/debt_reminder_device.dart';
import 'package:eldafttar/src/features/debts/data/debt_native_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'debt_due_fixtures.dart';
import 'debt_native_fixtures.dart';

void main() {
  group('native reminder lifecycle regressions', () {
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
      'cold restart tap uses persisted route after fired request left pending',
      () async {
        await c.enable();
        final token = store.value.requests.single.token;
        g.rows = [nativeFixture(trigger: '2026-10-14T11:00:00Z')];
        await c.reconcile();
        expect(port.pending, isEmpty);
        expect(store.value.requests, isEmpty);
        c = DebtReminderCoordinator(
          gateway: g,
          store: store,
          port: port,
          clock: clock,
        );
        await c.bind(dueUser, dueShop);
        expect(port.pending, isEmpty);
        expect(g.detailReads, 0);
        port.tap!(token);
        await c.reconcile();
        final detail = await c.readTap();
        expect(detail, isNotNull);
        expect(detail!.row.due.shopId, dueShop);
        expect(detail.row.due.summary.sourceId, dueSourceId);
        expect(g.detailReads, 1);
        expect(g.sent, isEmpty);
      },
    );

    test(
      'late tap source read after account and token change is discarded',
      () async {
        await c.enable();
        port.tap!(store.value.requests.single.token);
        await c.reconcile();
        final started = Completer<void>(), release = Completer<void>();
        g.readOverride = () async {
          started.complete();
          await release.future;
          return parseDebtNativeDetail(g.data);
        };
        final reading = c.readTap();
        await started.future;
        g.session = 'rotated';
        final changing = c.bind(dueShop, dueKey);
        release.complete();
        expect(await reading, isNull);
        await changing;
        expect(await c.readTap(), isNull);
        expect(g.sent, isEmpty);
      },
    );

    test(
      'durable write failure before OS registration never registers and retries',
      () async {
        g.rows = [];
        await c.enable();
        expect(port.registrations, isEmpty);
        expect(port.permissionRequests, 1);
        g.rows = [nativeFixture()];
        store.failure = StateError('durable_write');
        await c.reconcile();
        expect(port.registrations, isEmpty);
        expect(port.pending, isEmpty);
        expect(c.report.state, DeviceReminderState.failed);
        expect(store.value.requests, isEmpty);
        expect(g.sent, isEmpty);
        store.failure = null;
        await c.reconcile();
        expect(port.pending.length, 1);
        expect(c.report.state, DeviceReminderState.registered);
        expect(port.permissionRequests, 1);
        expect(g.sent, isEmpty);
      },
    );

    test(
      'restart after failed cancellation retries removal without enable or metadata',
      () async {
        await c.enable();
        expect(port.permissionRequests, 1);
        expect(port.pending, isNotEmpty);
        port.cancelOverride = (_) async {};
        await c.disable();
        expect(c.report.state, DeviceReminderState.failed);
        expect(c.enabled, isFalse);
        expect(store.value.requests, isNotEmpty);
        expect(port.pending, isNotEmpty);
        expect(g.sent, isEmpty);
        port.cancelOverride = null;
        c = DebtReminderCoordinator(
          gateway: g,
          store: store,
          port: port,
          clock: clock,
        );
        await c.bind(dueUser, dueShop);
        expect(c.enabled, isFalse);
        expect(port.pending, isEmpty);
        expect(store.value.requests, isEmpty);
        expect(port.permissionRequests, 1);
        expect(g.sent, isEmpty);
      },
    );
  });
}
