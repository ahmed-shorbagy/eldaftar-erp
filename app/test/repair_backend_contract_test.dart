import 'dart:convert';
import 'dart:io';
import 'package:eldafttar/src/features/daily_ledger/data/daily_ledger_codec.dart';
import 'package:eldafttar/src/features/repairs/data/repair_codec.dart';
import 'package:flutter_test/flutter_test.dart';

// Actual jsonb results from the independent disposable PostgreSQL race fixture.
// All shops, owners, contacts and operations are synthetic; no hosted data.
void main() {
  test(
    'actual repair SQL responses decode and fee collection leaves stock and sales untouched',
    () {
      final raw =
          jsonDecode(
                File(
                  'test/fixtures/repair_server_contract.json',
                ).readAsStringSync(),
              )
              as Map;
      final ledger = parseDailyLedger(raw['ledger']);
      final fees = ledger.feed
          .where((entry) => entry.kind == 'repair_fee')
          .toList();
      expect(fees, hasLength(2));
      expect(fees.map((entry) => entry.totalPounds), ['200.00', '200.00']);
      expect(
        fees.every(
          (entry) => entry.labelAr == 'أجرة إصلاح' && entry.weightGrams == null,
        ),
        isTrue,
      );
      expect(ledger.stock.single.milligrams, '5000');
      expect(
        ledger.cash.singleWhere((entry) => entry.method == 'cash').piastres,
        '524000',
      );
      expect(
        ledger.cash.singleWhere((entry) => entry.method == 'wallet').piastres,
        '116000',
      );
      expect(ledger.daySummary!.salePiastres, '0');
      expect(ledger.daySummary!.purchasePiastres, '0');
      expect(ledger.daySummary!.goldByBucket, isEmpty);
      final page = parseLedgerOperationPage(
        raw['ledger_page'],
        expectedShopId: 'd2d2d2d2-d2d2-42d2-82d2-d2d2d2d2d2d2',
      );
      expect(
        page.items.where((entry) => entry.kind == 'repair_fee'),
        hasLength(2),
      );
      final context = parseRepairContext(raw['context']);
      expect(context.cashMethods, hasLength(4));
      expect(context.day.isOpen, isTrue);
      final repairs = parseRepairPage(raw['repairs']);
      expect(repairs.items, hasLength(2));
      expect(
        repairs.items.every(
          (item) =>
              !item.custodyHeld && item.outstandingPiastres == BigInt.zero,
        ),
        isTrue,
      );
      final detail = parseRepairDetail(raw['detail']);
      expect(detail.summary.measuredMilligrams, BigInt.from(1255));
      expect(detail.summary.estimatedFeePiastres, BigInt.from(15000));
      expect(detail.summary.finalFeePiastres, BigInt.from(20000));
      expect(detail.events, hasLength(4));
      expect(detail.custodyEvents.map((event) => event.direction), [
        'intake',
        'release',
      ]);
      expect(detail.financialOperationId, isNotNull);
    },
  );
}
