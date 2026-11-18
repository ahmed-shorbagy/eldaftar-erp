// «التقارير» opens on a day that has an operation the server does not name.
//
// Found on development on 2026-11-18: the second test shop could not open its
// report («تعذر تحميل التقرير من الخادم…») because the day held an
// «إضافة مخزون». The server sends stock moves, trader receipts and reversals
// with `label: null`; the parser required a label and failed the whole read.
// Such a row now counts in every total and check, and is not listed, as in
// the daily ledger.

import 'package:eldafttar/src/features/reports/data/report_codec.dart';
import 'package:eldafttar/src/features/reports/presentation/report_pdf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'report_fixtures.dart';
import 'report_widget_test.dart' show reportApp;

/// An operation the server gives no label, as development returned it.
Map<String, dynamic> _unnamed(int sequence, String kind) => {
  'id': 'b5555555-5555-4555-8555-${sequence.toString().padLeft(12, '0')}',
  'sequence': '$sequence',
  'kind': kind,
  'label': null,
  'state': 'confirmed',
  'at_shop': '2026-10-21 10:39:04',
  'source_id': null,
  'description': '',
  'original_total': '0',
  'sale': '0',
  'purchase': '0',
  'expense': '0',
  'cash': '0',
  'opening_cash': '0',
  'methods': [],
  'inventory': [
    {'karat': 21, 'milligrams': '5250'},
  ],
  'items': [],
};

/// [reportFixture] with unnamed rows added and the row count kept honest.
Map<String, dynamic> _withUnnamed(List<String> kinds, {bool empty = false}) {
  final data = reportFixture(empty: empty);
  final rows = List<Map<String, dynamic>>.from(data['transactions'] as List);
  for (final (index, kind) in kinds.indexed) {
    rows.add(_unnamed(rows.length + 1 + index, kind));
  }
  return {
    ...data,
    'transactions': rows,
    'summary': {
      ...(data['summary'] as Map<String, dynamic>),
      'audit_row_count': '${rows.length}',
    },
  };
}

const _unnamedKinds = [
  'inventory_addition',
  'inventory_removal',
  'inventory_correction',
  'inventory_conversion',
  'inventory_receipt',
  'inventory_recognition',
  'ownership_transfer',
  'receipt_manual_allocation',
];

void main() {
  test('a day with an unnamed operation parses and keeps it for totals', () {
    final report = parseFinancialDayReport(_withUnnamed(_unnamedKinds));
    expect(report.transactions, hasLength(4 + _unnamedKinds.length));
    expect(report.listedTransactions, hasLength(4));
    expect(report.listedTransactions.every((t) => t.label != null), isTrue);
    expect(
      report.transactions.where((t) => !t.listed).map((t) => t.kind),
      _unnamedKinds,
    );
  });

  test('the development shape: opening plus «إضافة مخزون» on a new shop', () {
    final report = parseFinancialDayReport(
      _withUnnamed(['inventory_addition'], empty: true),
    );
    expect(report.transactions.single.kind, 'inventory_addition');
    expect(report.listedTransactions, isEmpty);
  });

  test('an unnamed row still has to match the server row count', () {
    final data = _withUnnamed(['inventory_addition']);
    (data['transactions'] as List).removeLast();
    expect(
      () => parseFinancialDayReport(data),
      throwsA(isA<FormatException>()),
    );
  });

  test('the PDF prints only named operations', () async {
    final report = parseFinancialDayReport(_withUnnamed(_unnamedKinds));
    final bytes = await buildFinancialDayPdf(report);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  testWidgets('«التقارير» opens and lists the named operations only', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(411, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = FakeReports()
      ..data = _withUnnamed(['inventory_addition', 'inventory_receipt']);
    await tester.pumpWidget(reportApp(gateway));
    await tester.pumpAndSettle();
    expect(find.textContaining('تعذر تحميل التقرير'), findsNothing);
    expect(find.textContaining('null'), findsNothing);
    expect(gateway.reads, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
