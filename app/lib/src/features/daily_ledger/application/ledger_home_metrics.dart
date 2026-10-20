import '../domain/gold_metrics.dart';

const ledgerDefaultHomeMetrics = <String>[
  'total_cash',
  'sale',
  'purchase',
  'sale_gold',
  'purchase_gold',
  'expense',
];
const ledgerMetricIds = <String>[
  ...ledgerDefaultHomeMetrics,
  'sale_karat_18',
  'sale_karat_21',
  'sale_karat_24',
  'scrap_purchase_18',
  'scrap_purchase_21',
  'scrap_purchase_24',
  'scrap_purchase_22',
  'scrap_purchase_14',
];

/// Six home slots; all other metrics remain in More. Gold totals never mix karats.
final class LedgerMetricLayout {
  const LedgerMetricLayout({
    required this.homeIds,
    this.normalizationKarat = 21,
    this.hiddenScrapKarats = const {},
  });
  final List<String> homeIds;
  final int normalizationKarat;
  final Set<int> hiddenScrapKarats;
  List<String> get availableIds => [
    for (final id in ledgerMetricIds)
      if (!_hiddenScrapMetric(id, hiddenScrapKarats)) id,
  ];
  List<String> get moreIds =>
      availableIds.where((id) => !homeIds.contains(id)).toList();
  bool get isValid =>
      homeIds.length == 6 &&
      homeIds.toSet().length == 6 &&
      homeIds.every(availableIds.contains) &&
      normalizationKarats.contains(normalizationKarat) &&
      hiddenScrapKarats.every(const {14, 22}.contains);
  LedgerMetricLayout copyWith({
    List<String>? homeIds,
    int? normalizationKarat,
    Set<int>? hiddenScrapKarats,
  }) => LedgerMetricLayout(
    homeIds: _sixVisibleMetrics(
      homeIds ?? this.homeIds,
      hiddenScrapKarats ?? this.hiddenScrapKarats,
    ),
    normalizationKarat: normalizationKarat ?? this.normalizationKarat,
    hiddenScrapKarats: Set.unmodifiable(
      hiddenScrapKarats ?? this.hiddenScrapKarats,
    ),
  );
}

bool _hiddenScrapMetric(String id, Set<int> hidden) =>
    id.startsWith('scrap_purchase_') &&
    hidden.contains(int.tryParse(id.substring(15)));

List<String> _sixVisibleMetrics(Iterable<String> preferred, Set<int> hidden) {
  final result = <String>[];
  for (final id in [
    ...preferred,
    ...ledgerDefaultHomeMetrics,
    ...ledgerMetricIds,
  ]) {
    if (result.length == 6) break;
    if (ledgerMetricIds.contains(id) &&
        !_hiddenScrapMetric(id, hidden) &&
        !result.contains(id)) {
      result.add(id);
    }
  }
  return List.unmodifiable(result);
}

LedgerMetricLayout migrateLedgerMetricLayout(Iterable<String>? saved) {
  final entries = saved?.toList() ?? const <String>[];
  final preferred = <String>[];
  final hidden = <String>{};
  final legacyMore = <String>{};
  var karat = 21;
  final hiddenScrap = <int>{};
  for (final entry in entries) {
    if (entry.startsWith('metric:')) {
      final id = entry.substring(7);
      if (ledgerMetricIds.contains(id) && !preferred.contains(id)) {
        preferred.add(id);
      }
    } else if (entry.startsWith('hidden:metric:')) {
      hidden.add(entry.substring(14));
    } else if (entry.startsWith('remaining:')) {
      legacyMore.add(entry.substring(10));
    } else if (entry.startsWith('normalize:')) {
      final value = int.tryParse(entry.substring(10));
      if (normalizationKarats.contains(value)) karat = value!;
    } else if (entry.startsWith('hide-scrap:')) {
      final value = int.tryParse(entry.substring(11));
      if (const {14, 22}.contains(value)) hiddenScrap.add(value!);
    }
  }
  final home = <String>[];
  void add(String id) {
    if (home.length < 6 &&
        !home.contains(id) &&
        !_hiddenScrapMetric(id, hiddenScrap)) {
      home.add(id);
    }
  }

  for (final id in [
    ...preferred,
    ...ledgerDefaultHomeMetrics,
    ...ledgerMetricIds,
  ]) {
    if (!hidden.contains(id) && !legacyMore.contains(id)) add(id);
  }
  for (final id in ledgerMetricIds) {
    add(id);
  }
  return LedgerMetricLayout(
    homeIds: List.unmodifiable(home),
    normalizationKarat: karat,
    hiddenScrapKarats: Set.unmodifiable(hiddenScrap),
  );
}

List<String> encodeLedgerMetricLayout(LedgerMetricLayout layout) => [
  for (final id in layout.homeIds) 'metric:$id',
  'normalize:${layout.normalizationKarat}',
  for (final karat in layout.hiddenScrapKarats.toList()..sort())
    'hide-scrap:$karat',
];

LedgerMetricLayout selectMetricForSlot(
  LedgerMetricLayout current,
  int slot,
  String id,
) {
  if (slot < 0 || slot >= 6 || !current.availableIds.contains(id)) {
    return current;
  }
  final home = [...current.homeIds];
  final existing = home.indexOf(id);
  if (existing >= 0) home[existing] = home[slot];
  home[slot] = id;
  return current.copyWith(homeIds: home);
}

LedgerMetricLayout moveHomeMetric(
  LedgerMetricLayout current,
  String id,
  int direction,
) {
  final slot = current.homeIds.indexOf(id);
  final to = slot + direction;
  if (slot < 0 || to < 0 || to >= 6) return current;
  return selectMetricForSlot(current, slot, current.homeIds[to]);
}

String ledgerMetricLabel(String id) {
  if (id.startsWith('sale_karat_')) return 'مبيعات عيار ${id.substring(11)}';
  if (id.startsWith('scrap_purchase_')) {
    return 'شراء كسر عيار ${id.substring(15)}';
  }
  return switch (id) {
    'total_cash' => 'إجمالي النقدية',
    'sale' => 'إجمالي البيع',
    'purchase' => 'إجمالي الشراء',
    'sale_gold' => 'ذهب مباع',
    'purchase_gold' => 'ذهب مشترى',
    'expense' => 'المصروفات',
    _ => id,
  };
}
