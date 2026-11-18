import '../../invoice_message/application/message_contract.dart';
import '../../debts/application/debt_native_contract.dart';
import 'dart:async';
import 'dart:typed_data';

import '../../../theme/app_confirm.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_banner.dart';
import '../../../theme/app_messages.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/feedback_copy.dart';
import '../../../theme/message_tone.dart';
import '../../shop_accounts/domain/shop_account.dart';
import '../../onboarding/application/onboarding_store.dart';
import '../../daily_notes/application/notes_gateway.dart';
import '../../daily_notes/data/note_image_file_store.dart';
import '../../daily_notes/data/platform_note_image_source.dart';
import '../../daily_notes/data/secure_note_draft_store.dart';
import '../../daily_notes/presentation/daily_notes_screen.dart';
import '../../reports/application/report_gateway.dart';
import '../application/ledger_date_gateway.dart';
import '../application/opening_gateway.dart';
import '../application/daily_ledger_view.dart';
import '../application/financial_gateway.dart';
import '../../inventory/application/inventory_gateway.dart';
import '../../debts/application/debt_contract.dart';
import '../../debts/application/debt_due_contract.dart';
import '../../customers/application/customer_contract.dart';
import '../../invoice_appearance/application/invoice_appearance_contract.dart';
import '../../repairs/application/repair_contract.dart';
import '../application/ledger_activity.dart';
import '../application/ledger_control_access.dart';
import '../application/ledger_line_items.dart';
import '../application/idempotency_key.dart';
import '../application/pending_opening_store.dart';
import '../application/pending_financial_command.dart';
import '../data/pending_financial_command.dart';
import '../domain/financial_draft.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';
import 'daily_ledger_controller.dart';
import 'confirmed_ledger_dashboard.dart';
import 'financial_trade_screen.dart';
import 'financial_operation_screen.dart';
import 'pending_invoice_sends_screen.dart';
import 'ledger_archive_screen.dart';
import 'daily_close_screen.dart';
import 'cash_transfer_screen.dart';
import 'scrap_to_stock_screen.dart';
import 'ledger_app_bar.dart';
import '../application/ledger_trade_change.dart';
import 'opening_copy.dart';

class DailyLedgerScreen extends StatefulWidget {
  const DailyLedgerScreen({
    super.key,
    required this.shop,
    this.onChangeShop,
    this.onActivateSubscription,
    this.gateway,
    this.store,
    this.userId,
    this.refreshGeneration = 0,
    this.syncTicks,
    this.newKey,
    this.onboardingStore,
    this.guideResumeGeneration = 0,
    this.inventoryPage,
    this.onOpenRepairs,
    this.onOpenDebts,
    this.onOpenCustomers,
    this.onOpenInvoiceAppearance,
    this.onOpenInvoiceMessage,
    this.shopImageBytes,
  });

  final ShopAccount shop;
  final VoidCallback? onChangeShop;
  final Future<void> Function()? onActivateSubscription;
  final OpeningGateway? gateway;
  final PendingOpeningStore? store;
  final String? userId;
  final int refreshGeneration;
  final Listenable? syncTicks;
  final String Function()? newKey;
  final OnboardingStore? onboardingStore;
  final int guideResumeGeneration;
  final WidgetBuilder? inventoryPage;
  final Future<void> Function()? onOpenRepairs;
  final Future<void> Function()? onOpenDebts;
  final Future<void> Function()? onOpenCustomers;
  final Future<void> Function()? onOpenInvoiceAppearance;
  final Future<void> Function()? onOpenInvoiceMessage;
  final Uint8List? shopImageBytes;

  @override
  State<DailyLedgerScreen> createState() => _DailyLedgerScreenState();
}

bool _positiveWireAmount(String value) {
  final parsed = Milligrams.parseWire(value);
  return parsed is Accepted<Milligrams> && parsed.value.value > BigInt.zero;
}

class _DailyLedgerScreenState extends State<DailyLedgerScreen>
    with WidgetsBindingObserver {
  LedgerControlAccess get _access => LedgerControlAccess.of(widget.shop);
  DailyLedgerController? _controller;
  final _scroll = ScrollController();
  FinancialDayState? _financialDay;
  String? _financialError;
  bool _financialLoading = false;
  bool _dayCommandBusy = false;
  final _financialPendingStore = const PendingFinancialCommands();
  PendingFinancialCommand? _financialPending;
  bool _pendingStatusUnknown = false;
  Timer? _syncTimer;
  Timer? _midnightTimer;
  LedgerJournalContext? _scheduledJournal;
  final _formInvalidations = ValueNotifier<int>(0);
  bool _headerCollapsed = false;
  bool _syncing = false;
  bool _syncQueued = false;
  bool _loadingOlder = false;
  bool _caughtUp = false;
  final _activity = LedgerActivityController();
  final Map<String, Future<List<LedgerLineItem>?>> _itemCache = {};
  Future<List<LedgerLineItem>?> Function(String operationId)? _itemsLoader;

  /// Trades can be edited or deleted, so every confirmed refresh re-reads
  /// items. A new callback identity tells each card to re-read quietly.
  void _dropItemCache() {
    _itemCache.clear();
    _itemsLoader = (operationId) => _loadOperationItems(operationId);
  }

  FinancialGateway? get _financialGateway => widget.gateway is FinancialGateway
      ? widget.gateway! as FinancialGateway
      : null;

  NotesGateway? get _notesGateway =>
      widget.gateway is NotesGateway ? widget.gateway! as NotesGateway : null;

  LedgerFeedGateway? get _feedGateway => widget.gateway is LedgerFeedGateway
      ? widget.gateway! as LedgerFeedGateway
      : null;

  bool get _expired => widget.shop.entitlement == ShopEntitlement.expired;

  /// Writes follow the open financial day until the owner closes it.
  /// Calendar midnight refreshes reads only; it does not open or close a day.
  bool _canStartEntry(String userId) =>
      mounted &&
      widget.userId == userId &&
      !_expired &&
      _controller?.readOnly == false &&
      _financialDay?.isOpen == true;

  String? get _tradeBlockedReason {
    if (_expired || (_controller?.readOnly ?? true)) {
      return 'الاشتراك منتهٍ. العرض للقراءة فقط.';
    }
    if (_financialPending != null) {
      return 'عملية مالية بانتظار تأكيد الحفظ. أكملها قبل إضافة عملية جديدة.';
    }
    if (_financialDay == null) {
      return 'جارٍ تحميل حالة يوم العمل.';
    }
    if (_financialDay!.isClosed) {
      return 'يوم العمل مغلق. افتح اليوم قبل إضافة عملية.';
    }
    return null;
  }

  void _requestTrade(FinancialKind kind) {
    final reason = _tradeBlockedReason;
    if (reason != null) {
      final closed = _financialDay?.isClosed == true;
      AppMessages.show(
        context,
        tone: closed ? MessageTone.warning : MessageTone.info,
        title: reason,
        id: 'ledger-trade-blocked',
      );
      return;
    }
    _startTrade(kind);
  }

  void _onScroll() {
    final collapsed =
        _scroll.hasClients && _scroll.offset > (_headerCollapsed ? 40 : 100);
    if (collapsed != _headerCollapsed) {
      setState(() => _headerCollapsed = collapsed);
    }
  }

  void _scheduleCalendarBoundary() {
    final journal = _controller?.ledger?.journalContext;
    if (journal == null || identical(journal, _scheduledJournal)) return;
    _scheduledJournal = journal;
    _midnightTimer?.cancel();
    _midnightTimer = Timer(journal.untilNextMidnight, () {
      if (!mounted) return;
      _formInvalidations.value++;
      _sync();
    });
    _formInvalidations.value++;
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
    widget.syncTicks?.addListener(_onSyncTicks);
    _syncTimer = Timer.periodic(const Duration(minutes: 1), (_) => _sync());
    _attach();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  Future<void> _sync() async {
    if (_syncing) {
      _syncQueued = true;
      return;
    }
    if (!mounted ||
        _dayCommandBusy ||
        ModalRoute.of(context)?.isCurrent != true ||
        !const {
          LedgerPhase.confirmed,
          LedgerPhase.refreshFailed,
          // Staff waiting for the owner, and an opening whose reply was lost,
          // both resolve on the next sync without a restart.
          LedgerPhase.notOpened,
          LedgerPhase.pending,
        }.contains(_controller?.phase)) {
      return;
    }
    _syncing = true;
    try {
      _dropItemCache();
      await _controller?.refresh();
      if (mounted) {
        await _catchUpFeed();
        await _maybeLoadFinancialDay(force: true);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _financialError =
              'تعذرت مزامنة الدفتر. ستُعاد المحاولة تلقائيًا.',
        );
      }
    } finally {
      _syncing = false;
      final queued = _syncQueued;
      _syncQueued = false;
      if (queued && mounted) unawaited(_sync());
    }
  }

  void _attach() {
    final gateway = widget.gateway;
    final store = widget.store;
    final userId = widget.userId;
    if (gateway == null || store == null || userId == null || userId.isEmpty) {
      return;
    }
    final controller = DailyLedgerController(
      gateway: gateway,
      store: store,
      userId: userId,
      shopId: widget.shop.id,
      shopIsActive: widget.shop.entitlement == ShopEntitlement.active,
      canOpen: _access.openDay,
      newKey: widget.newKey,
    );
    controller.addListener(_onController);
    _controller = controller;
    controller.start();
  }

  void _onController() {
    if (!mounted) return;
    _scheduleCalendarBoundary();
    _adoptFeed();
    if (!_caughtUp &&
        _controller?.phase == LedgerPhase.confirmed &&
        _feedGateway != null) {
      _caughtUp = true;
      _catchUpFeed();
    }
    setState(() {});
    _maybeLoadFinancialDay();
  }

  void _adoptFeed() {
    final userId = widget.userId;
    final controller = _controller;
    if (userId == null || controller == null || _feedGateway == null) return;
    _activity.adoptSummary(
      userId: userId,
      shopId: widget.shop.id,
      ledger: controller.ledger,
    );
  }

  Future<void> _catchUpFeed() async {
    final gateway = _feedGateway;
    final userId = widget.userId;
    if (gateway == null || userId == null) return;
    _adoptFeed();
    final added = await _activity.catchUp(gateway: gateway, userId: userId);
    if (added > 0) {
      _dropItemCache();
      await _controller?.refresh();
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadOlder() async {
    final gateway = _feedGateway;
    final userId = widget.userId;
    if (gateway == null || userId == null || _loadingOlder) return;
    setState(() => _loadingOlder = true);
    try {
      await _activity.loadOlder(gateway: gateway, userId: userId);
    } on CalendarLedgerChanged {
      _dropItemCache();
      await _controller?.refresh();
    } catch (_) {
      if (mounted) {
        setState(
          () => _financialError =
              'تعذر تحميل العمليات الأقدم. الحركة المعروضة لم تُحذف.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  void _openDailyNotes() {
    final gateway = _notesGateway;
    final userId = widget.userId;
    if (gateway == null || userId == null) return;
    final day = _controller?.ledger?.businessDay;
    final canWrite =
        !_expired &&
        (_financialGateway == null || _financialDay?.isOpen == true) &&
        day != null;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => DailyNotesScreen(
          gateway: gateway,
          userId: userId,
          shopId: widget.shop.id,
          businessDayId: day?.id,
          businessDate: _controller?.ledger?.journalContext?.businessDate,
          writesStillAllowed: () => _canStartEntry(userId),
          invalidations: _formInvalidations,
          canWrite: canWrite,
          canManageNotes: widget.shop.isOwner,
          drafts: const SecureNoteDraftStore(),
          files: ApplicationNoteImageFileStore(),
          images: const PlatformNoteImageSource(),
          newKey: widget.newKey,
        ),
      ),
    );
  }

  Future<void> _maybeLoadFinancialDay({bool force = false}) async {
    final gateway = _financialGateway;
    final controller = _controller;
    if (gateway == null ||
        controller?.phase != LedgerPhase.confirmed ||
        _financialLoading ||
        (!force && _financialDay != null)) {
      return;
    }
    final userId = widget.userId;
    if (userId == null) return;
    _financialLoading = true;
    try {
      final pending = await _financialPendingStore.read(userId, widget.shop.id);
      if (pending != null &&
          (repairRpcs.containsKey(pending.kind) ||
              debtRpcs.containsKey(pending.kind) ||
              (pending.kind == debtDueKind || pending.kind == debtNativeKind) ||
              customerRpcs.containsKey(pending.kind) ||
              pending.kind == invoiceMessageKind ||
              pending.kind == invoiceAppearanceKind ||
              pending.kind == invoicePresentationKind)) {
        if (mounted && userId == widget.userId) {
          setState(() {
            _financialPending = pending;
            _pendingStatusUnknown = true;
          });
        }
      } else if (pending != null) {
        final status = await widget.gateway!.status(
          callerUserId: userId,
          idempotencyKey: pending.key,
        );
        if (status is StatusCompleted) {
          await _financialPendingStore.clear(
            userId,
            widget.shop.id,
            pending.key,
          );
          if (mounted) setState(() => _financialPending = null);
          _dropItemCache();
          await controller!.refresh();
        } else if (mounted) {
          setState(() {
            _financialPending = pending;
            _pendingStatusUnknown = status is! StatusAbsent;
          });
        }
      } else if (mounted) {
        setState(() => _financialPending = null);
      }
      final state = await gateway.dayState(callerUserId: userId);
      if (!mounted || userId != widget.userId) return;
      setState(() {
        _financialDay = state;
        _financialError = null;
      });
    } on LedgerReadException catch (error) {
      if (!mounted || userId != widget.userId) return;
      if (error.code == 'rpc_unavailable') {
        setState(() {
          _financialDay = null;
          _financialError = null;
        });
        return;
      }
      setState(
        () => _financialError =
            'تعذر تحميل حالة يوم العمل. حدّث الدفتر للمحاولة مرة أخرى.',
      );
    } catch (_) {
      if (!mounted || userId != widget.userId) return;
      setState(
        () => _financialError =
            'تعذر تحميل حالة يوم العمل. حدّث الدفتر للمحاولة مرة أخرى.',
      );
    } finally {
      _financialLoading = false;
    }
  }

  Future<void> _resolveFinancialPending({bool retry = false}) async {
    final pending = _financialPending;
    final userId = widget.userId;
    final gateway = _financialGateway;
    if (pending == null ||
        userId == null ||
        gateway == null ||
        _dayCommandBusy) {
      return;
    }
    if (pending.kind == invoiceMessageKind) {
      final open = widget.onOpenInvoiceMessage;
      if (open != null) await open();
      if (!mounted) return;
      _dropItemCache();
      await _controller?.refresh();
      await _maybeLoadFinancialDay(force: true);
      return;
    }
    if (pending.kind == invoiceAppearanceKind ||
        pending.kind == invoicePresentationKind) {
      if (pending.kind == invoiceAppearanceKind) {
        final open = widget.onOpenInvoiceAppearance;
        if (open == null) {
          setState(
            () => _financialError =
                'يوجد طلب مظهر فاتورة محفوظ. افتح مظهر الفاتورة من المزيد للتحقق منه.',
          );
          return;
        }
        await open();
      } else {
        final opened = await _openPendingPresentation(pending);
        if (!opened && mounted) {
          setState(
            () => _financialError =
                'يوجد طلب نسخة عرض محفوظ. افتح العملية المؤكدة للتحقق منه.',
          );
        }
      }
      if (!mounted) return;
      _dropItemCache();
      await _controller?.refresh();
      await _maybeLoadFinancialDay(force: true);
      return;
    }
    if (repairRpcs.containsKey(pending.kind) ||
        debtRpcs.containsKey(pending.kind) ||
        (pending.kind == debtDueKind || pending.kind == debtNativeKind) ||
        customerRpcs.containsKey(pending.kind)) {
      final debt =
          debtRpcs.containsKey(pending.kind) ||
          (pending.kind == debtDueKind || pending.kind == debtNativeKind);
      final customer = customerRpcs.containsKey(pending.kind);
      final open = customer
          ? widget.onOpenCustomers
          : debt
          ? widget.onOpenDebts
          : widget.onOpenRepairs;
      if (open == null) {
        setState(
          () => _financialError = customer
              ? 'يوجد طلب عميل محفوظ. افتح العملاء للتحقق منه.'
              : debt
              ? 'يوجد طلب ديون محفوظ. افتح النوتة من المزيد للتحقق منه.'
              : 'يوجد طلب مرمة محفوظ. افتح المرمات من المزيد للتحقق منه.',
        );
        return;
      }
      await open();
      if (!mounted) return;
      _dropItemCache();
      await _controller?.refresh();
      await _maybeLoadFinancialDay(force: true);
      return;
    }
    setState(() => _dayCommandBusy = true);
    try {
      final status = await widget.gateway!.status(
        callerUserId: userId,
        idempotencyKey: pending.key,
      );
      if (!mounted) return;
      if (status is StatusCompleted) {
        await _financialPendingStore.clear(userId, widget.shop.id, pending.key);
        if (!mounted) return;
        setState(() => _financialPending = null);
        _dropItemCache();
        await _controller?.refresh();
        await _maybeLoadFinancialDay(force: true);
      } else if (status is StatusAbsent && retry) {
        final result = await gateway.retryPending(
          callerUserId: userId,
          command: pending,
        );
        if (!mounted) return;
        if (result is FinancialCommitted) {
          await _financialPendingStore.clear(
            userId,
            widget.shop.id,
            pending.key,
          );
          if (!mounted) return;
          setState(() => _financialPending = null);
          _dropItemCache();
          await _controller?.refresh();
          await _maybeLoadFinancialDay(force: true);
        } else if (result is FinancialRejected) {
          await _financialPendingStore.clear(
            userId,
            widget.shop.id,
            pending.key,
          );
          if (!mounted) return;
          setState(() {
            _financialPending = null;
            _financialError = result.code == 'retired_return'
                ? tradeChangeFailure(result.code)
                : 'تعذر حفظ العملية. حدّث الدفتر وراجع البيانات قبل المحاولة مجددًا.';
          });
        } else if (result is FinancialCountMismatch) {
          await _financialPendingStore.clear(
            userId,
            widget.shop.id,
            pending.key,
          );
          if (!mounted) return;
          setState(() {
            _financialPending = null;
            _financialError =
                'تغيّرت الأرصدة المسجلة. حدّث الدفتر وأعد المراجعة.';
          });
        } else {
          setState(() => _pendingStatusUnknown = true);
        }
      } else {
        setState(() => _pendingStatusUnknown = status is! StatusAbsent);
      }
    } catch (_) {
      if (mounted) setState(() => _pendingStatusUnknown = true);
    } finally {
      if (mounted) setState(() => _dayCommandBusy = false);
    }
  }

  Future<void> _startTrade(FinancialKind kind) async {
    final gateway = _financialGateway;
    final userId = widget.userId;
    if (gateway == null ||
        userId == null ||
        _financialDay?.isOpen != true ||
        _financialPending != null) {
      return;
    }
    final catalog = gateway is InventoryGateway
        ? gateway as InventoryGateway
        : null;
    // Trades show their own outcome page (tier 1), so the result needs no
    // extra toast here.
    if (kind == FinancialKind.sale ||
        kind == FinancialKind.purchase ||
        kind == FinancialKind.customerReturn) {
      await showFinancialTradeSheet(
        context: context,
        kind: kind,
        gateway: gateway,
        statusGateway: widget.gateway!,
        userId: userId,
        shopId: widget.shop.id,
        catalog: catalog,
        canSendInvoice: _access.sendInvoice,
        inventoryPage: widget.inventoryPage,
        canRead: () => mounted && widget.userId == userId,
        canWrite: () => _canStartEntry(userId),
        syncTicks: Listenable.merge([widget.syncTicks, _formInvalidations]),
      );
    } else {
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => FinancialTradeScreen(
            kind: kind,
            gateway: gateway,
            statusGateway: widget.gateway!,
            userId: userId,
            shopId: widget.shop.id,
            canRead: () => mounted && widget.userId == userId,
            canWrite: () => _canStartEntry(userId),
            syncTicks: Listenable.merge([widget.syncTicks, _formInvalidations]),
            canSendInvoice: _access.sendInvoice,
          ),
        ),
      );
    }
    if (!mounted) return;
    _dropItemCache();
    await _controller?.refresh();
    await _maybeLoadFinancialDay(force: true);
  }

  Future<void> _closeDay() async {
    final gateway = _financialGateway;
    final userId = widget.userId;
    final day = _financialDay;
    if (gateway == null ||
        userId == null ||
        day?.isOpen != true ||
        _financialPending != null) {
      return;
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DailyCloseScreen(
          gateway: gateway,
          statusGateway: widget.gateway!,
          userId: userId,
          shopId: widget.shop.id,
          day: day!,
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      AppMessages.success(context, FeedbackCopy.dayClosed);
      _dropItemCache();
      await _controller?.refresh();
      await _maybeLoadFinancialDay(force: true);
    }
  }

  Future<void> _transferCash() async {
    final gateway = _financialGateway;
    final userId = widget.userId;
    final cash = _controller?.ledger?.cash;
    if (gateway is! CashTransferGateway ||
        userId == null ||
        cash == null ||
        _financialDay?.isOpen != true ||
        _financialPending != null) {
      return;
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CashTransferScreen(
          gateway: gateway as CashTransferGateway,
          statusGateway: widget.gateway!,
          userId: userId,
          shopId: widget.shop.id,
          cash: cash,
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      AppMessages.success(context, FeedbackCopy.cashTransferred);
      _dropItemCache();
      await _controller?.refresh();
      await _maybeLoadFinancialDay(force: true);
    }
  }

  Future<void> _convertScrapToStock() async {
    final gateway = _financialGateway;
    final userId = widget.userId;
    final scrap = _controller?.ledger?.scrap;
    if (gateway is! ScrapToStockGateway ||
        userId == null ||
        scrap == null ||
        !scrap.any((line) => _positiveWireAmount(line.milligrams)) ||
        _financialDay?.isOpen != true ||
        _financialPending != null) {
      return;
    }
    final scrapGateway = gateway as ScrapToStockGateway;
    final catalog = gateway is InventoryGateway
        ? gateway as InventoryGateway
        : null;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ScrapToStockScreen(
          gateway: scrapGateway,
          statusGateway: widget.gateway!,
          userId: userId,
          shopId: widget.shop.id,
          scrap: scrap,
          catalog: catalog,
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      // U20: the screen showed its own outcome page.
      _dropItemCache();
      await _controller?.refresh();
      await _maybeLoadFinancialDay(force: true);
    }
  }

  Future<List<LedgerLineItem>?> _loadOperationItems(String operationId) {
    return _itemCache.putIfAbsent(operationId, () {
      final pending = () async {
        final gateway = _financialGateway;
        final userId = widget.userId;
        if (gateway == null || userId == null) return null;
        final operation = await gateway.operation(
          callerUserId: userId,
          operationId: operationId,
        );
        final payload = operation['payload'];
        return ledgerLineItemsFromPayload(payload);
      }();
      unawaited(
        pending.then(
          (items) {
            if (items == null) _itemCache.remove(operationId);
          },
          onError: (Object _, StackTrace _) {
            _itemCache.remove(operationId);
          },
        ),
      );
      return pending;
    });
  }

  Future<bool> _openPendingPresentation(PendingFinancialCommand pending) async {
    final gateway = _financialGateway;
    final userId = widget.userId;
    final raw = pending.body['p_payload'];
    final operationId = raw is Map ? raw['operation_id'] : null;
    if (gateway == null || userId == null || operationId is! String) {
      return false;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FinancialOperationScreen(
          gateway: gateway,
          userId: userId,
          shopId: widget.shop.id,
          canChangeOperation: widget.shop.isOwner,
          canSendInvoice: _access.sendInvoice,
          canRead: () => mounted && widget.userId == userId,
          canWrite: () =>
              mounted &&
              widget.userId == userId &&
              !_expired &&
              _controller?.readOnly == false &&
              widget.shop.entitlement == ShopEntitlement.active,
          line: LedgerFeedLine(
            kind: 'sale',
            labelAr: 'بيع',
            operationId: operationId,
            actorDisplayName: '',
            occurredAt: '',
            occurredAtCairo: '',
          ),
          syncTicks: widget.syncTicks,
        ),
      ),
    );
    return true;
  }

  Future<void> _openOperation(LedgerFeedLine line) async {
    final gateway = _financialGateway;
    final userId = widget.userId;
    if (gateway == null || userId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FinancialOperationScreen(
          gateway: gateway,
          userId: userId,
          shopId: widget.shop.id,
          canChangeOperation: widget.shop.isOwner,
          canSendInvoice: _access.sendInvoice,
          canRead: () => mounted && widget.userId == userId,
          canWrite: () =>
              mounted &&
              widget.userId == userId &&
              !_expired &&
              _controller?.readOnly == false &&
              widget.shop.entitlement == ShopEntitlement.active,
          line: line,
          syncTicks: widget.syncTicks,
        ),
      ),
    );
    if (!mounted) return;
    _dropItemCache();
    await _controller?.refresh();
    await _maybeLoadFinancialDay(force: true);
  }

  void _openArchive(String date) {
    final gateway = widget.gateway;
    final userId = widget.userId;
    if (gateway is! ReportGateway ||
        gateway is! LedgerDateGateway ||
        gateway is! FinancialGateway ||
        userId == null) {
      return;
    }
    final reports = gateway as ReportGateway;
    final dates = gateway as LedgerDateGateway;
    final money = gateway as FinancialGateway;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LedgerArchiveScreen(
          reportGateway: reports,
          dateGateway: dates,
          financialGateway: money,
          userId: userId,
          shopId: widget.shop.id,
          canRead: () => mounted && widget.userId == userId,
          syncTicks: widget.syncTicks,
          initialDate: date,
          canSendInvoice: _access.sendInvoice,
        ),
      ),
    );
  }

  void _openPendingInvoices() {
    final gateway = _financialGateway;
    final userId = widget.userId;
    if (gateway is! InvoiceDispatchGateway || userId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PendingInvoiceSendsScreen(
          gateway: gateway as FinancialGateway,
          userId: userId,
          syncTicks: widget.syncTicks,
          canChangeOperation: widget.shop.isOwner,
        ),
      ),
    );
  }

  Future<void> _openDay() async {
    final gateway = _financialGateway;
    final userId = widget.userId;
    if (gateway == null ||
        userId == null ||
        _dayCommandBusy ||
        _financialPending != null) {
      return;
    }
    final confirmed = await showAppConfirm(
      context,
      title: 'فتح يوم عمل جديد؟',
      message:
          'ستبدأ العمليات التالية في يوم عمل جديد. سيظهر تاريخه بعد تأكيد الفتح.',
      confirmLabel: 'فتح اليوم',
    );
    if (!confirmed || !mounted) return;
    setState(() => _dayCommandBusy = true);
    try {
      final key = newIdempotencyKey();
      final pending = PendingFinancialCommand(
        key: key,
        kind: 'open_day',
        body: {'p_idempotency_key': key},
      );
      await _financialPendingStore.save(userId, widget.shop.id, pending);
      final result = await gateway.openDay(
        callerUserId: userId,
        idempotencyKey: key,
      );
      if (!mounted) return;
      if (result is FinancialCommitted) {
        await _financialPendingStore.clear(userId, widget.shop.id, key);
        if (!mounted) return;
        _dropItemCache();
        await _controller?.refresh();
        await _maybeLoadFinancialDay(force: true);
      } else if (result is FinancialRejected) {
        await _financialPendingStore.clear(userId, widget.shop.id, key);
        if (!mounted) return;
        setState(
          () =>
              _financialError = 'تعذر فتح اليوم. تحقق من حالة اليوم والاشتراك.',
        );
      } else {
        setState(() => _financialPending = pending);
        setState(
          () => _financialError =
              'تعذر تأكيد فتح اليوم. حدّث الدفتر للتحقق من حالته.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _financialError =
              'تعذر حفظ طلب فتح اليوم أو تأكيده. تحقق من الحالة.',
        );
      }
    } finally {
      if (mounted) setState(() => _dayCommandBusy = false);
    }
  }

  @override
  void didUpdateWidget(covariant DailyLedgerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncTicks != widget.syncTicks) {
      oldWidget.syncTicks?.removeListener(_onSyncTicks);
      widget.syncTicks?.addListener(_onSyncTicks);
    }
    final identityChanged =
        oldWidget.userId != widget.userId ||
        oldWidget.shop.id != widget.shop.id ||
        oldWidget.gateway != widget.gateway ||
        oldWidget.store != widget.store;
    if (identityChanged) {
      _midnightTimer?.cancel();
      _scheduledJournal = null;
      _formInvalidations.value++;
      _financialDay = null;
      _financialPending = null;
      _financialError = null;
      _activity.reset();
      _caughtUp = false;
      _controller?.removeListener(_onController);
      _controller?.dispose();
      _controller = null;
      _attach();
      return;
    }
    _controller?.updateShopActive(
      widget.shop.entitlement == ShopEntitlement.active,
    );
    if (widget.syncTicks == null &&
        oldWidget.refreshGeneration != widget.refreshGeneration) {
      _dropItemCache();
      _controller?.refresh();
      _maybeLoadFinancialDay(force: true);
    }
  }

  void _onSyncTicks() {
    if (mounted) unawaited(_sync());
  }

  @override
  void dispose() {
    widget.syncTicks?.removeListener(_onSyncTicks);
    _syncTimer?.cancel();
    _midnightTimer?.cancel();
    _formInvalidations.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onController);
    _controller?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
    final compact = MediaQuery.sizeOf(context).width < 400;
    final businessDay =
        controller?.ledger?.journalContext?.businessDate ??
        controller?.ledger?.businessDay?.businessDate;
    // U17: a closed day is not the work day any more; say so.
    final daySubtitle = businessDay == null
        ? null
        : _financialDay?.isClosed == true
        ? 'لا يوجد يوم مفتوح · آخر يوم مقفول ${formatServerDate(businessDay)}'
        : 'يوم العمل ${formatServerDate(businessDay)}';
    return Scaffold(
      appBar: LedgerAppBar(
        textScaler: MediaQuery.textScalerOf(context),
        shopName: widget.shop.name,
        shopImageBytes: widget.shopImageBytes,
        subtitle: daySubtitle,
        topInset: MediaQuery.paddingOf(context).top,
        compact: compact,
        collapsed: _headerCollapsed,
        onChangeShop: widget.onChangeShop,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTokens.contentMaxWidth,
          ),
          child: ListView(
            key: const Key('ledger-scroll'),
            controller: _scroll,
            padding: EdgeInsetsDirectional.fromSTEB(
              MediaQuery.sizeOf(context).width < AppTokens.wideBreakpoint
                  ? AppTokens.ledgerPhoneGutter
                  : AppTokens.spaceLg,
              compact ? 16 : 20,
              MediaQuery.sizeOf(context).width < AppTokens.wideBreakpoint
                  ? AppTokens.ledgerPhoneGutter
                  : AppTokens.spaceLg,
              compact ? 28 : 36,
            ),
            children: [
              if (_expired || (controller?.readOnly ?? false)) ...[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer.withValues(
                      alpha: 0.55,
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: theme.colorScheme.error.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'منتهي - للقراءة فقط',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text('الاشتراك منتهٍ. العرض للقراءة فقط.'),
                        const SizedBox(height: 4),
                        const Text(
                          'انتهى اشتراك هذا المتجر. الوصول الحالي للقراءة فقط، ولا يمكن إجراء تغييرات.',
                        ),
                        if (widget.onActivateSubscription != null) ...[
                          const SizedBox(height: 12),
                          FilledButton(
                            key: const Key('subscription-open'),
                            onPressed: widget.onActivateSubscription,
                            child: const Text('تفعيل الاشتراك'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              if (controller == null)
                const SizedBox.shrink()
              else if (controller.phase == LedgerPhase.loading)
                const LinearProgressIndicator(key: Key('ledger-loading'))
              else ...[
                if (_financialError != null)
                  Text(
                    _financialError!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                if (_financialPending != null) ...[
                  const SizedBox(height: 8),
                  Card(
                    color: theme.colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            _financialPending!.kind == invoiceMessageKind
                                ? 'طلب نص رسالة بانتظار التأكيد'
                                : _financialPending!.kind ==
                                      invoiceAppearanceKind
                                ? 'طلب مظهر فاتورة بانتظار التأكيد'
                                : _financialPending!.kind ==
                                      invoicePresentationKind
                                ? 'طلب نسخة عرض بانتظار التأكيد'
                                : repairRpcs.containsKey(
                                    _financialPending!.kind,
                                  )
                                ? 'طلب مرمة بانتظار تأكيد الحفظ'
                                : (debtRpcs.containsKey(
                                        _financialPending!.kind,
                                      ) ||
                                      (_financialPending!.kind == debtDueKind ||
                                          _financialPending!.kind ==
                                              debtNativeKind))
                                ? 'طلب ديون بانتظار تأكيد الحفظ'
                                : customerRpcs.containsKey(
                                    _financialPending!.kind,
                                  )
                                ? 'طلب عميل بانتظار تأكيد الحفظ'
                                : 'عملية مالية بانتظار تأكيد الحفظ',
                          ),
                          Text(
                            _pendingStatusUnknown
                                ? 'تعذر تحديد حالتها بعد. تحقق قبل تسجيل عملية أخرى.'
                                : 'لم نتأكد من حفظها بعد. أعد المحاولة دون تغيير البيانات.',
                          ),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton.icon(
                              key: const Key('ledger-retry-pending'),
                              onPressed: _dayCommandBusy
                                  ? null
                                  : () => _resolveFinancialPending(retry: true),
                              icon: const Icon(Icons.sync),
                              label: Text(
                                _financialPending!.kind == invoiceMessageKind
                                    ? 'متابعة طلب نص الرسالة'
                                    : _financialPending!.kind ==
                                          invoiceAppearanceKind
                                    ? 'متابعة مظهر الفاتورة'
                                    : _financialPending!.kind ==
                                          invoicePresentationKind
                                    ? 'متابعة طلب النسخة'
                                    : repairRpcs.containsKey(
                                        _financialPending!.kind,
                                      )
                                    ? 'متابعة طلب المرمة'
                                    : (debtRpcs.containsKey(
                                            _financialPending!.kind,
                                          ) ||
                                          (_financialPending!.kind ==
                                                  debtDueKind ||
                                              _financialPending!.kind ==
                                                  debtNativeKind))
                                    ? 'متابعة طلب النوتة'
                                    : customerRpcs.containsKey(
                                        _financialPending!.kind,
                                      )
                                    ? 'متابعة طلب العميل'
                                    : 'التحقق وإعادة المحاولة',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                _LedgerBody(
                  controller: controller,
                  expired: _expired,
                  day: _financialDay,
                  dayBusy: _dayCommandBusy,
                  canReturn:
                      _financialGateway is LinkedReturnGateway &&
                      _financialDay?.isOpen == true &&
                      !_expired &&
                      !controller.readOnly &&
                      _financialPending == null,
                  // U16: no sale or purchase entry while no day is open.
                  // ADR 0033: each control follows the member's grants; the
                  // server enforces them as well.
                  onSale: _financialDay?.isClosed == true || !_access.sale
                      ? null
                      : () => _requestTrade(FinancialKind.sale),
                  onPurchase:
                      _financialDay?.isClosed == true || !_access.purchase
                      ? null
                      : () => _requestTrade(FinancialKind.purchase),
                  onAddReturn:
                      _financialGateway is CustomerReturnGateway &&
                          _access.customerReturn &&
                          _financialDay?.isOpen == true &&
                          !_expired &&
                          !controller.readOnly &&
                          _financialPending == null
                      ? () => _startTrade(FinancialKind.customerReturn)
                      : null,
                  onExpense:
                      _access.expense &&
                          _financialDay?.isOpen == true &&
                          !_expired &&
                          !controller.readOnly &&
                          _financialPending == null
                      ? () => _startTrade(FinancialKind.expense)
                      : null,
                  onCashTransfer:
                      _access.cashTransfer &&
                          _financialDay?.isOpen == true &&
                          !_expired &&
                          !controller.readOnly &&
                          _financialPending == null &&
                          _financialGateway is CashTransferGateway
                      ? _transferCash
                      : null,
                  onScrapSale:
                      _access.scrapSale &&
                          _financialDay?.isOpen == true &&
                          !_expired &&
                          !controller.readOnly &&
                          _financialPending == null
                      ? () => _startTrade(FinancialKind.scrapSale)
                      : null,
                  onScrapToStock:
                      _access.scrapToStock &&
                          _financialDay?.isOpen == true &&
                          !_expired &&
                          !controller.readOnly &&
                          _financialPending == null &&
                          _financialGateway is ScrapToStockGateway &&
                          (controller.ledger?.scrap.any(
                                (line) => _positiveWireAmount(line.milligrams),
                              ) ??
                              false)
                      ? _convertScrapToStock
                      : null,
                  onCloseDay:
                      _access.closeDay &&
                          _financialDay?.isOpen == true &&
                          !_expired &&
                          !controller.readOnly &&
                          _financialPending == null
                      ? _closeDay
                      : null,
                  onOpenDay:
                      _access.openDay &&
                          _financialDay?.isClosed == true &&
                          !_expired &&
                          !controller.readOnly &&
                          _financialPending == null
                      ? _openDay
                      : null,
                  onOpenArchive: _access.archive ? _openArchive : null,
                  onOperation: _financialGateway == null
                      ? null
                      : _openOperation,
                  onPendingInvoices:
                      _access.pendingInvoices &&
                          _financialGateway is InvoiceDispatchGateway
                      ? _openPendingInvoices
                      : null,
                  onDailyNotes:
                      _access.dailyNotes &&
                          _notesGateway != null &&
                          widget.userId != null
                      ? _openDailyNotes
                      : null,
                  hideShopBalances: _access.hidesShopBalances,
                  canEnterOpening: _access.openDay,
                  onLoadOlder:
                      _feedGateway != null &&
                          (_activity.state.hasOlder || _loadingOlder)
                      ? _loadOlder
                      : null,
                  loadingOlder: _loadingOlder,
                  activityLines:
                      _feedGateway == null || _activity.state.userId.isEmpty
                      ? null
                      : _activity.state.lines,
                  loadItems: _itemsLoader ??= _loadOperationItems,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LedgerBody extends StatelessWidget {
  const _LedgerBody({
    required this.controller,
    required this.expired,
    required this.day,
    required this.dayBusy,
    this.canReturn = false,
    this.onSale,
    this.onPurchase,
    this.onExpense,
    this.onCashTransfer,
    this.onScrapSale,
    this.onScrapToStock,
    this.onCloseDay,
    this.onOpenDay,
    this.onOpenArchive,
    this.onOperation,
    this.onPendingInvoices,
    this.onDailyNotes,
    this.onAddReturn,
    this.onLoadOlder,
    this.loadingOlder = false,
    this.activityLines,
    this.loadItems,
    this.hideShopBalances = false,
    this.canEnterOpening = true,
  });

  final DailyLedgerController controller;
  final bool hideShopBalances;

  /// Only the owner opens the shop's ledger; staff wait for them.
  final bool canEnterOpening;
  final bool expired;
  final FinancialDayState? day;
  final bool dayBusy;
  final bool canReturn;
  final VoidCallback? onSale;
  final VoidCallback? onPurchase;
  final VoidCallback? onExpense;
  final VoidCallback? onCashTransfer;
  final VoidCallback? onScrapSale;
  final VoidCallback? onScrapToStock;
  final VoidCallback? onCloseDay;
  final VoidCallback? onOpenDay;
  final ValueChanged<String>? onOpenArchive;
  final ValueChanged<LedgerFeedLine>? onOperation;
  final VoidCallback? onPendingInvoices;
  final VoidCallback? onDailyNotes;
  final VoidCallback? onAddReturn;
  final VoidCallback? onLoadOlder;
  final bool loadingOlder;
  final List<LedgerFeedLine>? activityLines;
  final Future<List<LedgerLineItem>?> Function(String operationId)? loadItems;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = controller.message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message != null) ...[
          Text(
            message,
            key: const Key('ledger-message'),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 12),
        ],
        switch (controller.phase) {
          LedgerPhase.notOpened =>
            canEnterOpening
                ? _NotOpenedNotice(
                    onRetry: controller.canRetryOpen
                        ? controller.retryOpen
                        : null,
                  )
                : const Text(
                    'لم يفتح صاحب المحل الدفتر بعد.',
                    key: Key('ledger-opening-owner-only'),
                  ),
          LedgerPhase.pending => _PendingNotice(onRetry: controller.refresh),
          LedgerPhase.confirmed => ConfirmedLedgerDashboard(
            ledger: controller.ledger,
            shopId: controller.shopId,
            dayClosed: day?.isClosed == true,
            canReturn: canReturn,
            onSale: onSale,
            onPurchase: onPurchase,
            onExpense: onExpense,
            onCashTransfer: onCashTransfer,
            onScrapSale: onScrapSale,
            onScrapToStock: onScrapToStock,
            onCloseDay: onCloseDay,
            onOpenDay: dayBusy ? null : onOpenDay,
            onOpenArchive: onOpenArchive,
            onOperation: onOperation,
            onPendingInvoices: onPendingInvoices,
            onDailyNotes: onDailyNotes,
            onAddReturn: onAddReturn,
            onLoadOlder: onLoadOlder,
            loadingOlder: loadingOlder,
            activityLines: activityLines,
            loadItems: loadItems,
            hideShopBalances: hideShopBalances,
            ownerControls: canEnterOpening,
          ),
          LedgerPhase.refreshFailed => _RefreshFailedNotice(
            onRetry: controller.refresh,
          ),
          LedgerPhase.accessDenied => const SizedBox.shrink(),
          LedgerPhase.expiredEmpty => const Text(
            'لم يُفتح دفتر هذا المحل بعد.',
            key: Key('ledger-not-opened'),
          ),
          LedgerPhase.failed => const SizedBox.shrink(),
          LedgerPhase.loading => const SizedBox.shrink(),
        },
      ],
    );
  }
}

/// The owner's ledger did not open on the first try. There is no form to
/// fill: the only action is to try again.
class _NotOpenedNotice extends StatelessWidget {
  const _NotOpenedNotice({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return AppBanner(
      tone: MessageTone.warning,
      title: 'تعذر فتح الدفتر',
      titleKey: const Key('ledger-open-failed'),
      message: 'تحقق من الاتصال ثم أعد المحاولة.',
      actionLabel: 'إعادة المحاولة',
      actionKey: const Key('ledger-open-retry'),
      onAction: onRetry,
    );
  }
}

class _PendingNotice extends StatelessWidget {
  const _PendingNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppBanner(
      tone: MessageTone.pending,
      title: 'جارٍ فتح الدفتر',
      titleKey: const Key('opening-pending'),
      message: 'بانتظار تأكيد الخادم.',
      actionLabel: 'إعادة المحاولة',
      actionKey: const Key('opening-pending-retry'),
      onAction: onRetry,
    );
  }
}

class _RefreshFailedNotice extends StatelessWidget {
  const _RefreshFailedNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppBanner(
      tone: MessageTone.warning,
      title: 'تم فتح الدفتر',
      message: 'تعذر تحديث الدفتر. أعد المحاولة.',
      actionLabel: 'إعادة المحاولة',
      actionKey: const Key('opening-refresh-retry'),
      onAction: onRetry,
    );
  }
}
