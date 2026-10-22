import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eldafttar/src/features/reports/application/weekly_report_export.dart';
import 'package:eldafttar/src/features/reports/application/weekly_report_gateway.dart';
import 'package:eldafttar/src/features/reports/data/weekly_report_codec.dart';
import 'package:eldafttar/src/features/reports/domain/financial_week_report.dart';
import 'package:eldafttar/src/features/reports/presentation/reports_screen.dart';
import 'package:eldafttar/src/features/reports/presentation/weekly_reports_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'report_fixtures.dart';
import 'weekly_report_fixtures.dart';

Widget weeklyApp(
  FakeShopReports gateway, {
  Brightness brightness = Brightness.light,
  double scale = 1,
  GlobalKey? capture,
  ValueNotifier<int>? sync,
  bool canRead = true,
  EdgeInsets viewInsets = EdgeInsets.zero,
  WeeklyReportRenderer? render,
  Future<String> Function(Uint8List, String, bool Function())? output,
}) => MaterialApp(
  theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale), viewInsets: viewInsets),
      child: RepaintBoundary(
        key: capture,
        child: WeeklyReportsScreen(
          sessions: gateway,
          gateway: gateway,
          userId: reportUser,
          shopId: reportShop,
          canRead: () => canRead && gateway.session != null,
          syncTicks: sync,
          render: render ?? (_) async => Uint8List(1),
          output: output ?? (bytes, name, allowed) async => 'saved',
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('daily Reports keeps its screen and opens the weekly route', (
    tester,
  ) async {
    final gateway = FakeShopReports();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: ReportsScreen(
          gateway: gateway,
          userId: reportUser,
          shopId: reportShop,
          canRead: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('تقرير يوم مالي'), findsOneWidget);
    expect(find.text('تصدير PDF عربي'), findsOneWidget);
    expect(find.text('90,071,992,547,409.93'), findsOneWidget);
    await tester.tap(find.byKey(const Key('reports-open-weekly')));
    await tester.pumpAndSettle();
    expect(find.text('التقرير الأسبوعي'), findsOneWidget);
    expect(find.text('اختيار آخر يوم في الأسبوع'), findsOneWidget);
    expect(find.text('تصدير PDF أسبوعي'), findsOneWidget);
    expect(find.text('صافي حركة النقد ليس ربحًا.'), findsNothing);
    expect(find.textContaining('ليس ربحًا'), findsWidgets);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('تقرير يوم مالي'), findsOneWidget);
    expect(find.text('تصدير PDF عربي'), findsOneWidget);
  });

  testWidgets(
    'weekly failure, retry, latest week and empty range stay truthful',
    (tester) async {
      final gateway = FakeShopReports()..failWeek = true;
      final sync = ValueNotifier(0);
      await tester.pumpWidget(weeklyApp(gateway, sync: sync));
      await tester.pumpAndSettle();
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      expect(find.text('متجر الذهب التجريبي'), findsNothing);
      gateway.failWeek = false;
      await tester.tap(find.text('إعادة المحاولة'));
      await tester.pumpAndSettle();
      expect(find.text('تصدير PDF أسبوعي'), findsOneWidget);
      expect(gateway.weekEnds, [null, null]);
      gateway.failWeek = true;
      sync.value++;
      await tester.pumpAndSettle();
      expect(find.text('فتح أحدث أسبوع'), findsOneWidget);
      expect(find.text('متجر الذهب التجريبي'), findsNothing);
      expect(gateway.weekEnds.last, '2026-10-22');
      gateway
        ..failWeek = false
        ..week = consistentWeek(const [], endDate: '2026-10-22');
      await tester.tap(find.text('فتح أحدث أسبوع'));
      await tester.pumpAndSettle();
      expect(gateway.weekEnds.last, isNull);
      expect(
        find.text('لا توجد أيام مالية مسجّلة في هذه الفترة.'),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('لا توجد حركة بيع أو شراء ذهب في هذه الفترة.'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.text('لا توجد حركة بيع أو شراء ذهب في هذه الفترة.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
      sync.dispose();
    },
  );

  testWidgets('late weekly content is discarded when the session is gone', (
    tester,
  ) async {
    final gateway = FakeShopReports();
    final pending = Completer<FinancialWeekReport>();
    final release = pending;
    final screen = WeeklyReportsScreen(
      sessions: gateway,
      gateway: _PendingWeek(gateway, () => release.future),
      userId: reportUser,
      shopId: reportShop,
      canRead: () => gateway.session != null,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: screen,
      ),
    );
    await tester.pump();
    expect(find.text('جارٍ تحميل الأسبوع من الخادم…'), findsOneWidget);
    gateway.session = null;
    release.complete(parseFinancialWeekReport(gateway.week));
    await tester.pumpAndSettle();
    expect(
      find.text('انتهت صلاحية الوصول إلى التقرير الأسبوعي.'),
      findsOneWidget,
    );
    expect(find.text('متجر الذهب التجريبي'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'export disables a second tap and reports cancellation or staleness',
    (tester) async {
      final gateway = FakeShopReports();
      final renderWait = Completer<Uint8List>();
      await tester.pumpWidget(
        weeklyApp(
          gateway,
          render: (_) => renderWait.future,
          output: (bytes, name, allowed) async => 'cancelled',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('weekly-report-export')));
      await tester.pump();
      expect(find.text('جارٍ تصدير الأسبوع…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('weekly-report-export')))
            .onPressed,
        isNull,
      );
      renderWait.complete(Uint8List(1));
      await tester.pumpAndSettle();
      expect(
        find.text('أُلغي حفظ أو مشاركة التقرير الأسبوعي.'),
        findsOneWidget,
      );
      gateway.week['fingerprint'] = 'c' * 64;
      await tester.tap(find.byKey(const Key('weekly-report-export')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'تغيّرت بيانات الأسبوع. راجع التقرير المحدّث ثم صدّره مجددًا.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'narrow enlarged weekly text and a keyboard inset do not overflow',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = FakeShopReports();
      await tester.pumpWidget(
        weeklyApp(
          gateway,
          scale: 1.7,
          viewInsets: const EdgeInsets.only(bottom: 280),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final handle = tester.ensureSemantics();
      Future<void> expectLabel(Key key, String label) async {
        final finder = find.byKey(key);
        await tester.scrollUntilVisible(
          finder,
          120,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(finder);
        expect(find.bySemanticsLabel(label), findsOneWidget);
      }

      await expectLabel(
        const Key('weekly-report-select-end'),
        'اختيار آخر يوم في الأسبوع',
      );
      await expectLabel(const Key('weekly-report-export'), 'تصدير PDF أسبوعي');
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(tester.takeException(), isNull);
      handle.dispose();
      Future<void> openTile(Key key) async {
        final header = find.descendant(
          of: find.byKey(key),
          matching: find.byType(ListTile),
        );
        await tester.scrollUntilVisible(
          header,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(header);
        ExpansibleController.of(tester.element(header)).expand();
        await tester.pumpAndSettle();
      }

      await openTile(const PageStorageKey('week-2026-10-22-worked_jewelry-14'));
      expect(tester.takeException(), isNull);
      expect(find.text('حركات البيع، شاملة المرتجعات'), findsOneWidget);
      await openTile(
        const PageStorageKey(
          'week-day-2026-10-22-b3333333-3333-4333-8333-333333333333',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('بيع •'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'labelled end-date picker opens and cancels without losing the week',
    (tester) async {
      final gateway = FakeShopReports();
      await tester.pumpWidget(weeklyApp(gateway));
      await tester.pumpAndSettle();
      final reads = gateway.weekReads;
      await tester.tap(find.byKey(const Key('weekly-report-select-end')));
      await tester.pumpAndSettle();
      expect(find.text('آخر يوم في الأسبوع'), findsOneWidget);
      await tester.tap(find.text('إلغاء'));
      await tester.pumpAndSettle();
      expect(find.text('التقرير الأسبوعي'), findsOneWidget);
      expect(gateway.weekReads, reads);
      await tester.pumpWidget(const SizedBox());
    },
  );

  if (!const bool.fromEnvironment('WEEKLY_REPORT_CAPTURES')) return;
  setUpAll(() async {
    final cairo = await File('assets/fonts/Cairo.ttf').readAsBytes();
    await (FontLoader(
      'Cairo',
    )..addFont(Future.value(ByteData.sublistView(cairo)))).load();
    final sdk = Platform.resolvedExecutable
        .split(RegExp(r'[/\\]bin[/\\]cache[/\\]'))
        .first;
    final icons = await File(
      '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
  });
  for (final width in [320.0, 390.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.7]) {
        testWidgets('weekly RTL $width $brightness $scale', (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final key = GlobalKey();
          final gateway = FakeShopReports();
          await tester.pumpWidget(
            weeklyApp(
              gateway,
              brightness: brightness,
              scale: scale,
              capture: key,
            ),
          );
          await tester.pumpAndSettle();
          Future<void> capture(String state) async {
            expect(tester.takeException(), isNull);
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final theme = brightness == Brightness.light ? 'light' : 'dark';
              final file = File(
                '../docs/reviews/weekly-reports-2026-10-22/captures/$state-${width.toInt()}-$theme-$scale.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }

          await capture('summary');
          Future<void> revealAndTap(Finder finder) async {
            final scrollable = find.byType(Scrollable).first;
            await tester.scrollUntilVisible(
              finder,
              240,
              scrollable: scrollable,
            );
            expect(finder, findsOneWidget);
            final viewHeight =
                tester.view.physicalSize.height / tester.view.devicePixelRatio;
            for (var attempt = 0; attempt < 6; attempt++) {
              final rect = tester.getRect(finder);
              final tooLow = rect.bottom > viewHeight - 12;
              final tooHigh = rect.top < 96;
              if (!tooLow && !tooHigh) break;
              final delta = tooLow
                  ? rect.bottom - (viewHeight - 24)
                  : rect.top - 120;
              await tester.drag(scrollable, Offset(0, -delta));
              await tester.pumpAndSettle();
            }
            final rect = tester.getRect(finder);
            expect(rect.top, greaterThanOrEqualTo(80));
            expect(rect.bottom, lessThanOrEqualTo(viewHeight));
            await tester.tap(finder);
            await tester.pumpAndSettle();
          }

          await revealAndTap(find.text('مشغولات ذهبية • عيار 21'));
          expect(find.text('حركات البيع، شاملة المرتجعات'), findsWidgets);
          await capture('group');
          await revealAndTap(
            find.descendant(
              of: find.byKey(
                const PageStorageKey('week-day-2026-10-22-$reportDayId'),
              ),
              matching: find.textContaining('اليوم المالي:'),
            ),
          );
          await revealAndTap(
            find.descendant(
              of: find.byKey(
                const PageStorageKey(
                  'week-2026-10-22-$reportDayId-b4444444-4444-4444-8444-000000000002',
                ),
              ),
              matching: find.text('بيع • \u20662\u2069'),
            ),
          );
          expect(find.text('قيمة العملية الأصلية'), findsWidgets);
          await capture('details');
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }
}

class _PendingWeek implements WeeklyReportGateway {
  _PendingWeek(this.inner, this.pending);
  final FakeShopReports inner;
  final Future<FinancialWeekReport> Function() pending;
  @override
  Future<FinancialWeekReport> financialWeekReport(
    String userId,
    String shopId, {
    String? endDate,
  }) => pending();
  @override
  Future<Uint8List> storeWeeklyReportPdf(
    String userId,
    FinancialWeekReport report,
    Uint8List bytes,
  ) => inner.storeWeeklyReportPdf(userId, report, bytes);
}
