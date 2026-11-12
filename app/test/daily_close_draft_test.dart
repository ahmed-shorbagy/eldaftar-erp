import 'package:eldafttar/src/features/daily_ledger/application/close_count_drafts.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/daily_close_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'financial_trade_screen_test.dart' show FakeFinancialGateway;

const _day = FinancialDayState(
  state: 'open',
  dayId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  businessDate: '2026-11-11',
  dayVersion: 3,
  counts: {
    'cash': {
      'cash': '100',
      'instant_transfer': '0',
      'wallet': '0',
      'card': '0',
    },
    'stock': [],
    'scrap': [],
  },
);

const _scope = DraftScope(
  userId: 'owner-close',
  shopId: 'shop-close',
  dayId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
  dayVersion: 3,
);

Future<void> _pumpHost(WidgetTester tester, CloseCountDrafts drafts) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      theme: AppTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                key: const Key('open-close'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<bool>(
                    builder: (_) => DailyCloseScreen(
                      gateway: FakeFinancialGateway(),
                      statusGateway: FakeFinancialGateway(),
                      userId: 'owner-close',
                      shopId: 'shop-close',
                      day: _day,
                      drafts: drafts,
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-close')));
  await tester.pumpAndSettle();
}

Future<void> _systemBack(WidgetTester tester) async {
  final dynamic state = tester.state(find.byType(Navigator));
  await (state as NavigatorState).maybePop();
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('Back with no counts leaves without asking', (tester) async {
    await _pumpHost(tester, MemoryCloseCountDrafts());
    await _systemBack(tester);
    expect(find.byKey(const Key('app-confirm')), findsNothing);
    expect(find.byKey(const Key('open-close')), findsOneWidget);
  });

  testWidgets('Back with counts asks; «متابعة العدّ» keeps the form', (
    tester,
  ) async {
    final drafts = MemoryCloseCountDrafts();
    await _pumpHost(tester, drafts);
    await tester.enterText(find.byKey(const Key('close-cash-cash')), '100');
    await tester.pump(const Duration(milliseconds: 500));
    expect(drafts.stored[_scope.storageKey], {'cash:cash': '100'});

    await _systemBack(tester);
    expect(find.byKey(const Key('app-confirm')), findsOneWidget);
    expect(find.text('الخروج من التقفيل؟'), findsOneWidget);
    await tester.tap(find.byKey(const Key('close-leave-cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('close-cash-cash')), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
  });

  testWidgets('«خروج» leaves and keeps the draft for next time', (
    tester,
  ) async {
    final drafts = MemoryCloseCountDrafts();
    await _pumpHost(tester, drafts);
    await tester.enterText(find.byKey(const Key('close-cash-cash')), '75');
    await _systemBack(tester);
    await tester.tap(find.byKey(const Key('close-leave-confirm')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('open-close')), findsOneWidget);
    expect(drafts.stored[_scope.storageKey], {'cash:cash': '75'});

    await tester.tap(find.byKey(const Key('open-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('close-draft-restored')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('close-cash-cash')))
          .controller!
          .text,
      '75',
    );
  });

  testWidgets('a saved draft is restored with a banner and can be cleared', (
    tester,
  ) async {
    final drafts = MemoryCloseCountDrafts()
      ..stored[_scope.storageKey] = {'cash:cash': '42', 'cash:wallet': '7'};
    await _pumpHost(tester, drafts);
    expect(find.byKey(const Key('close-draft-restored')), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('close-cash-cash')))
          .controller!
          .text,
      '42',
    );
    await tester.tap(find.byKey(const Key('close-draft-discard')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('close-draft-restored')), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('close-cash-cash')))
          .controller!
          .text,
      isEmpty,
    );
    expect(drafts.stored, isEmpty);
  });

  testWidgets('a draft for another day version is not restored', (
    tester,
  ) async {
    final drafts = MemoryCloseCountDrafts()
      ..stored['close-count-draft:owner-close:shop-close:${_day.dayId}:2'] = {
        'cash:cash': '42',
      };
    await _pumpHost(tester, drafts);
    expect(find.byKey(const Key('close-draft-restored')), findsNothing);
  });
}
