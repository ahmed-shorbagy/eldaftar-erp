import 'dart:typed_data';
import '../domain/financial_week_report.dart';
import 'report_export.dart';
import 'report_gateway.dart';
import 'weekly_report_gateway.dart';

typedef WeeklyReportRenderer = Future<Uint8List> Function(FinancialWeekReport);

class WeeklyReportExport {
  WeeklyReportExport(
    this.sessions,
    this.gateway,
    this.userId,
    this.shopId,
    this.canRead,
  );
  final ReportGateway sessions;
  final WeeklyReportGateway gateway;
  final String userId, shopId;
  final bool Function() canRead;
  bool busy = false;
  Future<String> run(
    FinancialWeekReport report,
    WeeklyReportRenderer render,
    ReportOutput output,
  ) async {
    if (busy) return 'busy';
    busy = true;
    final session = sessions.reportSession(userId);
    bool allowed() =>
        canRead() &&
        session != null &&
        sessions.reportSession(userId) == session;
    Uint8List? bytes, verified;
    try {
      if (!allowed()) return 'denied';
      final current = await gateway.financialWeekReport(
        userId,
        shopId,
        endDate: report.endDate,
      );
      if (!allowed()) return 'denied';
      if (current.fingerprint != report.fingerprint) return 'stale';
      bytes = await render(current);
      if (!allowed()) return 'denied';
      final after = await gateway.financialWeekReport(
        userId,
        shopId,
        endDate: report.endDate,
      );
      if (!allowed()) return 'denied';
      if (after.fingerprint != current.fingerprint) return 'stale';
      verified = await gateway.storeWeeklyReportPdf(userId, current, bytes);
      if (!allowed()) return 'denied';
      final finalRead = await gateway.financialWeekReport(
        userId,
        shopId,
        endDate: report.endDate,
      );
      if (!allowed()) return 'denied';
      if (finalRead.fingerprint != current.fingerprint) return 'stale';
      return await output(
        verified,
        'تقرير-أسبوعي-${report.startDate}-${report.endDate}.pdf',
        allowed,
      );
    } on ReportChanged {
      return allowed() ? 'stale' : 'denied';
    } catch (_) {
      return allowed() ? 'failed' : 'denied';
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      verified?.fillRange(0, verified.length, 0);
      busy = false;
    }
  }
}
