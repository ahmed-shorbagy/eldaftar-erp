import 'package:flutter/widgets.dart';

import '../application/daily_ledger_view.dart';
import '../application/opening_flow.dart';
import '../application/opening_gateway.dart';
import '../application/pending_opening_store.dart';
import '../domain/opening_catalog.dart';
import '../domain/opening_draft.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';
import 'opening_copy.dart';

enum LedgerPhase {
  loading,
  form,
  review,
  pending,
  confirmed,
  refreshFailed,
  expiredEmpty,
  accessDenied,
  failed,
}

class StockEntry {
  StockEntry(this.id)
    : grams = TextEditingController(),
      count = TextEditingController();

  final int id;
  StockCategory category = StockCategory.workedJewelry;
  int karat = 18;
  final TextEditingController grams;
  final TextEditingController count;

  void dispose() {
    grams.dispose();
    count.dispose();
  }
}

class ScrapEntry {
  ScrapEntry(this.id) : grams = TextEditingController();

  final int id;
  int karat = 18;
  final TextEditingController grams;

  void dispose() => grams.dispose();
}

class DailyLedgerController extends ChangeNotifier {
  DailyLedgerController({
    required OpeningGateway gateway,
    required PendingOpeningStore store,
    required this.userId,
    required this.shopId,
    required bool shopIsActive,
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
  bool _shopIsActive;
  bool _disposed = false;
  LedgerPhase? _heldPhase;

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
      if (phase == LedgerPhase.form || phase == LedgerPhase.review) {
        _heldPhase = phase;
        phase = LedgerPhase.expiredEmpty;
      }
    } else if (_heldPhase != null &&
        ledger?.isConfirmed != true &&
        (ledger == null || ledger!.canConfirm)) {
      phase = _heldPhase!;
      _heldPhase = null;
    }
    return true;
  }

  bool get _writesAllowed =>
      _shopIsActive && (ledger == null || ledger!.canConfirm);

  final cash = <CashMethod, TextEditingController>{
    for (final method in CashMethod.canonicalOrder)
      method: TextEditingController(),
  };
  final stock = <StockEntry>[StockEntry(0)];
  final scrap = <ScrapEntry>[ScrapEntry(0)];
  var _rowSeed = 1;

  LedgerPhase phase = LedgerPhase.loading;
  String? message;
  OpeningDraft? reviewDraft;
  DailyLedgerView? ledger;
  bool _submitGuard = false;

  bool get fieldsLocked =>
      phase == LedgerPhase.pending || _submitGuard || !_shopIsActive;

  bool get readOnly =>
      !_shopIsActive ||
      ledger?.entitlementStatus == 'expired' ||
      (ledger != null && ledger!.isUninitialized && !ledger!.canConfirm);

  Future<void> start() => _applyFuture(
    _flow.open(userId: userId, shopId: shopId, writesAllowed: _writesAllowed),
  );

  Future<void> refresh() => _applyFuture(
    _flow.refresh(
      userId: userId,
      shopId: shopId,
      writesAllowed: _writesAllowed,
    ),
    preserveUninitializedWork: true,
  );

  void addStock() {
    if (fieldsLocked) return;
    stock.add(StockEntry(_rowSeed++));
    notifyListeners();
  }

  void addScrap() {
    if (fieldsLocked) return;
    scrap.add(ScrapEntry(_rowSeed++));
    notifyListeners();
  }

  void removeStock(StockEntry entry) {
    if (fieldsLocked || stock.length == 1) return;
    stock.remove(entry);
    entry.dispose();
    notifyListeners();
  }

  void removeScrap(ScrapEntry entry) {
    if (fieldsLocked || scrap.length == 1) return;
    scrap.remove(entry);
    entry.dispose();
    notifyListeners();
  }

  void setStockCategory(StockEntry entry, StockCategory category) {
    if (fieldsLocked) return;
    entry.category = category;
    if (!category.allowsKarat(entry.karat)) {
      entry.karat = (category.karats.toList()..sort()).first;
    }
    notifyListeners();
  }

  void setStockKarat(StockEntry entry, int karat) {
    if (fieldsLocked || !entry.category.allowsKarat(karat)) return;
    entry.karat = karat;
    notifyListeners();
  }

  void setScrapKarat(ScrapEntry entry, int karat) {
    if (fieldsLocked || !scrapKaratChoices.contains(karat)) return;
    entry.karat = karat;
    notifyListeners();
  }

  void reviewEntered() {
    if (fieldsLocked || readOnly) return;
    final draft = _draftFromForm();
    if (draft == null) {
      notifyListeners();
      return;
    }
    reviewDraft = draft;
    phase = LedgerPhase.review;
    message = null;
    notifyListeners();
  }

  void reviewZeros() {
    if (fieldsLocked || readOnly) return;
    final draft = OpeningDraft.compose();
    if (draft is! Accepted<OpeningDraft>) {
      message = openingFailureCopy(
        draft is Rejected<OpeningDraft> ? draft.code.wire : null,
      );
      notifyListeners();
      return;
    }
    reviewDraft = draft.value;
    phase = LedgerPhase.review;
    message = null;
    notifyListeners();
  }

  void backToEdit() {
    if (phase == LedgerPhase.pending || _submitGuard) return;
    phase = LedgerPhase.form;
    notifyListeners();
  }

  Future<void> confirmReview() async {
    if (_submitGuard || phase == LedgerPhase.pending || !_writesAllowed) {
      return;
    }
    final draft = reviewDraft;
    if (draft == null || _disposed) return;
    final previousPhase = phase;
    final previousMessage = message;
    _submitGuard = true;
    phase = LedgerPhase.pending;
    message = null;
    notifyListeners();
    final result = await _flow.confirm(
      userId: userId,
      shopId: shopId,
      draft: draft,
      writesAllowed: _writesAllowed,
    );
    if (_disposed) return;
    if (result is OpeningIgnored) {
      _submitGuard = false;
      if (phase == LedgerPhase.pending) {
        phase = previousPhase;
        message = previousMessage;
      }
      notifyListeners();
      return;
    }
    _submitGuard = false;
    _apply(result);
  }

  OpeningDraft? _draftFromForm() {
    final amounts = <CashMethod, Piastres>{};
    for (final method in CashMethod.canonicalOrder) {
      final text = cash[method]!.text.trim();
      if (text.isEmpty) continue;
      final parsed = Piastres.parsePounds(text);
      if (parsed is Rejected<Piastres>) {
        message = openingFailureCopy(parsed.code.wire);
        return null;
      }
      amounts[method] = (parsed as Accepted<Piastres>).value;
    }
    final stockRows = <OpeningStockBucket>[];
    for (final row in stock) {
      final grams = row.grams.text.trim();
      final count = row.count.text.trim();
      if (grams.isEmpty && count.isEmpty) continue;
      if (grams.isEmpty || count.isEmpty) {
        message = 'أكمل الصف أو اتركه فارغًا';
        return null;
      }
      final milligrams = Milligrams.parseGrams(grams);
      if (milligrams is Rejected<Milligrams>) {
        message = openingFailureCopy(milligrams.code.wire);
        return null;
      }
      final pieces = PieceCount.parseWire(count);
      if (pieces is Rejected<PieceCount>) {
        message = openingFailureCopy(pieces.code.wire);
        return null;
      }
      final bucket = OpeningStockBucket.tryCreate(
        category: row.category,
        karat: row.karat,
        milligrams: (milligrams as Accepted<Milligrams>).value,
        count: (pieces as Accepted<PieceCount>).value,
      );
      if (bucket is Rejected<OpeningStockBucket>) {
        message = openingFailureCopy(bucket.code.wire);
        return null;
      }
      stockRows.add((bucket as Accepted<OpeningStockBucket>).value);
    }
    final scrapRows = <OpeningScrapBucket>[];
    for (final row in scrap) {
      final grams = row.grams.text.trim();
      if (grams.isEmpty) continue;
      final milligrams = Milligrams.parseGrams(grams);
      if (milligrams is Rejected<Milligrams>) {
        message = openingFailureCopy(milligrams.code.wire);
        return null;
      }
      final bucket = OpeningScrapBucket.tryCreate(
        karat: row.karat,
        milligrams: (milligrams as Accepted<Milligrams>).value,
      );
      if (bucket is Rejected<OpeningScrapBucket>) {
        message = openingFailureCopy(bucket.code.wire);
        return null;
      }
      scrapRows.add((bucket as Accepted<OpeningScrapBucket>).value);
    }
    final draft = OpeningDraft.compose(
      cash: amounts,
      stock: stockRows,
      scrap: scrapRows,
    );
    if (draft is Rejected<OpeningDraft>) {
      message = openingFailureCopy(draft.code.wire);
      return null;
    }
    message = null;
    return (draft as Accepted<OpeningDraft>).value;
  }

  Future<void> _applyFuture(
    Future<OpeningFlow> future, {
    bool preserveUninitializedWork = false,
  }) async {
    final phaseAtStart = phase;
    final result = await future;
    if (_disposed) return;
    final keepEditing =
        preserveUninitializedWork &&
        _shopIsActive &&
        (phaseAtStart == LedgerPhase.form ||
            phaseAtStart == LedgerPhase.review) &&
        ((result is OpeningIdle &&
                result.ledger.isUninitialized &&
                result.ledger.canConfirm) ||
            result is OpeningRejectedDraft);
    if (keepEditing) {
      if (result is OpeningIdle) ledger = result.ledger;
      notifyListeners();
      return;
    }
    _apply(result);
  }

  void _apply(OpeningFlow result) {
    if (_disposed) return;
    switch (result) {
      case OpeningIgnored():
        notifyListeners();
      case OpeningIdle(:final ledger):
        _showLedger(ledger, keepMessage: false);
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
      case OpeningRejectedDraft(:final code, :final draft):
        _restoreDraft(draft);
        reviewDraft = draft;
        _submitGuard = false;
        if (readOnly) {
          phase = LedgerPhase.expiredEmpty;
          message = null;
        } else {
          phase = LedgerPhase.form;
          message = openingFailureCopy(code);
        }
        notifyListeners();
      case OpeningRefreshFailed(:final code):
        if (openingAccessDenied(code)) ledger = null;
        phase = LedgerPhase.refreshFailed;
        message = null;
        notifyListeners();
      case OpeningStorageFailed():
        _submitGuard = false;
        message = openingStorageCopy;
        phase = readOnly
            ? LedgerPhase.expiredEmpty
            : (reviewDraft == null ? LedgerPhase.form : LedgerPhase.review);
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

  void _showLedger(DailyLedgerView next, {required bool keepMessage}) {
    ledger = next;
    if (next.isConfirmed) {
      phase = LedgerPhase.confirmed;
      message = null;
    } else if (readOnly) {
      if (phase == LedgerPhase.form || phase == LedgerPhase.review) {
        _heldPhase = phase;
      }
      phase = LedgerPhase.expiredEmpty;
      message = null;
    } else {
      phase = LedgerPhase.form;
      if (!keepMessage) message = null;
    }
    notifyListeners();
  }

  void _restoreDraft(OpeningDraft draft) {
    for (final method in CashMethod.canonicalOrder) {
      final amount = draft.cash[method];
      cash[method]!.text = amount.value == BigInt.zero ? '' : amount.poundsText;
    }
    for (final row in stock) {
      row.dispose();
    }
    stock
      ..clear()
      ..addAll(
        draft.stock.isEmpty
            ? [StockEntry(_rowSeed++)]
            : [
                for (final row in draft.stock)
                  StockEntry(_rowSeed++)
                    ..category = row.category
                    ..karat = row.karat
                    ..grams.text = row.milligrams.gramsText
                    ..count.text = row.count.wire,
              ],
      );
    for (final row in scrap) {
      row.dispose();
    }
    scrap
      ..clear()
      ..addAll(
        draft.scrap.isEmpty
            ? [ScrapEntry(_rowSeed++)]
            : [
                for (final row in draft.scrap)
                  ScrapEntry(_rowSeed++)
                    ..karat = row.karat
                    ..grams.text = row.milligrams.gramsText,
              ],
      );
  }

  @override
  void dispose() {
    _disposed = true;
    for (final controller in cash.values) {
      controller.dispose();
    }
    for (final row in stock) {
      row.dispose();
    }
    for (final row in scrap) {
      row.dispose();
    }
    super.dispose();
  }
}
