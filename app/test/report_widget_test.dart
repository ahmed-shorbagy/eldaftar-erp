import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/features/reports/presentation/reports_screen.dart';
import 'package:eldafttar/src/features/reports/data/report_codec.dart';
import 'package:eldafttar/src/features/reports/domain/financial_day_report.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'report_fixtures.dart';

Widget reportApp(
  FakeReports g, {
  Brightness brightness = Brightness.light,
  double scale = 1,
  GlobalKey? capture,
  ValueNotifier<int>? sync,
}) => MaterialApp(
  theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: RepaintBoundary(
      key: capture,
      child: ReportsScreen(
        gateway: g,
        userId: reportUser,
        shopId: reportShop,
        canRead: () => true,
        syncTicks: sync,
      ),
    ),
  ),
);

void main() {
  testWidgets('phone More Reports entry opens the operational screen', (
    t,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final g = FakeReports();
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ShopWorkspace(
            shop: const ShopAccount(
              id: reportShop,
              name: 'متجر تجريبي',
              role: 'owner',
              entitlement: ShopEntitlement.active,
            ),
            onSignOut: () async {},
            onToggleTheme: (_) async {},
            reportsBuilder: (_) => ReportsScreen(
              gateway: g,
              userId: reportUser,
              shopId: reportShop,
              canRead: () => true,
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('workspace-nav-4')));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
      find.text('التقارير'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('التقارير'));
    await t.pumpAndSettle();
    expect(find.text('تقرير يوم مالي'), findsOneWidget);
    expect(find.text('تصدير PDF عربي'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('loads historical day, complete empty state, failure and retry', (
    t,
  ) async {
    final g = FakeReports()..fail = true;
    await t.pumpWidget(reportApp(g));
    await t.pumpAndSettle();
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    g.fail = false;
    await t.tap(find.text('إعادة المحاولة'));
    await t.pumpAndSettle();
    expect(find.text('تصدير PDF عربي'), findsOneWidget);
    await t.tap(find.byType(DropdownButtonFormField<String>));
    await t.pumpAndSettle();
    await t.tap(find.text(g.days.last.label).last);
    await t.pumpAndSettle();
    expect(find.text('اليوم مغلق'), findsOneWidget);
    await t.scrollUntilVisible(
      find.text('لا توجد عمليات لهذا اليوم المالي.'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('لا توجد عمليات لهذا اليوم المالي.'), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });
  testWidgets('late response is discarded after session revocation', (t) async {
    final g = FakeReports();
    final pending = Completer<FinancialDayReport>();
    g.read = (_) => pending.future;
    final sync = ValueNotifier(0);
    await t.pumpWidget(reportApp(g, sync: sync));
    await t.pump();
    expect(find.text('جارٍ تحميل التقرير المؤكد…'), findsOneWidget);
    g.session = null;
    pending.complete(parseFinancialDayReport(g.data));
    await t.pumpAndSettle();
    expect(find.text('انتهت صلاحية الوصول إلى التقرير.'), findsOneWidget);
    expect(find.text('متجر الذهب التجريبي'), findsNothing);
    await t.pumpWidget(const SizedBox());
    sync.dispose();
  });
  testWidgets(
    'cross-session sync refreshes without retaining stale totals on failure',
    (t) async {
      final g = FakeReports();
      final sync = ValueNotifier(0);
      await t.pumpWidget(reportApp(g, sync: sync));
      await t.pumpAndSettle();
      g.fail = true;
      sync.value++;
      await t.pumpAndSettle();
      expect(find.text('إعادة المحاولة'), findsOneWidget);
      expect(find.text('متجر الذهب التجريبي'), findsNothing);
      await t.pumpWidget(const SizedBox());
      sync.dispose();
    },
  );
  if (!const bool.fromEnvironment('REPORT_CAPTURES')) return;
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
        testWidgets('report RTL $width $brightness $scale', (t) async {
          t.view.physicalSize = Size(width, 1000);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final key = GlobalKey();
          final g = FakeReports();
          await t.pumpWidget(
            reportApp(g, brightness: brightness, scale: scale, capture: key),
          );
          await t.pumpAndSettle();
          Future<void> capture(String state) async {
            expect(t.takeException(), isNull);
            await t.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'build/reports/captures/$state-${width.toInt()}-${brightness.name}-$scale.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }

          await capture('summary');
          await t.scrollUntilVisible(
            find.text('عيار 21'),
            400,
            scrollable: find.byType(Scrollable).first,
          );
          await t.pumpAndSettle();
          await capture('gold');
          await t.scrollUntilVisible(
            find.textContaining('بيع •'),
            400,
            scrollable: find.byType(Scrollable).first,
          );
          await t.ensureVisible(find.textContaining('بيع •'));
          await t.tap(find.textContaining('بيع •'));
          await t.pumpAndSettle();
          await capture('details');
          await t.pumpWidget(const SizedBox());
        });
      }
    }
  }
}
