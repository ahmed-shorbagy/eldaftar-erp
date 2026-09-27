import '../application/daily_ledger_view.dart';
import '../application/idempotency_key.dart';
import '../domain/opening_catalog.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';

const _cashLabels = <String, String>{
  'cash': 'نقدي',
  'instant_transfer': 'انستا',
  'wallet': 'محفظة',
  'card': 'فيزا',
};

const _stockLabels = <String, String>{
  'worked_jewelry': 'مشغولات',
  'bullion': 'سبائك',
  'coin': 'جنيهات',
};

/// `YYYY-MM-DD` that is a real calendar day.
bool isCalendarDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
  if (match == null) return false;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1) return false;
  final probed = DateTime.utc(year, month, day);
  return probed.year == year && probed.month == month && probed.day == day;
}

bool _clock(int hour, int minute, int second) =>
    hour >= 0 &&
    hour <= 23 &&
    minute >= 0 &&
    minute <= 59 &&
    second >= 0 &&
    second <= 59;

/// Server UTC timestamp with an explicit zone.
bool _utcTimestamp(String value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(Z|[+-]00:00)$',
  ).firstMatch(value);
  if (match == null) return false;
  if (!isCalendarDate(
    '${match.group(1)}-${match.group(2)}-${match.group(3)}',
  )) {
    return false;
  }
  return _clock(
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}

/// Cairo wall time as produced by the server, without a zone suffix.
bool _cairoLocal(String value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})$',
  ).firstMatch(value);
  if (match == null) return false;
  if (!isCalendarDate(
    '${match.group(1)}-${match.group(2)}-${match.group(3)}',
  )) {
    return false;
  }
  return _clock(
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  );
}

bool _plainText(String value) =>
    value.isNotEmpty &&
    value.length <= 200 &&
    !value.runes.any((rune) => rune < 0x20);

DailyLedgerView parseDailyLedger(Object? json) {
  if (json is! Map) {
    throw const FormatException('ledger');
  }
  const fields = {
    'read_model_version',
    'state',
    'entitlement_status',
    'can_confirm',
    'business_day',
    'cash',
    'stock',
    'scrap',
    'feed',
  };
  if (json.length != fields.length ||
      json.keys.any((key) => !fields.contains(key))) {
    throw const FormatException('ledger');
  }
  if (json['read_model_version'] is! int || json['read_model_version'] != 1) {
    throw const FormatException('version');
  }
  final state = json['state'];
  final entitlement = json['entitlement_status'];
  final canConfirm = json['can_confirm'];
  if ((state != 'uninitialized' && state != 'confirmed') ||
      (entitlement != 'active' && entitlement != 'expired') ||
      canConfirm is! bool) {
    throw const FormatException('ledger');
  }
  if (entitlement == 'expired' && canConfirm) {
    throw const FormatException('entitlement');
  }
  if (state == 'confirmed' && canConfirm) {
    throw const FormatException('can_confirm');
  }
  if (state == 'uninitialized' && entitlement == 'active' && !canConfirm) {
    throw const FormatException('can_confirm');
  }
  final confirmed = state == 'confirmed';
  final businessDay = _businessDay(json['business_day'], confirmed: confirmed);
  final cash = _cash(json['cash'], confirmed: confirmed);
  final stock = _stock(json['stock'], confirmed: confirmed);
  final scrap = _scrap(json['scrap'], confirmed: confirmed);
  final feed = _feed(json['feed'], confirmed: confirmed);
  if (confirmed && businessDay == null) {
    throw const FormatException('business_day');
  }
  return DailyLedgerView(
    state: state,
    entitlementStatus: entitlement,
    canConfirm: canConfirm,
    businessDay: businessDay,
    cash: cash,
    stock: stock,
    scrap: scrap,
    feed: feed,
  );
}

LedgerBusinessDay? _businessDay(Object? value, {required bool confirmed}) {
  if (!confirmed) {
    if (value != null) throw const FormatException('business_day');
    return null;
  }
  if (value is! Map) throw const FormatException('business_day');
  const fields = {'id', 'business_date', 'opened_at'};
  if (value.length != fields.length ||
      value.keys.any((key) => !fields.contains(key))) {
    throw const FormatException('business_day');
  }
  final id = value['id'];
  final date = value['business_date'];
  final opened = value['opened_at'];
  if (id is! String ||
      date is! String ||
      opened is! String ||
      !isUuid(id) ||
      !isCalendarDate(date) ||
      !_utcTimestamp(opened)) {
    throw const FormatException('business_day');
  }
  return LedgerBusinessDay(id: id, businessDate: date, openedAt: opened);
}

List<LedgerCashLine> _cash(Object? value, {required bool confirmed}) {
  if (value is! List) throw const FormatException('cash');
  if (!confirmed) {
    if (value.isNotEmpty) throw const FormatException('cash');
    return const [];
  }
  if (value.length != CashMethod.canonicalOrder.length) {
    throw const FormatException('cash');
  }
  final lines = [for (final row in value) _cashLine(row)];
  final methods = lines.map((line) => line.method).toSet();
  if (methods.length != lines.length ||
      CashMethod.canonicalOrder.any(
        (method) => !methods.contains(method.code),
      )) {
    throw const FormatException('cash');
  }
  return lines;
}

LedgerCashLine _cashLine(Object? row) {
  if (row is! Map) throw const FormatException('cash');
  const fields = {'method', 'label_ar', 'piastres', 'pounds'};
  if (row.length != fields.length ||
      row.keys.any((key) => !fields.contains(key))) {
    throw const FormatException('cash');
  }
  final method = row['method'];
  final label = row['label_ar'];
  final piastres = row['piastres'];
  final pounds = row['pounds'];
  if (method is! String ||
      label is! String ||
      piastres is! String ||
      pounds is! String ||
      _cashLabels[method] != label) {
    throw const FormatException('cash');
  }
  final parsed = Piastres.parseWire(piastres);
  if (parsed is! Accepted<Piastres> || parsed.value.poundsText != pounds) {
    throw const FormatException('cash');
  }
  return LedgerCashLine(
    method: method,
    labelAr: label,
    piastres: piastres,
    pounds: pounds,
  );
}

List<LedgerStockLine> _stock(Object? value, {required bool confirmed}) {
  if (value is! List) throw const FormatException('stock');
  if (!confirmed && value.isNotEmpty) throw const FormatException('stock');
  final lines = [for (final row in value) _stockLine(row)];
  final seen = <String>{};
  for (final line in lines) {
    if (!seen.add('${line.category}:${line.karat}')) {
      throw const FormatException('stock');
    }
  }
  return lines;
}

LedgerStockLine _stockLine(Object? row) {
  if (row is! Map) throw const FormatException('stock');
  const fields = {
    'category',
    'label_ar',
    'karat',
    'milligrams',
    'grams',
    'count',
  };
  if (row.length != fields.length ||
      row.keys.any((key) => !fields.contains(key))) {
    throw const FormatException('stock');
  }
  final categoryCode = row['category'];
  final label = row['label_ar'];
  final karat = row['karat'];
  final milligrams = row['milligrams'];
  final grams = row['grams'];
  final count = row['count'];
  if (categoryCode is! String ||
      label is! String ||
      karat is! int ||
      milligrams is! String ||
      grams is! String ||
      count is! String) {
    throw const FormatException('stock');
  }
  final category = StockCategory.byCode(categoryCode);
  if (category == null ||
      !category.allowsKarat(karat) ||
      _stockLabels[categoryCode] != label) {
    throw const FormatException('stock');
  }
  final weight = Milligrams.parseWire(milligrams);
  final pieces = PieceCount.parseWire(count);
  if (weight is! Accepted<Milligrams> ||
      pieces is! Accepted<PieceCount> ||
      weight.value.gramsText != grams ||
      pieces.value.wire != count ||
      weight.value.value == BigInt.zero ||
      pieces.value.value == BigInt.zero) {
    throw const FormatException('stock');
  }
  return LedgerStockLine(
    category: categoryCode,
    labelAr: label,
    karat: karat,
    milligrams: milligrams,
    grams: grams,
    count: count,
  );
}

List<LedgerScrapLine> _scrap(Object? value, {required bool confirmed}) {
  if (value is! List) throw const FormatException('scrap');
  if (!confirmed && value.isNotEmpty) throw const FormatException('scrap');
  final lines = [for (final row in value) _scrapLine(row)];
  final seen = <int>{};
  for (final line in lines) {
    if (!seen.add(line.karat)) throw const FormatException('scrap');
  }
  return lines;
}

LedgerScrapLine _scrapLine(Object? row) {
  if (row is! Map) throw const FormatException('scrap');
  const fields = {'karat', 'label_ar', 'milligrams', 'grams'};
  if (row.length != fields.length ||
      row.keys.any((key) => !fields.contains(key))) {
    throw const FormatException('scrap');
  }
  final karat = row['karat'];
  final label = row['label_ar'];
  final milligrams = row['milligrams'];
  final grams = row['grams'];
  if (karat is! int ||
      label is! String ||
      milligrams is! String ||
      grams is! String ||
      label != 'كسر' ||
      !ScrapKarats.allowed.contains(karat)) {
    throw const FormatException('scrap');
  }
  final weight = Milligrams.parseWire(milligrams);
  if (weight is! Accepted<Milligrams> ||
      weight.value.gramsText != grams ||
      weight.value.value == BigInt.zero) {
    throw const FormatException('scrap');
  }
  return LedgerScrapLine(
    karat: karat,
    labelAr: label,
    milligrams: milligrams,
    grams: grams,
  );
}

List<LedgerFeedLine> _feed(Object? value, {required bool confirmed}) {
  if (value is! List) throw const FormatException('feed');
  if (confirmed) {
    if (value.length != 1) throw const FormatException('feed');
  } else if (value.isNotEmpty) {
    throw const FormatException('feed');
  }
  return [for (final row in value) _feedLine(row)];
}

LedgerFeedLine _feedLine(Object? row) {
  if (row is! Map) throw const FormatException('feed');
  const fields = {
    'kind',
    'label_ar',
    'operation_id',
    'actor_display_name',
    'occurred_at',
    'occurred_at_cairo',
  };
  if (row.length != fields.length ||
      row.keys.any((key) => !fields.contains(key))) {
    throw const FormatException('feed');
  }
  final kind = row['kind'];
  final label = row['label_ar'];
  final operationId = row['operation_id'];
  final actor = row['actor_display_name'];
  final occurredAt = row['occurred_at'];
  final cairo = row['occurred_at_cairo'];
  if (kind != 'opening_balances_confirmed' ||
      label != 'رصيد افتتاحي' ||
      operationId is! String ||
      actor is! String ||
      occurredAt is! String ||
      cairo is! String ||
      !isUuid(operationId) ||
      !_plainText(actor) ||
      !_utcTimestamp(occurredAt) ||
      !_cairoLocal(cairo)) {
    throw const FormatException('feed');
  }
  return LedgerFeedLine(
    kind: kind,
    labelAr: label,
    operationId: operationId,
    actorDisplayName: actor,
    occurredAt: occurredAt,
    occurredAtCairo: cairo,
  );
}
