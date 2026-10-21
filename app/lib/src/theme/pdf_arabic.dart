import 'package:pdf/widgets.dart' as pw;

/// Letters that connect to the following letter. A yeh after anything else
/// takes its isolated form.
const _dualJoining = 'بتثجحخسشصضطظعغفقكلمنهيئـیپچگک';

/// The bundled Cairo font has no usable isolated yeh glyph, so the PDF
/// library drops it ("نقدي" prints as "نقد"). Isolated yeh is written as the
/// dotless alef maksura, the common Egyptian spelling; joined forms are kept.
String pdfArabic(String text) {
  if (!text.contains('ي')) return text;
  final out = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (char == 'ي') {
      final previous = i == 0 ? '' : text[i - 1];
      final next = i + 1 < text.length ? text[i + 1] : '';
      final joinsBefore =
          previous.isNotEmpty && _dualJoining.contains(previous);
      final joinsAfter = next.isNotEmpty && _isArabicLetter(next);
      if (!joinsBefore && !joinsAfter) {
        out.write('ى');
        continue;
      }
    }
    out.write(char);
  }
  return out.toString();
}

bool _isArabicLetter(String char) {
  final unit = char.codeUnitAt(0);
  return unit >= 0x0621 && unit <= 0x064A || unit >= 0x0671 && unit <= 0x06D3;
}

pw.Text pdfText(
  String text, {
  pw.TextStyle? style,
  pw.TextAlign? textAlign,
  pw.TextDirection? textDirection,
}) => pw.Text(
  pdfArabic(text),
  style: style,
  textAlign: textAlign,
  textDirection: textDirection,
);
