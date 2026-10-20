import 'closing_delegation_gateway.dart';

/// Durable commands retain their original envelope through timeouts and restarts.
/// The owner re-enters a creation password; it is never written to this store.
final class DelegationFlow {
  DelegationFlow({
    required this.gateway,
    required this.store,
    required this.userId,
    required this.scope,
  });
  final ClosingDelegationGateway gateway;
  final DelegationPendingStore store;
  final String userId, scope;
  PendingDelegation? pending;
  DelegationStatus status = DelegationStatus.absent;
  String? failure;
  bool restoringFailed = false;
  bool _running = false;
  Future<void> restore() async {
    try {
      pending = await store.read(userId, scope);
      restoringFailed = false;
      if (pending != null) await check();
    } catch (_) {
      restoringFailed = true;
      failure = 'local_persistence';
    }
  }

  Future<void> check() async {
    final command = pending;
    if (command == null) return;
    status = command.kind == 'create'
        ? await gateway.closingStaffCreationStatus(
            userId: userId,
            key: command.key,
          )
        : await gateway.closingDelegationStatus(
            userId: userId,
            key: command.key,
          );
    if (status == DelegationStatus.confirmed) {
      await store.clear(userId, scope, command.key);
      pending = null;
      failure = null;
    }
  }

  Future<void> run(PendingDelegation command, {String? password}) async {
    if (_running) return;
    _running = true;
    try {
      await _run(command, password: password);
    } finally {
      _running = false;
    }
  }

  Future<void> _run(PendingDelegation command, {String? password}) async {
    if (restoringFailed) return;
    await store.save(userId, scope, command);
    pending = command;
    status = DelegationStatus.unknown;
    failure = null;
    final p = command.payload;
    final DelegationResult result;
    try {
      result = switch (command.kind) {
        'create' => await gateway.createClosingStaff(
          userId: userId,
          key: command.key,
          name: p['name'] as String,
          phone: p['phone'] as String,
          password: password ?? '',
        ),
        'submit' => await gateway.submitClosingCount(
          userId: userId,
          key: command.key,
          taskId: p['task_id'] as String,
          observations: Map<String, Object?>.from(p['observations'] as Map),
        ),
        _ => await gateway.changeClosingAssignment(
          userId: userId,
          key: command.key,
          action: command.kind,
          target: p['target'] as String,
          dayId: p['day_id'] as String?,
          dayVersion: p['day_version'] as String?,
        ),
      };
    } catch (_) {
      failure = 'unknown';
      return;
    }
    if (result is DelegationRejected &&
        result.code == 'payload_mismatch' &&
        command.kind == 'create') {
      status = DelegationStatus.prepared;
      failure = result.code;
      return;
    }
    if (result is DelegationCommitted || result is DelegationRejected) {
      await store.clear(userId, scope, command.key);
      pending = null;
      status = result is DelegationCommitted
          ? DelegationStatus.confirmed
          : DelegationStatus.absent;
      failure = result is DelegationRejected ? result.code : null;
    } else {
      failure = 'unknown';
    }
  }
}
