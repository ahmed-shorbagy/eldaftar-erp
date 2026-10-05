import 'dart:async';

import 'package:flutter/material.dart';

import '../../../shell/shell_copy.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/brand_mark.dart';
import '../../shop_accounts/domain/shop_account.dart';
import '../../onboarding/application/onboarding_store.dart';
import '../../daily_notes/application/notes_gateway.dart';
import '../../daily_notes/data/note_image_file_store.dart';
import '../../daily_notes/data/platform_note_image_source.dart';
import '../../daily_notes/data/secure_note_draft_store.dart';
import '../../daily_notes/presentation/daily_notes_screen.dart';
import '../application/opening_gateway.dart';
import '../application/daily_ledger_view.dart';
import '../application/financial_gateway.dart';
import '../application/ledger_activity.dart';
import '../application/idempotency_key.dart';
import '../application/pending_opening_store.dart';
import '../application/pending_financial_command.dart';
import '../data/pending_financial_command.dart';
import '../domain/opening_catalog.dart';
import '../domain/financial_draft.dart';
import '../domain/opening_draft.dart';
import '../domain/opening_issue.dart';
import '../domain/postgres_integer.dart';
import '../domain/quantities.dart';
import 'daily_ledger_controller.dart';
import 'confirmed_ledger_dashboard.dart';
import 'financial_trade_screen.dart';
import 'financial_operation_screen.dart';
import 'pending_invoice_sends_screen.dart';
import 'daily_close_screen.dart';
import 'cash_transfer_screen.dart';
import 'scrap_to_stock_screen.dart';
import 'ledger_form_fields.dart';
import 'opening_copy.dart';

class DailyLedgerScreen extends StatefulWidget {
  const DailyLedgerScreen({
    super.key,
    required this.shop,
    required this.onSignOut,
    required this.onToggleTheme,
    this.onChangeShop,
    this.onRefreshShops,
    this.gateway,
    this.store,
    this.userId,
    this.refreshGeneration = 0,
    this.newKey,
    this.onboardingStore,
    this.guideResumeGeneration = 0,
  });

  final ShopAccount shop;
  final Future<void> Function() onSignOut;
  final Future<void> Function(Brightness) onToggleTheme;
  final VoidCallback? onChangeShop;
  final Future<void> Function()? onRefreshShops;
  final OpeningGateway? gateway;
  final PendingOpeningStore? store;
  final String? userId;
  final int refreshGeneration;
  final String Function()? newKey;
  final OnboardingStore? onboardingStore;
  final int guideResumeGeneration;

  @override
  State<DailyLedgerScreen> createState() => _DailyLedgerScreenState();
}

bool _positiveWireAmount(String value) {
  final parsed = Milligrams.parseWire(value);
  return parsed is Accepted<Milligrams> && parsed.value.value > BigInt.zero;
}

class _DailyLedgerScreenState extends State<DailyLedgerScreen>
    with WidgetsBindingObserver {
  DailyLedgerController? _controller;
  final _scroll = ScrollController();
  final _refreshFocus = FocusNode();
  FinancialDayState? _financialDay;
  String? _financialError;
  bool _financialLoading = false;
  bool _dayCommandBusy = false;
  final _financialPendingStore = const PendingFinancialCommands();
  PendingFinancialCommand? _financialPending;
  bool _pendingStatusUnknown = false;
  Timer? _syncTimer;
  bool _syncing = false;
  bool _loadingOlder = false;
  bool _caughtUp = false;
  final _activity = LedgerActivityController();

  FinancialGateway? get _financialGateway => widget.gateway is FinancialGateway
      ? widget.gateway! as FinancialGateway
      : null;

  NotesGateway? get _notesGateway =>
      widget.gateway is NotesGateway ? widget.gateway! as NotesGateway : null;

  LedgerFeedGateway? get _feedGateway => widget.gateway is LedgerFeedGateway
      ? widget.gateway! as LedgerFeedGateway
      : null;

  bool get _expired => widget.shop.entitlement == ShopEntitlement.expired;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncTimer = Timer.periodic(const Duration(minutes: 1), (_) => _sync());
    _attach();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  Future<void> _sync() async {
    if (!mounted ||
        _syncing ||
        _dayCommandBusy ||
        ModalRoute.of(context)?.isCurrent != true ||
        _controller?.phase != LedgerPhase.confirmed) {
      return;
    }
    _syncing = true;
    try {
      await _controller?.refresh();
      if (mounted) {
        await _catchUpFeed();
        await _maybeLoadFinancialDay(force: true);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _financialError =
              'تعذرت مزامنة الدفتر. استخدم زر التحديث للتحقق من الأرصدة.',
        );
      }
    } finally {
      _syncing = false;
    }
  }

  void _refreshLedger() {
    (widget.onRefreshShops ?? _controller?.refresh)?.call();
    _maybeLoadFinancialDay(force: true);
    _catchUpFeed();
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
      newKey: widget.newKey,
    );
    controller.addListener(_onController);
    _controller = controller;
    controller.start();
  }

  void _onController() {
    if (!mounted) return;
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
    if (added > 0) await _controller?.refresh();
    if (mounted) setState(() {});
  }

  Future<void> _loadOlder() async {
    final gateway = _feedGateway;
    final userId = widget.userId;
    if (gateway == null || userId == null || _loadingOlder) return;
    setState(() => _loadingOlder = true);
    try {
      await _activity.loadOlder(gateway: gateway, userId: userId);
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
          canWrite: canWrite,
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
      if (pending != null) {
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
            _financialError =
                'رفض الخادم إعادة المحاولة: ${result.code}. حدّث الدفتر قبل طلب جديد.';
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
                'تغير العد على الخادم. حدّث الدفتر وأعد المراجعة.';
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
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FinancialTradeScreen(
          kind: kind,
          gateway: gateway,
          statusGateway: widget.gateway!,
          userId: userId,
          shopId: widget.shop.id,
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حفظ العملية بنجاح')));
    }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حفظ العملية بنجاح')));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حفظ العملية بنجاح')));
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
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ScrapToStockScreen(
          gateway: scrapGateway,
          statusGateway: widget.gateway!,
          userId: userId,
          shopId: widget.shop.id,
          scrap: scrap,
        ),
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم حفظ العملية بنجاح')));
      await _controller?.refresh();
      await _maybeLoadFinancialDay(force: true);
    }
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
          line: line,
        ),
      ),
    );
    if (!mounted) return;
    await _controller?.refresh();
    await _maybeLoadFinancialDay(force: true);
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('فتح يوم عمل جديد'),
        content: const Text(
          'ستبدأ العمليات التالية في يوم عمل جديد. يحدد الخادم تاريخ الفتح.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('فتح اليوم'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
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
        await _controller?.refresh();
        await _maybeLoadFinancialDay(force: true);
      } else if (result is FinancialRejected) {
        await _financialPendingStore.clear(userId, widget.shop.id, key);
        if (!mounted) return;
        setState(
          () => _financialError =
              'رفض الخادم فتح اليوم. تحقق من حالة اليوم والاشتراك.',
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
    final identityChanged =
        oldWidget.userId != widget.userId ||
        oldWidget.shop.id != widget.shop.id ||
        oldWidget.gateway != widget.gateway ||
        oldWidget.store != widget.store;
    if (identityChanged) {
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
    if (oldWidget.refreshGeneration != widget.refreshGeneration) {
      _controller?.refresh();
      _maybeLoadFinancialDay(force: true);
    }
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller?.removeListener(_onController);
    _controller?.dispose();
    _scroll.dispose();
    _refreshFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = _controller;
    final compact = MediaQuery.sizeOf(context).width < 400;
    return Scaffold(
      appBar: AppBar(
        title: BrandLockup(
          title: 'الدفتر اليومي',
          titleKey: const Key('ledger-title'),
          markSize: 22,
          maxLines: 2,
          style: compact ? theme.textTheme.titleMedium : null,
        ),
        actions: [
          IconButton(
            tooltip: 'تحديث الدفتر',
            focusNode: _refreshFocus,
            onPressed: _refreshLedger,
            icon: const Icon(Icons.refresh),
          ),
          if (compact)
            PopupMenuButton<String>(
              tooltip: 'المزيد',
              onSelected: (value) {
                switch (value) {
                  case 'shop':
                    widget.onChangeShop?.call();
                  case 'theme':
                    widget.onToggleTheme(theme.brightness);
                  case 'signout':
                    widget.onSignOut();
                }
              },
              itemBuilder: (context) => [
                if (widget.onChangeShop != null)
                  const PopupMenuItem(
                    value: 'shop',
                    child: Text('اختيار متجر آخر'),
                  ),
                PopupMenuItem(
                  value: 'theme',
                  child: Text(
                    theme.brightness == Brightness.dark
                        ? ShellCopy.toggleToLight
                        : ShellCopy.toggleToDark,
                  ),
                ),
                const PopupMenuItem(
                  value: 'signout',
                  child: Text('تسجيل الخروج'),
                ),
              ],
            )
          else ...[
            if (widget.onChangeShop != null)
              IconButton(
                tooltip: 'اختيار متجر آخر',
                onPressed: widget.onChangeShop,
                icon: const Icon(Icons.storefront_outlined),
              ),
            IconButton(
              key: const Key('theme-toggle'),
              tooltip: theme.brightness == Brightness.dark
                  ? ShellCopy.toggleToLight
                  : ShellCopy.toggleToDark,
              onPressed: () => widget.onToggleTheme(theme.brightness),
              icon: Icon(
                theme.brightness == Brightness.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
              ),
            ),
            IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout),
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTokens.contentMaxWidth,
            ),
            child: ListView(
              key: const Key('ledger-scroll'),
              controller: _scroll,
              padding: EdgeInsetsDirectional.fromSTEB(
                compact ? 16 : 24,
                compact ? 12 : 20,
                compact ? 16 : 24,
                compact ? 28 : 36,
              ),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        widget.shop.name,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (_expired || (controller?.readOnly ?? false)) ...[
                  const SizedBox(height: 12),
                  Text(
                    'منتهي - للقراءة فقط',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('الاشتراك منتهٍ. العرض للقراءة فقط.'),
                  const SizedBox(height: 8),
                  const Text(
                    'انتهى اشتراك هذا المتجر. الوصول الحالي للقراءة فقط، ولا يمكن إجراء تغييرات.',
                  ),
                ],
                const SizedBox(height: 20),
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
                            const Text('عملية مالية بانتظار تأكيد الخادم'),
                            Text(
                              _pendingStatusUnknown
                                  ? 'تعذر تحديد حالتها بعد. تحقق قبل تسجيل عملية أخرى.'
                                  : 'لم تظهر بعد على الخادم. أعد المحاولة بالمفتاح نفسه.',
                            ),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: TextButton.icon(
                                key: const Key('ledger-retry-pending'),
                                onPressed: _dayCommandBusy
                                    ? null
                                    : () =>
                                          _resolveFinancialPending(retry: true),
                                icon: const Icon(Icons.sync),
                                label: const Text('التحقق وإعادة المحاولة'),
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
                    onSale:
                        _financialDay?.isOpen == true &&
                            !_expired &&
                            !controller.readOnly &&
                            _financialPending == null
                        ? () => _startTrade(FinancialKind.sale)
                        : null,
                    onPurchase:
                        _financialDay?.isOpen == true &&
                            !_expired &&
                            !controller.readOnly &&
                            _financialPending == null
                        ? () => _startTrade(FinancialKind.purchase)
                        : null,
                    onExpense:
                        _financialDay?.isOpen == true &&
                            !_expired &&
                            !controller.readOnly &&
                            _financialPending == null
                        ? () => _startTrade(FinancialKind.expense)
                        : null,
                    onCashTransfer:
                        _financialDay?.isOpen == true &&
                            !_expired &&
                            !controller.readOnly &&
                            _financialPending == null &&
                            _financialGateway is CashTransferGateway
                        ? _transferCash
                        : null,
                    onScrapSale:
                        _financialDay?.isOpen == true &&
                            !_expired &&
                            !controller.readOnly &&
                            _financialPending == null
                        ? () => _startTrade(FinancialKind.scrapSale)
                        : null,
                    onScrapToStock:
                        _financialDay?.isOpen == true &&
                            !_expired &&
                            !controller.readOnly &&
                            _financialPending == null &&
                            _financialGateway is ScrapToStockGateway &&
                            (controller.ledger?.scrap.any(
                                  (line) =>
                                      _positiveWireAmount(line.milligrams),
                                ) ??
                                false)
                        ? _convertScrapToStock
                        : null,
                    onCloseDay:
                        _financialDay?.isOpen == true &&
                            !_expired &&
                            !controller.readOnly &&
                            _financialPending == null
                        ? _closeDay
                        : null,
                    onOpenDay:
                        _financialDay?.isClosed == true &&
                            !_expired &&
                            !controller.readOnly &&
                            _financialPending == null
                        ? _openDay
                        : null,
                    onOperation: _financialGateway == null
                        ? null
                        : _openOperation,
                    onPendingInvoices:
                        _financialGateway is InvoiceDispatchGateway
                        ? _openPendingInvoices
                        : null,
                    onDailyNotes: _notesGateway != null && widget.userId != null
                        ? _openDailyNotes
                        : null,
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
                  ),
                ],
              ],
            ),
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
    this.onSale,
    this.onPurchase,
    this.onExpense,
    this.onCashTransfer,
    this.onScrapSale,
    this.onScrapToStock,
    this.onCloseDay,
    this.onOpenDay,
    this.onOperation,
    this.onPendingInvoices,
    this.onDailyNotes,
    this.onLoadOlder,
    this.loadingOlder = false,
    this.activityLines,
  });

  final DailyLedgerController controller;
  final bool expired;
  final FinancialDayState? day;
  final bool dayBusy;
  final VoidCallback? onSale;
  final VoidCallback? onPurchase;
  final VoidCallback? onExpense;
  final VoidCallback? onCashTransfer;
  final VoidCallback? onScrapSale;
  final VoidCallback? onScrapToStock;
  final VoidCallback? onCloseDay;
  final VoidCallback? onOpenDay;
  final ValueChanged<LedgerFeedLine>? onOperation;
  final VoidCallback? onPendingInvoices;
  final VoidCallback? onDailyNotes;
  final VoidCallback? onLoadOlder;
  final bool loadingOlder;
  final List<LedgerFeedLine>? activityLines;

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
          LedgerPhase.form =>
            controller.readOnly
                ? const Text('لا يوجد رصيد افتتاحي مؤكد لهذا المتجر.')
                : _EntryForm(controller: controller),
          LedgerPhase.review => _Review(
            controller: controller,
            showActions: !controller.readOnly,
          ),
          LedgerPhase.pending => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _PendingNotice(),
              if (controller.reviewDraft != null) ...[
                const SizedBox(height: 12),
                _Review(controller: controller, showActions: false),
              ],
            ],
          ),
          LedgerPhase.confirmed => ConfirmedLedgerDashboard(
            ledger: controller.ledger,
            shopId: controller.shopId,
            dayClosed: day?.isClosed == true,
            onSale: onSale,
            onPurchase: onPurchase,
            onExpense: onExpense,
            onCashTransfer: onCashTransfer,
            onScrapSale: onScrapSale,
            onScrapToStock: onScrapToStock,
            onCloseDay: onCloseDay,
            onOpenDay: dayBusy ? null : onOpenDay,
            onOperation: onOperation,
            onPendingInvoices: onPendingInvoices,
            onDailyNotes: onDailyNotes,
            onLoadOlder: onLoadOlder,
            loadingOlder: loadingOlder,
            activityLines: activityLines,
          ),
          LedgerPhase.refreshFailed => const _RefreshFailedNotice(),
          LedgerPhase.accessDenied => const SizedBox.shrink(),
          LedgerPhase.expiredEmpty => const Text(
            'لا يوجد رصيد افتتاحي مؤكد لهذا المتجر.',
          ),
          LedgerPhase.failed => const SizedBox.shrink(),
          LedgerPhase.loading => const SizedBox.shrink(),
        },
      ],
    );
  }
}

class _EntryForm extends StatelessWidget {
  const _EntryForm({required this.controller});

  final DailyLedgerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('إعداد الأرصدة الافتتاحية', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'أدخل النقد والذهب، ثم راجع الأثر قبل التأكيد على الخادم.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 20),
        _EntrySection(
          icon: Icons.account_balance_wallet_outlined,
          title: 'النقدية',
          description: 'الرصيد الحالي لكل وسيلة دفع بالجنيه',
          child: Column(
            children: [
              for (final method in CashMethod.canonicalOrder) ...[
                _AmountField(
                  label: cashMethodLabel(method),
                  controller: controller.cash[method]!,
                  fieldKey: Key('cash-${method.code}'),
                  locked: controller.fieldsLocked,
                ),
                if (method != CashMethod.canonicalOrder.last)
                  const SizedBox(height: 16),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _EntrySection(
          icon: Icons.scale_outlined,
          title: 'المخزون',
          description: 'حدد الصنف والعيار والعدد والوزن بدقة ثلاثة منازل',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < controller.stock.length; index++) ...[
                _StockRow(
                  entry: controller.stock[index],
                  index: index,
                  controller: controller,
                ),
                const SizedBox(height: 16),
              ],
              OutlinedButton.icon(
                key: const Key('add-stock'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: controller.fieldsLocked ? null : controller.addStock,
                icon: const Icon(Icons.add),
                label: const Text('إضافة صنف'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _EntrySection(
          icon: Icons.inventory_2_outlined,
          title: 'الكسر',
          description: 'سجل الوزن لكل عيار على حدة',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var index = 0; index < controller.scrap.length; index++) ...[
                _ScrapRow(
                  entry: controller.scrap[index],
                  index: index,
                  controller: controller,
                ),
                const SizedBox(height: 16),
              ],
              OutlinedButton.icon(
                key: const Key('add-scrap'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: controller.fieldsLocked ? null : controller.addScrap,
                icon: const Icon(Icons.add),
                label: const Text('إضافة كسر'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('review-values'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: controller.fieldsLocked ? null : controller.reviewEntered,
          child: const Text('مراجعة الأرصدة'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('review-zero'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: controller.fieldsLocked ? null : controller.reviewZeros,
          child: const Text('تأكيد أرصدة صفرية'),
        ),
      ],
    );
  }
}

class _EntrySection extends StatelessWidget {
  const _EntrySection({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.label,
    required this.controller,
    required this.fieldKey,
    required this.locked,
  });

  final String label;
  final TextEditingController controller;
  final Key fieldKey;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: fieldKey,
      controller: controller,
      readOnly: locked,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textDirection: TextDirection.ltr,
      decoration: ledgerFieldDecoration(
        context,
        label: label,
        helper: 'بالجنيه',
      ),
    );
  }
}

class _StockRow extends StatelessWidget {
  const _StockRow({
    required this.entry,
    required this.index,
    required this.controller,
  });

  final StockEntry entry;
  final int index;
  final DailyLedgerController controller;

  @override
  Widget build(BuildContext context) {
    final karats = entry.category.karats.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        LedgerFieldPair(
          first: DropdownButtonFormField<StockCategory>(
            key: Key('stock-category-$index'),
            initialValue: entry.category,
            isExpanded: true,
            decoration: ledgerFieldDecoration(context, label: 'الصنف'),
            items: [
              for (final category in openingCategoryChoices)
                DropdownMenuItem(
                  value: category,
                  child: Text(stockCategoryLabel(category)),
                ),
            ],
            onChanged: controller.fieldsLocked
                ? null
                : (value) {
                    if (value != null) {
                      controller.setStockCategory(entry, value);
                    }
                  },
          ),
          second: DropdownButtonFormField<int>(
            key: ValueKey(
              'stock-karat-$index-${entry.category.code}-${entry.karat}',
            ),
            initialValue: entry.karat,
            isExpanded: true,
            decoration: ledgerFieldDecoration(context, label: 'العيار'),
            items: [
              for (final karat in karats)
                DropdownMenuItem(value: karat, child: Text('$karat')),
            ],
            onChanged: controller.fieldsLocked
                ? null
                : (value) {
                    if (value != null) controller.setStockKarat(entry, value);
                  },
          ),
        ),
        const SizedBox(height: 12),
        LedgerFieldPair(
          first: TextField(
            key: Key('stock-grams-$index'),
            controller: entry.grams,
            readOnly: controller.fieldsLocked,
            textDirection: TextDirection.ltr,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: ledgerFieldDecoration(
              context,
              label: 'الوزن بالجرام',
              helper: 'حتى ثلاث منازل',
            ),
          ),
          second: TextField(
            key: Key('stock-count-$index'),
            controller: entry.count,
            readOnly: controller.fieldsLocked,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.number,
            decoration: ledgerFieldDecoration(context, label: 'العدد'),
          ),
        ),
        if (controller.stock.length > 1)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: controller.fieldsLocked
                  ? null
                  : () => controller.removeStock(entry),
              child: const Text('حذف الصف'),
            ),
          ),
      ],
    );
  }
}

class _ScrapRow extends StatelessWidget {
  const _ScrapRow({
    required this.entry,
    required this.index,
    required this.controller,
  });

  final ScrapEntry entry;
  final int index;
  final DailyLedgerController controller;

  @override
  Widget build(BuildContext context) {
    return LedgerFieldPair(
      first: DropdownButtonFormField<int>(
        key: Key('scrap-karat-$index'),
        initialValue: entry.karat,
        isExpanded: true,
        decoration: ledgerFieldDecoration(context, label: 'عيار الكسر'),
        items: [
          for (final karat in scrapKaratChoices)
            DropdownMenuItem(value: karat, child: Text('$karat')),
        ],
        onChanged: controller.fieldsLocked
            ? null
            : (value) {
                if (value != null) controller.setScrapKarat(entry, value);
              },
      ),
      second: TextField(
        key: Key('scrap-grams-$index'),
        controller: entry.grams,
        readOnly: controller.fieldsLocked,
        textDirection: TextDirection.ltr,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: ledgerFieldDecoration(
          context,
          label: 'وزن الكسر بالجرام',
          helper: 'حتى ثلاث منازل',
        ),
      ),
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({required this.controller, required this.showActions});

  final DailyLedgerController controller;
  final bool showActions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final draft = controller.reviewDraft;
    if (draft == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('مراجعة الأرصدة الافتتاحية', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'يؤكد هذا الإجراء الأرصدة الافتتاحية مرة واحدة، ولا يُعاد تأكيده.',
        ),
        const SizedBox(height: 12),
        Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'الأثر بعد التأكيد',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                _ReviewEffectLine(
                  icon: Icons.scale_outlined,
                  label: 'الذهب في المخزون والكسر',
                  value: '${_totalGold(draft)} جرام',
                ),
                const SizedBox(height: 8),
                _ReviewEffectLine(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'النقدية بكل الوسائل',
                  value: '${_totalCash(draft) ?? '—'} جنيه',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('النقد بالجنيه', style: theme.textTheme.titleSmall),
        for (final method in CashMethod.canonicalOrder)
          _ReviewLine(
            label: cashMethodLabel(method),
            amount: draft.cash[method].poundsText,
          ),
        if (_totalCash(draft) case final total?)
          _ReviewLine(label: 'إجمالي النقد', amount: '$total جنيه'),
        if (draft.stock.isNotEmpty)
          Text('المخزون', style: theme.textTheme.titleSmall),
        for (final row in draft.stock) ...[
          _ReviewLine(
            label: '${stockCategoryLabel(row.category)} عيار ${row.karat}',
            amount: '${row.milligrams.gramsText} جرام',
          ),
          _ReviewLine(label: 'العدد', amount: row.count.wire),
        ],
        if (draft.scrap.isNotEmpty)
          Text('الكسر', style: theme.textTheme.titleSmall),
        for (final row in draft.scrap)
          _ReviewLine(
            label: 'كسر عيار ${row.karat}',
            amount: '${row.milligrams.gramsText} جرام',
          ),
        if (showActions) ...[
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('confirm-opening'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: controller.fieldsLocked
                ? null
                : controller.confirmReview,
            child: const Text('تأكيد الأرصدة الافتتاحية'),
          ),
          const SizedBox(height: 8),
          TextButton(
            key: const Key('back-to-edit'),
            onPressed: controller.fieldsLocked ? null : controller.backToEdit,
            child: const Text('رجوع للتعديل'),
          ),
        ],
      ],
    );
  }
}

class _ReviewEffectLine extends StatelessWidget {
  const _ReviewEffectLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onPrimaryContainer;
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelWidget = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(color: color),
              ),
            ),
          ],
        );
        final valueWidget = Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            value,
            textAlign: TextAlign.end,
            softWrap: true,
            style: theme.textTheme.titleSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
        if (constraints.maxWidth < 360) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [labelWidget, const SizedBox(height: 4), valueWidget],
          );
        }
        return Row(
          children: [
            Expanded(child: labelWidget),
            const SizedBox(width: 8),
            Flexible(child: valueWidget),
          ],
        );
      },
    );
  }
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine({required this.label, required this.amount});

  final String label;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(label)),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Text(amount, textAlign: TextAlign.end),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingNotice extends StatelessWidget {
  const _PendingNotice();

  @override
  Widget build(BuildContext context) {
    return const Text('بانتظار تأكيد الخادم', key: Key('opening-pending'));
  }
}

class _RefreshFailedNotice extends StatelessWidget {
  const _RefreshFailedNotice();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('تم تأكيد الأرصدة الافتتاحية'),
        SizedBox(height: 8),
        Text('تعذر تحديث الدفتر بعد التأكيد.'),
      ],
    );
  }
}

String? _totalCash(OpeningDraft draft) {
  final sum = PostgresInteger.checkedSum([
    for (final method in CashMethod.canonicalOrder) draft.cash[method].value,
  ]);
  if (sum == null) return null;
  final parsed = Piastres.parseWire(sum.toString());
  if (parsed is! Accepted<Piastres>) return null;
  return parsed.value.poundsText;
}

String _totalGold(OpeningDraft draft) {
  final total = [
    ...draft.stock.map((row) => row.milligrams.value),
    ...draft.scrap.map((row) => row.milligrams.value),
  ].fold(BigInt.zero, (sum, value) => sum + value);
  final whole = total ~/ BigInt.from(1000);
  final fraction = (total % BigInt.from(1000)).toString().padLeft(3, '0');
  return '$whole.$fraction';
}
