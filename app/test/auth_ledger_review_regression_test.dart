import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_journal_table.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/confirmed_ledger_dashboard.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ledger_journal_table_test.dart' show line, items;

DailyLedgerView balance(String piastres, String pounds) => DailyLedgerView(
  state: 'confirmed',
  entitlementStatus: 'active',
  canConfirm: true,
  businessDay: null,
  stock: const [],
  scrap: const [],
  feed: const [],
  cash: [
    LedgerCashLine(
      method: 'cash',
      labelAr: 'نقدي',
      piastres: piastres,
      pounds: pounds,
    ),
  ],
);

Widget host(Widget child, {double scale = 1}) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: AppTheme.dark(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'old hidden summary still shows exactly six at enlarged phone width',
    (t) async {
      SharedPreferences.setMockInitialValues({
        'ledger_layout_legacy': [
          'hidden:metrics',
          'metric:operations',
          'hidden:metric:sale',
        ],
      });
      t.view.physicalSize = const Size(320, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(
        host(
          ConfirmedLedgerDashboard(
            ledger: balance('10000', '100'),
            shopId: 'legacy',
          ),
          scale: 1.7,
        ),
      );
      await t.pumpAndSettle();
      final strip = find.byKey(const Key('ledger-metric-strip'));
      expect(strip, findsOneWidget);
      final ids = [
        'ledger-total-cash',
        'ledger-metric-sale_karat_18',
        'ledger-metric-sale_karat_21',
        'ledger-metric-sale_karat_24',
        'ledger-metric-sale',
        'ledger-metric-purchase',
        'ledger-metric-sale_gold',
        'ledger-metric-purchase_gold',
        'ledger-metric-expense',
      ];
      expect(
        ids.where(
          (id) => find
              .descendant(of: strip, matching: find.byKey(Key(id)))
              .evaluate()
              .isNotEmpty,
        ),
        hasLength(6),
      );
      expect(find.byKey(const Key('ledger-show-metrics')), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'operation card is numbered, opens details, and shows items without a toggle',
    (t) async {
      var reads = 0, opens = 0;
      await t.pumpWidget(
        host(
          LedgerOperationTable(
            line: line('legacy'),
            position: 3,
            loadItems: (_) async {
              reads++;
              return items;
            },
            onOpen: () => opens++,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);
      expect(find.byType(Table), findsOneWidget);
      expect(reads, 1);
      expect(find.text('خاتم اختبار'), findsOneWidget);
      await t.tap(find.byKey(const Key('ledger-open-sale-legacy')));
      expect(opens, 1);
      expect(t.takeException(), isNull);
    },
  );
}
