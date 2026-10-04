import '../application/daily_ledger_view.dart';
import '../application/idempotency_key.dart';
import '../application/ledger_activity.dart';
import '../domain/opening_catalog.dart';
import '../domain/opening_issue.dart';
import '../domain/postgres_integer.dart';
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
  final version = json['read_model_version'];
  if (version is! int || (version != 1 && version != 2)) {
    throw const FormatException('version');
  }
  final allowedFields = version == 2 ? {...fields, 'day_summary'} : fields;
  final keys = json.keys.toSet();
  final extra = keys.difference(allowedFields);
  if (!keys.containsAll(allowedFields) ||
      extra.any((key) => key != 'feed_page') ||
      (extra.contains('feed_page') && version != 2)) {
    throw const FormatException('ledger');
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
  final daySummary = version == 2 ? _daySummary(json['day_summary']) : null;
  if (version == 2 && !confirmed) throw const FormatException('day_summary');
  if (json.containsKey('feed_page') && !confirmed) {
    throw const FormatException('feed_page');
  }
  final feedCursor = json.containsKey('feed_page')
      ? _feedCursor(json['feed_page'])
      : null;
  if (confirmed && businessDay == null) {
    throw const FormatException('business_day');
  }
  final view = DailyLedgerView(
    state: state,
    entitlementStatus: entitlement,
    canConfirm: canConfirm,
    businessDay: businessDay,
    cash: cash,
    stock: stock,
    scrap: scrap,
    feed: feed,
    daySummary: daySummary,
    feedCursor: feedCursor,
  );
  if (confirmed && view.totalCashPounds == null) {
    throw const FormatException('cash_total');
  }
  return view;
}

LedgerDaySummary _daySummary(Object? value) {
  if (value is! Map || (value.length != 6 && value.length != 7)) {
    throw const FormatException('day_summary');
  }
  const money = ['sale_piastres', 'purchase_piastres', 'expense_piastres'];
  const counts = ['sale_count', 'purchase_count', 'expense_count'];
  for (final field in money) {
    final raw = value[field];
    if (raw is! String || Piastres.parseWire(raw) is! Accepted<Piastres>) {
      throw const FormatException('day_summary');
    }
  }
  for (final field in counts) {
    final raw = value[field];
    if (raw is! int || raw < 0) throw const FormatException('day_summary');
  }
  final goldRaw = value['gold_by_bucket'];
  if (value.length == 7 && goldRaw is! List) {
    throw const FormatException('day_summary');
  }
  final gold = <LedgerGoldMovement>[];
  final seen = <String>{};
  if (goldRaw is List) {
    for (final row in goldRaw) {
      if (row is! Map ||
          row.length != 5 ||
          row['kind'] is! String ||
          row['category'] is! String ||
          row['karat'] is! int ||
          row['milligrams'] is! String ||
          row['count'] is! String) {
        throw const FormatException('day_summary');
      }
      final kind = row['kind'] as String;
      final category = row['category'] as String;
      final karat = row['karat'] as int;
      final milligrams = row['milligrams'] as String;
      final count = row['count'] as String;
      final weight = Milligrams.parseWire(milligrams);
      final pieces = PieceCount.parseWire(count);
      final stockCategory = StockCategory.byCode(category);
      final validPair = category == 'scrap'
          ? ScrapKarats.allowed.contains(karat)
          : stockCategory?.allowsKarat(karat) ?? false;
      if ((kind != 'sale' && kind != 'purchase') ||
          !validPair ||
          weight is! Accepted<Milligrams> ||
          weight.value.value == BigInt.zero ||
          pieces is! Accepted<PieceCount> ||
          (category == 'scrap' && pieces.value.value != BigInt.zero) ||
          (category != 'scrap' && pieces.value.value == BigInt.zero) ||
          !seen.add('$kind:$category:$karat')) {
        throw const FormatException('day_summary');
      }
      gold.add(
        LedgerGoldMovement(
          kind: kind,
          category: category,
          karat: karat,
          milligrams: milligrams,
          count: count,
        ),
      );
    }
  }
  return LedgerDaySummary(
    salePiastres: value['sale_piastres'] as String,
    purchasePiastres: value['purchase_piastres'] as String,
    expensePiastres: value['expense_piastres'] as String,
    saleCount: value['sale_count'] as int,
    purchaseCount: value['purchase_count'] as int,
    expenseCount: value['expense_count'] as int,
    goldByBucket: List.unmodifiable(gold),
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
      (weight.value.value == BigInt.zero) !=
          (pieces.value.value == BigInt.zero)) {
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
  if (weight is! Accepted<Milligrams> || weight.value.gramsText != grams) {
    throw const FormatException('scrap');
  }
  return LedgerScrapLine(
    karat: karat,
    labelAr: label,
    milligrams: milligrams,
    grams: grams,
  );
}

/// One ledger response holds at most 200 lines. That bound is not the history.
List<LedgerFeedLine> _feed(Object? value, {required bool confirmed}) {
  if (value is! List) throw const FormatException('feed');
  if (confirmed) {
    if (value.isEmpty || value.length > 200) {
      throw const FormatException('feed');
    }
  } else if (value.isNotEmpty) {
    throw const FormatException('feed');
  }
  return [for (final row in value) _feedLine(row)];
}

LedgerFeedLine _feedLine(Object? row) {
  if (row is! Map) throw const FormatException('feed');
  const required = {
    'kind',
    'label_ar',
    'operation_id',
    'actor_display_name',
    'occurred_at',
    'occurred_at_cairo',
  };
  const optional = {
    'has_note',
    'shop_sequence',
    'is_daily_note',
    'is_return',
    'occurred_at_shop',
  };
  if (required.any((key) => !row.containsKey(key)) ||
      row.keys.any(
        (key) => !required.contains(key) && !optional.contains(key),
      )) {
    throw const FormatException('feed');
  }
  final kind = row['kind'];
  final label = row['label_ar'];
  final operationId = row['operation_id'];
  final actor = row['actor_display_name'];
  final occurredAt = row['occurred_at'];
  final cairo = row['occurred_at_cairo'];
  final hasNote = row.containsKey('has_note') ? row['has_note'] : false;
  const labels = {
    'opening_balances_confirmed': 'رصيد افتتاحي',
    'opening_balances': 'رصيد افتتاحي',
    'sale': 'بيع',
    'purchase': 'شراء',
    'expense': 'مصروف',
    'purchase_settlement': 'سداد شراء',
    'cash_transfer': 'تحويل نقدية',
    'scrap_sale': 'بيع كسر',
    'scrap_to_stock': 'تحويل كسر إلى مخزون',
    'sale_return': 'مرتجع بيع',
    'purchase_return': 'مرتجع شراء',
    'close_day': 'تقفيل اليومية',
    'open_day': 'فتح اليومية',
    'daily_note': 'ملاحظة يومية',
  };
  final shopSequence = row['shop_sequence'];
  final shopTime = row['occurred_at_shop'];
  final dailyNote = row.containsKey('is_daily_note')
      ? row['is_daily_note']
      : false;
  final isReturn = row.containsKey('is_return') ? row['is_return'] : false;
  if (kind is! String ||
      label != labels[kind] ||
      operationId is! String ||
      actor is! String ||
      occurredAt is! String ||
      cairo is! String ||
      hasNote is! bool ||
      dailyNote is! bool ||
      isReturn is! bool ||
      (shopSequence != null && shopSequence is! String) ||
      (shopTime != null && shopTime is! String) ||
      (dailyNote && kind != 'daily_note') ||
      (isReturn && kind != 'sale_return' && kind != 'purchase_return') ||
      !isUuid(operationId) ||
      !_plainText(actor) ||
      !_utcTimestamp(occurredAt) ||
      !_cairoLocal(cairo) ||
      (shopSequence is String &&
          PostgresInteger.parseCanonical(shopSequence) == null) ||
      (shopTime is String && !_cairoLocal(shopTime))) {
    throw const FormatException('feed');
  }
  return LedgerFeedLine(
    kind: kind,
    labelAr: label,
    operationId: operationId,
    actorDisplayName: actor,
    occurredAt: occurredAt,
    occurredAtCairo: cairo,
    occurredAtShop: shopTime is String ? shopTime : null,
    hasNote: hasNote,
    shopSequence: shopSequence is String ? shopSequence : null,
    isDailyNote: dailyNote,
    isReturn: isReturn,
  );
}

LedgerFeedCursor _feedCursor(Object? value) {
  if (value is! Map) throw const FormatException('feed_page');
  const fields = {
    'limit',
    'has_more',
    'direction',
    'next_before_sequence',
    'server_sequence',
    'snapshot_sequence',
  };
  if (value.length != fields.length ||
      value.keys.any((key) => !fields.contains(key))) {
    throw const FormatException('feed_page');
  }
  final limit = value['limit'];
  final hasMore = value['has_more'];
  final direction = value['direction'];
  final before = value['next_before_sequence'];
  final server = value['server_sequence'];
  final snapshot = value['snapshot_sequence'];
  if (limit is! int ||
      limit < 1 ||
      limit > 100 ||
      hasMore is! bool ||
      (direction != 'desc' && direction != 'asc') ||
      server is! String ||
      snapshot is! String ||
      PostgresInteger.parseCanonical(server, allowZero: true) == null ||
      PostgresInteger.parseCanonical(snapshot, allowZero: true) == null ||
      (before != null &&
          (before is! String ||
              PostgresInteger.parseCanonical(before) == null)) ||
      (hasMore && direction == 'desc' && before == null) ||
      (!hasMore && before != null)) {
    throw const FormatException('feed_page');
  }
  return LedgerFeedCursor(
    limit: limit,
    hasMore: hasMore,
    direction: direction,
    serverSequence: server,
    snapshotSequence: snapshot,
    nextBeforeSequence: before is String ? before : null,
  );
}

/// A bounded operation page. [expectedShopId] rejects another shop's payload.
LedgerOperationPage parseLedgerOperationPage(
  Object? json, {
  required String expectedShopId,
}) {
  if (json is! Map) throw const FormatException('page');
  const fields = {
    'shop_id',
    'day_id',
    'direction',
    'limit',
    'has_more',
    'server_sequence',
    'snapshot_sequence',
    'next_before_sequence',
    'next_after_sequence',
    'items',
  };
  if (json.length != fields.length ||
      json.keys.any((key) => !fields.contains(key))) {
    throw const FormatException('page');
  }
  final shopId = json['shop_id'];
  if (shopId is! String || shopId != expectedShopId) {
    throw const FormatException('shop');
  }
  final dayId = json['day_id'];
  final direction = json['direction'];
  final limit = json['limit'];
  final hasMore = json['has_more'];
  final server = json['server_sequence'];
  final snapshot = json['snapshot_sequence'];
  final before = json['next_before_sequence'];
  final after = json['next_after_sequence'];
  final items = json['items'];
  if ((dayId != null && (dayId is! String || !isUuid(dayId))) ||
      (direction != 'desc' && direction != 'asc') ||
      limit is! int ||
      limit < 1 ||
      limit > 100 ||
      hasMore is! bool ||
      server is! String ||
      snapshot is! String ||
      PostgresInteger.parseCanonical(server, allowZero: true) == null ||
      PostgresInteger.parseCanonical(snapshot, allowZero: true) == null ||
      before != null && after != null ||
      (direction == 'desc' && after != null) ||
      (direction == 'asc' && before != null) ||
      (before != null &&
          (before is! String ||
              PostgresInteger.parseCanonical(before) == null)) ||
      (after != null &&
          (after is! String ||
              PostgresInteger.parseCanonical(after) == null)) ||
      (hasMore && direction == 'desc' && before == null) ||
      (hasMore && direction == 'asc' && after == null) ||
      (!hasMore && (before != null || after != null)) ||
      items is! List ||
      items.length > limit) {
    throw const FormatException('page');
  }
  final lines = <LedgerFeedLine>[];
  for (final row in items) {
    if (row is! Map ||
        !row.containsKey('shop_sequence') ||
        !row.containsKey('occurred_at_shop') ||
        !row.containsKey('is_daily_note') ||
        !row.containsKey('is_return')) {
      throw const FormatException('page');
    }
    lines.add(_feedLine(row));
  }
  return LedgerOperationPage(
    shopId: shopId,
    dayId: dayId is String ? dayId : null,
    direction: direction,
    limit: limit,
    hasMore: hasMore,
    serverSequence: server,
    snapshotSequence: snapshot,
    nextBeforeSequence: before is String ? before : null,
    nextAfterSequence: after is String ? after : null,
    items: lines,
  );
}
