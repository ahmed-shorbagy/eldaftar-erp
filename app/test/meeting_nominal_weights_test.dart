import 'package:eldafttar/src/features/daily_ledger/domain/nominal_weight_suggestions.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/trade_nominal_picker.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('meeting coin denominations use their requested exact gram weights', () {
    final suggestions = nominalSuggestionsFor(category: 'coin');
    expect(
      {for (final item in suggestions) item.label: item.grams},
      {
        'ثمن جنيه': '1.000',
        'ربع جنيه': '2.000',
        'نصف جنيه': '4.000',
        'جنيه': '8.000',
        'خمسة جنيهات': '40.000',
      },
    );
    expect(suggestions.every((item) => !item.fromCatalog), isTrue);
  });

  test(
    'bullion suggestions cover quarter gram through the requested ounce',
    () {
      final weights = nominalSuggestionsFor(
        category: 'bullion',
      ).map((item) => item.grams);
      expect(weights, [
        '0.250',
        '0.500',
        '1.000',
        '2.500',
        '5.000',
        '10.000',
        '20.000',
        '25.000',
        '31.100',
      ]);
    },
  );

  test(
    'an active shop denomination remains authoritative and adds choices',
    () {
      final suggestions = nominalSuggestionsFor(
        category: 'coin',
        catalog: const [
          CatalogNominalChoice(label: 'جنيه', grams: '8.005', active: true),
          CatalogNominalChoice(label: 'جنيهان', grams: '16.000', active: true),
          CatalogNominalChoice(
            label: 'نوع متوقف',
            grams: '3.000',
            active: false,
          ),
        ],
      );
      expect(
        suggestions.singleWhere((item) => item.label == 'جنيه').grams,
        '8.005',
      );
      expect(
        suggestions.singleWhere((item) => item.label == 'جنيه').fromCatalog,
        isTrue,
      );
      expect(
        suggestions.singleWhere((item) => item.label == 'جنيهان').grams,
        '16.000',
      );
      expect(suggestions.any((item) => item.label == 'نوع متوقف'), isFalse);
    },
  );

  test(
    'mixed denominations retain their identity, counts and exact total weights',
    () {
      final coins = nominalSuggestionsFor(category: 'coin');
      final pounds = NominalSelection.tryCreate(
        coins.singleWhere((x) => x.label == 'جنيه'),
        '2',
      )!;
      final half = NominalSelection.tryCreate(
        coins.singleWhere((x) => x.label == 'نصف جنيه'),
        '1',
      )!;
      expect(pounds.count.wire, '2');
      expect(pounds.milligrams.wire, '16000');
      expect(half.milligrams.wire, '4000');
      expect(
        pounds.milligrams.value + half.milligrams.value,
        BigInt.from(20000),
      );
      expect(NominalSelection.tryCreate(coins.first, '1.5'), isNull);
      expect(NominalSelection.tryCreate(coins.first, '0'), isNull);
      expect(
        NominalSelection.tryCreate(coins.first, '9223372036854775807'),
        isNull,
      );
    },
  );

  testWidgets(
    'quantity steppers keep Arabic labels and localized digits as exact integers',
    (tester) async {
      tester.view.physicalSize = const Size(390, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          theme: AppTheme.light(),
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: SizedBox(
                height: 720,
                child: TradeNominalPicker(
                  category: 'coin',
                  suggestions: nominalSuggestionsFor(category: 'coin'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nominal-select-3')));
      await tester.pumpAndSettle();
      expect(find.byTooltip('إنقاص العدد'), findsOneWidget);
      expect(find.byTooltip('زيادة العدد'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('nominal-count-3')), '٢');
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('nominal-count-3')))
            .controller!
            .text,
        '2',
      );
      expect(find.textContaining('16'), findsWidgets);
    },
  );
}
