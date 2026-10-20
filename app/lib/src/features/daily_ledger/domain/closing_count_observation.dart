import 'postgres_integer.dart';

/// Compares named physical observations with book buckets. Null weight remains
/// unmeasured. It is never replaced by the recorded inventory weight.
bool closingObservationsMatch(
  Map<String, Object?> observations,
  Map<String, Object?> book,
) {
  final rows = observations['stock'];
  final expected = book['stock'];
  if (observations['version'] != 2 ||
      rows is! List ||
      expected is! List ||
      rows.length > 200) {
    return false;
  }
  final counts = <String, BigInt>{};
  final weights = <String, BigInt>{};
  final unmeasured = <String>{};
  final names = <String>{};
  final allowed = {
    for (final row in expected)
      if (row is Map) '${row['category']}:${row['karat']}',
  };
  for (final row in rows) {
    if (row is! Map) return false;
    final key = '${row['category']}:${row['karat']}';
    final name = row['item_name'];
    final countText = row['count'];
    final weightText = row['milligrams'];
    if (!allowed.contains(key) ||
        name is! String ||
        name.trim().isEmpty ||
        name.runes.length > 120 ||
        name.runes.any((rune) => rune < 32 || rune == 127) ||
        !names.add('$key:${name.trim()}') ||
        countText is! String) {
      return false;
    }
    final count = PostgresInteger.parseCanonical(countText, allowZero: true);
    if (count == null) return false;
    counts[key] = (counts[key] ?? BigInt.zero) + count;
    if (weightText == null) {
      unmeasured.add(key);
    } else {
      if (weightText is! String) return false;
      final weight = PostgresInteger.parseCanonical(
        weightText,
        allowZero: true,
      );
      if (weight == null || (count == BigInt.zero) != (weight == BigInt.zero)) {
        return false;
      }
      weights[key] = (weights[key] ?? BigInt.zero) + weight;
    }
  }
  for (final row in expected) {
    if (row is! Map) return false;
    final key = '${row['category']}:${row['karat']}';
    final weight = BigInt.tryParse('${row['milligrams']}');
    final count = BigInt.tryParse('${row['count']}');
    if (weight == null ||
        count == null ||
        counts[key] != count ||
        (weights[key] ?? BigInt.zero) > weight ||
        (!unmeasured.contains(key) && (weights[key] ?? BigInt.zero) != weight)) {
      return false;
    }
  }
  final cash = observations['cash'];
  final expectedCash = book['cash'];
  if (cash is! Map ||
      expectedCash is! Map ||
      cash.length != expectedCash.length ||
      cash.entries.any((entry) => expectedCash[entry.key] != entry.value)) {
    return false;
  }
  final scrap = observations['scrap'];
  final expectedScrap = book['scrap'];
  if (scrap is! List ||
      expectedScrap is! List ||
      scrap.length != expectedScrap.length) {
    return false;
  }
  for (var i = 0; i < scrap.length; i++) {
    if (scrap[i] is! Map ||
        expectedScrap[i] is! Map ||
        (scrap[i] as Map).length != (expectedScrap[i] as Map).length ||
        (scrap[i] as Map).entries.any(
          (entry) => (expectedScrap[i] as Map)[entry.key] != entry.value,
        )) {
      return false;
    }
  }
  return true;
}
