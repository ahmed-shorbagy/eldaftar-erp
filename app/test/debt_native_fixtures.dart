import 'package:eldafttar/src/features/debts/application/debt_native_gateway.dart';
import 'package:eldafttar/src/features/debts/application/debt_gateway.dart';
import 'package:eldafttar/src/features/debts/application/debt_reminder_device.dart';
import 'package:eldafttar/src/features/debts/data/debt_native_codec.dart';
import 'package:eldafttar/src/features/debts/domain/debt_rules.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'debt_due_fixtures.dart';

Map<String, Object?> nativeFixture({
  String source = 'standalone',
  String direction = 'shop_owes',
  int? karat,
  String? time = '16:00',
  String? date = '2026-10-14',
  String state = 'open',
  String remaining = '10005',
  int version = 1,
  String? trigger = '2026-10-14T13:00:00Z',
  bool valid = true,
}) => {
  ...dueFixture(
    source: source,
    direction: direction,
    karat: karat,
    date: date,
    state: state,
    remaining: remaining,
  ),
  'reminder_time': time,
  'native_version': '$version',
  'native_freshness': dueHash,
  'time_valid': valid,
  'native_actor_user_id': version == 0 ? null : dueUser,
  'native_updated_at': version == 0 ? null : '2026-10-13T12:00:00Z',
  'trigger_at': time == null || date == null || !valid ? null : trigger,
  'can_write': state == 'open' && remaining != '0',
  'native_history': version == 0
      ? <Object?>[]
      : [
          {
            'id': dueKey,
            'old_time': null,
            'new_time': time,
            'due_date': date,
            'time_zone': 'Africa/Cairo',
            'native_version': '$version',
            'actor_user_id': dueUser,
            'actor_display_name': 'المالك',
            'at_shop': '2026-10-13T15:00:00',
            'at': '2026-10-13T12:00:00Z',
          },
        ],
};
Map<String, Object?> nativeReceipt(PendingFinancialCommand c) => {
  'version': 1,
  'shop_id': dueShop,
  'key': c.key,
  'kind': 'debt_native',
  'source_kind': (c.body['p_payload'] as Map)['source_kind'],
  'source_id': (c.body['p_payload'] as Map)['source_id'],
  'payload': c.body['p_payload'],
  'reminder_time': (c.body['p_payload'] as Map)['reminder_time'],
  'native_version':
      (BigInt.parse(
                (c.body['p_payload'] as Map)['expected_native_version']
                    as String,
              ) +
              BigInt.one)
          .toString(),
  'actor_user_id': dueUser,
  'at': '2026-10-14T12:00:00Z',
  'freshness': dueHash,
  'replayed': false,
  'cash_piastres': '0',
  'gold_milligrams': '0',
  'stock_milligrams': '0',
  'custody_milligrams': '0',
  'invoice_effect': false,
};
Map<String, Object?> nativePage(
  List<Map<String, Object?>> rows, {
  int offset = 0,
  int? total,
  String? cursor,
  String? hash,
}) => {
  'version': 1,
  'shop_id': dueShop,
  'snapshot_at': '2026-10-14T12:00:00Z',
  'freshness': hash ?? dueHash,
  'items': [
    for (final r in rows)
      {
        for (final k in [
          'source_kind',
          'source_id',
          'native_freshness',
          'trigger_at',
          'time_valid',
        ])
          k: r[k],
      },
  ],
  'total': total ?? rows.length,
  'offset': offset,
  'next_cursor': cursor,
};

class FakeNative implements DebtNativeGateway {
  Object? session = 'token';
  Map<String, Object?> data = nativeFixture();
  List<Map<String, Object?>> rows = [nativeFixture()];
  final sent = <PendingFinancialCommand>[];
  final pages = <String?>[];
  bool unknown = false;
  String? error;
  int detailReads = 0, reviews = 0;
  DateTime? instant(String? time) => time == null
      ? null
      : DateTime.parse(
          '${data['due_date']}T$time:00Z',
        ).subtract(const Duration(hours: 3));
  Future<DebtNativeDetail> Function()? readOverride;
  Future<DebtNativePage> Function(String?)? pageOverride;
  Future<DebtNativeTransport> Function(PendingFinancialCommand)? sendOverride,
      statusOverride;
  @override
  Object? nativeSession(String userId) => session;
  @override
  Future<DebtNativeDetail> readNative({
    required String userId,
    required String shopId,
    required DebtSourceKind sourceKind,
    required String sourceId,
  }) async {
    detailReads++;
    return readOverride == null ? parseDebtNativeDetail(data) : readOverride!();
  }

  @override
  Future<DebtNativeReview> reviewNative({
    required String userId,
    required String shopId,
    required DebtSourceKind sourceKind,
    required String sourceId,
    required String? time,
  }) async {
    reviews++;
    if (error != null) throw DebtReadException(error);
    return DebtNativeReview(parseDebtNativeDetail(data), time, instant(time));
  }

  @override
  Future<DebtNativePage> readNativeQueue({
    required String userId,
    required String shopId,
    required String? cursor,
  }) async {
    pages.add(cursor);
    if (error != null) throw DebtReadException(error);
    return pageOverride == null
        ? parseDebtNativePage(nativePage(rows))
        : pageOverride!(cursor);
  }

  @override
  Future<DebtNativeTransport> sendNative({
    required String userId,
    required String shopId,
    required PendingFinancialCommand command,
  }) async {
    sent.add(command);
    if (sendOverride != null) return sendOverride!(command);
    if (error != null) return DebtNativeTransport(error: error);
    if (unknown) return const DebtNativeTransport();
    final receipt = nativeReceipt(command),
        time = receipt['reminder_time'] as String?,
        version = receipt['native_version'] as String;
    data = {
      ...data,
      'native_version': version,
      'reminder_time': time,
      'native_updated_at': receipt['at'],
      'trigger_at': instant(time)?.toIso8601String(),
      'native_history': [
        ...data['native_history'] as List,
        {
          'id': 'afffffff-ffff-4fff-8fff-${version.padLeft(12, '0')}',
          'old_time': data['reminder_time'],
          'new_time': time,
          'due_date': data['due_date'],
          'time_zone': data['time_zone'],
          'native_version': version,
          'actor_user_id': dueUser,
          'actor_display_name': 'المالك',
          'at_shop': '2026-10-14T15:00:00',
          'at': receipt['at'],
        },
      ],
    };
    return DebtNativeTransport(receipt: parseDebtNativeReceipt(receipt));
  }

  @override
  Future<DebtNativeTransport> nativeStatus({
    required String userId,
    required String shopId,
    required PendingFinancialCommand command,
  }) async => statusOverride == null
      ? const DebtNativeTransport(absent: true)
      : statusOverride!(command);
}

class MemoryDeviceStore implements DeviceReminderStore {
  DeviceReminderManifest value = const DeviceReminderManifest(
    installation: dueKey,
  );
  Object? failure;
  final saves = <DeviceReminderManifest>[];
  @override
  Future<DeviceReminderManifest> load() async => value;
  @override
  Future<void> save(DeviceReminderManifest m) async {
    if (failure != null) throw failure!;
    value = m;
    saves.add(m);
  }
}

class FakeNotificationPort implements DebtNotificationPort {
  ReminderPermission allowed = ReminderPermission.allowed;
  final pending = <int>{};
  final registrations = <DeviceReminderRequest>[], cancellations = <int>[];
  int permissionRequests = 0;
  void Function(String)? tap;
  Future<void> Function(DeviceReminderRequest)? replaceOverride;
  Future<void> Function(int)? cancelOverride;
  @override
  Future<void> initialize(void Function(String token) onTap) async {
    tap = onTap;
  }

  @override
  Future<ReminderPermission> permission() async => allowed;
  @override
  Future<ReminderPermission> requestPermission() async {
    permissionRequests++;
    return allowed;
  }

  @override
  Future<bool> openSettings() async => true;
  @override
  Future<Set<int>> pendingIds() async => Set.of(pending);
  @override
  Future<void> replace(DeviceReminderRequest r) async {
    registrations.add(r);
    pending.add(r.id);
    await replaceOverride?.call(r);
  }

  @override
  Future<void> cancel(int id) async {
    cancellations.add(id);
    if (cancelOverride != null) {
      await cancelOverride!(id);
    } else {
      pending.remove(id);
    }
  }
}

class FakeReminderClock implements ReminderClock {
  DateTime now = DateTime.parse('2026-10-14T12:00:00Z');
  Duration elapsedTime = Duration.zero;
  @override
  DateTime nowUtc() => now;
  @override
  Duration get elapsed => elapsedTime;
}
