/// Session-scoped shop invalidation. Domain stays independent of Supabase.
enum ShopSyncScope {
  ledger,
  inventory,
  trader,
  invoice,
  day,
  location,
  subscription,
  repair,
}

class ShopSyncSnapshot {
  const ShopSyncSnapshot({
    required this.shopId,
    required this.revision,
    this.ledgerRevision = 0,
    this.inventoryRevision = 0,
    this.traderRevision = 0,
    this.invoiceRevision = 0,
    this.dayRevision = 0,
    this.locationRevision = 0,
    this.subscriptionRevision = 0,
    this.repairRevision = 0,
    this.forceRefresh = false,
  });

  final String shopId;
  final int revision;
  final int ledgerRevision;
  final int inventoryRevision;
  final int traderRevision;
  final int invoiceRevision;
  final int dayRevision;
  final int locationRevision;
  final int subscriptionRevision;
  final int repairRevision;

  /// Connection recovery requests an authoritative read even at the same revision.
  final bool forceRefresh;

  ShopSyncSnapshot asCatchUp() => ShopSyncSnapshot(
    shopId: shopId,
    revision: revision,
    ledgerRevision: ledgerRevision,
    inventoryRevision: inventoryRevision,
    traderRevision: traderRevision,
    invoiceRevision: invoiceRevision,
    dayRevision: dayRevision,
    locationRevision: locationRevision,
    subscriptionRevision: subscriptionRevision,
    repairRevision: repairRevision,
    forceRefresh: true,
  );

  Set<ShopSyncScope> changedFrom(ShopSyncSnapshot? previous) {
    if (previous == null || previous.shopId != shopId) {
      return ShopSyncScope.values.toSet();
    }
    final scopes = <ShopSyncScope>{};
    if (ledgerRevision != previous.ledgerRevision) {
      scopes.add(ShopSyncScope.ledger);
    }
    if (inventoryRevision != previous.inventoryRevision) {
      scopes.add(ShopSyncScope.inventory);
    }
    if (traderRevision != previous.traderRevision) {
      scopes.add(ShopSyncScope.trader);
    }
    if (invoiceRevision != previous.invoiceRevision) {
      scopes.add(ShopSyncScope.invoice);
    }
    if (dayRevision != previous.dayRevision) {
      scopes.add(ShopSyncScope.day);
    }
    if (locationRevision != previous.locationRevision) {
      scopes.add(ShopSyncScope.location);
    }
    if (subscriptionRevision != previous.subscriptionRevision) {
      scopes.add(ShopSyncScope.subscription);
    }
    if (repairRevision != previous.repairRevision) {
      scopes.add(ShopSyncScope.repair);
    }
    if (scopes.isEmpty && revision != previous.revision) {
      return ShopSyncScope.values.toSet();
    }
    return scopes;
  }
}

/// Watches RLS-protected revision rows and refetches authoritative snapshots
/// after reconnect. Implementations live in the data layer. Each [watch]
/// owns its channel; cancelling the stream closes only that subscription.
abstract class ShopSyncGateway {
  Stream<ShopSyncSnapshot> watch({
    required String shopId,
    required String userId,
  });

  Future<ShopSyncSnapshot?> read({required String shopId});

  Future<void> close();
}
