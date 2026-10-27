import 'dart:typed_data';

import 'package:eldafttar/src/features/analytics/application/analytics_gateway.dart';
import 'package:eldafttar/src/features/analytics/domain/period_analytics.dart';
import 'package:eldafttar/src/features/analytics/presentation/analytics_screen.dart';
import 'package:eldafttar/src/features/reports/application/report_gateway.dart';
import 'package:eldafttar/src/features/reports/domain/financial_day_report.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

PeriodAnalytics _sample({required bool isOwner}) => PeriodAnalytics(
  shopId: 'shop-1',
  shopName: 'متجر',
  timeZone: 'Africa/Cairo',
  period: 'month',
  anchorDate: '2026-10-15',
  startDate: '2026-10-01',
  endDate: '2026-10-31',
  serverDate: '2026-10-27',
  lastSelectableDate: '2026-10-27',
  firstBusinessDate: '2026-09-01',
  generatedAtShop: '2026-10-27 12:00:00',
  fingerprint: 'a' * 64,
  containsOpenDay: false,
  isOwner: isOwner,
  dayCount: 2,
  summary: {
    for (final key in reportSummaryLabels.keys) key: BigInt.zero,
  },
  gold: [
    for (final k in [14, 18, 21, 22, 24])
      ReportGold(k, BigInt.zero, BigInt.zero),
  ],
  actors: isOwner
      ? [
          AnalyticsActor(
            actorUserId: 'user-2',
            displayName: 'موظف الاختبار',
            role: 'employee',
            gold: const [],
            soldTotal: BigInt.from(2000),
            boughtTotal: BigInt.zero,
          ),
        ]
      : const [],
);

class _Sessions implements ReportGateway {
  @override
  Object? reportSession(String userId) => 'session';

  @override
  Future<List<ReportDay>> reportDays(String userId, String shopId) async => [];

  @override
  Future<FinancialDayReport> financialDayReport(
    String userId,
    String shopId,
    String dayId,
  ) => Future.error(UnimplementedError());

  @override
  Future<Uint8List> storeReportPdf(
    String userId,
    FinancialDayReport report,
    Uint8List bytes,
  ) => Future.error(UnimplementedError());
}

class _Analytics implements AnalyticsGateway {
  _Analytics(this.report);
  final PeriodAnalytics report;

  @override
  Future<PeriodAnalytics> periodAnalytics(
    String userId,
    String shopId, {
    required AnalyticsPeriod period,
    String? anchorDate,
  }) async => report;

  @override
  Future<Uint8List> storePeriodAnalyticsPdf(
    String userId,
    PeriodAnalytics report,
    Uint8List bytes,
  ) async => bytes;
}

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: AppTheme.light(),
  home: child,
);

void main() {
  testWidgets('owner sees staff weight section', (tester) async {
    await tester.pumpWidget(
      _host(
        AnalyticsScreen(
          sessions: _Sessions(),
          gateway: _Analytics(_sample(isOwner: true)),
          userId: 'user-1',
          shopId: 'shop-1',
          canRead: () => true,
          isOwner: true,
          output: (bytes, name, allowed) async => 'shared',
          render: (_) async => Uint8List.fromList([1, 2, 3]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('analytics-actor-user-2')),
      200,
      scrollable: find
          .byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          )
          .first,
    );
    expect(find.text('أوزان الموظفين والمستخدمين'), findsOneWidget);
    expect(find.text('موظف الاختبار'), findsOneWidget);
    expect(find.byKey(const Key('analytics-actor-user-2')), findsOneWidget);
  });

  testWidgets('non-owner does not see staff section', (tester) async {
    await tester.pumpWidget(
      _host(
        AnalyticsScreen(
          sessions: _Sessions(),
          gateway: _Analytics(_sample(isOwner: false)),
          userId: 'user-1',
          shopId: 'shop-1',
          canRead: () => true,
          isOwner: false,
          output: (bytes, name, allowed) async => 'shared',
          render: (_) async => Uint8List.fromList([1, 2, 3]),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('أوزان الموظفين والمستخدمين'), findsNothing);
    expect(find.byKey(const Key('analytics-actor-user-2')), findsNothing);
    expect(find.text('موظف الاختبار'), findsNothing);
  });
}
