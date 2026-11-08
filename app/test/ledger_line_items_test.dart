import 'package:eldafttar/src/features/daily_ledger/application/ledger_line_items.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> payload(Object? price) => {
    'items': [
      {
        'item_name': 'خاتم',
        'milligrams': '1000',
        'karat': 21,
        'category': 'worked_jewelry',
        'line_price_piastres': ?price,
      },
    ],
  };

  test('a wire line price becomes pounds text', () {
    final items = ledgerLineItemsFromPayload(payload('125050'));
    expect(items, isNotNull);
    expect(items!.single.linePricePounds, '1250.50');
  });

  test('a missing line price stays null', () {
    final items = ledgerLineItemsFromPayload(payload(null));
    expect(items!.single.linePricePounds, isNull);
  });

  test('a malformed line price stays null', () {
    final items = ledgerLineItemsFromPayload(payload('12.50'));
    expect(items!.single.linePricePounds, isNull);
  });
}
