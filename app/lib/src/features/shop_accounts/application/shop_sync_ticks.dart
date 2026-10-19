import 'package:flutter/foundation.dart';

import '../domain/shop_sync.dart';

/// Notifies open routes of coalesced shop invalidations without rebuilding
/// the navigator stack or wiping edit drafts.
class ShopSyncTicks extends ChangeNotifier {
  int ledger = 0;
  int inventory = 0;
  int trader = 0;
  int invoice = 0;
  int repair = 0;
  int debt = 0;
  int customer = 0;
  int appearance = 0;
  int message = 0;
  final _appearanceSettings = ChangeNotifier();
  final _messageSettings = ChangeNotifier();
  Listenable get appearanceSettings => _appearanceSettings;
  Listenable get messageSettings => _messageSettings;

  @override
  void dispose() {
    _appearanceSettings.dispose();
    _messageSettings.dispose();
    super.dispose();
  }

  void apply(Set<ShopSyncScope> scopes) {
    var changed = false;
    if (scopes.contains(ShopSyncScope.ledger) ||
        scopes.contains(ShopSyncScope.day)) {
      ledger++;
      changed = true;
    }
    if (scopes.contains(ShopSyncScope.inventory) ||
        scopes.contains(ShopSyncScope.ledger)) {
      inventory++;
      changed = true;
    }
    if (scopes.contains(ShopSyncScope.trader) ||
        scopes.contains(ShopSyncScope.ledger)) {
      trader++;
      changed = true;
    }
    if (scopes.contains(ShopSyncScope.invoice) ||
        scopes.contains(ShopSyncScope.ledger) ||
        scopes.contains(ShopSyncScope.day)) {
      invoice++;
      changed = true;
    }
    if (scopes.contains(ShopSyncScope.repair) ||
        scopes.contains(ShopSyncScope.ledger) ||
        scopes.contains(ShopSyncScope.day) ||
        scopes.contains(ShopSyncScope.subscription) ||
        scopes.contains(ShopSyncScope.location)) {
      repair++;
      changed = true;
    }
    if (scopes.contains(ShopSyncScope.debt) ||
        scopes.contains(ShopSyncScope.ledger) ||
        scopes.contains(ShopSyncScope.inventory) ||
        scopes.contains(ShopSyncScope.trader) ||
        scopes.contains(ShopSyncScope.location) ||
        scopes.contains(ShopSyncScope.subscription)) {
      debt++;
      changed = true;
    }
    if (scopes.contains(ShopSyncScope.customer) ||
        scopes.contains(ShopSyncScope.ledger) ||
        scopes.contains(ShopSyncScope.location) ||
        scopes.contains(ShopSyncScope.subscription)) {
      customer++;
      changed = true;
    }
    if (scopes.contains(ShopSyncScope.appearance)) {
      appearance++;
      changed = true;
    }
    if (scopes.contains(ShopSyncScope.message)) {
      message++;
      changed = true;
    }
    final access =
        scopes.contains(ShopSyncScope.subscription) ||
        scopes.contains(ShopSyncScope.location);
    if (access || scopes.contains(ShopSyncScope.appearance)) {
      _appearanceSettings.notifyListeners();
    }
    if (access || scopes.contains(ShopSyncScope.message)) {
      _messageSettings.notifyListeners();
    }
    if (changed) notifyListeners();
  }
}
