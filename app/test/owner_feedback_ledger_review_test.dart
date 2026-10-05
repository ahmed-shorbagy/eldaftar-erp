import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/daily_ledger_screen.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'daily_ledger_capture_test.dart' show confirmedLedger;
import 'financial_trade_screen_test.dart' show FakeFinancialGateway;
import 'daily_ledger_widget_test.dart' show MemoryStore;

class ReviewGateway extends FakeFinancialGateway {
  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async {
    final base = confirmedLedger();
    return DailyLedgerView(
      state: base.state,
      entitlementStatus: base.entitlementStatus,
      canConfirm: false,
      businessDay: base.businessDay,
      cash: base.cash,
      stock: base.stock,
      scrap: base.scrap,
      daySummary: base.daySummary,
      feed: [
        for (final row in [
          ('sale', 'بيع', 'عميل تجريبي', '7000.00', '1.830', 21),
          ('purchase', 'شراء', 'تاجر تجريبي', '20500.50', '10.000', 21),
          ('sale_return', 'مرتجع بيع', 'عميل تجريبي', '1250.25', '0.500', 18),
        ])
          LedgerFeedLine(
            kind: row.$1,
            labelAr: row.$2,
            operationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
            actorDisplayName: 'مالك تجريبي',
            occurredAt: '2026-09-26T00:30:00Z',
            occurredAtCairo: '2026-09-26T03:30:00',
            partyName: row.$3,
            totalPounds: row.$4,
            weightGrams: row.$5,
            karat: row.$6,
            paymentLabel: 'كاش',
            isReturn: row.$1 == 'sale_return',
          ),
      ],
    );
  }
}

Future<void> saveReview(WidgetTester tester, GlobalKey key, String name) async {
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final picture = await boundary.toImage();
    final png = await picture.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/owner-feedback-review/ledger/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(png!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'NotoSansArabic',
    )..addFont(rootBundle.load('assets/fonts/NotoSansArabic.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  for (final width in [320.0, 390.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'owner ledger and journals ${dark ? 'dark' : 'light'} $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final key = GlobalKey();
          final gateway = ReviewGateway();
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('ar'),
              supportedLocales: const [Locale('ar')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              home: RepaintBoundary(
                key: key,
                child: DailyLedgerScreen(
                  shop: const ShopAccount(
                    id: 'shop-1',
                    name: 'محل تجريبي',
                    role: 'owner',
                    entitlement: ShopEntitlement.active,
                  ),
                  gateway: gateway,
                  store: MemoryStore(),
                  userId: 'owner-1',
                  onSignOut: () async {},
                  onToggleTheme: (_) async {},
                  onChangeShop: () {},
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('onboarding-guide')), findsNothing);
          expect(find.byKey(const Key('ledger-new-sale')), findsOneWidget);
          final suffix = '${dark ? 'dark' : 'light'}-${width.toInt()}';
          await saveReview(tester, key, 'top-$suffix');
          await tester.ensureVisible(find.text('دفتر البيع'));
          await tester.pumpAndSettle();
          expect(find.text('بيع · عميل تجريبي'), findsOneWidget);
          expect(find.text('مرتجع بيع · عميل تجريبي'), findsNothing);
          await saveReview(tester, key, 'journals-$suffix');
          await tester.ensureVisible(find.text('دفتر المرتجعات'));
          await tester.tap(find.text('دفتر المرتجعات'));
          await tester.pumpAndSettle();
          expect(find.text('مرتجع بيع · عميل تجريبي'), findsOneWidget);
          expect(gateway.keys, isEmpty);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
