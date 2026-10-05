import '../domain/opening_issue.dart';
import '../domain/postgres_integer.dart';
import '../domain/quantities.dart';

/// Server read model. Quantities stay the strings the server sent.
final class DailyLedgerView {
  const DailyLedgerView({
    required this.state,
    required this.entitlementStatus,
    required this.canConfirm,
    required this.businessDay,
    required this.cash,
    required this.stock,
    required this.scrap,
    required this.feed,
    this.daySummary,
    this.feedCursor,
  });

  final String state;
  final String entitlementStatus;
  final bool canConfirm;
  final LedgerBusinessDay? businessDay;
  final List<LedgerCashLine> cash;
  final List<LedgerStockLine> stock;
  final List<LedgerScrapLine> scrap;
  final List<LedgerFeedLine> feed;
  final LedgerDaySummary? daySummary;
  final LedgerFeedCursor? feedCursor;

  bool get isConfirmed => state == 'confirmed';
  bool get isUninitialized => state == 'uninitialized';

  /// Overall confirmed cash, calculated exactly from the four server balances.
  String? get totalCashPounds {
    if (!isConfirmed) return null;
    final values = <BigInt>[];
    for (final line in cash) {
      final parsed = Piastres.parseWire(line.piastres);
      if (parsed is! Accepted<Piastres>) return null;
      values.add(parsed.value.value);
    }
    final total = PostgresInteger.checkedSum(values);
    if (total == null) return null;
    final parsedTotal = Piastres.parseWire(total.toString());
    return parsedTotal is Accepted<Piastres>
        ? parsedTotal.value.poundsText
        : null;
  }
}

final class LedgerDaySummary {
  const LedgerDaySummary({
    required this.salePiastres,
    required this.purchasePiastres,
    required this.expensePiastres,
    required this.saleCount,
    required this.purchaseCount,
    required this.expenseCount,
    this.goldByBucket = const [],
  });

  final String salePiastres;
  final String purchasePiastres;
  final String expensePiastres;
  final int saleCount;
  final int purchaseCount;
  final int expenseCount;
  final List<LedgerGoldMovement> goldByBucket;

  BigInt goldMilligrams({required String kind, required int karat}) =>
      goldByBucket
          .where((line) => line.kind == kind && line.karat == karat)
          .fold(
            BigInt.zero,
            (sum, line) => sum + BigInt.parse(line.milligrams),
          );
}

final class LedgerGoldMovement {
  const LedgerGoldMovement({
    required this.kind,
    required this.category,
    required this.karat,
    required this.milligrams,
    required this.count,
  });
  final String kind;
  final String category;
  final int karat;
  final String milligrams;
  final String count;
}

final class LedgerBusinessDay {
  const LedgerBusinessDay({
    required this.id,
    required this.businessDate,
    required this.openedAt,
  });

  final String id;
  final String businessDate;
  final String openedAt;
}

final class LedgerCashLine {
  const LedgerCashLine({
    required this.method,
    required this.labelAr,
    required this.piastres,
    required this.pounds,
  });

  final String method;
  final String labelAr;
  final String piastres;
  final String pounds;
}

final class LedgerStockLine {
  const LedgerStockLine({
    required this.category,
    required this.labelAr,
    required this.karat,
    required this.milligrams,
    required this.grams,
    required this.count,
  });

  final String category;
  final String labelAr;
  final int karat;
  final String milligrams;
  final String grams;
  final String count;
}

final class LedgerScrapLine {
  const LedgerScrapLine({
    required this.karat,
    required this.labelAr,
    required this.milligrams,
    required this.grams,
  });

  final int karat;
  final String labelAr;
  final String milligrams;
  final String grams;
}

final class LedgerFeedCursor {
  const LedgerFeedCursor({
    required this.limit,
    required this.hasMore,
    required this.direction,
    required this.serverSequence,
    required this.snapshotSequence,
    this.nextBeforeSequence,
  });

  final int limit;
  final bool hasMore;
  final String direction;
  final String serverSequence;
  final String snapshotSequence;
  final String? nextBeforeSequence;
}

final class LedgerFeedLine {
  const LedgerFeedLine({
    required this.kind,
    required this.labelAr,
    required this.operationId,
    required this.actorDisplayName,
    required this.occurredAt,
    required this.occurredAtCairo,
    this.occurredAtShop,
    this.hasNote = false,
    this.shopSequence,
    this.isDailyNote = false,
    this.isReturn = false,
    this.partyName,
    this.totalPounds,
    this.weightGrams,
    this.karat,
    this.paymentLabel,
    this.itemSummary,
    this.pieceCount,
  });

  final String kind;
  final String labelAr;
  final String operationId;
  final String actorDisplayName;
  final String occurredAt;
  final String occurredAtCairo;
  final String? occurredAtShop;
  final bool hasNote;
  final String? shopSequence;
  final bool isDailyNote;
  final bool isReturn;
  final String? partyName;
  final String? totalPounds;
  final String? weightGrams;
  final int? karat;
  final String? paymentLabel;
  final String? itemSummary;
  final String? pieceCount;

  String get displayTime => occurredAtShop ?? occurredAtCairo;
}
