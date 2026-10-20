/// Owner-controlled invoice appearance. No widgets, HTTP, files, or PDF.
enum InvoiceTemplate {
  header('header'),
  compact('compact'),
  dark('dark');

  const InvoiceTemplate(this.wire);
  final String wire;

  static InvoiceTemplate? parse(Object? value) {
    for (final template in values) {
      if (template.wire == value) return template;
    }
    return null;
  }
}

enum InvoiceAccent {
  brown('brown'),
  gold('gold'),
  neutral('neutral');

  const InvoiceAccent(this.wire);
  final String wire;

  static InvoiceAccent? parse(Object? value) {
    for (final accent in values) {
      if (accent.wire == value) return accent;
    }
    return null;
  }
}

/// Document colors belong to the branded copy, not the app theme.
abstract final class InvoiceDocumentPalette {
  static const int paper = 0xFFFFFBF5;
  static const int whitePaper = 0xFFFFFFFF;
  static const int darkPaper = 0xFF0C0D0D;
  static const int darkInk = 0xFFEFEFEF;
  static const int darkGold = 0xFFD4AF37;
  static const int ink = 0xFF1C1915;
  static const int brown = 0xFF6F4E1B;
  static const int gold = 0xFF94681F;
  static const int neutral = 0xFF1C1915;

  static int accent(InvoiceAccent value) => switch (value) {
    InvoiceAccent.brown => brown,
    InvoiceAccent.gold => gold,
    InvoiceAccent.neutral => neutral,
  };
}

const invoiceSloganMax = 120;
const invoiceAddressMax = 200;
const invoiceAddressMaxLines = 4;

/// Trimmed optional text. Blank becomes null. Control characters other than
/// newline are rejected. Address is also limited to four lines.
String? normalizeInvoiceText(
  Object? raw, {
  required int maxChars,
  required int maxLines,
}) {
  if (raw == null) return null;
  if (raw is! String) {
    throw const FormatException('invalid_input');
  }
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length > maxChars) {
    throw const FormatException('invalid_input');
  }
  for (final rune in trimmed.runes) {
    final forbidden = rune != 0x0A && (rune < 0x20 || rune == 0x7F);
    if (forbidden) throw const FormatException('invalid_input');
  }
  if ('\n'.allMatches(trimmed).length + 1 > maxLines) {
    throw const FormatException('invalid_input');
  }
  return trimmed;
}

String? normalizeSlogan(Object? raw) => normalizeInvoiceText(
  raw,
  maxChars: invoiceSloganMax,
  maxLines: invoiceSloganMax,
);

String? normalizeAddress(Object? raw) => normalizeInvoiceText(
  raw,
  maxChars: invoiceAddressMax,
  maxLines: invoiceAddressMaxLines,
);

final class InvoiceAppearanceValue {
  const InvoiceAppearanceValue({
    required this.revision,
    required this.template,
    required this.accent,
    this.slogan,
    this.address,
    this.logoAssetId,
    this.logoSha256,
  });

  static const defaults = InvoiceAppearanceValue(
    revision: 0,
    template: InvoiceTemplate.header,
    accent: InvoiceAccent.brown,
  );

  final int revision;
  final InvoiceTemplate template;
  final InvoiceAccent accent;
  final String? slogan;
  final String? address;
  final String? logoAssetId;
  final String? logoSha256;

  InvoiceAppearanceValue copyWith({
    int? revision,
    InvoiceTemplate? template,
    InvoiceAccent? accent,
    String? slogan,
    String? address,
    String? logoAssetId,
    String? logoSha256,
    bool clearSlogan = false,
    bool clearAddress = false,
    bool clearLogo = false,
  }) => InvoiceAppearanceValue(
    revision: revision ?? this.revision,
    template: template ?? this.template,
    accent: accent ?? this.accent,
    slogan: clearSlogan ? null : slogan ?? this.slogan,
    address: clearAddress ? null : address ?? this.address,
    logoAssetId: clearLogo ? null : logoAssetId ?? this.logoAssetId,
    logoSha256: clearLogo ? null : logoSha256 ?? this.logoSha256,
  );
}
