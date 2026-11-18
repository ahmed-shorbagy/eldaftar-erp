import 'package:flutter/services.dart';

import '../features/daily_ledger/domain/opening_issue.dart';
import '../features/daily_ledger/domain/quantities.dart';

/// Every weight is entered with at most two decimals.
const gramDecimalPlaces = 2;

String? gramEntryValue(String input, {required int decimalPlaces}) {
  final digits = StringBuffer();
  for (final rune in input.runes) {
    digits.writeCharCode(switch (rune) {
      >= 0x0660 && <= 0x0669 => rune - 0x0660 + 0x30,
      >= 0x06f0 && <= 0x06f9 => rune - 0x06f0 + 0x30,
      0x066b => 0x2e,
      _ => rune,
    });
  }
  var text = digits.toString();
  if (!RegExp(r'^[0-9]*(?:\.[0-9]*)?$').hasMatch(text)) return null;
  final point = text.indexOf('.');
  if (point >= 0 && text.length - point - 1 > decimalPlaces) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    if (text.length - point - 1 > decimalPlaces) return null;
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  }
  return text;
}

/// ASCII digits for parsing. Blank stays empty; a trailing decimal point is dropped.
String? canonicalNumericEntry(String input, {required int decimalPlaces}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '';
  var text = gramEntryValue(trimmed, decimalPlaces: decimalPlaces);
  if (text == null) return null;
  if (text.isEmpty || text == '.') return '';
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return text;
}

/// Text for a weight field that starts from a recorded weight.
String gramFieldText(BigInt milligrams) => twoDecimalGrams(milligrams);

/// Reads a weight field: at most two decimals, Arabic or ASCII digits.
///
/// A field that still shows [gramFieldText] of [recorded] returns the recorded
/// weight itself. An older weight stored with a third decimal is then not
/// changed by a field nobody edited, and a full return of it still matches.
DomainResult<Milligrams> readGramField(String text, {BigInt? recorded}) {
  final entry = canonicalNumericEntry(text, decimalPlaces: gramDecimalPlaces);
  if (entry == null || entry.isEmpty) {
    return const Rejected(OpeningIssueCode.invalidInput);
  }
  final parsed = Milligrams.parseGrams(entry);
  if (recorded == null ||
      recorded.isNegative ||
      parsed is! Accepted<Milligrams>) {
    return parsed;
  }
  return Milligrams.parseWire(
    matchRecordedWeight(parsed.value.value, recorded).toString(),
  );
}

/// The one weight input rule: two decimals. Counts reuse it with zero.
class GramInputFormatter extends TextInputFormatter {
  const GramInputFormatter({this.decimalPlaces = gramDecimalPlaces});
  final int decimalPlaces;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    final text = gramEntryValue(newValue.text, decimalPlaces: decimalPlaces);
    if (text == null) return oldValue;
    return newValue.copyWith(
      text: text,
      selection: TextSelection(
        baseOffset: newValue.selection.baseOffset.clamp(-1, text.length),
        extentOffset: newValue.selection.extentOffset.clamp(-1, text.length),
      ),
    );
  }
}
