import 'debt_native_gateway.dart';

enum ReminderPermission { allowed, denied, unsupported }

enum DeviceReminderState {
  disabled,
  preparing,
  registered,
  pending,
  failed,
  permissionDenied,
  unsupported,
  missed,
  outsideHorizon,
  capacity,
  invalidTime,
  stale,
  clockMismatch,
}

/// OS/device time is used only for OS feasibility and transport freshness.
/// Business due status and missed classification use the fresh server snapshot.
abstract interface class ReminderClock {
  DateTime nowUtc();
  Duration get elapsed;
}

final class DeviceReminderRequest {
  const DeviceReminderRequest({
    required this.id,
    required this.token,
    required this.sourceKind,
    required this.sourceId,
    required this.fingerprint,
    required this.at,
    this.applied = false,
  });
  final int id;
  final String token, sourceKind, sourceId, fingerprint;
  final DateTime at;
  final bool applied;
  DeviceReminderRequest marked(bool value) => DeviceReminderRequest(
    id: id,
    token: token,
    sourceKind: sourceKind,
    sourceId: sourceId,
    fingerprint: fingerprint,
    at: at,
    applied: value,
  );
}

final class DeviceReminderManifest {
  const DeviceReminderManifest({
    required this.installation,
    this.userId,
    this.shopId,
    this.enabled = false,
    this.requests = const [],
    this.routes = const [],
    this.tapToken,
  });
  final String installation;
  final String? userId, shopId, tapToken;
  final bool enabled;
  final List<DeviceReminderRequest> requests;

  /// Last 64 opaque tap routes survive firing/removal from the pending queue.
  final List<DeviceReminderRequest> routes;
  DeviceReminderManifest copy({
    bool? enabled,
    List<DeviceReminderRequest>? requests,
    List<DeviceReminderRequest>? routes,
    String? tapToken,
    bool clearTap = false,
  }) => DeviceReminderManifest(
    installation: installation,
    userId: userId,
    shopId: shopId,
    enabled: enabled ?? this.enabled,
    requests: requests ?? this.requests,
    routes: routes ?? this.routes,
    tapToken: clearTap ? null : tapToken ?? this.tapToken,
  );
}

abstract interface class DeviceReminderStore {
  Future<DeviceReminderManifest> load();
  Future<void> save(DeviceReminderManifest manifest);
}

abstract interface class DebtNotificationPort {
  Future<void> initialize(void Function(String token) onTap);
  Future<ReminderPermission> permission();
  Future<ReminderPermission> requestPermission();
  Future<bool> openSettings();
  Future<Set<int>> pendingIds();
  Future<void> replace(DeviceReminderRequest request);
  Future<void> cancel(int id);
}

final class ReminderDeviceReport {
  const ReminderDeviceReport(
    this.state, {
    this.rows = const {},
    this.at,
    this.error,
  });
  final DeviceReminderState state;
  final Map<String, DeviceReminderState> rows;
  final DateTime? at;
  final String? error;
}

/// Desired requests carry only opaque route/source identity and time, never balances.
typedef ReminderSnapshot = ({
  List<DebtScheduledIntent> rows,
  DateTime at,
  Duration receivedAt,
});
