import 'dart:async';
import 'package:eldafttar/src/features/shop_accounts/application/shop_sync_coordinator.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account_gateway.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_sync.dart';
import 'package:eldafttar/src/features/shop_accounts/presentation/shop_accounts_gate.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _shop = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const _owner = '11111111-1111-4111-8111-111111111111';

class _Sync implements ShopSyncGateway {
  final events = StreamController<ShopSyncSnapshot>.broadcast();
  @override
  Stream<ShopSyncSnapshot> watch({
    required String shopId,
    required String userId,
  }) => events.stream;
  @override
  Future<ShopSyncSnapshot?> read({required String shopId}) async =>
      ShopSyncSnapshot(shopId: shopId, revision: 1);
  @override
  Future<void> close() async {
    await events.close();
  }
}

class _Accounts implements ShopAccountGateway {
  _Accounts({this.id = _shop});
  final String id;
  String name = 'متجر الاختبار';
  @override
  Future<List<ShopAccount>> listMyShopAccounts() async => [
    ShopAccount(
      id: id,
      name: name,
      role: 'owner',
      entitlement: ShopEntitlement.active,
    ),
  ];

  @override
  Future<List<SubscriptionNotice>> listMySubscriptionNotices() async =>
      const [];

  @override
  Future<void> dismissSubscriptionNotice({
    required String shopId,
    required SubscriptionNoticeKind kind,
    required DateTime expiresAt,
  }) async {}

  @override
  Future<SubscriptionActivationResult> activateSubscription({
    required String requestKey,
    required String code,
    required String shopId,
  }) async => throw const SubscriptionActivationException(
    SubscriptionActivationFailure.unavailable,
  );
}

void main() {
  testWidgets('initial catch-up preserves revisions received during refresh', (
    tester,
  ) async {
    final gateway = _Sync();
    final first = Completer<void>();
    var calls = 0;
    final coordinator = ShopSyncCoordinator(
      gateway: gateway,
      shopId: _shop,
      userId: _owner,
      pollInterval: const Duration(days: 1),
      onInvalidate: (_) async {
        calls++;
        if (calls == 1) await first.future;
      },
    );
    await coordinator.start();
    await tester.pump(const Duration(milliseconds: 121));
    expect(
      calls,
      1,
      reason: 'The initial read closes the startup observation gap.',
    );
    gateway.events.add(
      const ShopSyncSnapshot(shopId: _shop, revision: 2, ledgerRevision: 1),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 121));
    expect(calls, 1);
    first.complete();
    await tester.pump();
    expect(calls, 2, reason: 'An in-flight revision needs a follow-up read.');
    gateway.events.add(const ShopSyncSnapshot(shopId: _shop, revision: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 121));
    expect(
      calls,
      2,
      reason: 'Stale revisions cannot restart a completed refresh.',
    );
    await tester.runAsync(() async {
      await coordinator.dispose();
      await gateway.close();
    });
  });
  testWidgets('failed refresh retries with a delay and stops after disposal', (
    tester,
  ) async {
    final gateway = _Sync();
    var calls = 0;
    final coordinator = ShopSyncCoordinator(
      gateway: gateway,
      shopId: _shop,
      userId: _owner,
      pollInterval: const Duration(days: 1),
      onInvalidate: (_) async {
        calls++;
        if (calls < 20) throw StateError('offline');
      },
    );
    await coordinator.start();
    await tester.pump(const Duration(milliseconds: 121));
    expect(calls, 1);
    await tester.pump(const Duration(milliseconds: 500));
    expect(calls, 1, reason: 'Failure must not spin immediate requests.');
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 2);
    await tester.runAsync(coordinator.dispose);
    await tester.pump(const Duration(seconds: 10));
    expect(calls, 2);
    await tester.runAsync(gateway.close);
  });
  testWidgets(
    'ordinary account refresh preserves later live metadata updates',
    (tester) async {
      final gateway = _Sync();
      final accounts = _Accounts();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: ShopAccountsGate(
              gateway: accounts,
              syncGateway: gateway,
              currentUserId: () => _owner,
              onSignOut: () async {},
              onToggleTheme: (_) async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 121));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      accounts.name = 'متجر بعد المزامنة';
      gateway.events.add(
        const ShopSyncSnapshot(shopId: _shop, revision: 2, locationRevision: 1),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 121));
      await tester.pump();
      expect(find.textContaining('أهلاً متجر بعد المزامنة'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      if (!gateway.events.isClosed) await tester.runAsync(gateway.close);
    },
  );
  testWidgets(
    'reconnect catches up unchanged revisions without lowering the observed head',
    (tester) async {
      final gateway = _Sync();
      var calls = 0;
      final coordinator = ShopSyncCoordinator(
        gateway: gateway,
        shopId: _shop,
        userId: _owner,
        pollInterval: const Duration(days: 1),
        onInvalidate: (_) async {
          calls++;
        },
      );
      await coordinator.start();
      await tester.pump(const Duration(milliseconds: 121));
      expect(calls, 1);
      gateway.events.add(
        const ShopSyncSnapshot(shopId: _shop, revision: 1).asCatchUp(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 121));
      expect(
        calls,
        2,
        reason: 'Reconnect must refetch even if the revision did not change.',
      );
      gateway.events.add(
        const ShopSyncSnapshot(shopId: _shop, revision: 0).asCatchUp(),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 121));
      expect(calls, 3);
      gateway.events.add(const ShopSyncSnapshot(shopId: _shop, revision: 1));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 121));
      expect(
        calls,
        3,
        reason: 'A stale catch-up snapshot cannot lower the observed head.',
      );
      await tester.runAsync(() async {
        await coordinator.dispose();
        await gateway.close();
      });
    },
  );
  testWidgets(
    'replacing an owner does not close the next owner shared sync gateway',
    (tester) async {
      final gateway = _Sync();
      var owner = _owner;
      final first = _Accounts();
      final next = _Accounts(id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')
        ..name = 'متجر المالك الثاني';
      Widget host(_Accounts accounts) => MaterialApp(
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ShopAccountsGate(
            key: ValueKey(owner),
            gateway: accounts,
            syncGateway: gateway,
            currentUserId: () => owner,
            onSignOut: () async {},
            onToggleTheme: (_) async {},
          ),
        ),
      );
      await tester.pumpWidget(host(first));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 121));
      await tester.pump();
      owner = '22222222-2222-4222-8222-222222222222';
      await tester.pumpWidget(host(next));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 121));
      await tester.pump();
      expect(find.textContaining('أهلاً متجر المالك الثاني'), findsWidgets);
      next.name = 'متجر المالك الثاني بعد المزامنة';
      gateway.events.add(
        ShopSyncSnapshot(shopId: next.id, revision: 2, locationRevision: 1),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 121));
      await tester.pump();
      expect(
        find.textContaining('أهلاً متجر المالك الثاني بعد المزامنة'),
        findsWidgets,
      );
      expect(find.textContaining('أهلاً متجر الاختبار'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(gateway.close);
    },
  );
}
