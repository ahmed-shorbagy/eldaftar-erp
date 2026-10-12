import '../domain/opening_issue.dart';
import '../domain/quantities.dart';

/// One confirmed item read from an operation payload. Not derived from a summary.
final class LedgerLineItem {
  const LedgerLineItem({
    required this.name,
    required this.grams,
    this.category,
    this.karat,
    this.count,
  });

  final String name;

  /// Exact three-decimal grams from the stored milligrams.
  final String grams;
  final String? category;
  final int? karat;
  final String? count;
}

/// Reads structured `items` from a confirmed operation payload.
///
/// Returns null when that array is absent. Malformed entries are skipped.
/// A lossy item-summary string is never split into rows.
List<LedgerLineItem>? ledgerLineItemsFromPayload(Object? payload) {
  if (payload is! Map) return null;
  final items = payload['items'];
  if (items is! List) return null;
  final parsed = <LedgerLineItem>[];
  for (final entry in items) {
    if (entry is! Map) continue;
    final name = entry['item_name'];
    final milligrams = entry['milligrams'];
    if (name is! String || name.trim().isEmpty || milligrams is! String) {
      continue;
    }
    final weight = Milligrams.parseWire(milligrams);
    if (weight is! Accepted<Milligrams>) continue;
    final karat = entry['karat'];
    final count = entry['count'];
    parsed.add(
      LedgerLineItem(
        name: name.trim(),
        grams: weight.value.gramsText,
        category: entry['category'] is String
            ? entry['category'] as String
            : null,
        karat: karat is int ? karat : int.tryParse('$karat'),
        count: count == null ? null : '$count',
      ),
    );
  }
  return parsed;
}
