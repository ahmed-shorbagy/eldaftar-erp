import 'package:eldafttar/src/features/daily_ledger/domain/jewelry_items.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every legacy name maps to its plural built-in', () {
    expect(jewelryLegacyNames.length, greaterThanOrEqualTo(10));
    for (final entry in jewelryLegacyNames.entries) {
      expect(canonicalJewelryName(entry.key), entry.value);
      expect(jewelryBuiltIns, contains(entry.value));
    }
  });

  test('a custom name passes through trimmed', () {
    expect(canonicalJewelryName('  مخصص  '), 'مخصص');
  });

  test('built-ins stay in the old-app order', () {
    expect(jewelryBuiltIns, [
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
    ]);
  });
}
