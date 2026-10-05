import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/confirmed_ledger_dashboard.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/opening_copy.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

DailyLedgerView view(int count) => DailyLedgerView(
  state: 'confirmed',
  entitlementStatus: 'active',
  canConfirm: false,
  businessDay: null,
  cash: const [],
  stock: const [],
  scrap: const [],
  feed: List.generate(
    count,
    (i) => LedgerFeedLine(
      kind: i.isEven ? 'sale' : 'purchase',
      labelAr: i.isEven ? 'بيع' : 'شراء',
      operationId: 'operation-$i',
      actorDisplayName: 'مالك تجريبي',
      occurredAt: '2026-10-04T22:30:00Z',
      occurredAtCairo: '2026-10-05T01:30:00',
      partyName: 'طرف تجريبي $i',
      totalPounds: '1234.56',
      weightGrams: '1.005',
    ),
  ),
);

Future<void> host(
  WidgetTester tester,
  Widget child, {
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a long ledger keeps home short and every record reachable', (
    tester,
  ) async {
    await host(
      tester,
      ConfirmedLedgerDashboard(ledger: view(10), shopId: 'compact'),
    );
    final initialExtent = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .maxScrollExtent;
    await host(
      tester,
      ConfirmedLedgerDashboard(ledger: view(200), shopId: 'compact'),
    );
    final longExtent = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .maxScrollExtent;
    expect(longExtent, initialExtent);
    expect(find.text('طرف تجريبي 199'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('ledger-view-all')));
    await tester.tap(find.byKey(const Key('ledger-view-all')));
    await tester.pumpAndSettle();
    expect(find.text('شراء · طرف تجريبي 199'), findsOneWidget);
    await tester.tap(find.byKey(const Key('ledger-filter-sale')));
    await tester.pumpAndSettle();
    expect(find.text('شراء · طرف تجريبي 199'), findsNothing);
    expect(find.text('بيع · طرف تجريبي 198'), findsOneWidget);
    await tester.tap(find.byKey(const Key('detail-close')));
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل اليوم'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'older records refresh in the open sheet and preserve its filter',
    (tester) async {
      var count = 4;
      var busy = false;
      late StateSetter update;
      await host(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return ConfirmedLedgerDashboard(
              ledger: view(count),
              shopId: 'paging',
              loadingOlder: busy,
              onLoadOlder: () => setState(() => busy = true),
            );
          },
        ),
      );
      await tester.ensureVisible(find.byKey(const Key('ledger-view-all')));
      await tester.tap(find.byKey(const Key('ledger-view-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ledger-filter-purchase')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('ledger-load-older')));
      await tester.tap(find.byKey(const Key('ledger-load-older')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('ledger-load-older')))
            .onPressed,
        isNull,
      );
      update(() {
        count = 6;
        busy = false;
      });
      await tester.pumpAndSettle();
      expect(find.text('شراء · طرف تجريبي 5'), findsOneWidget);
      expect(find.text('بيع · طرف تجريبي 4'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('removing the owning ledger closes its financial details', (
    tester,
  ) async {
    var visible = true;
    late StateSetter update;
    await host(
      tester,
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return visible
              ? ConfirmedLedgerDashboard(ledger: view(4), shopId: 'access')
              : const Text('يلزم تسجيل الدخول');
        },
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('ledger-view-all')));
    await tester.tap(find.byKey(const Key('ledger-view-all')));
    await tester.pumpAndSettle();
    expect(find.text('شراء · طرف تجريبي 3'), findsOneWidget);
    update(() => visible = false);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('detail-close')), findsNothing);
    expect(find.text('شراء · طرف تجريبي 3'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text keeps exact cash readable in a narrow detail sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const amount = DailyLedgerView(
      state: 'confirmed',
      entitlementStatus: 'active',
      canConfirm: false,
      businessDay: null,
      stock: [],
      scrap: [],
      feed: [],
      cash: [
        LedgerCashLine(
          method: 'cash',
          labelAr: 'نقدي',
          piastres: '100000055',
          pounds: '1000000.55',
        ),
      ],
    );
    await host(
      tester,
      const Padding(
        padding: EdgeInsets.all(16),
        child: ConfirmedLedgerDashboard(ledger: amount, shopId: 'scale'),
      ),
      textScale: 2,
    );
    expect(find.text('1 مليون'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('ledger-view-cash')));
    await tester.tap(find.byKey(const Key('ledger-view-cash')));
    await tester.pumpAndSettle();
    expect(find.text('1,000,000.55'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'short dates keep the server shop day across midnight and omit seconds',
    () {
      expect(
        formatCompactServerTimestamp('2026-10-05T01:30:00'),
        '5 أكتوبر · 01:30',
      );
      expect(
        formatCompactServerTimestamp('2026-10-04T23:59:59'),
        '4 أكتوبر · 23:59',
      );
      expect(formatCompactServerTimestamp('—'), '—');
    },
  );
}
