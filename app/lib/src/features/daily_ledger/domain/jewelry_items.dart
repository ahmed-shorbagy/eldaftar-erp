/// Old app order (owner, 2026-11-10). Plural, as stored for new lines.
const jewelryBuiltIns = <String>[
  'محابس',
  'توينز',
  'غوايش',
  'سلاسل',
  'انسيالات',
  'حلقان',
  'اساور',
  'تعاليق',
  'كوليهات',
  'دبل',
  'خواتم',
];

/// Names stored before 2026-11-10 → their built-in.
const jewelryLegacyNames = <String, String>{
  'خاتم': 'خواتم',
  'حلق': 'حلقان',
  'سلسلة': 'سلاسل',
  'تعليقة': 'تعاليق',
  'دبلة': 'دبل',
  'محبس': 'محابس',
  'غويشة': 'غوايش',
  'إسورة': 'اساور',
  'اسورة': 'اساور',
  'انسيال': 'انسيالات',
  'كوليه': 'كوليهات',
};

/// Stock confirmed before item names existed (opening balances, ADR 0043).
const pooledOpeningItemName = 'رصيد افتتاحي مجمّع';

/// O2: an older backfill named the pooled opening lots this way.
const legacyPooledOpeningItemName = 'رصيد سابق مجمّع';

String canonicalJewelryName(String name) {
  final trimmed = name.trim();
  if (trimmed == legacyPooledOpeningItemName) return pooledOpeningItemName;
  return jewelryLegacyNames[trimmed] ?? trimmed;
}

/// The pooled opening stock is not an item the owner can choose.
bool isPooledOpeningItem(String name) =>
    canonicalJewelryName(name) == pooledOpeningItemName;

/// Built-ins shown as the four main trade tiles (glyphs).
const jewelryMainTileNames = <String>['خواتم', 'حلقان', 'سلاسل', 'تعاليق'];

/// «أخرى» list: built-ins that are not main tiles, old-app order.
List<String> get tradeOtherJewelryNames => [
  for (final name in jewelryBuiltIns)
    if (!jewelryMainTileNames.contains(name)) name,
];
