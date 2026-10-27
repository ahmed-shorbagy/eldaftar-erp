import 'dart:typed_data';

import '../domain/period_analytics.dart';

abstract interface class AnalyticsGateway {
  Future<PeriodAnalytics> periodAnalytics(
    String userId,
    String shopId, {
    required AnalyticsPeriod period,
    String? anchorDate,
  });

  Future<Uint8List> storePeriodAnalyticsPdf(
    String userId,
    PeriodAnalytics report,
    Uint8List bytes,
  );
}
