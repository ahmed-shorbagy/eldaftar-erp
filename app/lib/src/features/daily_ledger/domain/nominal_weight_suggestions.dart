import 'opening_issue.dart';
import 'postgres_integer.dart';
import 'quantities.dart';

/// Editable nominal weights offered while entering a coin or bullion line.
///
/// These are suggestions the owner can change. They are not measured stock
/// and they do not claim a physical standard. A shop catalog value with the
/// same label replaces the built-in suggestion.
final class NominalWeightSuggestion {
  const NominalWeightSuggestion({
    required this.label,
    required this.grams,
    required this.category,
    required this.fromCatalog,
  });

  final String label;

  /// Exact three-decimal grams for the input, never a rounded display.
  final String grams;
  final String category;
  final bool fromCatalog;
}

/// One selected denomination. The weight is the exact total for all pieces.
final class NominalSelection {
  const NominalSelection._(this.suggestion, this.count, this.milligrams);

  final NominalWeightSuggestion suggestion;
  final PieceCount count;
  final Milligrams milligrams;

  static NominalSelection? tryCreate(
    NominalWeightSuggestion suggestion,
    String countText,
  ) {
    final count = PieceCount.parseWire(countText);
    final unit = Milligrams.parseGrams(suggestion.grams);
    if (count is! Accepted<PieceCount> ||
        count.value.value == BigInt.zero ||
        unit is! Accepted<Milligrams> ||
        unit.value.value == BigInt.zero) {
      return null;
    }
    final total = PostgresInteger.checkedMultiply(
      unit.value.value,
      count.value.value,
    );
    if (total == null) return null;
    final weight = Milligrams.parseWire(total.toString());
    return weight is Accepted<Milligrams>
        ? NominalSelection._(suggestion, count.value, weight.value)
        : null;
  }
}

const builtinNominalWeightSuggestions = <NominalWeightSuggestion>[
  NominalWeightSuggestion(
    label: 'سبيكة ربع جرام',
    grams: '0.250',
    category: 'bullion',
    fromCatalog: false,
  ),
  NominalWeightSuggestion(
    label: 'سبيكة نصف جرام',
    grams: '0.500',
    category: 'bullion',
    fromCatalog: false,
  ),
  NominalWeightSuggestion(
    label: 'سبيكة جرام',
    grams: '1.000',
    category: 'bullion',
    fromCatalog: false,
  ),
  NominalWeightSuggestion(
    label: 'سبيكة 2.5 جرام',
    grams: '2.500',
    category: 'bullion',
    fromCatalog: false,
  ),
  NominalWeightSuggestion(
    label: 'سبيكة 5 جرام',
    grams: '5.000',
    category: 'bullion',
    fromCatalog: false,
  ),
  NominalWeightSuggestion(
    label: 'سبيكة 10 جرام',
    grams: '10.000',
    category: 'bullion',
    fromCatalog: false,
  ),
  NominalWeightSuggestion(
    label: 'سبيكة 20 جرام',
    grams: '20.000',
    category: 'bullion',
    fromCatalog: false,
  ),
  NominalWeightSuggestion(
    label: 'سبيكة 25 جرام',
    grams: '25.000',
    category: 'bullion',
    fromCatalog: false,
  ),
  NominalWeightSuggestion(
    label: 'سبيكة أونصة',
    grams: '31.100',
    category: 'bullion',
    fromCatalog: false,
  ),
  NominalWeightSuggestion(
    label: 'ثمن جنيه',
    grams: '1.000',
    category: 'coin',
    fromCatalog: false,
  ),
  NominalWeightSuggestion(
    label: 'ربع جنيه',
    grams: '2.000',
    category: 'coin',
    fromCatalog: false,
  ),
  NominalWeightSuggestion(
    label: 'نصف جنيه',
    grams: '4.000',
    category: 'coin',
    fromCatalog: false,
  ),
  NominalWeightSuggestion(
    label: 'جنيه',
    grams: '8.000',
    category: 'coin',
    fromCatalog: false,
  ),
  NominalWeightSuggestion(
    label: 'خمسة جنيهات',
    grams: '40.000',
    category: 'coin',
    fromCatalog: false,
  ),
];

/// A catalog row reduced to the fields needed to override a suggestion.
final class CatalogNominalChoice {
  const CatalogNominalChoice({
    required this.label,
    required this.grams,
    required this.active,
  });

  final String label;
  final String? grams;
  final bool active;
}

List<NominalWeightSuggestion> nominalSuggestionsFor({
  required String category,
  Iterable<CatalogNominalChoice> catalog = const [],
}) {
  final builtins = [
    for (final suggestion in builtinNominalWeightSuggestions)
      if (suggestion.category == category) suggestion,
  ];
  final active = [
    for (final choice in catalog)
      if (choice.active && choice.label.trim().isNotEmpty) choice,
  ];
  final byLabel = <String, CatalogNominalChoice>{
    for (final choice in active) _normalize(choice.label): choice,
  };
  final used = <String>{};
  final resolved = <NominalWeightSuggestion>[];
  for (final suggestion in builtins) {
    final match = byLabel[_normalize(suggestion.label)];
    final grams = match == null ? null : _exactGrams(match.grams);
    if (match != null && grams != null) {
      used.add(_normalize(match.label));
      resolved.add(
        NominalWeightSuggestion(
          label: match.label.trim(),
          grams: grams,
          category: category,
          fromCatalog: true,
        ),
      );
    } else {
      resolved.add(suggestion);
    }
  }
  for (final choice in active) {
    final key = _normalize(choice.label);
    if (used.contains(key)) continue;
    final grams = _exactGrams(choice.grams);
    if (grams == null) continue;
    used.add(key);
    resolved.add(
      NominalWeightSuggestion(
        label: choice.label.trim(),
        grams: grams,
        category: category,
        fromCatalog: true,
      ),
    );
  }
  return resolved;
}

String _normalize(String label) => label.trim().replaceAll(RegExp(r'\s+'), ' ');

String? _exactGrams(String? grams) {
  if (grams == null) return null;
  final text = grams.trim();
  if (!RegExp(r'^[0-9]+\.[0-9]{3}$').hasMatch(text)) return null;
  return text;
}
