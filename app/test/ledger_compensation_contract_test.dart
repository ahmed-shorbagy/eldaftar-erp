import 'dart:convert';
import 'dart:io';
import 'package:eldafttar/src/features/daily_ledger/data/daily_ledger_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/ledger_compensation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'current client decodes synthetic compensation ledger, page and operation remainders',
    () {
      final capture =
          jsonDecode(
                File(
                  'test/fixtures/compensation_contract.json',
                ).readAsStringSync(),
              )
              as Map;
      final ledger = parseDailyLedger(capture['ledger']);
      final page = parseLedgerOperationPage(
        capture['page'],
        expectedShopId: (capture['page'] as Map)['shop_id'] as String,
      );
      expect(ledger.feed.any((row) => row.kind == 'ledger_correction'), isTrue);
      expect(ledger.feed.any((row) => row.kind == 'exchange'), isTrue);
      expect(page.items.length, ledger.feed.length);
      for (final raw in capture['operations'] as List) {
        final operation = raw as Map;
        if (operation['kind'] == 'sale' || operation['kind'] == 'purchase') {
          final result = parseReturnRemainder(
            Map<String, Object?>.from(operation['return_remainder'] as Map),
          );
          expect(result, isA<CompensationAccepted<ReturnRemainder>>());
          final bounds =
              (result as CompensationAccepted<ReturnRemainder>).value;
          expect(bounds.originalImmutable, isTrue);
          expect(bounds.remainderConsideration.isNegative, isFalse);
        }
        if (operation['kind'] == 'sale_return' ||
            operation['kind'] == 'purchase_return') {
          final payload = operation['payload'] as Map;
          expect(payload['total_piastres'], payload['consideration_piastres']);
          for (final row in payload['items'] as List) {
            expect((row as Map)['item_name'], isA<String>());
            expect(row['category'], isA<String>());
          }
        }
      }
    },
  );
}
