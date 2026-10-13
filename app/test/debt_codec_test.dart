import 'package:eldafttar/src/features/debts/data/debt_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a committed debt result and rejects custody movement', () {
    final committed = parseDebtCommand({
      'ok': true,
      'replayed': false,
      'command_kind': 'debt_declare',
      'source_kind': 'standalone',
      'source_id': 'd3000000-0000-4000-8000-000000000201',
      'display_status': 'open',
      'original_amount': '1050',
      'settled_amount': '0',
      'remaining_amount': '1050',
      'ledger_effect': 'none',
      'operation_id': null,
      'cash_piastres': '0',
      'gold_milligrams': '0',
      'gold_count': '0',
      'custody_milligrams': '0',
      'saleable_stock_milligrams': '0',
    });
    expect(committed.effect.isZero, isTrue);
    expect(committed.operationId, isNull);
    expect(
      () => parseDebtEffect({
        'cash_piastres': '0',
        'gold_milligrams': '0',
        'gold_count': '0',
        'custody_milligrams': '1',
        'saleable_stock_milligrams': '0',
      }),
      throwsFormatException,
    );
    expect(
      () => parseDebtEffect({
        'cash_piastres': '9223372036854775808',
        'gold_milligrams': '0',
        'gold_count': '0',
        'custody_milligrams': '0',
        'saleable_stock_milligrams': '0',
      }),
      throwsFormatException,
    );
  });

  test('parses list, empty phone, absent status and uninitialized context', () {
    expect(parseDebtCommandStatus({'status': 'absent'}), isA<Object>());
    final page = parseDebtPage({
      'items': [
        {
          'debt_key': 'standalone:d3000000-0000-4000-8000-000000000201',
          'source_kind': 'standalone',
          'source_id': 'd3000000-0000-4000-8000-000000000201',
          'direction': 'shop_owes',
          'unit': 'money',
          'karat': null,
          'party_name': 'طرف',
          'contact_phone': '',
          'reason': 'سبب',
          'external_reference': null,
          'original_amount': '1000',
          'settled_amount': '0',
          'remaining_amount': '1000',
          'display_status': 'open',
          'record_version': '1',
          'created_at': '2026-10-13T20:00:00.000000Z',
          'created_at_shop': '2026-10-13T22:00:00',
        },
      ],
      'next_cursor': null,
      'time_zone': 'Africa/Cairo',
    });
    expect(page.items.single.contactPhone, '');
    expect(page.items.single.original, BigInt.from(1000));
    final context = parseDebtContext({
      'time_zone': 'Africa/Cairo',
      'day': {'state': 'uninitialized'},
      'cash_methods': [],
      'lots': [],
    });
    expect(context.day.isOpen, isFalse);
  });
}
