import 'dart:typed_data';
import '../domain/financial_day_report.dart';
import 'report_gateway.dart';

typedef ReportRenderer = Future<Uint8List> Function(FinancialDayReport);
typedef ReportOutput =
    Future<String> Function(Uint8List, String, bool Function());

class ReportExport {
  ReportExport(this.gateway, this.userId, this.shopId, this.canRead);
  final ReportGateway gateway;
  final String userId, shopId;
  final bool Function() canRead;
  bool busy = false;
  Future<String> run(
    FinancialDayReport report,
    ReportRenderer render,
    ReportOutput output,
  ) async {
    if (busy) return 'busy';
    busy = true;
    final session = gateway.reportSession(userId);
    bool allowed() =>
        canRead() &&
        session != null &&
        gateway.reportSession(userId) == session;
    Uint8List? bytes;
    Uint8List? verified;
    try {
      if (!allowed()) return 'denied';
      final current = await gateway.financialDayReport(
        userId,
        shopId,
        report.day.id,
      );
      if (!allowed()) return 'denied';
      if (current.fingerprint != report.fingerprint) return 'stale';
      bytes = await render(current);
      if (!allowed()) return 'denied';
      final after = await gateway.financialDayReport(
        userId,
        shopId,
        report.day.id,
      );
      if (!allowed()) return 'denied';
      if (after.fingerprint != current.fingerprint) return 'stale';
      verified = await gateway.storeReportPdf(userId, current, bytes);
      if (!allowed()) return 'denied';
      final last = await gateway.financialDayReport(
        userId,
        shopId,
        report.day.id,
      );
      if (!allowed()) return 'denied';
      if (last.fingerprint != current.fingerprint) return 'stale';
      return await output(verified, 'تقرير-${report.day.date}.pdf', allowed);
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
