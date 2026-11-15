import '../../shop_accounts/domain/shop_account.dart';

/// Which ledger controls a member may use (ADR 0033). The server enforces
/// every grant; this only keeps the screen from offering what it would refuse.
class LedgerControlAccess {
  const LedgerControlAccess._(this._shop);

  factory LedgerControlAccess.of(ShopAccount shop) =>
      LedgerControlAccess._(shop);

  final ShopAccount _shop;

  bool get sale => _shop.hasPermission(ShopPermission.sale);
  bool get purchase => _shop.hasPermission(ShopPermission.purchase);
  bool get expense => _shop.hasPermission(ShopPermission.expense);

  /// Scrap sales are sales on the server.
  bool get scrapSale => sale;

  /// Customer returns are posted under the sale grant.
  bool get customerReturn => sale;

  /// Moving cash between methods needs the shop's balances, which an
  /// employee never receives.
  bool get cashTransfer => expense && !_shop.isEmployee;

  /// Scrap-to-stock needs the scrap balances, which an employee never receives.
  bool get scrapToStock =>
      _shop.hasPermission(ShopPermission.inventory) && !_shop.isEmployee;

  /// Opening and closing the financial day stay with the owner.
  bool get openDay => _shop.isOwner;
  bool get closeDay => _shop.isOwner;

  bool get pendingInvoices => _shop.hasPermission(ShopPermission.invoiceSend);
  bool get sendInvoice => _shop.hasPermission(ShopPermission.invoiceSend);
  bool get archive => _shop.hasPermission(ShopPermission.reports);

  /// Daily notes stay owner-only.
  bool get dailyNotes => _shop.isOwner;

  /// Employees see their own operations and totals, never the shop's cash.
  bool get hidesShopBalances => _shop.isEmployee;
}
