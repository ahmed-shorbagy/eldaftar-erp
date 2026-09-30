import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/daily_close_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_trade_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _UnusedGateway implements FinancialGateway, OpeningGateway {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _boundary = Key('financial-capture-boundary');

Future<void> _save(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundary),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/financial-flow-review');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = await File('assets/fonts/NotoSansArabic.ttf').readAsBytes();
    await (FontLoader(
      'NotoSansArabic',
    )..addFont(Future<ByteData>.value(ByteData.sublistView(font)))).load();
    final icons = await File(
      r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future<ByteData>.value(ByteData.sublistView(icons)))).load();
  });
  final gateway = _UnusedGateway();
  for (final width in [320.0, 1440.0]) {
    for (final dark in [false, true]) {
      final suffix = '${dark ? 'dark' : 'light'}-${width.toInt()}';
      testWidgets('captures sale entry and review $suffix', (tester) async {
        tester.view.physicalSize = Size(width, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ar'),
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: RepaintBoundary(
              key: _boundary,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: FinancialTradeScreen(
                  kind: FinancialKind.sale,
                  gateway: gateway,
                  statusGateway: gateway,
                  userId: 'capture-owner',
                  shopId: 'capture-shop',
                ),
              ),
            ),
          ),
        );
        await _save(tester, 'sale-entry-$suffix');
        await tester.enterText(
          find.byKey(const Key('trade-name-0')),
          'خاتم ذهب',
        );
        await tester.enterText(find.byKey(const Key('trade-grams-0')), '1.830');
        await tester.dragUntilVisible(
          find.byKey(const Key('trade-tender-amount-0')),
          find.byType(ListView),
          const Offset(0, -250),
        );
        await tester.enterText(
          find.byKey(const Key('trade-tender-amount-0')),
          '4200.25',
        );
        await tester.tap(find.byKey(const Key('trade-review')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('trade-confirm')), findsOneWidget);
        await _save(tester, 'sale-review-$suffix');
      });
      testWidgets('captures manual close $suffix', (tester) async {
        tester.view.physicalSize = Size(width, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ar'),
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: RepaintBoundary(
              key: _boundary,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: DailyCloseScreen(
                  gateway: gateway,
                  statusGateway: gateway,
                  userId: 'capture-owner',
                  shopId: 'capture-shop',
                  day: const FinancialDayState(
                    state: 'open',
                    dayId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
                    dayVersion: 2,
                    counts: {
                      'cash': {
                        'cash': '10000',
                        'instant_transfer': '0',
                        'wallet': '0',
                        'card': '0',
                      },
                      'stock': [],
                      'scrap': [],
                    },
                  ),
                ),
              ),
            ),
          ),
        );
        await _save(tester, 'close-entry-$suffix');
      });
      testWidgets('captures partial purchase review $suffix', (tester) async {
        tester.view.physicalSize = Size(width, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ar'),
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: RepaintBoundary(
              key: _boundary,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: FinancialTradeScreen(
                  kind: FinancialKind.purchase,
                  gateway: gateway,
                  statusGateway: gateway,
                  userId: 'capture-owner',
                  shopId: 'capture-shop',
                ),
              ),
            ),
          ),
        );
        await tester.enterText(find.byKey(const Key('trade-name-0')), 'سوار');
        await tester.enterText(
          find.byKey(const Key('trade-grams-0')),
          '10.000',
        );
        await tester.dragUntilVisible(
          find.byKey(const Key('trade-purchase-price')),
          find.byType(ListView),
          const Offset(0, -250),
        );
        await tester.enterText(
          find.byKey(const Key('trade-purchase-price')),
          '60000',
        );
        await tester.enterText(
          find.byKey(const Key('trade-seller-name')),
          'تاجر تجريبي',
        );
        await tester.dragUntilVisible(
          find.byKey(const Key('trade-tender-amount-0')),
          find.byType(ListView),
          const Offset(0, -250),
        );
        await tester.enterText(
          find.byKey(const Key('trade-tender-amount-0')),
          '20000',
        );
        await tester.tap(find.byKey(const Key('trade-review')));
        await tester.pumpAndSettle();
        expect(find.textContaining('يبقى مستحقاً للبائع'), findsOneWidget);
        await _save(tester, 'partial-purchase-review-$suffix');
      });
      testWidgets('captures scrap cash review $suffix', (tester) async {
        tester.view.physicalSize = Size(width, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('ar'),
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: RepaintBoundary(
              key: _boundary,
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: FinancialTradeScreen(
                  kind: FinancialKind.scrapSale,
                  gateway: gateway,
                  statusGateway: gateway,
                  userId: 'capture-owner',
                  shopId: 'capture-shop',
                ),
              ),
            ),
          ),
        );
        await _save(tester, 'scrap-sale-entry-$suffix');
        await tester.enterText(find.byKey(const Key('trade-name-0')), 'كسر');
        await tester.enterText(find.byKey(const Key('trade-grams-0')), '0.375');
        await tester.dragUntilVisible(
          find.byKey(const Key('trade-tender-amount-0')),
          find.byType(ListView),
          const Offset(0, -250),
        );
        await tester.enterText(
          find.byKey(const Key('trade-tender-amount-0')),
          '125.25',
        );
        await tester.tap(find.byKey(const Key('trade-review')));
        await tester.pumpAndSettle();
        expect(find.textContaining('ينقص الكسر'), findsOneWidget);
        await _save(tester, 'scrap-sale-review-$suffix');
      });
    }
  }
}
