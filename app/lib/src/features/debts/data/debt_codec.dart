import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/domain/postgres_integer.dart';
import '../application/debt_gateway.dart';
import '../application/debt_contract.dart';
import '../domain/debt_rules.dart';

Map<String, Object?> debtMap(Object? raw) {
  if (raw is! Map) throw const FormatException('debt');
  return Map<String, Object?>.from(raw);
}

String _text(Object? raw) {
  if (raw is! String || raw.isEmpty) throw const FormatException('debt');
  return raw;
}

String _optionalPhone(Object? raw) {
  if (raw is! String || raw.length > 20) throw const FormatException('debt');
  return raw;
}

String _uuid(Object? raw) {
  final value = _text(raw);
  if (!isUuid(value)) throw const FormatException('debt');
  return value;
}

BigInt _nonNegative(Object? raw, {bool allowZero = true}) {
  if (raw is! String) throw const FormatException('debt');
  final value = PostgresInteger.parseCanonical(raw, allowZero: allowZero);
  if (value == null) throw const FormatException('debt');
  return value;
}

BigInt _signed(Object? raw) {
  if (raw is! String || !RegExp(r'^-?(0|[1-9][0-9]{0,18})$').hasMatch(raw)) {
    throw const FormatException('debt');
  }
  final value = BigInt.parse(raw);
  if (!PostgresInteger.fits(value)) throw const FormatException('debt');
  return value;
}

int? _karat(Object? raw) {
  if (raw == null) return null;
  if (raw is! int || !const {14, 18, 21, 22, 24}.contains(raw)) {
    throw const FormatException('debt');
  }
  return raw;
}

DebtEffect parseDebtEffect(Map<String, Object?> json) {
  final custody = _signed(json['custody_milligrams']);
  if (custody != BigInt.zero) throw const FormatException('debt');
  return DebtEffect(
    cashPiastres: _signed(json['cash_piastres']),
    goldMilligrams: _signed(json['gold_milligrams']),
    goldCount: _signed(json['gold_count']),
    saleableStockMilligrams: _signed(json['saleable_stock_milligrams']),
  );
}

DebtRpcCommitted parseDebtCommand(Object? raw) {
  final json = debtMap(raw);
  if (json['ok'] != true || json['replayed'] is! bool) {
    throw const FormatException('debt');
  }
  final kind = DebtSourceKind.byWire(_text(json['source_kind']));
  if (kind == null) throw const FormatException('debt');
  final operation = json['operation_id'];
  final commandKind = _text(json['command_kind']);
  final displayStatus = _text(json['display_status']);
  final ledgerEffect = _text(json['ledger_effect']);
  if (!debtRpcs.containsKey(commandKind) ||
      !const {
        'open',
        'settled',
        'cancelled',
        'archived',
      }.contains(displayStatus) ||
      !const {'move', 'none'}.contains(ledgerEffect) ||
      (ledgerEffect == 'move') != (operation != null)) {
    throw const FormatException('debt');
  }
  _checkAmounts(json);
  final effect = parseDebtEffect(json);
  if (ledgerEffect == 'none' && !effect.isZero) {
    throw const FormatException('debt');
  }
  return DebtRpcCommitted(
    sourceId: _uuid(json['source_id']),
    sourceKind: kind.wire,
    commandKind: _text(json['command_kind']),
    replayed: json['replayed'] as bool,
    effect: effect,
    displayStatus: _text(json['display_status']),
    original: _nonNegative(json['original_amount'], allowZero: false),
    settled: _nonNegative(json['settled_amount']),
    remaining: _nonNegative(json['remaining_amount']),
    ledgerEffect: _text(json['ledger_effect']),
    operationId: operation == null ? null : _uuid(operation),
    result: json,
  );
}

DebtRemoteStatus parseDebtCommandStatus(Object? raw) {
  final json = debtMap(raw);
  final status = json['status'];
  if (status == 'absent') return const DebtRemoteAbsent();
  if (status != 'completed') throw const FormatException('debt');
  final result = parseDebtCommand(json['result']);
  if (result.sourceId != _uuid(json['source_id']) ||
      result.sourceKind != _text(json['source_kind']) ||
      result.commandKind != _text(json['command_kind'])) {
    throw const FormatException('debt');
  }
  return DebtRemoteCompleted(committed: result);
}

DebtContext parseDebtContext(Object? raw) {
  final json = debtMap(raw);
  final day = debtMap(json['day']);
  final methods = json['cash_methods'];
  final lots = json['lots'];
  if (methods is! List || lots is! List) throw const FormatException('debt');
  final state = _text(day['state']);
  if (!const {'open', 'closed', 'uninitialized'}.contains(state)) {
    throw const FormatException('debt');
  }
  return DebtContext(
    timeZone: _text(json['time_zone']),
    day: DebtDayContext(
      state: state,
      dayId: state == 'uninitialized' ? null : _uuid(day['business_day_id']),
      businessDate: day['business_date'] as String?,
      dayVersion: state == 'uninitialized'
          ? null
          : _nonNegative(day['day_version'], allowZero: false),
    ),
    cashMethods: [
      for (final item in methods)
        DebtCashMethod(
          method: _text(debtMap(item)['method']),
          balancePiastres: _signed(debtMap(item)['balance_piastres']),
        ),
    ],
    lots: [for (final item in lots) _lot(debtMap(item))],
  );
}

DebtLot _lot(Map<String, Object?> json) {
  final tracks = json['tracks_count'];
  if (tracks is! bool) throw const FormatException('debt');
  final count = json['count'];
  final category = _text(json['category']);
  final karat = _karat(json['karat']);
  if (karat == null ||
      !debtCategoryAllows(category, karat) ||
      tracks == (category == 'scrap') ||
      (!tracks && count != null)) {
    throw const FormatException('debt');
  }
  return DebtLot(
    id: _uuid(json['lot_id']),
    category: category,
    karat: karat,
    displayName: _text(json['display_name']),
    milligrams: _nonNegative(json['milligrams'], allowZero: false),
    count: tracks ? _nonNegative(count, allowZero: false) : null,
    tracksCount: tracks,
  );
}

DebtPage parseDebtPage(Object? raw) {
  final json = debtMap(raw);
  final items = json['items'];
  if (items is! List) throw const FormatException('debt');
  final cursor = json['next_cursor'];
  return DebtPage(
    items: [for (final item in items) parseDebtSummary(debtMap(item))],
    nextCursor: cursor == null ? null : _text(cursor),
    timeZone: _text(json['time_zone']),
  );
}

DebtSummary parseDebtSummary(Map<String, Object?> json) {
  final kind = DebtSourceKind.byWire(_text(json['source_kind']));
  final direction = DebtDirection.byWire(_text(json['direction']));
  final unit = DebtUnit.byWire(_text(json['unit']));
  if (kind == null || direction == null || unit == null) {
    throw const FormatException('debt');
  }
  final phone = json['contact_phone'];
  final external = json['external_reference'];
  final version = json['record_version'];
  _checkAmounts(json);
  final karat = _karat(json['karat']);
  final status = _text(json['display_status']);
  if ((unit == DebtUnit.gold) != (karat != null) ||
      !const {'open', 'settled', 'cancelled', 'archived'}.contains(status) ||
      _text(json['debt_key']) != '${kind.wire}:${_uuid(json['source_id'])}') {
    throw const FormatException('debt');
  }
  return DebtSummary(
    debtKey: _text(json['debt_key']),
    sourceKind: kind,
    sourceId: _uuid(json['source_id']),
    direction: direction,
    unit: unit,
    karat: karat,
    partyName: _text(json['party_name']),
    contactPhone: phone == null ? null : _optionalPhone(phone),
    reason: _text(json['reason']),
    externalReference: external == null ? null : _text(external),
    original: _nonNegative(json['original_amount'], allowZero: false),
    settled: _nonNegative(json['settled_amount']),
    remaining: _nonNegative(json['remaining_amount']),
    displayStatus: _text(json['display_status']),
    recordVersion: version == null
        ? null
        : _nonNegative(version, allowZero: false),
    createdAt: _text(json['created_at']),
    createdAtShop: _text(json['created_at_shop']),
  );
}

DebtDetail parseDebtDetail(Object? raw) {
  final json = debtMap(raw);
  final history = json['history'];
  if (history is! List ||
      json['can_settle'] is! bool ||
      json['can_cancel'] is! bool ||
      json['can_archive'] is! bool ||
      json['no_ledger_allowed'] is! bool) {
    throw const FormatException('debt');
  }
  return DebtDetail(
    summary: parseDebtSummary(json),
    timeZone: _text(json['time_zone']),
    canSettle: json['can_settle'] as bool,
    canCancel: json['can_cancel'] as bool,
    canArchive: json['can_archive'] as bool,
    noLedgerAllowed: json['no_ledger_allowed'] as bool,
    history: [for (final item in history) _history(debtMap(item))],
  );
}

DebtHistoryEntry _history(Map<String, Object?> json) {
  final payload = json['payload'];
  if (payload is! Map) throw const FormatException('debt');
  return DebtHistoryEntry(
    id: _uuid(json['id']),
    at: _text(json['at']),
    atShop: _text(json['at_shop']),
    eventType: _text(json['event_type']),
    kind: _text(json['kind']),
    label: _text(json['label_ar']),
    payload: {
      ...Map<String, Object?>.from(payload),
      for (final key in [
        'amount',
        'cancelled_amount',
        'cash_piastres',
        'gold_milligrams',
        'gold_count',
        'custody_milligrams',
        'saleable_stock_milligrams',
      ])
        if (json[key] != null) key: json[key],
    },
    actorUserId: _uuid(json['actor_user_id']),
    actorDisplayName: _text(json['actor_display_name']),
  );
}

void _checkAmounts(Map<String, Object?> json) {
  final original = _nonNegative(json['original_amount'], allowZero: false);
  final settled = _nonNegative(json['settled_amount']);
  final remaining = _nonNegative(json['remaining_amount']);
  final cancelled = json['cancelled_amount'] == null
      ? BigInt.zero
      : _nonNegative(json['cancelled_amount']);
  if (original != settled + remaining + cancelled) {
    throw const FormatException('debt');
  }
}
