import '../domain/opening_draft.dart';
import '../domain/opening_issue.dart';
import 'daily_ledger_view.dart';
import 'idempotency_key.dart';
import 'opening_gateway.dart';
import 'pending_opening_store.dart';

const openingValidationCodes = <String>{
  'invalid_input',
  'negative_amount',
  'overflow',
  'unsupported_category_karat',
  'duplicate_bucket',
};

const openingAccessDeniedCodes = <String>{
  'forbidden',
  'shop_unavailable',
  'session_expired',
  'unauthenticated',
};

sealed class OpeningFlow {
  const OpeningFlow();
}

final class OpeningIdle extends OpeningFlow {
  const OpeningIdle(this.ledger);
  final DailyLedgerView ledger;
}

final class OpeningIgnored extends OpeningFlow {
  const OpeningIgnored();
}

final class OpeningUnresolved extends OpeningFlow {
  const OpeningUnresolved({required this.idempotencyKey, this.noticeCode});
  final String idempotencyKey;
  final String? noticeCode;
}

final class OpeningRejectedDraft extends OpeningFlow {
  const OpeningRejectedDraft({
    required this.idempotencyKey,
    required this.code,
    required this.draft,
  });
  final String idempotencyKey;
  final String code;
  final OpeningDraft draft;
}

final class OpeningReady extends OpeningFlow {
  const OpeningReady(this.ledger);
  final DailyLedgerView ledger;
}

/// The confirm call was acknowledged and the following ledger read failed.
final class OpeningRefreshFailed extends OpeningFlow {
  const OpeningRefreshFailed({required this.operationId, this.code});
  final String operationId;
  final String? code;
}

final class OpeningStorageFailed extends OpeningFlow {
  const OpeningStorageFailed();
}

final class OpeningFailed extends OpeningFlow {
  const OpeningFailed(this.code);
  final String code;
}

class OpeningFlowCoordinator {
  OpeningFlowCoordinator({
    required OpeningGateway gateway,
    required PendingOpeningStore store,
    String Function()? newKey,
    bool Function()? sessionLive,
    bool Function()? writesStillAllowed,
  }) : _gateway = gateway,
       _store = store,
       _newKey = newKey ?? newIdempotencyKey,
       _sessionLive = sessionLive,
       _writesStillAllowed = writesStillAllowed;

  final OpeningGateway _gateway;
  final PendingOpeningStore _store;
  final String Function() _newKey;
  final bool Function()? _sessionLive;
  final bool Function()? _writesStillAllowed;

  bool get _alive => _sessionLive?.call() ?? true;

  bool get _mayWrite => _alive && (_writesStillAllowed?.call() ?? true);
  bool _busy = false;
  bool _unresolved = false;

  bool get hasUnresolvedAttempt => _unresolved;

  Future<OpeningFlow> open({
    required String userId,
    required String shopId,
    required bool writesAllowed,
  }) {
    return _guard(
      () => _reconcile(
        userId: userId,
        shopId: shopId,
        retryAbsent: true,
        writesAllowed: writesAllowed,
      ),
    );
  }

  Future<OpeningFlow> refresh({
    required String userId,
    required String shopId,
    required bool writesAllowed,
  }) {
    return _guard(
      () => _reconcile(
        userId: userId,
        shopId: shopId,
        retryAbsent: _unresolved,
        writesAllowed: writesAllowed,
      ),
    );
  }

  Future<OpeningFlow> confirm({
    required String userId,
    required String shopId,
    required OpeningDraft draft,
    required bool writesAllowed,
  }) {
    return _guard(
      () => _confirm(
        userId: userId,
        shopId: shopId,
        draft: draft,
        writesAllowed: writesAllowed,
      ),
    );
  }

  Future<OpeningFlow> _guard(Future<OpeningFlow> Function() body) async {
    if (_busy) return const OpeningIgnored();
    _busy = true;
    try {
      return await body();
    } catch (_) {
      _unresolved = true;
      return const OpeningStorageFailed();
    } finally {
      _busy = false;
    }
  }

  Future<OpeningFlow> _confirm({
    required String userId,
    required String shopId,
    required OpeningDraft draft,
    required bool writesAllowed,
  }) async {
    if (!writesAllowed || !_mayWrite) return const OpeningIgnored();
    final existing = await _load(userId: userId, shopId: shopId);
    if (existing is OpeningStorageFailed) return existing;
    final pending = existing as PendingOpening?;
    if (pending != null &&
        pending.disposition == PendingDisposition.unresolved) {
      _unresolved = true;
      return OpeningUnresolved(idempotencyKey: pending.idempotencyKey);
    }
    if (pending != null &&
        pending.disposition == PendingDisposition.acknowledged) {
      _unresolved = true;
      return _finishCommitted(
        userId: userId,
        shopId: shopId,
        pending: pending,
        operationId: pending.operationId!,
      );
    }
    final key = pending?.idempotencyKey ?? _newKey();
    if (!isUuid(key)) return const OpeningStorageFailed();
    final frozen = PendingOpening(
      idempotencyKey: key,
      payload: draft.toCanonicalJson(),
      disposition: PendingDisposition.unresolved,
    );
    final saved = await _persist(
      userId: userId,
      shopId: shopId,
      pending: frozen,
    );
    if (saved is OpeningStorageFailed) return saved;
    _unresolved = true;
    return _send(
      userId: userId,
      shopId: shopId,
      pending: frozen,
      draft: draft,
      writesAllowed: true,
    );
  }

  Future<OpeningFlow> _reconcile({
    required String userId,
    required String shopId,
    required bool retryAbsent,
    required bool writesAllowed,
  }) async {
    final loaded = await _load(userId: userId, shopId: shopId);
    if (loaded is OpeningStorageFailed) return loaded;
    final pending = loaded as PendingOpening?;
    if (pending == null) {
      _unresolved = false;
      return _readLedger(userId);
    }
    if (pending.disposition == PendingDisposition.validationRejected) {
      _unresolved = false;
      final draft = OpeningDraft.parseJson(pending.payload);
      if (draft is! Accepted<OpeningDraft>) return const OpeningStorageFailed();
      return OpeningRejectedDraft(
        idempotencyKey: pending.idempotencyKey,
        code: pending.rejectionCode ?? 'invalid_input',
        draft: draft.value,
      );
    }
    if (pending.disposition == PendingDisposition.acknowledged) {
      _unresolved = true;
      return _finishCommitted(
        userId: userId,
        shopId: shopId,
        pending: pending,
        operationId: pending.operationId!,
      );
    }
    _unresolved = true;
    final StatusResult status;
    try {
      status = await _gateway.status(
        callerUserId: userId,
        idempotencyKey: pending.idempotencyKey,
      );
    } catch (_) {
      return OpeningUnresolved(idempotencyKey: pending.idempotencyKey);
    }
    if (!_alive) {
      return OpeningUnresolved(idempotencyKey: pending.idempotencyKey);
    }
    switch (status) {
      case StatusCompleted(:final operationId):
        return _finishCommitted(
          userId: userId,
          shopId: shopId,
          pending: pending,
          operationId: operationId,
        );
      case StatusAbsent():
        final peeked = await _peekLedger(userId);
        if (peeked is OpeningFailed) {
          return OpeningUnresolved(
            idempotencyKey: pending.idempotencyKey,
            noticeCode: peeked.code == 'unknown' ? null : peeked.code,
          );
        }
        if (peeked is OpeningIdle && peeked.ledger.isConfirmed) {
          await _retire(userId: userId, shopId: shopId);
          _unresolved = false;
          return OpeningReady(peeked.ledger);
        }
        if (!retryAbsent ||
            !_mayWrite ||
            !writesAllowed ||
            peeked is! OpeningIdle ||
            !peeked.ledger.canConfirm) {
          return OpeningUnresolved(idempotencyKey: pending.idempotencyKey);
        }
        final draft = OpeningDraft.parseJson(pending.payload);
        return _send(
          userId: userId,
          shopId: shopId,
          pending: pending,
          draft: draft is Accepted<OpeningDraft> ? draft.value : null,
          writesAllowed: true,
        );
      case StatusRejected(:final code):
        return OpeningUnresolved(
          idempotencyKey: pending.idempotencyKey,
          noticeCode: code,
        );
      case StatusUnknown():
        return OpeningUnresolved(idempotencyKey: pending.idempotencyKey);
    }
  }

  Future<OpeningFlow> _send({
    required String userId,
    required String shopId,
    required PendingOpening pending,
    required OpeningDraft? draft,
    required bool writesAllowed,
  }) async {
    if (!writesAllowed || !_mayWrite) {
      _unresolved = true;
      return OpeningUnresolved(idempotencyKey: pending.idempotencyKey);
    }
    final ConfirmResult result;
    try {
      result = await _gateway.confirm(
        callerUserId: userId,
        idempotencyKey: pending.idempotencyKey,
        payload: pending.payload,
      );
    } catch (_) {
      _unresolved = true;
      return OpeningUnresolved(idempotencyKey: pending.idempotencyKey);
    }
    if (!_alive) {
      _unresolved = true;
      return OpeningUnresolved(idempotencyKey: pending.idempotencyKey);
    }
    switch (result) {
      case ConfirmCommitted(:final operationId):
        return _finishCommitted(
          userId: userId,
          shopId: shopId,
          pending: pending,
          operationId: operationId,
        );
      case ConfirmUnknown():
        return _resolveUnknown(
          userId: userId,
          shopId: shopId,
          pending: pending,
          draft: draft,
          writesAllowed: writesAllowed,
        );
      case ConfirmRejected(:final code):
        if (openingValidationCodes.contains(code) && draft != null) {
          final editable = PendingOpening(
            idempotencyKey: pending.idempotencyKey,
            payload: pending.payload,
            disposition: PendingDisposition.validationRejected,
            rejectionCode: code,
          );
          final saved = await _persist(
            userId: userId,
            shopId: shopId,
            pending: editable,
          );
          if (saved is OpeningStorageFailed) {
            _unresolved = true;
            return saved;
          }
          _unresolved = false;
          return OpeningRejectedDraft(
            idempotencyKey: pending.idempotencyKey,
            code: code,
            draft: draft,
          );
        }
        if (code == 'opening_already_confirmed') {
          final ledger = await _readLedger(userId);
          if (ledger is OpeningIdle && ledger.ledger.isConfirmed) {
            await _retire(userId: userId, shopId: shopId);
            _unresolved = false;
            return OpeningReady(ledger.ledger);
          }
          _unresolved = true;
          return OpeningUnresolved(
            idempotencyKey: pending.idempotencyKey,
            noticeCode:
                ledger is OpeningFailed &&
                    openingAccessDeniedCodes.contains(ledger.code)
                ? ledger.code
                : code,
          );
        }
        _unresolved = true;
        return OpeningUnresolved(
          idempotencyKey: pending.idempotencyKey,
          noticeCode: code,
        );
    }
  }

  Future<OpeningFlow> _resolveUnknown({
    required String userId,
    required String shopId,
    required PendingOpening pending,
    required OpeningDraft? draft,
    required bool writesAllowed,
  }) async {
    final StatusResult status;
    try {
      status = await _gateway.status(
        callerUserId: userId,
        idempotencyKey: pending.idempotencyKey,
      );
    } catch (_) {
      _unresolved = true;
      return OpeningUnresolved(idempotencyKey: pending.idempotencyKey);
    }
    switch (status) {
      case StatusCompleted(:final operationId):
        return _finishCommitted(
          userId: userId,
          shopId: shopId,
          pending: pending,
          operationId: operationId,
        );
      case StatusAbsent():
        if (!writesAllowed || !_mayWrite) {
          _unresolved = true;
          return OpeningUnresolved(idempotencyKey: pending.idempotencyKey);
        }
        final ConfirmResult again;
        try {
          again = await _gateway.confirm(
            callerUserId: userId,
            idempotencyKey: pending.idempotencyKey,
            payload: pending.payload,
          );
        } catch (_) {
          _unresolved = true;
          return OpeningUnresolved(idempotencyKey: pending.idempotencyKey);
        }
        if (!_alive) {
          _unresolved = true;
          return OpeningUnresolved(idempotencyKey: pending.idempotencyKey);
        }
        if (again is ConfirmCommitted) {
          return _finishCommitted(
            userId: userId,
            shopId: shopId,
            pending: pending,
            operationId: again.operationId,
          );
        }
        if (again is ConfirmRejected &&
            openingValidationCodes.contains(again.code) &&
            draft != null) {
          final editable = PendingOpening(
            idempotencyKey: pending.idempotencyKey,
            payload: pending.payload,
            disposition: PendingDisposition.validationRejected,
            rejectionCode: again.code,
          );
          final saved = await _persist(
            userId: userId,
            shopId: shopId,
            pending: editable,
          );
          if (saved is OpeningStorageFailed) {
            _unresolved = true;
            return saved;
          }
          _unresolved = false;
          return OpeningRejectedDraft(
            idempotencyKey: pending.idempotencyKey,
            code: again.code,
            draft: draft,
          );
        }
        _unresolved = true;
        final notice = again is ConfirmRejected ? again.code : null;
        return OpeningUnresolved(
          idempotencyKey: pending.idempotencyKey,
          noticeCode: notice,
        );
      case StatusRejected(:final code):
        _unresolved = true;
        return OpeningUnresolved(
          idempotencyKey: pending.idempotencyKey,
          noticeCode: code,
        );
      case StatusUnknown():
        _unresolved = true;
        return OpeningUnresolved(idempotencyKey: pending.idempotencyKey);
    }
  }

  Future<OpeningFlow> _finishCommitted({
    required String userId,
    required String shopId,
    required PendingOpening pending,
    required String operationId,
  }) async {
    final read = await _readAfterCommit(userId, operationId);
    if (read is OpeningReady) {
      await _retire(userId: userId, shopId: shopId);
      _unresolved = false;
      return read;
    }
    final acknowledged = PendingOpening(
      idempotencyKey: pending.idempotencyKey,
      payload: pending.payload,
      disposition: PendingDisposition.acknowledged,
      operationId: operationId,
    );
    await _persist(userId: userId, shopId: shopId, pending: acknowledged);
    _unresolved = true;
    return read;
  }

  bool _matches(DailyLedgerView ledger, String operationId) {
    if (!ledger.isConfirmed || ledger.businessDay == null) return false;
    return ledger.feed.any(
      (line) =>
          line.kind == 'opening_balances_confirmed' &&
          line.operationId == operationId,
    );
  }

  Future<OpeningFlow> _readAfterCommit(
    String userId,
    String operationId,
  ) async {
    try {
      final ledger = await _gateway.ledger(callerUserId: userId);
      if (!_matches(ledger, operationId)) {
        return OpeningRefreshFailed(operationId: operationId);
      }
      return OpeningReady(ledger);
    } on LedgerReadException catch (error) {
      return OpeningRefreshFailed(operationId: operationId, code: error.code);
    } catch (_) {
      return OpeningRefreshFailed(operationId: operationId);
    }
  }

  Future<OpeningFlow> _peekLedger(String userId) async {
    try {
      return OpeningIdle(await _gateway.ledger(callerUserId: userId));
    } on LedgerReadException catch (error) {
      return OpeningFailed(error.code ?? 'unknown');
    } catch (_) {
      return const OpeningFailed('unknown');
    }
  }

  Future<OpeningFlow> _readLedger(String userId) async {
    try {
      return OpeningIdle(await _gateway.ledger(callerUserId: userId));
    } on LedgerReadException catch (error) {
      return OpeningFailed(error.code ?? 'unknown');
    } catch (_) {
      return const OpeningFailed('unknown');
    }
  }

  Future<Object?> _load({
    required String userId,
    required String shopId,
  }) async {
    final PendingOpening? pending;
    try {
      pending = await _store.read(userId: userId, shopId: shopId);
    } catch (_) {
      return const OpeningStorageFailed();
    }
    if (pending == null) return null;
    if (!isUuid(pending.idempotencyKey)) return const OpeningStorageFailed();
    if (pending.disposition == PendingDisposition.acknowledged) {
      final operationId = pending.operationId;
      if (operationId == null || !isUuid(operationId)) {
        return const OpeningStorageFailed();
      }
      return pending;
    }
    final parsed = OpeningDraft.parseJson(pending.payload);
    if (parsed is! Accepted<OpeningDraft>) return const OpeningStorageFailed();
    return PendingOpening(
      idempotencyKey: pending.idempotencyKey,
      payload: parsed.value.toCanonicalJson(),
      disposition: pending.disposition,
      rejectionCode: pending.rejectionCode,
    );
  }

  Future<OpeningFlow?> _persist({
    required String userId,
    required String shopId,
    required PendingOpening pending,
  }) async {
    try {
      await _store.save(userId: userId, shopId: shopId, pending: pending);
      return null;
    } catch (_) {
      return const OpeningStorageFailed();
    }
  }

  Future<void> _retire({required String userId, required String shopId}) async {
    try {
      await _store.retire(userId: userId, shopId: shopId);
    } catch (_) {}
  }
}
