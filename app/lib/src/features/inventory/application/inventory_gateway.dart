import '../../daily_ledger/application/financial_gateway.dart';
import '../../daily_ledger/application/opening_gateway.dart';
import '../../daily_ledger/application/pending_financial_command.dart';
import '../domain/inventory_models.dart';

class InventoryReadException implements Exception {
  const InventoryReadException([this.code]);
  final String? code;

  @override
  String toString() => 'InventoryReadException($code)';
}

final class InventoryBucket {
  const InventoryBucket({
    required this.category,
    required this.karat,
    required this.quantities,
  });

  final String category;
  final int karat;
  final QuantityTriple quantities;
}

final class InventoryTotals {
  const InventoryTotals(this.buckets);
  final List<InventoryBucket> buckets;
}

final class LotPage {
  const LotPage(this.items, this.nextCursor);
  final List<LotSnapshot> items;
  final String? nextCursor;
}

final class MovementLine {
  const MovementLine({
    required this.id,
    required this.deltaMilligrams,
    required this.deltaCount,
    required this.movementKind,
    required this.allocationMode,
    required this.operationId,
    required this.operationKind,
    required this.createdAt,
    required this.cursor,
  });

  final String id;
  final BigInt deltaMilligrams;
  final BigInt deltaCount;
  final String movementKind;
  final String allocationMode;
  final String? operationId;
  final String? operationKind;
  final String createdAt;
  final String cursor;
}

final class MovementPage {
  const MovementPage(this.items, this.nextCursor);
  final List<MovementLine> items;
  final String? nextCursor;
}

final class TraderSummary {
  const TraderSummary({
    required this.id,
    required this.displayName,
    required this.phone,
    required this.active,
    required this.createdAt,
    required this.cursor,
  });

  final String id;
  final String displayName;
  final String phone;
  final bool active;
  final String createdAt;
  final String cursor;
}

final class TraderPage {
  const TraderPage(this.items, this.nextCursor);
  final List<TraderSummary> items;
  final String? nextCursor;
}

final class TraderHolding {
  const TraderHolding({
    required this.category,
    required this.karat,
    required this.originalMilligrams,
    required this.originalCount,
    required this.currentMilligrams,
    required this.currentCount,
    required this.pendingReceiptCount,
  });

  final String category;
  final int karat;
  final BigInt originalMilligrams;
  final BigInt? originalCount;
  final BigInt currentMilligrams;
  final BigInt? currentCount;
  final BigInt pendingReceiptCount;
}

final class TraderDetail {
  const TraderDetail({
    required this.id,
    required this.displayName,
    required this.phone,
    required this.note,
    required this.active,
    required this.createdAt,
    required this.originalHeldMilligrams,
    required this.currentHeldMilligrams,
    required this.pendingReceiptCount,
    required this.cashPayableRemainingPiastres,
    required this.goldRemaining,
    required this.buckets,
  });

  final String id;
  final String displayName;
  final String phone;
  final String note;
  final bool active;
  final String createdAt;
  final BigInt originalHeldMilligrams;
  final BigInt currentHeldMilligrams;
  final BigInt pendingReceiptCount;
  final BigInt cashPayableRemainingPiastres;
  final List<TraderGoldBalance> goldRemaining;
  final List<TraderHolding> buckets;
}

final class TraderGoldBalance {
  const TraderGoldBalance({
    required this.karat,
    required this.initialMilligrams,
    required this.remainingMilligrams,
  });

  final int karat;
  final BigInt initialMilligrams;
  final BigInt remainingMilligrams;
}

final class TraderActivity {
  const TraderActivity({
    required this.operationId,
    required this.kind,
    required this.shopSequence,
    required this.receiptId,
    required this.createdAt,
    required this.cursor,
  });

  final String operationId;
  final String kind;
  final String shopSequence;
  final String? receiptId;
  final String createdAt;
  final String cursor;
}

final class TraderActivityPage {
  const TraderActivityPage(this.items, this.nextCursor);
  final List<TraderActivity> items;
  final String? nextCursor;
}

final class CatalogProduct {
  const CatalogProduct({
    required this.id,
    required this.name,
    required this.category,
    required this.karat,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String category;
  final int karat;
  final String createdAt;
}

final class CatalogDenomination {
  const CatalogDenomination({
    required this.id,
    required this.label,
    required this.nominalMilligrams,
    required this.active,
    required this.createdAt,
  });

  final String id;
  final String label;
  final BigInt nominalMilligrams;
  final bool active;
  final String createdAt;
}

final class CatalogCoin {
  const CatalogCoin({
    required this.id,
    required this.label,
    required this.nominalMilligrams,
    required this.active,
    required this.createdAt,
  });

  final String id;
  final String label;
  final BigInt? nominalMilligrams;
  final bool active;
  final String createdAt;
}

final class GoldObligationView {
  const GoldObligationView({
    required this.operationId,
    required this.traderId,
    required this.karat,
    required this.initialMilligrams,
    required this.remainingMilligrams,
    required this.createdAt,
    required this.cursor,
  });

  final String operationId;
  final String? traderId;
  final int karat;
  final BigInt initialMilligrams;
  final BigInt remainingMilligrams;
  final String createdAt;
  final String cursor;
}

final class TraderObligation {
  const TraderObligation({
    required this.operationId,
    required this.unit,
    required this.karat,
    required this.original,
    required this.remaining,
    required this.createdAt,
    required this.cursor,
  });

  final String operationId;
  final String unit;
  final int? karat;
  final BigInt original;
  final BigInt remaining;
  final String createdAt;
  final String cursor;
}

/// A page that says whether the source exists. A full page keeps [nextCursor].
final class ReadPage<T> {
  const ReadPage.missing() : items = null, nextCursor = null;
  const ReadPage.ready(List<T> this.items, this.nextCursor);

  final List<T>? items;
  final String? nextCursor;
  bool get available => items != null;
}

final class ReceiptPage {
  const ReceiptPage.missing() : items = null, nextCursor = null;
  const ReceiptPage.ready(List<ReceiptSnapshot> this.items, this.nextCursor);

  final List<ReceiptSnapshot>? items;
  final String? nextCursor;
  bool get available => items != null;
}

abstract class InventoryGateway {
  Future<InventoryTotals> totals({
    required String callerUserId,
    String? category,
    int? karat,
  });

  Future<LotPage> lots({
    required String callerUserId,
    String? category,
    int? karat,
    String? stockClass,
    String? query,
    String? cursor,
  });

  Future<MovementPage> movements({
    required String callerUserId,
    required String lotId,
    String? cursor,
  });

  Future<TraderPage> traders({
    required String callerUserId,
    String? query,
    String? cursor,
  });

  Future<TraderDetail> trader({
    required String callerUserId,
    required String traderId,
  });

  Future<TraderActivityPage> traderActivity({
    required String callerUserId,
    required String traderId,
    String? cursor,
  });

  Future<ReceiptPage> receipts({
    required String callerUserId,
    String? ownerKind,
    String? traderId,
    String? recognition,
    String? cursor,
  });

  Future<ReadPage<CatalogProduct>> products({
    required String callerUserId,
    String? query,
    String? cursor,
  });

  Future<ReadPage<CatalogDenomination>> denominations({
    required String callerUserId,
    String? query,
    String? cursor,
  });

  Future<ReadPage<CatalogCoin>> coins({
    required String callerUserId,
    String? query,
    String? cursor,
  });

  Future<ReadPage<GoldObligationView>> goldObligations({
    required String callerUserId,
    String? cursor,
  });

  Future<ReadPage<TraderObligation>> traderObligations({
    required String callerUserId,
    required String traderId,
    String? unit,
    String? cursor,
  });

  /// Catalog idempotency lives in inventory_catalog_requests, not opening status.
  Future<StatusResult> catalogStatus({
    required String callerUserId,
    required String idempotencyKey,
  });

  /// Posts the stored envelope unchanged.
  Future<FinancialCommandResult> postStored({
    required String callerUserId,
    required PendingFinancialCommand command,
  });
}
