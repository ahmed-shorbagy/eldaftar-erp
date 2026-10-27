import 'opening_catalog.dart';

/// Live Arabic labels and archive flags for the four cash methods.
///
/// Updated from confirmed ledger cash lines and from the owner settings RPC.
abstract final class PaymentMethodCatalog {
  static final Map<String, _Entry> _entries = {
    for (final method in CashMethod.canonicalOrder)
      method.code: _Entry(_defaultLabel(method), false),
  };

  static String label(CashMethod method) =>
      _entries[method.code]?.labelAr ?? _defaultLabel(method);

  static String labelForCode(String code) {
    final method = CashMethod.byCode(code);
    if (method != null) return label(method);
    return _entries[code]?.labelAr ?? 'وسيلة دفع';
  }

  static bool isArchived(CashMethod method) =>
      _entries[method.code]?.archived ?? false;

  static List<CashMethod> activeForEntry() => [
    for (final method in CashMethod.canonicalOrder)
      if (!isArchived(method)) method,
  ];

  /// Entry dropdowns; falls back to all four if every method were archived.
  static List<CashMethod> entryChoices() {
    final active = activeForEntry();
    return active.isEmpty ? CashMethod.canonicalOrder : active;
  }

  static void applyCashLines(
    Iterable<({String method, String labelAr, bool archived})> lines,
  ) {
    for (final line in lines) {
      if (CashMethod.byCode(line.method) == null) continue;
      final trimmed = line.labelAr.trim();
      if (trimmed.isEmpty) continue;
      _entries[line.method] = _Entry(trimmed, line.archived);
    }
  }

  static void applyMethods(
    Iterable<({String method, String labelAr, bool archived})> methods,
  ) {
    applyCashLines(methods);
  }

  static void resetDefaults() {
    for (final method in CashMethod.canonicalOrder) {
      _entries[method.code] = _Entry(_defaultLabel(method), false);
    }
  }

  static String _defaultLabel(CashMethod method) => switch (method) {
    CashMethod.cash => 'نقدي',
    CashMethod.instantTransfer => 'انستا',
    CashMethod.wallet => 'محفظة',
    CashMethod.card => 'فيزا',
  };
}

final class _Entry {
  const _Entry(this.labelAr, this.archived);
  final String labelAr;
  final bool archived;
}
