// Layout fit on a phone, at the default font and one step larger (130 %).
//
// Found on the emulator on 2026-11-18 (Arabic RTL, 411 px wide): the ledger
// summary sliced its third tile at the screen edge, the floating quick-action
// button covered the last ledger card, the «الجرد الفوري» table pushed its
// numbers to the far edge and wrapped «عدد · وزن», number fields sat on the
// left under right-aligned labels, short fields carried «0/200» counters, a
// payment label sat on its card border, and review values were the smallest
// text on the screen. Each test below fails on that layout.

import 'dart:io';

import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/confirmed_ledger_dashboard.dart';
import 'package:eldafttar/src/features/inventory/domain/inventory_item_grid.dart';
import 'package:eldafttar/src/features/inventory/presentation/inventory_item_grid_view.dart';
import 'package:eldafttar/src/features/inventory/presentation/inventory_widgets.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:eldafttar/src/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'daily_ledger_capture_test.dart' show confirmedLedger;
import 'financial_trade_screen_test.dart' show FakeFinancialGateway, pumpTrade;

const _phone = Size(411, 900);
const _scales = [1.0, 1.3];

Widget _host(Widget child, {double scale = 1, bool dark = true}) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: dark ? AppTheme.dark() : AppTheme.light(),
  builder: (context, page) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: page!,
  ),
  home: Scaffold(body: child),
);

void _phoneSize(WidgetTester tester, [Size size = _phone]) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Tiles on screen are whole: none starts before the left edge or ends after
/// the right edge.
void _expectWholeTiles(WidgetTester tester, double width) {
  final strip = find.byKey(const Key('ledger-metric-strip'));
  final tiles = find.descendant(
    of: strip,
    matching: find.byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          (key.value == 'ledger-total-cash' ||
              key.value.startsWith('ledger-metric-')) &&
          key.value != 'ledger-metric-strip' &&
          key.value != 'ledger-metric-pages';
    }),
  );
  expect(tiles, findsWidgets);
  var onScreen = 0;
  for (final element in tiles.evaluate()) {
    final rect = tester.getRect(find.byWidget(element.widget));
    if (rect.right <= 0.5 || rect.left >= width - 0.5) continue;
    onScreen++;
    expect(rect.left, greaterThanOrEqualTo(-0.5), reason: '$rect');
    expect(rect.right, lessThanOrEqualTo(width + 0.5), reason: '$rect');
  }
  // Two figures side by side on a phone, at both font sizes.
  expect(onScreen, greaterThanOrEqualTo(2));
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = await File('assets/fonts/Cairo.ttf').readAsBytes();
    await (FontLoader(
      'Cairo',
    )..addFont(Future.value(ByteData.sublistView(font)))).load();
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('ledger summary', () {
    for (final scale in _scales) {
      for (final width in [360.0, 411.0]) {
        testWidgets('shows whole tiles on every page, $width px at $scale', (
          tester,
        ) async {
          _phoneSize(tester, Size(width, 900));
          await tester.pumpWidget(
            _host(
              SingleChildScrollView(
                child: ConfirmedLedgerDashboard(
                  ledger: confirmedLedger(),
                  shopId: 'fit',
                ),
              ),
              scale: scale,
            ),
          );
          await tester.pumpAndSettle();
          _expectWholeTiles(tester, width);
          expect(find.byKey(const Key('ledger-metric-pages')), findsOneWidget);
          // The next page also lands on whole tiles.
          await tester.fling(
            find.byKey(const Key('ledger-metric-strip')),
            const Offset(300, 0),
            1500,
          );
          await tester.pumpAndSettle();
          _expectWholeTiles(tester, width);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('leaves room under the last card for the quick actions', (
      tester,
    ) async {
      _phoneSize(tester);
      await tester.pumpWidget(
        _host(
          SingleChildScrollView(
            child: ConfirmedLedgerDashboard(
              ledger: confirmedLedger(),
              shopId: 'fit',
              onExpense: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final clearance = find.byKey(const Key('ledger-fab-clearance'));
      expect(clearance, findsOneWidget);
      // The button is 56 px; the space under the last card covers it.
      expect(tester.getSize(clearance).height, greaterThanOrEqualTo(72));
    });
  });

  group('«الجرد الفوري» item table', () {
    final grid = InventoryItemGrid(
      rows: [
        InventoryGridRow(
          itemName: 'خواتم',
          cells: {
            18: InventoryGridCell(
              count: BigInt.one,
              countKnown: true,
              milligrams: BigInt.from(1830),
            ),
          },
        ),
      ],
      scrapByKarat: {},
      totals: {},
    );

    for (final scale in _scales) {
      testWidgets('keeps headings on one line and numbers near names, $scale', (
        tester,
      ) async {
        _phoneSize(tester);
        await tester.pumpWidget(
          _host(
            SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: InventoryItemGridView(
                  grid: grid,
                  order: inventoryDefaultKaratOrder,
                  expanded: false,
                  onExpanded: (_) {},
                  onOrder: () {},
                  onCell: (_, _) {},
                ),
              ),
            ),
            scale: scale,
          ),
        );
        await tester.pumpAndSettle();
        for (final element in find.text('عدد · وزن').evaluate()) {
          final paragraph = element.renderObject! as RenderParagraph;
          expect(paragraph.didExceedMaxLines, isFalse);
        }
        // The name column takes at most 40 % of the table, so the first
        // karat column starts within 60 % of the width from the left.
        final table = tester.getRect(find.byKey(const Key('inventory-grid')));
        final cell = tester.getRect(
          find.byKey(const Key('inventory-grid-cell-خواتم-18')),
        );
        expect(
          cell.right,
          greaterThanOrEqualTo(table.left + table.width * 0.5),
        );
        // An empty scrap cell reads 0.00, not a blank band.
        expect(
          find.descendant(
            of: find.byKey(const Key('inventory-grid-scrap')),
            matching: find.text('0.00'),
          ),
          findsNWidgets(2),
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('fields', () {
    testWidgets('inventory number fields sit right and carry no counter', (
      tester,
    ) async {
      _phoneSize(tester);
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => Column(
              children: [
                inventoryField(
                  context: context,
                  controller: controller,
                  label: 'العدد',
                  fieldKey: const Key('count'),
                  keyboard: TextInputType.number,
                ),
                inventoryField(
                  context: context,
                  controller: controller,
                  label: 'سبب الإضافة',
                  fieldKey: const Key('reason'),
                  maxLength: 1000,
                ),
              ],
            ),
          ),
        ),
      );
      final count = tester.widget<TextField>(find.byKey(const Key('count')));
      expect(count.textAlign, TextAlign.right);
      expect(count.decoration!.counterText, '');
      final reason = tester.widget<TextField>(find.byKey(const Key('reason')));
      // A long reason keeps its count.
      expect(reason.decoration!.counterText, isNull);
    });

    testWidgets('sale count sits right and the payment label clears its card', (
      tester,
    ) async {
      await pumpTrade(tester, FakeFinancialGateway(), FinancialKind.sale);
      final countField = find.byKey(const Key('trade-count-0'));
      await tester.scrollUntilVisible(
        countField,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('trade-count-0')))
            .textAlign,
        TextAlign.right,
      );
      final method = find.byKey(const Key('trade-tender-method-0'));
      await tester.ensureVisible(method);
      await tester.pumpAndSettle();
      final card = find.ancestor(of: method, matching: find.byType(Card)).first;
      final label = find.descendant(
        of: method,
        matching: find.text('وسيلة الدفع'),
      );
      expect(
        tester.getRect(label).top,
        greaterThanOrEqualTo(tester.getRect(card).top + 2),
      );
    });
  });

  test('a value at the end of a list row reads at body size', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final style = theme.listTileTheme.leadingAndTrailingTextStyle!;
      expect(style.fontSize, AppTokens.bodySize);
      expect(style.fontWeight, FontWeight.w700);
    }
  });
}
