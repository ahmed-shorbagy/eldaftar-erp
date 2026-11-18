import 'dart:async';

import 'package:flutter/widgets.dart';

import '../application/daily_ledger_view.dart';
import '../application/opening_flow.dart';
import '../application/opening_gateway.dart';
import '../application/pending_opening_store.dart';
import '../domain/opening_draft.dart';
import '../domain/opening_issue.dart';
import 'opening_copy.dart';

enum LedgerPhase {
  loading,

  /// The shop's ledger has not been opened. The owner's app opens it by
  /// itself; this phase is what staff see meanwhile, and what the owner sees
  /// with a retry when opening failed.
  notOpened,
  pending,
  confirmed,
  refreshFailed,
  expiredEmpty,
  accessDenied,
  failed,
}

/// Loads the daily ledger and, for a new shop, opens it.
///
/// Owner decision of 2026-11-17 (ADR 0049): there is no opening-balances
/// form. A new shop's ledger opens directly. The first time the owner
/// reaches it, the app confirms zero opening balances through the same
/// idempotent command, with nothing to review because nothing changes. Cash
/// and gold are entered afterwards from «الجرد الفوري».
class DailyLedgerController extends ChangeNotifier {
  DailyLedgerController({
    required OpeningGateway gateway,
    required PendingOpeningStore store,
    required this.userId,
    required this.shopId,
    required bool shopIsActive,
    this.canOpen = true,
    String Function()? newKey,
  }) : _shopIsActive = shopIsActive {
    _flow = OpeningFlowCoordinator(
      gateway: gateway,
      store: store,
      newKey: newKey,
      sessionLive: () => !_disposed,
      writesStillAllowed: () => !_disposed && _writesAllowed,
    );
  }

  late final OpeningFlowCoordinator _flow;
  final String userId;
  final String shopId;

  /// Only the owner opens the shop's ledger. Staff wait for them.
  bool canOpen;
  bool _shopIsActive;
  bool _disposed = false;
  bool _held = false;
  bool _opening = false;
  bool _openTried = false;

  bool get shopIsActive => _shopIsActive;

  set shopIsActive(bool value) {
    if (_applyShopActive(value)) notifyListeners();
  }

  /// Updates write allowance without notifying. The screen calls this from
  /// `didUpdateWidget`, whose following build already redraws the phase.
  void updateShopActive(bool value) {
    _applyShopActive(value);
  }

  bool _applyShopActive(bool value) {
    if (_disposed || _shopIsActive == value) return false;
    _shopIsActive = value;
    if (!value) {
      if (phase == LedgerPhase.notOpened) {
        _held = true;
        phase = LedgerPhase.expiredEmpty;
      }
    } else if (_held &&
        ledger?.isConfirmed != true &&
        (ledger == null || ledger!.canConfirm)) {
      phase = LedgerPhase.notOpened;
      _held = false;
    }
    return true;
  }

  bool get _writesAllowed =>
      _shopIsActive && (ledger == null || ledger!.canConfirm);

  LedgerPhase phase = LedgerPhase.loading;
  String? message;
  DailyLedgerView? ledger;

  bool get readOnly =>
      !_shopIsActive ||
      ledger?.entitlementStatus == 'expired' ||
      (ledger != null && ledger!.isUninitialized && !ledger!.canConfirm);

  /// True when the owner may press «إعادة المحاولة» on an unopened ledger.
  bool get canRetryOpen =>
      phase == LedgerPhase.notOpened && canOpen && !readOnly && !_opening;

  Future<void> start() => _applyFuture(
    _flow.open(userId: userId, shopId: shopId, writesAllowed: _writesAllowed),
  );

  Future<void> refresh() => _applyFuture(
    _flow.refresh(
      userId: userId,
      shopId: shopId,
      writesAllowed: _writesAllowed,
    ),
  );

  /// The owner's retry after an opening attempt failed.
  Future<void> retryOpen() async {
    if (!canRetryOpen) return;
    _openTried = false;
    await _openDirectly();
  }

  /// Confirms zero opening balances once, so the ledger is usable at once.
  /// The command and its stored key are the ones the old form used, so a
  /// lost reply is reconciled the same way and never posts twice.
  Future<void> _openDirectly() async {
    if (_opening || _disposed || !canOpen || !_writesAllowed) return;
    final zero = OpeningDraft.compose();
    if (zero is! Accepted<OpeningDraft>) return;
    _opening = true;
    _openTried = true;
    phase = LedgerPhase.loading;
    message = null;
    notifyListeners();
    final result = await _flow.confirm(
      userId: userId,
      shopId: shopId,
      draft: zero.value,
      writesAllowed: _writesAllowed,
    );
    _opening = false;
    if (_disposed) return;
    if (result is OpeningIgnored) {
      phase = LedgerPhase.notOpened;
      notifyListeners();
      return;
    }
    _apply(result);
  }

  Future<void> _applyFuture(Future<OpeningFlow> future) async {
    final result = await future;
    if (_disposed) return;
    _apply(result);
  }

  void _apply(OpeningFlow result) {
    if (_disposed) return;
    switch (result) {
      case OpeningIgnored():
        notifyListeners();
      case OpeningIdle(:final ledger):
        _showLedger(ledger);
      case OpeningReady(:final ledger):
        this.ledger = ledger;
        phase = LedgerPhase.confirmed;
        message = null;
        notifyListeners();
      case OpeningUnresolved(:final noticeCode):
        if (openingAccessDenied(noticeCode)) {
          ledger = null;
          phase = LedgerPhase.accessDenied;
          message = openingFailureCopy(noticeCode);
        } else {
          phase = LedgerPhase.pending;
          message = noticeCode == null ? null : openingFailureCopy(noticeCode);
        }
        notifyListeners();
      case OpeningRejectedDraft(:final code):
        phase = readOnly ? LedgerPhase.expiredEmpty : LedgerPhase.notOpened;
        message = readOnly ? null : openingFailureCopy(code);
        notifyListeners();
      case OpeningRefreshFailed(:final code):
        if (openingAccessDenied(code)) ledger = null;
        phase = LedgerPhase.refreshFailed;
        message = null;
        notifyListeners();
      case OpeningStorageFailed():
        message = openingStorageCopy;
        phase = readOnly ? LedgerPhase.expiredEmpty : LedgerPhase.notOpened;
        notifyListeners();
      case OpeningFailed(:final code):
        if (openingAccessDenied(code)) {
          ledger = null;
          phase = LedgerPhase.accessDenied;
        } else {
          phase = LedgerPhase.failed;
        }
        message = openingFailureCopy(code);
        notifyListeners();
    }
  }

  void _showLedger(DailyLedgerView next) {
    ledger = next;
    if (next.isConfirmed) {
      phase = LedgerPhase.confirmed;
      message = null;
      notifyListeners();
      return;
    }
    if (readOnly) {
      if (phase == LedgerPhase.notOpened) _held = true;
      phase = LedgerPhase.expiredEmpty;
      message = null;
      notifyListeners();
      return;
    }
    if (canOpen && !_openTried) {
      // Not awaited: the caller's read is done; the opening reports through
      // the phase like any other load.
      unawaited(_openDirectly());
      return;
    }
    phase = LedgerPhase.notOpened;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
