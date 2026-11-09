import 'daily_ledger_view.dart';
import 'ledger_activity.dart';

class LedgerDateSnapshot {
  const LedgerDateSnapshot({
    required this.shopId,
    required this.businessDate,
    required this.serverDate,
    required this.dayIds,
    required this.summary,
    required this.page,
  });
  final String shopId, businessDate, serverDate;
  final List<String> dayIds;
  final LedgerDaySummary summary;
  final LedgerOperationPage page;
}

abstract class LedgerDateGateway {
  Future<LedgerDateSnapshot> readLedgerDate({
    required String userId,
    required String shopId,
    String? businessDate,
    String? beforeSequence,

    /// One financial day only. A closed day and a day opened later on the
    /// same calendar date share a date, so «الدفاتر» and home read by id.
    String? dayId,
  });
}
