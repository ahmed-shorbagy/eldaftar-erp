import 'dart:typed_data';
import '../domain/financial_day_report.dart';

abstract interface class ReportGateway {
  Object? reportSession(String userId);
  Future<List<ReportDay>> reportDays(String userId, String shopId);
  Future<FinancialDayReport> financialDayReport(
    String userId,
    String shopId,
    String dayId,
  );

  /// Upload/verify to R2, require the same current server snapshot, then read
  /// the verified PDF back. Content addressing makes retries idempotent.
  Future<Uint8List> storeReportPdf(
    String userId,
    FinancialDayReport report,
    Uint8List bytes,
  );
}

class ReportChanged implements Exception {
  const ReportChanged();
}
