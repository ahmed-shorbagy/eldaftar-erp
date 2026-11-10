import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/nominal_weight_suggestions.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/trade_nominal_picker.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'batch2_trade_support.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets(
    'the weight helper is gone and a picked coin count stays locked',
    (tester) async {
      final gateway = Batch2TradeGateway();
      await pumpTradeScreen(
        tester,
        gateway: gateway,
        statusGateway: gateway,
        kind: FinancialKind.sale,
      );
      await chooseTradeItem(tester, 'خواتم');
      expect(
        find.text('دقة 0.01 جرام · منزلتان عشريتان كحد أقصى'),
        findsNothing,
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('trade-count-0')))
            .readOnly,
        isFalse,
      );
      await chooseTradeItem(tester, 'جنيهات');
      await tester.tap(find.byKey(const Key('nominal-select-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nominal-apply')));
      await tester.pumpAndSettle();
      final locked = tester.widget<TextField>(
        find.byKey(const Key('trade-count-0')),
      );
      expect(locked.readOnly, isTrue);
      final before = locked.controller!.text;
      await tester.enterText(find.byKey(const Key('trade-count-0')), '9');
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('trade-count-0')))
            .controller!
            .text,
        before,
      );
      await tester.tap(find.byKey(const Key('trade-count-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nominal-apply')), findsOneWidget);
    },
  );

  testWidgets('the customer label stays inside the expanded section', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.sale,
      size: const Size(360, 800),
    );
    await revealTrade(
      tester,
      find.byKey(const Key('trade-customer-disclosure')),
    );
    await tester.tap(find.byKey(const Key('trade-customer-disclosure')));
    await tester.pumpAndSettle();
    final label = tester.getRect(find.text('اسم العميل (اختياري)'));
    final tile = tester.getRect(
      find.byKey(const Key('trade-customer-disclosure')),
    );
    expect(label.top, greaterThanOrEqualTo(tile.top));
    expect(label.bottom, lessThanOrEqualTo(tile.bottom));
  });

  testWidgets('other tiles stay compact', (tester) async {
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.sale,
    );
    await chooseTradeItem(tester, 'أخرى');
    expect(
      tester.getSize(find.byKey(const Key('trade-select-دبل'))).height,
      lessThanOrEqualTo(44),
    );
  });

  testWidgets('a selected bar quantity stays on screen', (tester) async {
    final bars = [
      for (final suggestion in builtinNominalWeightSuggestions)
        if (suggestion.category == 'bullion') suggestion,
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 640)),
          child: const Scaffold(body: SizedBox.shrink()),
        ),
      ),
    );
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: TradeNominalPicker(category: 'bullion', suggestions: bars),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final chip = find.byKey(const Key('nominal-select-8'));
    await tester.scrollUntilVisible(chip, 80);
    await tester.drag(find.byType(ListView), const Offset(0, -48));
    await tester.pumpAndSettle();
    await tester.tap(chip);
    await tester.pumpAndSettle();
    final row = tester.getRect(find.byKey(const Key('nominal-qty-row-8')));
    expect(row.top, greaterThanOrEqualTo(0));
    expect(row.bottom, lessThanOrEqualTo(640));
    expect(
      find.text(
        'اضغط النوع لاختياره، ثم حدد العدد بالأسفل.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('more shows the app version', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: const Locale('ar'),
        home: ShopWorkspace(
          shop: const ShopAccount(
            id: 'shop-1',
            name: 'متجر',
            role: 'owner',
            entitlement: ShopEntitlement.active,
          ),
          onSignOut: () async {},
          onToggleTheme: (_) async {},
          appVersion: '1.4.2',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workspace-nav-4')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('workspace-app-version')),
      200,
    );
    expect(find.byKey(const Key('workspace-app-version')), findsOneWidget);
    expect(find.textContaining('1.4.2'), findsOneWidget);
  });
}
