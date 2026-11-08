import 'dart:io';

import 'package:eldafttar/src/features/auth/presentation/auth_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_operation_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_trade_screen.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_capture_test.dart' show CaptureAuth;
import 'daily_ledger_widget_test.dart' show MemoryStore;
import 'owner_feedback_ledger_review_test.dart' show ReviewGateway;
import 'operation_details_test.dart' show DetailsGateway, line;
import 'batch2_trade_support.dart' show Batch2TradeGateway;

/// Synthetic artifacts only; opt in with OWNER_FEEDBACK_CAPTURE and --update-goldens.
void main() {
  if (!const bool.fromEnvironment('OWNER_FEEDBACK_CAPTURE')) return;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = await File('assets/fonts/Cairo.ttf').readAsBytes();
    await (FontLoader(
      'Cairo',
    )..addFont(Future.value(ByteData.sublistView(font)))).load();
    final icons = await File(
      r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
  });
  for (final width in [320.0, 390.0, 1440.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.7]) {
        final suffix = '${width.toInt()}-${dark ? 'dark' : 'light'}-$scale';
        testWidgets('owner feedback captures $suffix', (t) async {
          SharedPreferences.setMockInitialValues({});
          FlutterSecureStorage.setMockInitialValues({});
          t.view.physicalSize = Size(width, width == 1440 ? 900 : 800);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final captureKey = GlobalKey();
          Widget host(Widget child) => MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: captureKey, child: child!),
            ),
            home: child,
          );
          Future<void> shot(String state) async {
            await t.pumpAndSettle();
            expect(t.takeException(), isNull, reason: '$state-$suffix');
            await expectLater(
              find.byKey(captureKey),
              matchesGoldenFile(
                '../../docs/reviews/owner-feedback-ledger-auth-2026-10-19/captures/$state-$suffix.png',
              ),
            );
          }

          Future<void> tap(Finder f) async {
            await t.ensureVisible(f);
            await t.pumpAndSettle();
            await t.tap(f);
            await t.pumpAndSettle();
          }

          await t.pumpWidget(
            host(
              AuthScreen(
                gateway: CaptureAuth(),
                onToggleTheme: (_) async {},
                onHold: (_) {},
                onSessionSettled: () {},
              ),
            ),
          );
          await t.pumpAndSettle();
          await t.runAsync(
            () => precacheImage(
              const AssetImage('assets/brand/auth-jewelry.png'),
              t.element(find.byType(AuthScreen)),
            ),
          );
          await shot('login');
          await tap(find.byKey(const Key('show-signup')));
          await shot('signup');
          await t.ensureVisible(find.byKey(const Key('signup-submit')));
          await shot('signup-bottom');
          await t.pumpWidget(
            host(
              ShopWorkspace(
                shop: const ShopAccount(
                  id: 'shop-1',
                  name: 'مجوهرات تجريبية',
                  role: 'owner',
                  entitlement: ShopEntitlement.active,
                ),
                gateway: ReviewGateway(),
                store: MemoryStore(),
                userId: 'owner-1',
                onSignOut: () async {},
                onToggleTheme: (_) async {},
              ),
            ),
          );
          await shot('ledger');
          await t.ensureVisible(find.byKey(const Key('ledger-journal-sale')));
          await shot('transactions');
          if (width < 840) {
            await tap(find.byKey(const Key('workspace-nav-4')));
          } else {
            await tap(find.text('المزيد').last);
          }
          await shot('more');
          await tap(find.byKey(const Key('more-inventory-scrap')));
          await shot('inventory');
          await tap(find.byKey(const Key('detail-close')));
          await t.pumpWidget(
            host(
              FinancialOperationScreen(
                gateway: DetailsGateway(const {
                  'customer_name': 'عميل تجريبي',
                  'customer_phone': '01011111111',
                  'note': 'تسليم مساءً',
                }),
                userId: 'owner-1',
                line: line(hasNote: true),
              ),
            ),
          );
          await shot('details');
          await tap(find.byKey(const Key('operation-notes')));
          await shot('notes');
          // Use the real trade screen with the same synthetic financial gateway.
          final g = Batch2TradeGateway();
          await t.pumpWidget(
            host(
              FinancialTradeScreen(
                kind: FinancialKind.sale,
                gateway: g,
                statusGateway: g,
                userId: 'owner-1',
                shopId: 'shop-1',
              ),
            ),
          );
          await tap(find.byKey(const Key('trade-select-أخرى')));
          await t.ensureVisible(find.byKey(const Key('trade-other-grid')));
          await shot('other-categories');
          await t.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
