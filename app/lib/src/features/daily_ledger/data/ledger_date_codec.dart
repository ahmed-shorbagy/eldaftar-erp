import '../application/ledger_date_gateway.dart';
import '../application/idempotency_key.dart';
import 'daily_ledger_codec.dart';

LedgerDateSnapshot parseLedgerDate(Object? raw, String shopId) {
  if (raw is! Map ||
      raw['read_model_version'] != 1 ||
      raw['shop_id'] != shopId ||
      raw['business_date'] is! String ||
      !isCalendarDate(raw['business_date'] as String) ||
      raw['server_date'] is! String ||
      !isCalendarDate(raw['server_date'] as String) ||
      (raw['business_date'] as String).compareTo(raw['server_date'] as String) >
          0 ||
      raw['day_ids'] is! List) {
    throw const FormatException('ledger_date');
  }
  final days = raw['day_ids'] as List;
  if (days.any((id) => id is! String || !isUuid(id)) ||
      days.toSet().length != days.length) {
    throw const FormatException('days');
  }
  final page = parseLedgerOperationPage(
    raw['feed_page'],
    expectedShopId: shopId,
  );
  final summary = parseLedgerDaySummary(raw['day_summary']);
  if (page.dayId != null ||
      page.direction != 'desc' ||
      (days.isEmpty &&
          (page.items.isNotEmpty ||
              page.hasMore ||
              summary.salePiastres != '0' ||
              summary.purchasePiastres != '0' ||
              summary.expensePiastres != '0' ||
              summary.saleCount != 0 ||
              summary.purchaseCount != 0 ||
              summary.expenseCount != 0 ||
              summary.goldByBucket.isNotEmpty))) {
    throw const FormatException('date_page');
  }
  return LedgerDateSnapshot(
    shopId: shopId,
    businessDate: raw['business_date'] as String,
    serverDate: raw['server_date'] as String,
    dayIds: List<String>.unmodifiable(days),
    summary: summary,
    page: page,
  );
}
