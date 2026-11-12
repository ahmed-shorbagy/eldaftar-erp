import 'dart:async';

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/ledger_line_items.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_journal_table.dart';
import 'package:eldafttar/src/theme/amount_format.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LedgerFeedLine line(
  String id, {
  String? partyName = 'عميل اختبار',
  String? partyPhone = '01012345678',
}) => LedgerFeedLine(
  kind: 'sale',
  labelAr: 'بيع',
  operationId: id,
  actorDisplayName: 'مالك اختبار',
  occurredAt: '2026-10-12T09:00:00Z',
  occurredAtCairo: '2026-10-12T12:00:00',
  partyName: partyName,
  partyPhone: partyPhone,
  totalPounds: '1200000.25',
  weightGrams: '1.255',
);

const items = [
  LedgerLineItem(name: 'خاتم اختبار', grams: '1.255', karat: 18, count: '1'),
  LedgerLineItem(name: 'سلسلة اختبار', grams: '2.500', karat: 21, count: '1'),
  LedgerLineItem(name: 'تعليقة اختبار', grams: '0.501', karat: 18, count: '1'),
];

Widget surface(Widget table, {bool dark = false, double scale = 1}) =>
    MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(body: SingleChildScrollView(child: table)),
        ),
      ),
    );

void main() {
  test(
    'gold rounding preserves storage strings and avoids a negative zero',
    () {
      for (final entry in {
        '1.254': '1.25',
        '1.255': '1.26',
        '0.999': '1.00',
        '-0.004': '0.00',
        '-1.255': '−1.26',
        '9007199254740.995': '9,007,199,254,741.00',
      }.entries) {
        expect(displayGrams(entry.key), entry.value);
      }
      expect(items.first.grams, '1.255');
      expect(displayPounds('1200000.25'), '1,200,000.25');
      expect(displayGoldEffect(BigInt.from(1830)), '1.83 جرام');
      expect(
        displayGoldEffect(BigInt.from(1255)),
        '1.26 جرام (1,255 ملليجرام)',
      );
      expect(displayGoldEffect(BigInt.from(4)), '0.00 جرام (4 ملليجرام)');
    },
  );

  testWidgets('U5: an expense card shows its description once', (tester) async {
    const expense = LedgerFeedLine(
      kind: 'expense',
      labelAr: 'مصروف',
      operationId: '00000000-0000-4000-8000-0000000000e5',
      actorDisplayName: 'مالك اختبار',
      occurredAt: '2026-10-12T09:00:00Z',
      occurredAtCairo: '2026-10-12T12:00:00',
      totalPounds: '250.00',
      itemSummary: 'إيجار المحل',
    );
    await tester.pumpWidget(surface(const LedgerOperationTable(line: expense)));
    await tester.pumpAndSettle();
    expect(
      find.byKey(
        const Key(
          'ledger-expense-description-00000000-0000-4000-8000-0000000000e5',
        ),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('إيجار المحل'), findsOneWidget);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'two items, full total and disclosure in ${dark ? 'dark' : 'light'} RTL',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          surface(
            LedgerOperationTable(
              line: line('sale'),
              loadItems: (_) async => items,
            ),
            dark: dark,
            scale: 1.5,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('خاتم اختبار'), findsOneWidget);
        expect(find.text('سلسلة اختبار'), findsOneWidget);
        expect(find.text('تعليقة اختبار'), findsOneWidget);
        expect(find.text('إظهار المزيد'), findsNothing);
        expect(find.text('1,200,000.25'), findsOneWidget);
        expect(find.text('العميل: عميل اختبار'), findsOneWidget);
        expect(find.textContaining('الجوال:'), findsOneWidget);
        expect(find.textContaining('01012345678'), findsOneWidget);
        expect(find.textContaining('اسم البائع: مالك اختبار'), findsOneWidget);
        expect(find.textContaining('كاش'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('an old item response cannot replace a different operation', (
    tester,
  ) async {
    final oldResponse = Completer<List<LedgerLineItem>?>();
    final newResponse = Completer<List<LedgerLineItem>?>();
    Future<List<LedgerLineItem>?> read(String id) =>
        id == 'old' ? oldResponse.future : newResponse.future;
    await tester.pumpWidget(
      surface(LedgerOperationTable(line: line('old'), loadItems: read)),
    );
    await tester.pumpWidget(
      surface(LedgerOperationTable(line: line('new'), loadItems: read)),
    );
    newResponse.complete([items[1]]);
    await tester.pumpAndSettle();
    oldResponse.complete([items[0]]);
    await tester.pumpAndSettle();
    expect(find.text('سلسلة اختبار'), findsOneWidget);
    expect(find.text('خاتم اختبار'), findsNothing);
  });

  testWidgets('omits customer lines when name and phone are absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      surface(
        LedgerOperationTable(
          line: line('sale', partyName: null, partyPhone: null),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('اسم البائع: مالك اختبار'), findsOneWidget);
    expect(find.textContaining('العميل:'), findsNothing);
    expect(find.textContaining('الجوال:'), findsNothing);
  });

  testWidgets('failed item reads have a retry with no fabricated rows', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      surface(
        LedgerOperationTable(
          line: line('sale'),
          loadItems: (_) async {
            if (++reads == 1) throw StateError('offline');
            return items;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('اسم البائع: مالك اختبار'), findsOneWidget);
    expect(find.text('العميل: عميل اختبار'), findsOneWidget);
    expect(find.text('خاتم اختبار'), findsNothing);
    await tester.tap(find.text('تعذر تحميل الأصناف. إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(find.text('خاتم اختبار'), findsOneWidget);
  });

  testWidgets('price column appears only when the invoice has item prices', (
    tester,
  ) async {
    await tester.pumpWidget(
      surface(
        LedgerOperationTable(
          line: line('unpriced'),
          loadItems: (_) async => items,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('خاتم اختبار'), findsOneWidget);
    expect(find.text('السعر'), findsNothing);
    expect(find.text('عدد القطع'), findsNothing);

    await tester.pumpWidget(
      surface(
        LedgerOperationTable(
          line: line('priced'),
          loadItems: (_) async => const [
            LedgerLineItem(
              name: 'خاتم اختبار',
              grams: '3.000',
              karat: 18,
              linePricePounds: '12500.00',
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('السعر'), findsOneWidget);
    expect(find.text(displayPounds('12500.00')), findsOneWidget);
  });

  testWidgets('a ledger refresh re-reads items without blanking the rows', (
    tester,
  ) async {
    final second = Completer<List<LedgerLineItem>?>();
    var reads = 0;
    Future<List<LedgerLineItem>?> first(String _) async {
      reads++;
      return items;
    }

    Future<List<LedgerLineItem>?> refreshed(String _) {
      reads++;
      return second.future;
    }

    await tester.pumpWidget(
      surface(LedgerOperationTable(line: line('same'), loadItems: first)),
    );
    await tester.pumpAndSettle();
    expect(find.text('سلسلة اختبار'), findsOneWidget);

    await tester.pumpWidget(
      surface(LedgerOperationTable(line: line('same'), loadItems: refreshed)),
    );
    await tester.pump();
    expect(reads, 2);
    expect(find.text('سلسلة اختبار'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    second.complete(const [
      LedgerLineItem(name: 'حلق بعد التعديل', grams: '2.000', karat: 21),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('حلق بعد التعديل'), findsOneWidget);
    expect(find.text('سلسلة اختبار'), findsNothing);
  });
}
