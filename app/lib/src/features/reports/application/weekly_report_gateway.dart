import 'dart:typed_data';
import '../domain/financial_week_report.dart';

abstract interface class WeeklyReportGateway {
  Future<FinancialWeekReport> financialWeekReport(
    String userId,
    String shopId, {
    String? endDate,
  });
  Future<Uint8List> storeWeeklyReportPdf(
    String userId,
    FinancialWeekReport report,
    Uint8List bytes,
  );
}
