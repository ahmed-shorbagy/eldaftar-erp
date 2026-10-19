import 'dart:async';

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_more_balances.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_journal_table.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/confirmed_ledger_dashboard.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ledger_more_balances_test.dart' show LiveMoreGateway, shop;
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

class ReviewBalancesGateway extends LiveMoreGateway {
  ReviewBalancesGateway() : super(balance('10000', '100'));
  bool denied = false;
  bool offline = false;
  Completer<DailyLedgerView>? held;
  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async {
    if (denied) throw const LedgerReadException('forbidden');
    if (offline) throw StateError('offline');
    final pending = held;
    if (pending != null) return pending.future;
    return super.ledger(callerUserId: callerUserId);
  }
}

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
    'collapsed legacy card is numbered, opens details, and reads items only on expansion',
    (t) async {
      var reads = 0, opens = 0;
      Future<void> pump(bool expanded) async {
        await t.pumpWidget(
          host(
            LedgerOperationTable(
              line: line('legacy'),
              position: 3,
              showDetails: expanded,
              loadItems: (_) async {
                reads++;
                return items;
              },
              onOpen: () => opens++,
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      await pump(false);
      expect(find.text('3'), findsOneWidget);
      expect(find.byType(Table), findsNothing);
      expect(reads, 0);
      await t.tap(find.byKey(const Key('ledger-open-sale-legacy')));
      expect(opens, 1);
      await pump(true);
      expect(reads, 1);
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('خاتم اختبار'), findsOneWidget);
      await pump(false);
      expect(find.byType(Table), findsNothing);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'open More breakdown follows sync, marks stale, rejects late replies and clears on denied access',
    (t) async {
      SharedPreferences.setMockInitialValues({
        'ledger_layout_more-shop': ['remaining:total_cash'],
      });
      final g = ReviewBalancesGateway();
      final ticks = ChangeNotifier();
      addTearDown(ticks.dispose);
      await t.pumpWidget(
        host(
          LedgerMoreBalances(
            shop: shop(),
            gateway: g,
            userId: 'owner-1',
            syncTicks: ticks,
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('more-cash-methods')));
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('100'),
        ),
        findsOneWidget,
      );
      g.view = balance('20000', '200');
      ticks.notifyListeners();
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('200'),
        ),
        findsOneWidget,
      );
      expect(find.text('100'), findsNothing);
      g.offline = true;
      ticks.notifyListeners();
      await t.pumpAndSettle();
      expect(find.textContaining('الأرقام المعروضة قديمة.'), findsWidgets);
      g.offline = false;
      final stale = Completer<DailyLedgerView>();
      g.held = stale;
      ticks.notifyListeners();
      await t.pump();
      await t.pump();
      g.held = null;
      g.view = balance('30000', '300');
      ticks.notifyListeners();
      await t.pumpAndSettle();
      stale.complete(balance('9900', '99'));
      await t.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('300'),
        ),
        findsOneWidget,
      );
      expect(find.text('99'), findsNothing);
      g.denied = true;
      ticks.notifyListeners();
      await t.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('300'), findsNothing);
      expect(find.byKey(const Key('more-metric-total_cash')), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
