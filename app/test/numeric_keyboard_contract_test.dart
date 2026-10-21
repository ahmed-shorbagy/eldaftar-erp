import 'dart:io';

import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_form_fields.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/partial_return_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ledger_compensation_workflow_test.dart';

/// Every money/weight/count TextField in lib must request a number keyboard.
List<String> _fieldsMissingNumericKeyboard(Directory lib) {
  final missing = <String>[];
  final fieldPattern = RegExp(r'(TextField|TextFormField)\s*\(');
  for (final file in lib.listSync(recursive: true).whereType<File>()) {
    if (!file.path.endsWith('.dart')) continue;
    final text = file.readAsStringSync();
    for (final match in fieldPattern.allMatches(text)) {
      var depth = 1;
      var i = match.end;
      while (i < text.length && depth > 0) {
        final ch = text[i];
        if (ch == '(') {
          depth++;
        } else if (ch == ')') {
          depth--;
        }
        i++;
        if (i - match.start > 5000) break;
      }
      final block = text.substring(match.start, i);
      final needsNumber =
          block.contains('CashInputFormatter') ||
          block.contains('GramInputFormatter') ||
          block.contains('ledgerMoneyField') ||
          block.contains('ledgerGramsField') ||
          block.contains('ledgerCountField') ||
          RegExp(
            r"label:\s*'[^']*(جرام|نقد|وزن|عدد|مبلغ|سعر|قطع|مستحق|المعدود)",
          ).hasMatch(block);
      if (!needsNumber) continue;
      // Helpers already enforce the keyboard; skip their call sites.
      if (RegExp(r'ledger(Money|Grams|Count)Field\s*\(').hasMatch(block)) {
        continue;
      }
      final hasKeyboard =
          block.contains('keyboardType') ||
          block.contains('ledgerDecimalKeyboard') ||
          block.contains('ledgerIntegerKeyboard') ||
          block.contains('ledgerSignedDecimalKeyboard');
      if (!hasKeyboard) {
        final line = text.substring(0, match.start).split('\n').length;
        final rel = file.path
            .replaceAll('\\', '/')
            .split('/lib/')
            .last;
        missing.add('$rel:$line');
      }
    }
  }
  return missing;
}

void main() {
  test('money weight and count fields request a numeric keyboard', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue);
    final missing = _fieldsMissingNumericKeyboard(lib);
    expect(
      missing,
      isEmpty,
      reason:
          'Numeric fields must set keyboardType (or use ledgerMoney/Grams/CountField):\n'
          '${missing.join('\n')}',
    );
  });

  testWidgets('return cash fields use the decimal number keyboard', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final gateway = CompensationReviewGateway();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: PartialReturnScreen(
          gateway: gateway,
          statusGateway: gateway,
          dayGateway: gateway,
          userId: ownerId,
          shopId: shopId,
          remainder: syntheticRemainder,
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final key in const [
      'partial-consideration',
      'partial-tender',
      'partial-tender-instant_transfer',
      'partial-tender-wallet',
      'partial-tender-card',
      'partial-grams-0',
    ]) {
      final field = tester.widget<TextField>(find.byKey(Key(key)));
      expect(
        field.keyboardType,
        ledgerDecimalKeyboard,
        reason: '$key must open a decimal number keyboard',
      );
      expect(field.autocorrect, isFalse);
      expect(field.enableSuggestions, isFalse);
    }
    final count = tester.widget<TextField>(
      find.byKey(const Key('partial-count-0')),
    );
    expect(count.keyboardType, ledgerIntegerKeyboard);
  });
}
