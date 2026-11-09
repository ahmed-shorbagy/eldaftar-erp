// Regressions for the 2026-11-09 review of batches A and B.
import 'dart:convert';
import 'dart:io';

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/ledger_activity.dart';
import 'package:eldafttar/src/features/daily_ledger/application/ledger_date_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/data/daily_ledger_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/data/ledger_date_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/closing_item_grid.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/closing_item_grid_view.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/confirmed_ledger_dashboard.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'batch2_trade_support.dart';
import 'ledger_revision_test_support.dart';
import 'meeting_calendar_and_count_test.dart' show calendarBody;

const _openDay = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';

class _DayFeed implements LedgerFeedGateway, LedgerDateGateway {
  final dayIds = <String?>[];
  final cursors = <String?>[];

  @override
  Future<LedgerOperationPage> operationPage({
    required String callerUserId,
    required String shopId,
    required String? dayId,
    required String? beforeSequence,
    required String? afterSequence,
    required int limit,
  }) => throw UnimplementedError();

  @override
  Future<LedgerDateSnapshot> readLedgerDate({
    required String userId,
    required String shopId,
    String? businessDate,
    String? beforeSequence,
    String? dayId,
  }) async {
    dayIds.add(dayId);
    cursors.add(beforeSequence);
    final raw = dateJson(date: businessDate!);
    return parseLedgerDate({
      ...raw,
      'feed_page': {...(raw['feed_page']! as Map), 'server_sequence': '20'},
    }, shopId);
  }
}

DailyLedgerView _home({required List<String> dayIds}) => parseDailyLedger({
  ...calendarBody(),
  'journal_context': {
    ...(calendarBody()['journal_context']! as Map),
    'business_date': '2026-10-18',
    'day_ids': dayIds,
  },
  'feed_page': {
    'limit': 100,
    'has_more': true,
    'direction': 'desc',
    'next_before_sequence': '9',
    'server_sequence': '20',
    'snapshot_sequence': '20',
  },
});

Widget _host(Widget child) => MaterialApp(
  locale: const Locale('ar'),
  theme: AppTheme.light(),
  home: Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(body: SingleChildScrollView(child: child)),
  ),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'home older pages read the open day only, not the calendar date',
    () async {
      final feed = _DayFeed();
      final controller = LedgerActivityController()
        ..adoptSummary(
          userId: revisionUser,
          shopId: revisionShop,
          ledger: _home(dayIds: const [_openDay]),
        );
      expect(controller.state.olderCursor, '9');
      await controller.loadOlder(gateway: feed, userId: revisionUser);
      expect(feed.dayIds, [_openDay]);
      expect(feed.cursors, ['9']);
    },
  );

  test('HTTP day read calls get_ledger_day_v1 and checks the day', () async {
    final calls = <(String, Map)>[];
    final gateway = HttpOpeningGateway(
      supabaseUrl: 'https://example.test',
      publishableKey: 'public',
      accessToken: () => 'token',
      currentUserId: () => revisionUser,
      client: MockClient((request) async {
        calls.add((request.url.path, jsonDecode(request.body) as Map));
        return http.Response(
          jsonEncode(dateJson(date: '2026-10-18')),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final snapshot = await gateway.readLedgerDate(
      userId: revisionUser,
      shopId: revisionShop,
      businessDate: '2026-10-18',
      dayId: revisionDay,
    );
    expect(snapshot.dayIds, [revisionDay]);
    expect(calls.single.$1, endsWith('/rpc/get_ledger_day_v1'));
    expect(calls.single.$2, {
      'p_day_id': revisionDay,
      'p_before_sequence': null,
      'p_limit': 100,
    });
    await expectLater(
      gateway.readLedgerDate(
        userId: revisionUser,
        shopId: revisionShop,
        dayId: _openDay,
      ),
      throwsFormatException,
    );
  });

  group('closing grid', () {
    final grid = ClosingItemGrid.build(
      bookStock: const [
        {'category': 'worked_jewelry', 'karat': 18, 'count': '2'},
        {'category': 'worked_jewelry', 'karat': 21, 'count': '2'},
        {'category': 'coin', 'karat': 21, 'count': '1'},
      ],
      shopNames: const [],
    );
    Map<String, TextEditingController> controllers() => {
      for (final row in grid.rows)
        for (final karat in row.karats)
          ClosingItemGridView.cellKey(row.name, karat): TextEditingController(),
    };

    for (final weights in [false, true]) {
      testWidgets('cells sit under their karat heading (weights: $weights)', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          _host(
            ClosingItemGridView(
              grid: grid,
              counts: controllers(),
              weights: controllers(),
              showWeights: weights,
              onShowWeights: (_) {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        final heading21 = tester.getRect(find.text('عيار 21'));
        final ring21 = tester.getRect(
          find.byKey(const Key('close-count-0-21')),
        );
        expect(ring21.center.dx, closeTo(heading21.center.dx, 41));
        expect(ring21.width, weights ? 80 : 64);
        if (weights) {
          final weight21 = tester.getRect(
            find.byKey(const Key('close-weight-0-21')),
          );
          expect(weight21.left, ring21.left);
          expect(weight21.width, ring21.width);
        }
        // The coin row names its karat under its own heading.
        expect(find.byKey(const Key('close-other-heading')), findsOneWidget);
        expect(find.text('جنيهات · عيار 21'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('no reset card before any close; no archive without reports', (
    tester,
  ) async {
    DailyLedgerView view({String? closed}) => parseDailyLedger({
      ...calendarBody(),
      'day_reset': true,
      'last_closed_business_date': closed,
    });
    await tester.pumpWidget(
      _host(
        ConfirmedLedgerDashboard(
          ledger: view(),
          shopId: 'shop-never-closed',
          onOpenDay: () {},
          onOpenArchive: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ledger-day-reset')), findsNothing);
    await tester.pumpWidget(
      _host(
        ConfirmedLedgerDashboard(
          ledger: view(closed: '2026-11-08'),
          shopId: 'shop-no-reports',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ledger-day-reset')), findsOneWidget);
    expect(find.byKey(const Key('ledger-day-reset-archive')), findsNothing);
    expect(find.byKey(const Key('ledger-day-reset-open')), findsNothing);
  });

  testWidgets('a purchase keeps its notes field and seller labels', (
    tester,
  ) async {
    final gateway = Batch2TradeGateway();
    await pumpTradeScreen(
      tester,
      gateway: gateway,
      statusGateway: gateway,
      kind: FinancialKind.purchase,
      size: const Size(390, 900),
    );
    await revealTrade(
      tester,
      find.byKey(const Key('trade-customer-disclosure')),
    );
    await tester.tap(find.byKey(const Key('trade-customer-disclosure')));
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل البائع (اختياري)'), findsOneWidget);
    expect(find.byKey(const Key('trade-note')), findsOneWidget);
  });

  test('purchase screens no longer show the payable labels', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final text = file.readAsStringSync();
      for (final phrase in const [
        'سداد مبلغ مستحق',
        'المدفوع عند الشراء',
        'المستحق للبائع',
      ]) {
        if (text.contains(phrase)) offenders.add('${file.path}: $phrase');
      }
    }
    expect(offenders, isEmpty);
  });
}
