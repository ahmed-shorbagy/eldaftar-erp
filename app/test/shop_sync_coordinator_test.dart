import 'dart:async';

import 'package:eldafttar/src/features/shop_accounts/application/shop_sync_coordinator.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_sync.dart';
import 'package:flutter_test/flutter_test.dart';

class MemorySyncGateway implements ShopSyncGateway {
  MemorySyncGateway(this.initial);
  ShopSyncSnapshot? initial;
  final controllers = <StreamController<ShopSyncSnapshot>>[];
  var closes = 0;
  var reads = 0;

  @override
  Stream<ShopSyncSnapshot> watch({
    required String shopId,
    required String userId,
  }) {
    final controller = StreamController<ShopSyncSnapshot>.broadcast();
    controllers.add(controller);
    return controller.stream;
  }

  @override
  Future<ShopSyncSnapshot?> read({required String shopId}) async {
    reads++;
    return initial;
  }

  @override
  Future<void> close() async {
    closes++;
    for (final controller in controllers) {
      await controller.close();
    }
  }

  void emit(ShopSyncSnapshot snapshot) {
    for (final controller in controllers) {
      if (!controller.isClosed) controller.add(snapshot);
    }
  }
}

ShopSyncSnapshot snap({
  int revision = 1,
  int ledger = 0,
  int inventory = 0,
  int trader = 0,
  int invoice = 0,
  int subscription = 0,
}) => ShopSyncSnapshot(
  shopId: 'shop-1',
  revision: revision,
  ledgerRevision: ledger,
  inventoryRevision: inventory,
  traderRevision: trader,
  invoiceRevision: invoice,
  subscriptionRevision: subscription,
);

void main() {
  test('initial catch-up refreshes all authoritative scopes', () async {
    final gateway = MemorySyncGateway(snap());
    final seen = <Set<ShopSyncScope>>[];
    final coordinator = ShopSyncCoordinator(
      gateway: gateway,
      shopId: 'shop-1',
      userId: 'user-1',
      onInvalidate: (scopes) async => seen.add(scopes),
      pollInterval: const Duration(days: 1),
      coalesceWindow: const Duration(milliseconds: 20),
    );
    await coordinator.start();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(seen, hasLength(1));
    expect(seen.single, unorderedEquals(ShopSyncScope.values));
    await coordinator.dispose();
  });

  test('coalesces rapid events and ignores older revisions', () async {
    final gateway = MemorySyncGateway(snap());
    final seen = <Set<ShopSyncScope>>[];
    final coordinator = ShopSyncCoordinator(
      gateway: gateway,
      shopId: 'shop-1',
      userId: 'user-1',
      onInvalidate: (scopes) async {
        seen.add(Set<ShopSyncScope>.from(scopes));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      },
      pollInterval: const Duration(days: 1),
      coalesceWindow: const Duration(milliseconds: 20),
    );
    await coordinator.start();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    seen.clear();
    gateway.emit(snap(revision: 2, ledger: 1, inventory: 1));
    gateway.emit(snap(revision: 3, ledger: 1, inventory: 1, trader: 1));
    gateway.emit(snap(revision: 2, ledger: 1));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(seen, hasLength(1));
    expect(
      seen.single,
      containsAll([
        ShopSyncScope.ledger,
        ShopSyncScope.inventory,
        ShopSyncScope.trader,
      ]),
    );
    await coordinator.dispose();
  });

  test('failed invalidation is requeued without an unhandled timer', () async {
    final gateway = MemorySyncGateway(snap());
    var attempts = 0;
    final coordinator = ShopSyncCoordinator(
      gateway: gateway,
      shopId: 'shop-1',
      userId: 'user-1',
      onInvalidate: (scopes) async {
        attempts++;
        if (attempts == 2) throw StateError('refresh failed');
      },
      pollInterval: const Duration(days: 1),
      coalesceWindow: const Duration(milliseconds: 20),
    );
    await coordinator.start();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(attempts, 1);
    gateway.emit(snap(revision: 2, ledger: 1));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(attempts, 2);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(attempts, 2);
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(attempts, 3);
    await coordinator.dispose();
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(attempts, 3);
  });
}
