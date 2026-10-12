import 'dart:async';

import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_trade_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'batch2_trade_support.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  for (final width in [320.0, 390.0, 1440.0]) {
    testWidgets('sale sheet stays within bounds at $width with a keyboard', (
      tester,
    ) async {
      final gateway = Batch2TradeGateway();
      final height = width >= 840 ? 900.0 : 800.0;
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showFinancialTradeSheet(
                    context: context,
                    kind: FinancialKind.sale,
                    gateway: gateway,
                    statusGateway: gateway,
                    userId: 'owner-1',
                    shopId: 'shop-1',
                  ),
                  child: const Text('فتح البيع'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('فتح البيع'));
      await tester.pumpAndSettle();
      _expectSheetBounds(tester, Size(width, height), 0);
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      _expectSheetBounds(tester, Size(width, height), 280);
      expect(find.byKey(const Key('trade-sheet-close')), findsOneWidget);
      expect(find.text('إضافة بيع'), findsOneWidget);
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('trade-sheet-body')), findsOneWidget);
      await tester.fling(
        find.byKey(const Key('trade-sheet-body')),
        const Offset(0, 400),
        800,
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('trade-sheet-body')), findsOneWidget);
      await tester.tap(find.byKey(const Key('trade-sheet-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('trade-sheet-body')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('pending sale sheet blocks close, back, and a second post', (
    tester,
  ) async {
    final gate = Completer<FinancialCommandResult>();
    final gateway = Batch2TradeGateway()..postGate = gate;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showFinancialTradeSheet(
                  context: context,
                  kind: FinancialKind.sale,
                  gateway: gateway,
                  statusGateway: gateway,
                  userId: 'owner-1',
                  shopId: 'shop-1',
                ),
                child: const Text('فتح البيع'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('فتح البيع'));
    await tester.pumpAndSettle();
    await chooseTradeItem(tester, 'خاتم');
    await enterTradeField(tester, const Key('trade-grams-0'), '1.000');
    await enterTradeField(tester, const Key('trade-tender-amount-0'), '25');
    await reviewTrade(tester);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('جارٍ حفظ العملية…'), findsOneWidget);
    final close = tester.widget<IconButton>(
      find.byKey(const Key('trade-sheet-close')),
    );
    expect(close.onPressed, isNull);
    await tester.tap(find.byKey(const Key('trade-sheet-close')));
    await tester.pump();
    expect(find.byKey(const Key('trade-sheet-body')), findsOneWidget);
    await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
    await tester.pump();
    expect(find.byKey(const Key('trade-sheet-body')), findsOneWidget);
    expect(find.text('جارٍ حفظ العملية…'), findsOneWidget);
    expect(gateway.keys, hasLength(1));
    gate.complete(const FinancialCommitted(tradeOperationId, replayed: false));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trade-success')), findsOneWidget);
    expect(gateway.keys, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}

void _expectSheetBounds(WidgetTester tester, Size view, double keyboard) {
  final body = tester.getRect(find.byKey(const Key('trade-sheet-body')));
  expect(body.width, lessThanOrEqualTo(720));
  expect(body.width, lessThanOrEqualTo(view.width + 0.1));
  expect(body.height, lessThanOrEqualTo((view.height - keyboard) * 0.84 + 0.1));
  expect(body.height, greaterThan(120));
  expect(
    tester.getSize(find.byType(BottomSheet)).height,
    lessThanOrEqualTo((view.height - keyboard) * 0.84 + keyboard + 1),
  );
  expect(body.bottom, lessThanOrEqualTo(view.height - keyboard + 1));
  expect(body.left, greaterThanOrEqualTo(-0.1));
  expect(body.right, lessThanOrEqualTo(view.width + 0.1));
  expect(tester.takeException(), isNull);
}
