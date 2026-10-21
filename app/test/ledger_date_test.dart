import 'dart:async';
import 'dart:convert';
import 'package:eldafttar/src/features/daily_ledger/application/ledger_date_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/data/ledger_date_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_date_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'ledger_revision_test_support.dart';
import 'ledger_feed_merge_test.dart' show line;
import 'ledger_trade_change_test.dart' show revisionHost;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('date read validates real dates, shop, empty day and exact summary', () {
    final raw = dateJson(rows: []);
    final value = parseLedgerDate(raw, revisionShop);
    expect(value.summary.salePiastres, '0');
    expect(value.dayIds, isEmpty);
    for (final bad in ['2026-02-30', '2026-10-20', '26-10-18']) {
      expect(
        () => parseLedgerDate({...raw, 'business_date': bad}, revisionShop),
        throwsFormatException,
      );
    }
    expect(
      () => parseLedgerDate({...raw, 'shop_id': revisionDay}, revisionShop),
      throwsFormatException,
    );
    expect(
      () => parseLedgerDate({
        ...raw,
        'day_ids': [revisionDay, revisionDay],
      }, revisionShop),
      throwsFormatException,
    );
    expect(
      () => parseLedgerDate({
        ...raw,
        'day_summary': {...(raw['day_summary'] as Map), 'sale_piastres': '1'},
      }, revisionShop),
      throwsFormatException,
    );
  });
  test(
    'HTTP initial request uses server date and rejects a mismatched historical date',
    () async {
      final bodies = <Map>[];
      final gateway = HttpOpeningGateway(
        supabaseUrl: 'https://example.test',
        publishableKey: 'public',
        accessToken: () => 'token',
        currentUserId: () => revisionUser,
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map);
          return http.Response(
            jsonEncode(dateJson(date: '2026-10-19')),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      expect(
        (await gateway.readLedgerDate(
          userId: revisionUser,
          shopId: revisionShop,
        )).businessDate,
        '2026-10-19',
      );
      expect(bodies.single, {
        'p_business_date': null,
        'p_before_sequence': null,
        'p_limit': 100,
      });
      await expectLater(
        gateway.readLedgerDate(
          userId: revisionUser,
          shopId: revisionShop,
          businessDate: '2026-10-18',
        ),
        throwsFormatException,
      );
    },
  );
  test('late HTTP response cannot cross the owner boundary', () async {
    var owner = revisionUser;
    final reply = Completer<http.Response>();
    final gateway = HttpOpeningGateway(
      supabaseUrl: 'https://example.test',
      publishableKey: 'public',
      accessToken: () => 'token',
      currentUserId: () => owner,
      client: MockClient((request) => reply.future),
    );
    final future = gateway.readLedgerDate(
      userId: revisionUser,
      shopId: revisionShop,
    );
    owner = 'other';
    reply.complete(
      http.Response(
        jsonEncode(dateJson()),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await expectLater(future, throwsA(anything));
  });
  Future<void> pumpDate(
    WidgetTester t,
    RevisionGateway gateway, {
    bool Function()? canRead,
    Listenable? ticks,
  }) async {
    await t.pumpWidget(
      revisionHost(
        LedgerDateScreen(
          gateway: gateway,
          userId: revisionUser,
          shopId: revisionShop,
          canRead: canRead ?? () => true,
          syncTicks: ticks,
          onOperation: (_) async {},
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'historical page uses selected date, no invented balance and bounded server pagination',
    (t) async {
      final gateway = RevisionGateway()
        ..dateValue = parseLedgerDate(
          dateJson(more: true, before: '2'),
          revisionShop,
        );
      await pumpDate(t, gateway);
      expect(gateway.dates, [null]);
      expect(find.byKey(const Key('date-metric-total_cash')), findsNothing);
      expect(find.byKey(const Key('ledger-select-date')), findsOneWidget);
      gateway.dateValue = parseLedgerDate(
        dateJson(rows: [line(1, kind: 'sale')]),
        revisionShop,
      );
      await t.scrollUntilVisible(
        find.byKey(const Key('ledger-date-older')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(
        t.element(find.byKey(const Key('ledger-date-older'))),
        alignment: 0.5,
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('ledger-date-older')));
      await t.pumpAndSettle();
      expect(gateway.dates.last, '2026-10-18');
      expect(gateway.cursors.last, '2');
      expect(
        find.byKey(ValueKey('dated-${line(2, kind: 'sale').operationId}')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('dated-${line(1, kind: 'sale').operationId}')),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'date picker is capped by server shop date and loads chosen day',
    (t) async {
      final gateway = RevisionGateway();
      await pumpDate(t, gateway);
      await t.tap(find.byKey(const Key('ledger-select-date')));
      await t.pumpAndSettle();
      final picker = t.widget<DatePickerDialog>(find.byType(DatePickerDialog));
      expect(picker.lastDate, DateTime(2026, 10, 19));
      gateway.dateValue = parseLedgerDate(
        dateJson(date: '2026-10-18', rows: []),
        revisionShop,
      );
      await t.tap(find.text('عرض الدفتر'));
      await t.pumpAndSettle();
      expect(gateway.dates.last, '2026-10-18');
      await t.scrollUntilVisible(
        find.byKey(const Key('ledger-date-empty')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('ledger-date-empty')), findsOneWidget);
    },
  );
  testWidgets('lost access hides data and ignores a late historical read', (
    t,
  ) async {
    var allowed = true;
    final ticks = ChangeNotifier();
    final gateway = RevisionGateway();
    await pumpDate(t, gateway, canRead: () => allowed, ticks: ticks);
    gateway.heldDate = Completer<LedgerDateSnapshot>();
    ticks.notifyListeners();
    await t.pump();
    allowed = false;
    ticks.notifyListeners();
    await t.pump();
    gateway.heldDate!.complete(parseLedgerDate(dateJson(), revisionShop));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('date-metric-sale')), findsNothing);
    expect(
      find.text('لم تعد بيانات الدفتر متاحة لهذا الحساب.'),
      findsOneWidget,
    );
  });
}
