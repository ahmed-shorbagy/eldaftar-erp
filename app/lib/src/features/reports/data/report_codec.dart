import '../domain/financial_day_report.dart';

Map<String, dynamic> _map(Object? v) => Map<String, dynamic>.from(v as Map);
List<dynamic> _list(Object? v) => v as List<dynamic>;
String _string(Object? v) => v as String;
BigInt _integer(Object? v) {
  final s = _string(v);
  if (!RegExp(r'^-?(0|[1-9][0-9]*)$').hasMatch(s)) {
    throw const FormatException('report_integer');
  }
  return BigInt.parse(s);
}

ReportDay parseReportDay(Object? raw) {
  final m = _map(raw);
  final day = ReportDay(
    _string(m['id']),
    _string(m['date']),
    _string(m['status']),
    _string(m['opened_at_shop']),
  );
  if (!{'open', 'closed'}.contains(day.status) ||
      day.openedAtShop.length != 19 ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day.date)) {
    throw const FormatException('report_day');
  }
  return day;
}

List<ReportDay> parseReportDays(Object? raw, String shopId) {
  final m = _map(raw);
  if (m['shop_id'] != shopId) throw const FormatException('report_shop');
  return List.unmodifiable(_list(m['days']).map(parseReportDay));
}

FinancialDayReport parseFinancialDayReport(Object? raw) {
  final m = _map(raw);
  if (m['version'] != 1 ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(_string(m['fingerprint']))) {
    throw const FormatException('report_version');
  }
  final summary = _map(m['summary']).map((k, v) => MapEntry(k, _integer(v)));
  if (!reportSummaryLabels.keys.every(summary.containsKey)) {
    throw const FormatException('report_summary');
  }
  final gold = _list(m['gold']).map((v) {
    final g = _map(v);
    return ReportGold(
      g['karat'] as int,
      _integer(g['sold']),
      _integer(g['bought']),
    );
  }).toList();
  if (gold.map((g) => g.karat).join(',') != '14,18,21,22,24') {
    throw const FormatException('report_karats');
  }
  final rows = _list(m['transactions']).map((v) {
    final r = _map(v);
    return ReportTransaction(
      id: _string(r['id']),
      sequence: _string(r['sequence']),
      kind: _string(r['kind']),
      label: _string(r['label']),
      state: _string(r['state']),
      atShop: _string(r['at_shop']),
      description: _string(r['description']),
      sourceId: r['source_id'] as String?,
      originalTotal: _integer(r['original_total']),
      sale: _integer(r['sale']),
      purchase: _integer(r['purchase']),
      expense: _integer(r['expense']),
      cash: _integer(r['cash']),
      openingCash: _integer(r['opening_cash']),
      items: List.unmodifiable(
        _list(r['items']).map((v) {
          final i = _map(v);
          return ReportItem(
            _string(i['name']),
            _string(i['category']),
            i['karat'] as int,
            _integer(i['milligrams']),
            _integer(i['sold']),
            _integer(i['bought']),
          );
        }),
      ),
      methods: Map.unmodifiable(
        Map.fromEntries(
          _list(r['methods']).map((v) {
            final t = _map(v);
            return MapEntry(_string(t['method']), _integer(t['amount']));
          }),
        ),
      ),
      inventory: Map.unmodifiable(
        Map.fromEntries(
          _list(r['inventory']).map((v) {
            final t = _map(v);
            return MapEntry(t['karat'] as int, _integer(t['milligrams']));
          }),
        ),
      ),
    );
  }).toList();
  BigInt sum(BigInt Function(ReportTransaction) f) =>
      rows.fold(BigInt.zero, (n, r) => n + f(r));
  // Integrity checks reject incomplete/mismatched responses; display values are
  // always the server totals, never totals of loaded UI cards.
  if (sum((r) => r.cash) != summary['net_cash'] ||
      sum((r) => r.sale) != summary['net_sales'] ||
      sum((r) => r.purchase) != summary['net_purchases'] ||
      sum((r) => r.expense) != summary['expenses'] ||
      sum((r) => r.openingCash) != summary['opening_cash'] ||
      BigInt.from(rows.length) != summary['audit_row_count'] ||
      rows.map((r) => r.id).toSet().length != rows.length) {
    throw const FormatException('report_incomplete');
  }
  for (final g in gold) {
    final items = rows.expand((r) => r.items).where((i) => i.karat == g.karat);
    if (items.fold(BigInt.zero, (n, i) => n + i.sold) != g.sold ||
        items.fold(BigInt.zero, (n, i) => n + i.bought) != g.bought) {
      throw const FormatException('report_gold');
    }
  }
  return FinancialDayReport(
    shopId: _string(m['shop_id']),
    shopName: _string(m['shop_name']),
    day: parseReportDay({...m, 'id': m['day_id']}),
    timeZone: _string(m['time_zone']),
    fingerprint: _string(m['fingerprint']),
    generatedAtShop: _string(m['generated_at_shop']),
    summary: Map.unmodifiable(summary),
    gold: List.unmodifiable(gold),
    transactions: List.unmodifiable(rows),
  );
}
