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
  });

  final String state;
  final String entitlementStatus;
  final bool canConfirm;
  final LedgerBusinessDay? businessDay;
  final List<LedgerCashLine> cash;
  final List<LedgerStockLine> stock;
  final List<LedgerScrapLine> scrap;
  final List<LedgerFeedLine> feed;

  bool get isConfirmed => state == 'confirmed';
  bool get isUninitialized => state == 'uninitialized';
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

final class LedgerFeedLine {
  const LedgerFeedLine({
    required this.kind,
    required this.labelAr,
    required this.operationId,
    required this.actorDisplayName,
    required this.occurredAt,
    required this.occurredAtCairo,
  });

  final String kind;
  final String labelAr;
  final String operationId;
  final String actorDisplayName;
  final String occurredAt;
  final String occurredAtCairo;
}
