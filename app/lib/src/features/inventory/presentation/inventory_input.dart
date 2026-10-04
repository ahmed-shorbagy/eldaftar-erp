import '../../daily_ledger/domain/opening_issue.dart';
import '../../daily_ledger/domain/quantities.dart';

BigInt? readGrams(String text) {
  final parsed = Milligrams.parseGrams(text.trim());
  if (parsed is! Accepted<Milligrams> || parsed.value.value == BigInt.zero) {
    return null;
  }
  return parsed.value.value;
}

BigInt? readCount(String text) {
  final parsed = PieceCount.parseWire(text.trim());
  if (parsed is! Accepted<PieceCount> || parsed.value.value == BigInt.zero) {
    return null;
  }
  return parsed.value.value;
}

BigInt? readPounds(String text) {
  final parsed = Piastres.parsePounds(text.trim());
  if (parsed is! Accepted<Piastres> || parsed.value.value == BigInt.zero) {
    return null;
  }
  return parsed.value.value;
}

BigInt? readSignedGrams(String text) {
  final trimmed = text.trim();
  final negative = trimmed.startsWith('-');
  final body = negative ? trimmed.substring(1) : trimmed;
  final magnitude =
      readGrams(body) ?? (body == '0' || body == '0.000' ? BigInt.zero : null);
  if (magnitude == null) return null;
  return negative ? -magnitude : magnitude;
}

BigInt? readSignedPounds(String text) {
  final trimmed = text.trim();
  final negative = trimmed.startsWith('-');
  final body = negative ? trimmed.substring(1) : trimmed;
  final parsed = Piastres.parsePounds(body);
  if (parsed is! Accepted<Piastres>) return null;
  final magnitude = parsed.value.value;
  if (magnitude == BigInt.zero) return BigInt.zero;
  return negative ? -magnitude : magnitude;
}
