import 'dart:io';

import 'package:eldafttar/src/features/daily_ledger/application/confirmed_operation_pdf.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('confirmed multi-item sale produces a shareable Arabic PDF', () async {
    final bytes = await buildConfirmedOperationPdf({
      'kind': 'sale',
      'shop_name': 'متجر تجريبي',
      'shop_sequence': '42',
      'occurred_at_cairo': '2026-09-29T09:00:00',
      'payload': {
        'total_piastres': '6000000',
        'customer_name': 'عميل تجريبي',
        'note': 'اختبار',
        'items': [
          {
            'item_name': 'خاتم',
            'karat': 21,
            'milligrams': '6000',
            'count': '1',
            'line_price_piastres': null,
          },
          {
            'item_name': 'سلسلة',
            'karat': 21,
            'milligrams': '4000',
            'count': '1',
            'line_price_piastres': null,
          },
        ],
        'tenders': [
          {'method': 'cash', 'piastres': '2000000'},
          {'method': 'card', 'piastres': '4000000'},
        ],
      },
    });
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(4000));
    final output = File('build/operation-fixture.pdf');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes);
  });

  test(
    'purchase PDF shows the original payable from its immutable payload',
    () async {
      final bytes = await buildConfirmedOperationPdf({
        'kind': 'purchase',
        'shop_name': 'متجر تجريبي',
        'shop_sequence': '43',
        'occurred_at_cairo': '2026-09-29T10:00:00',
        'purchase_payable_remaining_piastres': '2000000',
        'payload': {
          'total_piastres': '6000000',
          'purchase_obligation_piastres': '4000000',
          'customer_name': 'تاجر تجريبي',
          'note': '',
          'items': [
            {
              'item_name': 'سوار',
              'karat': 21,
              'milligrams': '10000',
              'count': '1',
              'line_price_piastres': null,
            },
          ],
          'tenders': [
            {'method': 'cash', 'piastres': '2000000'},
          ],
        },
      });
      expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      final output = File('build/partial-purchase-fixture.pdf');
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes);
    },
  );
}
