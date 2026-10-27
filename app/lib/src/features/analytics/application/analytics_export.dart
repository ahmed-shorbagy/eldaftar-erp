import 'dart:typed_data';

import '../../reports/application/report_export.dart';
import '../../reports/application/report_gateway.dart';
import '../domain/period_analytics.dart';
import 'analytics_gateway.dart';

export '../../reports/application/report_gateway.dart' show ReportChanged;

typedef AnalyticsRenderer = Future<Uint8List> Function(PeriodAnalytics);

class AnalyticsExport {
  AnalyticsExport(
    this.sessions,
    this.gateway,
    this.userId,
    this.shopId,
    this.canRead,
  );
  final ReportGateway sessions;
  final AnalyticsGateway gateway;
  final String userId, shopId;
  final bool Function() canRead;
  bool busy = false;

  Future<String> run(
    PeriodAnalytics report,
    AnalyticsRenderer render,
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
      final current = await gateway.periodAnalytics(
        userId,
        shopId,
        period: report.periodKind,
        anchorDate: report.anchorDate,
      );
      if (!allowed()) return 'denied';
      if (current.fingerprint != report.fingerprint) return 'stale';
      bytes = await render(current);
      if (!allowed()) return 'denied';
      final after = await gateway.periodAnalytics(
        userId,
        shopId,
        period: report.periodKind,
        anchorDate: report.anchorDate,
      );
      if (!allowed()) return 'denied';
      if (after.fingerprint != current.fingerprint) return 'stale';
      verified = await gateway.storePeriodAnalyticsPdf(userId, current, bytes);
      if (!allowed()) return 'denied';
      final finalRead = await gateway.periodAnalytics(
        userId,
        shopId,
        period: report.periodKind,
        anchorDate: report.anchorDate,
      );
      if (!allowed()) return 'denied';
      if (finalRead.fingerprint != current.fingerprint) return 'stale';
      return await output(
        verified,
        'تحليلات-${report.period}-${report.startDate}-${report.endDate}.pdf',
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
