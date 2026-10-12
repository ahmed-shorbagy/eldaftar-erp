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

const builtinNominalWeightSuggestions = <NominalWeightSuggestion>[
  NominalWeightSuggestion(
    label: 'سبيكة',
    grams: '0.250',
    category: 'bullion',
    fromCatalog: false,
  ),
  NominalWeightSuggestion(
    label: 'عملة',
    grams: '1.000',
    category: 'coin',
    fromCatalog: false,
  ),
  NominalWeightSuggestion(
    label: 'عملة نصف جرام',
    grams: '0.500',
    category: 'coin',
    fromCatalog: false,
  ),
  NominalWeightSuggestion(
    label: 'ربع جنيه',
    grams: '1.000',
    category: 'coin',
    fromCatalog: false,
  ),
  NominalWeightSuggestion(
    label: 'نصف جنيه',
    grams: '2.500',
    category: 'coin',
    fromCatalog: false,
  ),
  NominalWeightSuggestion(
    label: 'جنيه',
    grams: '10.000',
    category: 'coin',
    fromCatalog: false,
  ),
  NominalWeightSuggestion(
    label: 'خمسة جنيهات',
    grams: '20.000',
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
