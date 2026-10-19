import 'package:flutter/services.dart';

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

/// Entry precision only. Persisted milligrams and historical invoices stay exact.
class GramInputFormatter extends TextInputFormatter {
  const GramInputFormatter({this.decimalPlaces = 3});
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
