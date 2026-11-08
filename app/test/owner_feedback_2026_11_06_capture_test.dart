import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/nominal_weight_suggestions.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_trade_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/invoice_pdf_share_dialog.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/trade_nominal_picker.dart';
import 'package:eldafttar/src/features/inventory/application/inventory_gateway.dart';
import 'package:eldafttar/src/features/inventory/presentation/inventory_screen.dart';
import 'package:eldafttar/src/features/invoice_message/domain/synthetic_message.dart';
import 'package:eldafttar/src/features/invoice_message/presentation/message_settings_screen.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'batch2_trade_support.dart';
import 'financial_trade_screen_test.dart' show FakeFinancialGateway;
import 'inventory_widget_test.dart';
import 'invoice_message_test.dart';
import 'meeting_ui_completion_test.dart' show completionShop, completionUser;

const _capture = Key('owner-feedback-capture');
const _operationId = 'a1333333-3333-4333-8333-333333333333';

Future<void> _save(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: name);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_capture),
  );
  await tester.runAsync(() async {
    final picture = await boundary.toImage();
    final data = await picture.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/owner-feedback-2026-11-06/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    picture.dispose();
  });
}

String _label(String scene, bool dark, Size size, double scale) =>
    '$scene-${dark ? 'dark' : 'light'}-${size.width.toInt()}'
    '${scale == 1 ? '' : '-scale13'}';

Future<void> _pump(
  WidgetTester tester, {
  required bool dark,
  required Size size,
  required double scale,
  required Widget home,
}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  if (scale == 1) {
    tester.platformDispatcher.clearTextScaleFactorTestValue();
  } else {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
  }
  await tester.pumpWidget(
    RepaintBoundary(
      key: _capture,
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openMore(WidgetTester tester) async {
  final nav = find.byKey(const Key('workspace-nav-4'));
  if (nav.evaluate().isNotEmpty) {
    await tester.tap(nav);
  } else {
    await tester.tap(find.text('المزيد').first);
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'Cairo',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'capture the 2026-11-06 trade, invoice, inventory, and more screens',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const cases = <(Size, double)>[
        (Size(360, 800), 1),
        (Size(390, 844), 1),
        (Size(1440, 900), 1),
        (Size(360, 800), 1.3),
      ];
      for (final dark in [false, true]) {
        for (final item in cases) {
          final size = item.$1;
          final scale = item.$2;
          final gateway = Batch2TradeGateway();
          await _pump(
            tester,
            dark: dark,
            size: size,
            scale: scale,
            home: FinancialTradeScreen(
              kind: FinancialKind.sale,
              gateway: gateway,
              statusGateway: gateway,
              userId: 'owner-1',
              shopId: 'shop-1',
            ),
          );
          await _save(tester, _label('sale-switch-off', dark, size, scale));
          await chooseTradeItem(tester, 'أخرى');
          await revealTrade(tester, find.byKey(const Key('trade-select-دبلة')));
          expect(find.byKey(const Key('trade-select-ميدالية')), findsOneWidget);
          await _save(tester, _label('sale-other-grid', dark, size, scale));
          await revealTrade(
            tester,
            find.byKey(const Key('trade-line-pricing')),
          );
          await tester.tap(find.byKey(const Key('trade-line-pricing')));
          await tester.pumpAndSettle();
          await chooseTradeItem(tester, 'جنيهات');
          await tester.tap(find.byKey(const Key('nominal-select-0')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('nominal-apply')));
          await tester.pumpAndSettle();
          await revealTrade(tester, find.byKey(const Key('trade-count-0')));
          expect(
            tester
                .widget<TextField>(find.byKey(const Key('trade-count-0')))
                .readOnly,
            isTrue,
          );
          await _save(tester, _label('sale-locked-count', dark, size, scale));
          await revealTrade(
            tester,
            find.byKey(const Key('trade-customer-disclosure')),
          );
          await tester.tap(find.byKey(const Key('trade-customer-disclosure')));
          await tester.pumpAndSettle();
          expect(find.text('اسم العميل (اختياري)'), findsWidgets);
          await _save(tester, _label('sale-customer', dark, size, scale));

          await _pump(
            tester,
            dark: dark,
            size: size,
            scale: scale,
            home: FinancialTradeScreen(
              kind: FinancialKind.purchase,
              gateway: gateway,
              statusGateway: gateway,
              userId: 'owner-1',
              shopId: 'shop-1',
            ),
          );
          await chooseTradeItem(tester, 'خاتم');
          await revealTrade(tester, find.byKey(const Key('trade-grams-0')));
          await _save(tester, _label('purchase-ring', dark, size, scale));

          final bars = [
            for (final suggestion in builtinNominalWeightSuggestions)
              if (suggestion.category == 'bullion') suggestion,
          ];
          await _pump(
            tester,
            dark: dark,
            size: size,
            scale: scale,
            home: Scaffold(
              body: TradeNominalPicker(category: 'bullion', suggestions: bars),
            ),
          );
          await tester.tap(find.byKey(const Key('nominal-select-0')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('nominal-qty-row-0')), findsOneWidget);
          await _save(tester, _label('bars-picker', dark, size, scale));

          await _pump(
            tester,
            dark: dark,
            size: size,
            scale: scale,
            home: Scaffold(
              body: InvoicePdfShareDialog(
                gateway: _InvoiceGateway(),
                userId: completionUser,
                shopId: completionShop,
                operationId: _operationId,
                canRead: () => true,
                canWrite: () => true,
              ),
            ),
          );
          expect(find.byKey(const Key('invoice-whatsapp-pdf')), findsOneWidget);
          await _save(tester, _label('invoice-dialog', dark, size, scale));

          await _pump(
            tester,
            dark: dark,
            size: size,
            scale: scale,
            home: InventoryScreen(
              gateway: _ReadyInventory(),
              statusGateway: QuietOpening(),
              userId: userId,
              shopId: shopId,
              shopName: 'متجر',
              readOnly: false,
              onboardingStore: MemoryGuide(),
              store: MemoryLocker(),
            ),
          );
          expect(find.byKey(const Key('inventory-new-item')), findsOneWidget);
          expect(
            find.text(
              'تعذر تحميل بعض خيارات الكتالوج. حدّث الاتصال قبل اختيار هوية جديدة.',
            ),
            findsNothing,
          );
          final wrap = tester.widget<Wrap>(
            find.byKey(const Key('inventory-karat-all-0')),
          );
          expect(
            [
              for (final child in wrap.children)
                ((child as ChoiceChip).label as Text).data,
            ],
            ['الكل', '18', '21', '24', '22', '14'],
          );
          await _save(tester, _label('inventory-top', dark, size, scale));

          final messages = MessageFake();
          await _pump(
            tester,
            dark: dark,
            size: size,
            scale: scale,
            home: ShopWorkspace(
              shop: const ShopAccount(
                id: messageShop,
                name: 'متجر تجريبي',
                role: 'owner',
                entitlement: ShopEntitlement.active,
              ),
              onSignOut: () async {},
              onToggleTheme: (_) async {},
              appVersion: '1.4.2',
              messageBuilder: (_) => MessageSettingsScreen(
                gateway: messages,
                store: MessageLocker(),
                userId: messageUser,
                shopId: messageShop,
                canRead: () => true,
                canWrite: () => messages.writable,
                newKey: () => messageKey,
              ),
            ),
          );
          await _openMore(tester);
          await tester.scrollUntilVisible(
            find.byKey(const Key('workspace-invoice-message')),
            200,
          );
          expect(
            find.byKey(const Key('workspace-invoice-message')),
            findsOneWidget,
          );
          await _save(tester, _label('more-message-link', dark, size, scale));
          await tester.tap(find.byKey(const Key('workspace-invoice-message')));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('message-editor')), findsOneWidget);
          await _save(tester, _label('message-editor', dark, size, scale));
        }
      }
    },
  );
}

final class _ReadyInventory extends QuietInventory {
  _ReadyInventory() : super(null);

  @override
  Future<ReadPage<CatalogProduct>> products({
    required String callerUserId,
    String? query,
    String? cursor,
  }) async => const ReadPage.ready([], null);

  @override
  Future<ReadPage<CatalogDenomination>> denominations({
    required String callerUserId,
    String? query,
    String? cursor,
  }) async => const ReadPage.ready([], null);

  @override
  Future<ReadPage<CatalogCoin>> coins({
    required String callerUserId,
    String? query,
    String? cursor,
  }) async => const ReadPage.ready([], null);
}

final class _InvoiceGateway extends FakeFinancialGateway {
  @override
  Future<Map<String, Object?>> operation({
    required String callerUserId,
    required String operationId,
  }) async {
    final base = syntheticMessageOperation();
    return {...base, 'operation_id': operationId, 'shop_id': completionShop};
  }
}
