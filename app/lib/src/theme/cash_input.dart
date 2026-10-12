import 'package:flutter/services.dart';

/// Converts only well-formed display grouping to the exact decimal input.
/// Domain parsers and stored financial values never receive separators.
String cashInputValue(String input) {
  final text = _cashDigits(input.trim());
  if (!text.contains(',')) return text;
  if (!RegExp(r'^-?[0-9]{1,3}(?:,[0-9]{3})+(?:\.[0-9]{0,2})?$')
      .hasMatch(text)) {
    return text;
  }
  return text.replaceAll(',', '');
}

String _cashDigits(String input) {
  final buffer = StringBuffer();
  for (final code in input.runes) {
    if (code >= 0x0660 && code <= 0x0669) {
      buffer.writeCharCode(0x30 + code - 0x0660);
    } else if (code >= 0x06f0 && code <= 0x06f9) {
      buffer.writeCharCode(0x30 + code - 0x06f0);
    } else {
      buffer.writeCharCode(switch (code) {
        0x066b => 0x2e,
        0x066c => 0x2c,
        0x2212 => 0x2d,
        _ => code,
      });
    }
  }
  return buffer.toString();
}

/// Groups the integer part without rounding, dropping cents or using doubles.
String editableCashText(String input) {
  final raw = cashInputValue(input);
  if (!RegExp(r'^-?[0-9]*(?:\.[0-9]{0,2})?$').hasMatch(raw)) {
    return input;
  }
  final parts = raw.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return parts.length == 1 ? whole : '$whole.${parts[1]}';
}

/// Live grouping with selection preservation, including deletion at a separator.
class CashInputFormatter extends TextInputFormatter {
  const CashInputFormatter({this.signed = false});
  final bool signed;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.composing.isCollapsed) return newValue;
    var text = _cashDigits(newValue.text);
    var selection = newValue.selection;
    if (oldValue.selection.isCollapsed &&
        selection.isCollapsed &&
        oldValue.text.length == text.length + 1) {
      final caret = oldValue.selection.extentOffset;
      final backspace = selection.extentOffset == caret - 1;
      final removedAt = backspace ? caret - 1 : caret;
      if (removedAt >= 0 &&
          removedAt < oldValue.text.length &&
          oldValue.text[removedAt] == ',' &&
          text == oldValue.text.replaceRange(removedAt, removedAt + 1, '')) {
        final digitAt = backspace ? removedAt - 1 : removedAt;
        if (digitAt >= 0 && digitAt < text.length &&
            RegExp(r'[0-9]').hasMatch(text[digitAt])) {
          text = text.replaceRange(digitAt, digitAt + 1, '');
          selection = TextSelection.collapsed(offset: digitAt);
        }
      }
    }
    // Reject malformed grouped pastes rather than silently changing their value.
    if (text.length > oldValue.text.length + 1 && text.contains(',') &&
        cashInputValue(text).contains(',')) {
      return oldValue;
    }
    var raw = text.replaceAll(',', '');
    final signLength = raw.startsWith('-') ? 1 : 0;
    final point = raw.indexOf('.');
    final wholeEnd = point < 0 ? raw.length : point;
    final whole = raw.substring(signLength, wholeEnd);
    final leadingZeros = RegExp(r'^0+(?=[0-9])').firstMatch(whole);
    final removedZeros = leadingZeros?.group(0)?.length ?? 0;
    if (removedZeros > 0) {
      raw = raw.replaceRange(signLength, signLength + removedZeros, '');
    }
    final pattern = signed
        ? RegExp(r'^-?[0-9]*(?:\.[0-9]{0,2})?$')
        : RegExp(r'^[0-9]*(?:\.[0-9]{0,2})?$');
    if (!pattern.hasMatch(raw)) return oldValue;
    final formatted = editableCashText(raw);
    int mapOffset(int offset) {
      if (offset < 0) return offset;
      final bounded = offset.clamp(0, text.length).toInt();
      final originalCount =
          text.substring(0, bounded).replaceAll(',', '').length;
      final zerosBeforeCaret =
          (originalCount - signLength).clamp(0, removedZeros).toInt();
      final count = originalCount - zerosBeforeCaret;
      if (count == 0) return 0;
      var seen = 0;
      for (var index = 0; index < formatted.length; index++) {
        if (formatted[index] != ',') seen++;
        if (seen == count) return index + 1;
      }
      return formatted.length;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection(
        baseOffset: mapOffset(selection.baseOffset),
        extentOffset: mapOffset(selection.extentOffset),
        affinity: selection.affinity,
        isDirectional: selection.isDirectional,
      ),
    );
  }
}
