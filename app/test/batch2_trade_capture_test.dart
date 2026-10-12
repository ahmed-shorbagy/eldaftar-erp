import 'dart:io';
import 'dart:ui' as ui;
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_trade_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'batch2_trade_support.dart';

Future<void> saveTradeCapture(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: name);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('trade-full-capture')),
  );
  await tester.runAsync(() async {
    final picture = await boundary.toImage();
    final data = await picture.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/batch2/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    picture.dispose();
  });
}

Future<void> openCapture(
  WidgetTester tester,
  Batch2TradeGateway gateway,
  FinancialKind kind,
  bool dark, {
  double scale = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('trade-full-capture'),
      child: MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showFinancialTradeSheet(
                  context: context,
                  kind: kind,
                  gateway: gateway,
                  statusGateway: gateway,
                  userId: 'owner-1',
                  shopId: 'shop-1',
                ),
                child: const Text('فتح العملية'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('فتح العملية'));
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
    'capture sale and purchase entry, keyboard, review and success in both themes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      for (final kind in [FinancialKind.sale, FinancialKind.purchase]) {
        for (final dark in [false, true]) {
          for (final size in [
            const Size(320, 800),
            const Size(390, 844),
            const Size(1440, 900),
          ]) {
            tester.view.physicalSize = size;
            tester.view.viewInsets = const FakeViewPadding();
            final gateway = Batch2DispatchGateway();
            await openCapture(tester, gateway, kind, dark);
            final label =
                '${kind.name}-${dark ? 'dark' : 'light'}-${size.width.toInt()}';
            await saveTradeCapture(tester, '$label-entry');
            await chooseTradeItem(tester, 'خاتم');
            await enterTradeField(tester, const Key('trade-grams-0'), '1.830');
            if (kind == FinancialKind.purchase) {
              await enterTradeField(
                tester,
                const Key('trade-purchase-price'),
                '60000',
              );
            }
            await enterTradeField(
              tester,
              const Key('trade-tender-amount-0'),
              kind == FinancialKind.sale ? '4200.25' : '20000',
            );
            tester.view.viewInsets = FakeViewPadding(
              bottom: size.width < 840 ? 240 : 0,
            );
            await saveTradeCapture(tester, '$label-keyboard');
            tester.view.viewInsets = const FakeViewPadding();
            await reviewTrade(tester);
            await saveTradeCapture(tester, '$label-review');
            await tester.tap(find.byKey(const Key('trade-confirm')));
            await tester.pumpAndSettle();
            expect(
              find.byKey(const Key('trade-send-invoice')),
              kind == FinancialKind.sale ? findsOneWidget : findsNothing,
            );
            await saveTradeCapture(tester, '$label-success');
            await tester.tap(find.byKey(const Key('trade-sheet-close')));
            await tester.pumpAndSettle();
          }
        }
      }
    },
  );
  testWidgets('capture uncertain outcome at increased text scale', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final dark in [false, true]) {
      tester.view.physicalSize = const Size(320, 800);
      final gateway = Batch2TradeGateway(
        result: const FinancialUnknown(),
        statusResult: const StatusUnknown(),
      );
      await openCapture(tester, gateway, FinancialKind.sale, dark, scale: 1.5);
      await chooseTradeItem(tester, 'خاتم');
      await enterTradeField(tester, const Key('trade-grams-0'), '1.830');
      await enterTradeField(
        tester,
        const Key('trade-tender-amount-0'),
        '4200.25',
      );
      await reviewTrade(tester);
      await tester.tap(find.byKey(const Key('trade-confirm')));
      await saveTradeCapture(
        tester,
        'sale-${dark ? 'dark' : 'light'}-320-unknown-scale',
      );
      expect(find.byKey(const Key('trade-check-status')), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.byKey(const Key('trade-sheet-close')))
            .onPressed,
        isNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
