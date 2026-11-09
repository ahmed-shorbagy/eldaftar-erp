// Display rules for «بيانات العملاء» (ADR 0043). Pure Dart: no widgets.

import 'customer_statistics.dart';

/// Karat boxes on a customer card: 18, 21 and 24 always, plus 22 and 14
/// only when the customer bought that karat. Order follows the shop's karat
/// display order (18, 21, 22, 24, 14 → shown as 18, 21, 24, 22, 14).
List<int> customerCardKarats(CustomerStatistics statistics) => [
  18,
  21,
  24,
  for (final karat in const [22, 14])
    if (statistics.weights.any(
      (weight) =>
          weight.karat == karat && weight.boughtMilligrams > BigInt.zero,
    ))
      karat,
];

/// Bought milligrams of [karat], zero when the server sent no row for it.
BigInt customerBoughtMilligrams(CustomerStatistics statistics, int karat) {
  for (final weight in statistics.weights) {
    if (weight.karat == karat) return weight.boughtMilligrams;
  }
  return BigInt.zero;
}

/// «منذ N يوم» for a shop-local timestamp (`YYYY-MM-DD…`).
///
/// Display only: it never orders operations or decides a business day.
/// [today] is the viewer's calendar date. When the timestamp is unreadable
/// or after [today] (a device clock behind the server), the result is null
/// and the caller shows the date instead.
String? customerSince(String shopTimestamp, DateTime today) {
  if (shopTimestamp.length < 10) return null;
  final parsed = DateTime.tryParse(shopTimestamp.substring(0, 10));
  if (parsed == null) return null;
  final from = DateTime.utc(parsed.year, parsed.month, parsed.day);
  final to = DateTime.utc(today.year, today.month, today.day);
  final days = to.difference(from).inDays;
  if (days < 0) return null;
  if (days == 0) return 'اليوم';
  if (days == 1) return 'أمس';
  if (days == 2) return 'منذ يومين';
  if (days < 11) return 'منذ $days أيام';
  if (days < 30) return 'منذ $days يوم';
  final months = days ~/ 30;
  if (months < 12) {
    return switch (months) {
      1 => 'منذ شهر',
      2 => 'منذ شهرين',
      _ when months < 11 => 'منذ $months أشهر',
      _ => 'منذ $months شهر',
    };
  }
  final years = days < 365 ? 1 : days ~/ 365;
  return switch (years) {
    1 => 'منذ سنة',
    2 => 'منذ سنتين',
    _ when years < 11 => 'منذ $years سنوات',
    _ => 'منذ $years سنة',
  };
}

/// Grouped count for the overview tiles, e.g. 1250 → «1,250».
String customerCount(BigInt value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);
