/// Home always shows exactly six of these seven figures.
const ledgerMetricIds = <String>[
  'total_cash',
  'total_gold',
  'sale',
  'purchase',
  'sale_gold',
  'purchase_gold',
  'expense',
];

/// Default home strip: cash, gold, sales, purchases, sold gold, bought gold.
const ledgerDefaultHomeMetrics = <String>[
  'total_cash',
  'total_gold',
  'sale',
  'purchase',
  'sale_gold',
  'purchase_gold',
];

const ledgerDefaultRemainingMetric = 'expense';

const _legacyOperationsId = 'operations';
const _homeSlotCount = 6;

/// Saved home figures and the leftover figure that belongs in More.
final class LedgerMetricLayout {
  const LedgerMetricLayout({required this.homeIds, required this.remainingId});

  final List<String> homeIds;
  final String remainingId;

  bool get isValid =>
      homeIds.length == _homeSlotCount &&
      homeIds.toSet().length == _homeSlotCount &&
      homeIds.every(ledgerMetricIds.contains) &&
      ledgerMetricIds.contains(remainingId) &&
      !homeIds.contains(remainingId);
}

/// Maps a stored preference list onto exactly six home figures.
///
/// Legacy hidden metrics, `operations` / count, and extra keys are dropped.
/// Missing slots fill from [ledgerMetricIds] so every shop has six figures.
LedgerMetricLayout migrateLedgerMetricLayout(Iterable<String>? saved) {
  final entries = saved?.toList() ?? const <String>[];
  final savedOrder = <String>[];
  final hidden = <String>{};
  String? remainingHint;
  for (final entry in entries) {
    if (entry.startsWith('metric:')) {
      final id = entry.substring(7);
      if (_isCurrentMetric(id) && !savedOrder.contains(id)) {
        savedOrder.add(id);
      }
    } else if (entry.startsWith('hidden:metric:')) {
      final id = entry.substring(14);
      if (_isCurrentMetric(id)) hidden.add(id);
    } else if (entry == 'hidden:count' ||
        entry == 'hidden:metric:$_legacyOperationsId') {
      continue;
    } else if (entry.startsWith('remaining:')) {
      final id = entry.substring(10);
      if (_isCurrentMetric(id)) remainingHint = id;
    }
  }

  final preferred = [
    for (final id in savedOrder)
      if (!hidden.contains(id) && id != remainingHint) id,
  ];
  final home = <String>[];
  void take(String id) {
    if (home.length >= _homeSlotCount ||
        home.contains(id) ||
        id == remainingHint) {
      return;
    }
    home.add(id);
  }

  for (final id in preferred) {
    take(id);
  }
  for (final id in ledgerMetricIds) {
    if (!hidden.contains(id)) take(id);
  }
  for (final id in ledgerMetricIds) {
    take(id);
  }
  final remaining = ledgerMetricIds.firstWhere(
    (id) => !home.contains(id),
    orElse: () => ledgerDefaultRemainingMetric,
  );
  return LedgerMetricLayout(
    homeIds: List<String>.unmodifiable(home),
    remainingId: remaining,
  );
}

/// Preference snapshot for the six home figures and the leftover More figure.
List<String> encodeLedgerMetricLayout(LedgerMetricLayout layout) {
  final normalized = layout.isValid
      ? layout
      : migrateLedgerMetricLayout([
          for (final id in layout.homeIds) 'metric:$id',
          'remaining:${layout.remainingId}',
        ]);
  return [
    for (final id in normalized.homeIds) 'metric:$id',
    'remaining:${normalized.remainingId}',
  ];
}

LedgerMetricLayout replaceRemainingMetric(
  LedgerMetricLayout current,
  String remainingId,
) {
  if (!_isCurrentMetric(remainingId) || current.remainingId == remainingId) {
    return current.isValid
        ? current
        : migrateLedgerMetricLayout(encodeLedgerMetricLayout(current));
  }
  final home = <String>[
    for (final id in current.homeIds)
      if (id != remainingId) id,
  ];
  if (!home.contains(current.remainingId) && home.length < _homeSlotCount) {
    final at = current.homeIds.indexOf(remainingId);
    if (at >= 0 && at <= home.length) {
      home.insert(at, current.remainingId);
    } else {
      home.add(current.remainingId);
    }
  }
  return migrateLedgerMetricLayout([
    for (final id in home) 'metric:$id',
    'remaining:$remainingId',
  ]);
}

LedgerMetricLayout moveHomeMetric(
  LedgerMetricLayout current,
  String id,
  int direction,
) {
  final home = [...current.homeIds];
  final from = home.indexOf(id);
  final to = from + direction;
  if (from < 0 || to < 0 || to >= home.length) return current;
  home[from] = home[to];
  home[to] = id;
  return LedgerMetricLayout(homeIds: home, remainingId: current.remainingId);
}

String ledgerMetricLabel(String id) => switch (id) {
  'total_cash' => 'إجمالي النقدية',
  'total_gold' => 'إجمالي الذهب',
  'sale' => 'إجمالي البيع',
  'purchase' => 'إجمالي الشراء',
  'sale_gold' => 'ذهب مباع',
  'purchase_gold' => 'ذهب مشترى',
  'expense' => 'المصروفات',
  _ => id,
};

bool _isCurrentMetric(String id) => ledgerMetricIds.contains(id);
