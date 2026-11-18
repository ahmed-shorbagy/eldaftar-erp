// FB-002 / ADR 0050: every weight is entered and shown with two decimals.
// Storage stays integer milligrams.

import 'package:eldafttar/src/features/customers/domain/customer_statistics.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/ledger_compensation.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/opening_catalog.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/opening_issue.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/quantities.dart';
import 'package:eldafttar/src/features/debts/presentation/debt_copy.dart';
import 'package:eldafttar/src/features/debts/presentation/debt_statement_pdf.dart';
import 'package:eldafttar/src/features/inventory/presentation/inventory_copy.dart';
import 'package:eldafttar/src/features/inventory/presentation/inventory_input.dart';
import 'package:eldafttar/src/features/repairs/presentation/repair_copy.dart';
import 'package:eldafttar/src/features/reports/domain/financial_day_report.dart';
import 'package:eldafttar/src/theme/amount_format.dart';
import 'package:eldafttar/src/theme/gram_input.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

BigInt _mg(int value) => BigInt.from(value);

BigInt? _read(String text, {int? recorded}) {
  final result = readGramField(
    text,
    recorded: recorded == null ? null : _mg(recorded),
  );
  return result is Accepted<Milligrams> ? result.value.value : null;
}

void main() {
  group('display', () {
    test('milligrams are written as grams with two decimals', () {
      expect(twoDecimalGrams(_mg(1250)), '1.25');
      expect(twoDecimalGrams(_mg(10000)), '10.00');
      expect(twoDecimalGrams(_mg(0)), '0.00');
      expect(twoDecimalGrams(_mg(1234560), grouped: true), '1,234.56');
      expect(twoDecimalGrams(_mg(1234560)), '1234.56');
    });

    test('an older third decimal rounds half away from zero', () {
      expect(twoDecimalGrams(_mg(1254)), '1.25');
      expect(twoDecimalGrams(_mg(1255)), '1.26');
      expect(twoDecimalGrams(_mg(995)), '1.00');
      expect(twoDecimalGrams(_mg(-1255)), '-1.26');
      expect(twoDecimalGrams(_mg(4)), '0.00');
      expect(twoDecimalGrams(_mg(-4)), '0.00');
    });

    test('every formatter in the app gives the same two decimals', () {
      final stored = _mg(65555);
      expect(displayGrams('65555'), '65.56');
      expect(displayGrams('65.555'), '65.56');
      expect(displayMilligrams(stored), '65.56');
      expect(displayGoldEffect(stored), '65.56 جرام');
      expect(customerGrams(stored), '65.56');
      expect(signedGramsText(stored), '65.56');
      expect(reportGrams(stored), '65.56');
      expect(statementGold(stored), '65.56');
      expect(gramsOf(stored), '65.56');
      expect(repairWeight(stored), '65.56 جرام');
      expect(debtGold(stored), contains('65.56'));
      expect(
        (Milligrams.parseWire('65555') as Accepted<Milligrams>).value.gramsText,
        '65.56',
      );
    });

    test('no milligram figure is added when a third decimal was stored', () {
      for (final text in [
        displayGoldEffect(_mg(1255)),
        repairWeight(_mg(1255)),
        debtGold(_mg(1255)),
      ]) {
        expect(text, isNot(contains('ملليجرام')));
        expect(text, isNot(contains('1,255')));
        expect(text, isNot(contains('1.255')));
      }
    });

    test('signed weights keep their sign and never show minus zero', () {
      expect(displayMilligrams(_mg(-1250)), '−1.25');
      expect(displayMilligrams(_mg(-1250), minus: '-'), '-1.25');
      expect(displayMilligrams(_mg(-3)), '0.00');
      expect(reportGrams(_mg(-2500000)), '-2,500.00');
    });
  });

  group('entry', () {
    test('a weight takes at most two decimals', () {
      expect(_read('1.25'), _mg(1250));
      expect(_read('1.2'), _mg(1200));
      expect(_read('12'), _mg(12000));
      expect(_read('1.255'), isNull);
      expect(_read(''), isNull);
      expect(Milligrams.parseGrams('1.255'), isA<Rejected<Milligrams>>());
      expect(Milligrams.parseGrams('1.25'), isA<Accepted<Milligrams>>());
    });

    test('Arabic digits and the Arabic decimal mark are read', () {
      expect(_read('١٫٢٥'), _mg(1250));
      expect(_read('۱.۲۵'), _mg(1250));
    });

    test('the field refuses a third decimal as it is typed', () {
      const formatter = GramInputFormatter();
      const before = TextEditingValue(
        text: '1.25',
        selection: TextSelection.collapsed(offset: 4),
      );
      const typed = TextEditingValue(
        text: '1.255',
        selection: TextSelection.collapsed(offset: 5),
      );
      expect(formatter.formatEditUpdate(before, typed).text, '1.25');
      expect(gramDecimalPlaces, 2);
    });

    test('catalog text with three decimals is data, not entry', () {
      final eighth = Milligrams.parseExactGrams('0.125');
      expect((eighth as Accepted<Milligrams>).value.wire, '125');
    });

    test('inventory forms read weights with the same rule', () {
      expect(readGrams('2.50'), _mg(2500));
      expect(readGrams('2.505'), isNull);
      expect(readGrams('65.56', recorded: _mg(65555)), _mg(65555));
      expect(readSignedGrams('0.00'), BigInt.zero);
    });
  });

  group('an older weight stored with a third decimal', () {
    test('fills its field with two decimals', () {
      expect(gramFieldText(_mg(1255)), '1.26');
      expect(gramFieldText(_mg(5000)), '5.00');
    });

    test('is kept whole when the field still shows it', () {
      expect(_read('1.26', recorded: 1255), _mg(1255));
      expect(_read('1.260', recorded: 1255), _mg(1255));
      expect(_read('١٫٢٦', recorded: 1255), _mg(1255));
    });

    test('gives way to a weight the user really changed', () {
      expect(_read('1.25', recorded: 1255), _mg(1250));
      expect(_read('1.30', recorded: 1255), _mg(1300));
      expect(matchRecordedWeight(_mg(1300), _mg(1255)), _mg(1300));
    });

    FinancialDraftResult edited(String grams, {String? recorded}) =>
        FinancialDraft.compose(
          kind: FinancialKind.sale,
          totalPounds: '100',
          items: [
            FinancialItemInput(
              category: 'worked_jewelry',
              karat: 21,
              grams: grams,
              count: '1',
              name: 'خواتم',
              recordedMilligrams: recorded,
            ),
          ],
          tenders: const [
            FinancialTenderInput(method: CashMethod.cash, pounds: '100'),
          ],
        );

    String sent(FinancialDraftResult result) =>
        (result.draft!.toJson()['items'] as List).single['milligrams']
            as String;

    test('survives an edit that leaves its weight alone', () {
      expect(sent(edited('1.26', recorded: '1255')), '1255');
    });

    test('is replaced when the edit changes the weight', () {
      expect(sent(edited('1.30', recorded: '1255')), '1300');
    });

    test('a new sale line cannot carry a third decimal', () {
      expect(edited('1.255').issue, FinancialIssue.invalidItem);
      expect(sent(edited('1.25')), '1250');
    });
  });

  // The scan that keeps the rejected wording out of `app/lib` and `admin/src`
  // is in owner_terms_guard_test.dart, with every other rejected term.
}
