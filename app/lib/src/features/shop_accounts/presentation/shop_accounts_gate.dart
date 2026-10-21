import '../../invoice_message/application/message_gateway.dart';
import '../../invoice_message/presentation/message_settings_screen.dart';
import '../../debts/application/debt_reminder_coordinator.dart';
import '../../debts/application/debt_reminder_device.dart';
import '../../debts/application/debt_native_gateway.dart';
import '../../debts/presentation/debt_native_screen.dart';
import 'dart:async';
import '../../reports/application/report_gateway.dart';
import '../../reports/presentation/reports_screen.dart';
import '../../closing_delegation/application/closing_delegation_gateway.dart';
import '../../closing_delegation/presentation/closing_staff_screen.dart';
import '../../closing_delegation/presentation/staff_count_portal.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../shell/shell_copy.dart';
import '../../../theme/brand_mark.dart';
import '../../../theme/app_tokens.dart';
import '../../daily_ledger/application/financial_gateway.dart';
import '../../daily_ledger/application/opening_gateway.dart';
import '../../daily_ledger/application/pending_opening_store.dart';
import '../../daily_ledger/data/pending_financial_command.dart';
import '../../../shell/shop_workspace.dart';
import '../../inventory/application/inventory_gateway.dart';
import '../../inventory/presentation/inventory_screen.dart';
import '../../inventory/presentation/trader_screen.dart';
import '../../debts/application/debt_gateway.dart';
import '../../customers/application/customer_gateway.dart';
import '../../customers/presentation/customer_screen.dart';
import '../../debts/presentation/debt_screen.dart';
import '../../repairs/application/repair_gateway.dart';
import '../../repairs/presentation/repair_screen.dart';
import '../../invoice_appearance/application/invoice_appearance_gateway.dart';
import '../../invoice_appearance/application/invoice_copy_files.dart';
import '../../invoice_appearance/presentation/invoice_appearance_screen.dart';
import '../../onboarding/application/onboarding_store.dart';
import '../application/shop_sync_coordinator.dart';
import '../application/shop_sync_ticks.dart';
import '../domain/shop_account.dart';
import '../domain/shop_account_gateway.dart';
import '../domain/shop_image.dart';
import '../domain/shop_sync.dart';
import 'shop_image_screen.dart';
import 'subscription_activation.dart';

class ShopAccountsGate extends StatefulWidget {
  const ShopAccountsGate({
    super.key,
    this.reminders,
    required this.gateway,
    required this.onSignOut,
    required this.onToggleTheme,
    this.openingGateway,
    this.pendingOpeningStore,
    this.currentUserId,
    this.onboardingStore,
    this.syncGateway,
    this.shopImageGateway,
  });

  final DebtReminderCoordinator? reminders;
  final ShopAccountGateway gateway;
  final Future<void> Function() onSignOut;
  final Future<void> Function(Brightness) onToggleTheme;
  final OpeningGateway? openingGateway;
  final PendingOpeningStore? pendingOpeningStore;
  final String? Function()? currentUserId;
  final OnboardingStore? onboardingStore;
  final ShopSyncGateway? syncGateway;
  final ShopImageGateway? shopImageGateway;

  @override
  State<ShopAccountsGate> createState() => _ShopAccountsGateState();
}

class _ShopAccountsGateState extends State<ShopAccountsGate>
    with WidgetsBindingObserver {
  List<ShopAccount>? _accounts;
  ShopAccount? _selected;
  bool _loading = false;
  bool _accessLost = false;
  String? _error;
  Timer? _refreshTimer;
  ShopSyncCoordinator? _sync;
  final _ticks = ShopSyncTicks();
  int _ledgerGeneration = 0;
  int _inventoryGeneration = 0;
  int _traderGeneration = 0;
  int _repairGeneration = 0;
  int _debtGeneration = 0;
  int _customerGeneration = 0;
  int _requestGeneration = 0;
  int _syncGeneration = 0;
  String? _userId;
  String? _syncIdentity;
  bool _activationDialogShown = false;
  Route<void>? _activationRoute;
  String? _activationShopId;
  bool _refreshQueued = false;
  StreamSubscription<ReminderDeviceReport>? _reminderEvents;
  bool _tapOpening = false;
  Uint8List? _shopImageBytes;
  String? _shopImageShopId;
  String? _shopImageSha;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _userId = widget.currentUserId?.call();
    _reminderEvents = widget.reminders?.changes.listen(
      (_) => _openReminderTap(),
    );
    _refresh();
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refresh(),
    );
  }

  @override
  void didUpdateWidget(covariant ShopAccountsGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextUser = widget.currentUserId?.call();
    if (nextUser != _userId) {
      unawaited(const InvoiceCopyFiles().clear());
    }
    if (oldWidget.gateway != widget.gateway ||
        oldWidget.syncGateway != widget.syncGateway ||
        nextUser != _userId) {
      _closeActivationDialog();
      _requestGeneration++;
      _syncGeneration++;
      _userId = nextUser;
      _accounts = null;
      _selected = null;
      _accessLost = false;
      _loading = false;
      _error = null;
      _activationDialogShown = false;
      _activationShopId = null;
      _syncIdentity = null;
      _ledgerGeneration++;
      _inventoryGeneration++;
      _traderGeneration++;
      _repairGeneration++;
      _debtGeneration++;
      _customerGeneration++;
      unawaited(_ensureSync());
      unawaited(_refresh());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sync?.resume();
      unawaited(widget.reminders?.reconcile());
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _closeActivationDialog();
    _requestGeneration++;
    _syncGeneration++;
    _refreshTimer?.cancel();
    _reminderEvents?.cancel();
    unawaited(widget.reminders?.bind(null, null));
    unawaited(_tearDownSync());
    _ticks.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) {
      _refreshQueued = true;
      return;
    }
    final generation = ++_requestGeneration;
    final userId = widget.currentUserId?.call();
    final gateway = widget.gateway;
    bool isCurrent() =>
        mounted &&
        generation == _requestGeneration &&
        userId == widget.currentUserId?.call();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final accounts = await gateway.listMyShopAccounts();
      if (!isCurrent()) return;
      final previous = _selected;
      setState(() {
        if (_accounts != null && _accounts!.isNotEmpty && accounts.isEmpty) {
          _markAccessLost();
        }
        _accounts = accounts;
        if (_selected != null) {
          final matching = accounts.where((item) => item.id == _selected!.id);
          if (matching.isEmpty) {
            _selected = null;
            _markAccessLost();
          } else {
            _selected = matching.first;
          }
        }
        if (_selected == null && accounts.isNotEmpty) {
          _selected = _preferredShop(accounts);
          _accessLost = false;
        } else if (accounts.isNotEmpty) {
          _accessLost = false;
        }
        if (previous?.id != _selected?.id ||
            previous?.entitlement != _selected?.entitlement) {
          _ledgerGeneration++;
          _inventoryGeneration++;
          _traderGeneration++;
          _repairGeneration++;
          _debtGeneration++;
          _customerGeneration++;
          if (previous?.id != _selected?.id) {
            _activationDialogShown = false;
            _activationShopId = null;
          }
        }
      });
      _dismissResolvedActivation();
      final reminderShop = _selected;
      unawaited(
        widget.reminders?.bind(
          reminderShop != null &&
                  reminderShop.entitlement != ShopEntitlement.pending
              ? userId
              : null,
          reminderShop != null &&
                  reminderShop.entitlement != ShopEntitlement.pending
              ? reminderShop.id
              : null,
        ),
      );
      unawaited(_ensureSync());
      unawaited(_ensureShopImage());
      _maybePromptActivation();
    } on ShopAccountException catch (error) {
      if (!isCurrent()) return;
      setState(() {
        _selected = null;
        _accounts = null;
        _shopImageBytes = null;
        _shopImageShopId = null;
        _shopImageSha = null;
        if (error.failure == ShopAccountFailure.unauthorized) {
          _markAccessLost();
        } else {
          _accessLost = false;
        }
        _error = _failureText(error.failure);
      });
      unawaited(_ensureSync());
      if (error.failure == ShopAccountFailure.unauthorized) {
        unawaited(widget.reminders?.bind(null, null));
      }
    } catch (_) {
      if (!isCurrent()) return;
      setState(() {
        _selected = null;
        _accounts = null;
        _shopImageBytes = null;
        _shopImageShopId = null;
        _shopImageSha = null;
        _error = 'تعذر تحميل المتاجر. تحقق من الاتصال وحاول مجددًا.';
      });
    } finally {
      if (isCurrent()) {
        setState(() => _loading = false);
        if (_refreshQueued) {
          _refreshQueued = false;
          unawaited(_refresh());
        }
      }
    }
  }

  Future<void> _openReminderTap() async {
    final reminders = widget.reminders,
        selected = _selected,
        user = widget.currentUserId?.call();
    if (_tapOpening ||
        reminders?.manifest?.tapToken == null ||
        selected == null ||
        user == null ||
        selected.entitlement == ShopEntitlement.pending) {
      return;
    }
    _tapOpening = true;
    try {
      final detail = await reminders!.readTap();
      if (!mounted ||
          widget.currentUserId?.call() != user ||
          _selected?.id != selected.id) {
        return;
      }
      await reminders.dismissTap();
      if (!mounted) return;
      if (detail == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'التذكير غير متاح لهذا الحساب. أعد فتح الديون للمراجعة.',
            ),
          ),
        );
        return;
      }
      final opening = widget.openingGateway;
      if (opening is! DebtNativeGateway) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => DebtNativeScreen(
            gateway: opening as DebtNativeGateway,
            store: const PendingFinancialCommands(),
            userId: user,
            shopId: selected.id,
            sourceKind: detail.row.due.summary.sourceKind,
            sourceId: detail.row.due.summary.sourceId,
            reminders: reminders,
            syncTicks: _ticks,
            canRead: () =>
                mounted &&
                widget.currentUserId?.call() == user &&
                _selected?.id == selected.id &&
                !_accessLost,
            canWrite: () =>
                mounted &&
                widget.currentUserId?.call() == user &&
                _selected?.id == selected.id &&
                _selected?.entitlement == ShopEntitlement.active,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذر قراءة التذكير بإذن حديث. افتح الديون عند عودة الاتصال.',
            ),
          ),
        );
      }
    } finally {
      _tapOpening = false;
    }
  }

  Future<void> _tearDownSync() async {
    final coordinator = _sync;
    _sync = null;
    _syncIdentity = null;
    await coordinator?.dispose();
  }

  Future<void> _ensureSync() async {
    final selected = _selected;
    final userId = widget.currentUserId?.call();
    final gateway = widget.syncGateway;
    final identity = selected == null || userId == null || userId.isEmpty
        ? null
        : '$userId:${selected.id}';
    if (identity != null &&
        identity == _syncIdentity &&
        _sync != null &&
        identical(_sync!.gateway, gateway)) {
      return;
    }
    final generation = ++_syncGeneration;
    final previous = _sync;
    _sync = null;
    _syncIdentity = identity;
    await previous?.dispose();
    if (identity == null || gateway == null) {
      return;
    }
    final coordinator = ShopSyncCoordinator(
      gateway: gateway,
      shopId: selected!.id,
      userId: userId!,
      onInvalidate: (scopes) async {
        if (!mounted || generation != _syncGeneration) return;
        if (scopes.contains(ShopSyncScope.subscription) ||
            scopes.contains(ShopSyncScope.location)) {
          await _refresh();
        }
        if (!mounted || generation != _syncGeneration) return;
        _ticks.apply(scopes);
        unawaited(widget.reminders?.reconcile());
        setState(() {
          if (scopes.contains(ShopSyncScope.ledger) ||
              scopes.contains(ShopSyncScope.day) ||
              scopes.contains(ShopSyncScope.invoice)) {
            _ledgerGeneration++;
          }
          if (scopes.contains(ShopSyncScope.inventory) ||
              scopes.contains(ShopSyncScope.ledger)) {
            _inventoryGeneration++;
          }
          if (scopes.contains(ShopSyncScope.trader) ||
              scopes.contains(ShopSyncScope.ledger)) {
            _traderGeneration++;
          }
          if (scopes.contains(ShopSyncScope.customer)) _customerGeneration++;
          if (scopes.contains(ShopSyncScope.repair) ||
              scopes.contains(ShopSyncScope.ledger) ||
              scopes.contains(ShopSyncScope.day)) {
            _repairGeneration++;
          }
          if (scopes.contains(ShopSyncScope.debt) ||
              scopes.contains(ShopSyncScope.ledger) ||
              scopes.contains(ShopSyncScope.inventory) ||
              scopes.contains(ShopSyncScope.trader)) {
            _debtGeneration++;
            _customerGeneration++;
          }
        });
      },
    );
    if (generation != _syncGeneration) {
      await coordinator.dispose();
      return;
    }
    _sync = coordinator;
    await coordinator.start();
    if (generation != _syncGeneration) {
      await coordinator.dispose();
      if (identical(_sync, coordinator)) _sync = null;
    }
  }

  Future<void> _ensureShopImage() async {
    final shop = _selected;
    final gateway = widget.shopImageGateway;
    if (shop == null || gateway == null) {
      if (_shopImageBytes != null || _shopImageShopId != null) {
        setState(() {
          _shopImageBytes = null;
          _shopImageShopId = null;
          _shopImageSha = null;
        });
      }
      return;
    }
    final knownSha = shop.imageSha256;
    // Cache hit only when the account list and local bytes agree.
    if (knownSha != null &&
        _shopImageShopId == shop.id &&
        _shopImageSha == knownSha &&
        _shopImageBytes != null) {
      return;
    }
    try {
      // Always ask the gateway. Do not clear local bytes just because the
      // account list has not returned shop_image_sha256 yet — that wiped the
      // header right after a successful save.
      final image = await gateway.readCurrent();
      if (!mounted || _selected?.id != shop.id) return;
      setState(() {
        _shopImageBytes = image?.bytes;
        _shopImageShopId = shop.id;
        _shopImageSha = image?.sha256;
      });
    } catch (_) {
      if (!mounted || _selected?.id != shop.id) return;
      // Keep a just-saved local preview; otherwise fall back to BrandMark.
      if (_shopImageShopId == shop.id && _shopImageBytes != null) return;
      setState(() {
        _shopImageBytes = null;
        _shopImageShopId = shop.id;
        _shopImageSha = knownSha;
      });
    }
  }

  void _onShopImageChanged(Uint8List? bytes) {
    if (!mounted) return;
    setState(() {
      _shopImageBytes = bytes;
      _shopImageShopId = _selected?.id;
      if (bytes == null) {
        _shopImageSha = null;
      }
      _ledgerGeneration++;
    });
    unawaited(_refresh());
  }

  void _dismissResolvedActivation() {
    if (mounted && !(_selected?.needsActivation ?? true)) {
      _closeActivationDialog();
    }
  }

  void _closeActivationDialog() {
    final route = _activationRoute;
    _activationRoute = null;
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = route.navigator;
      if (navigator != null && route.isActive) navigator.removeRoute(route);
    });
  }

  void _maybePromptActivation() {
    final selected = _selected;
    if (!mounted || selected == null || !selected.needsActivation) {
      return;
    }
    if (_activationDialogShown && _activationShopId == selected.id) {
      return;
    }
    _activationDialogShown = true;
    _activationShopId = selected.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selected?.id != selected.id) return;
      unawaited(
        showSubscriptionActivationDialog(
          context: context,
          account: selected,
          gateway: widget.gateway,
          onActivated: _afterActivation,
          onRouteCreated: (route) => _activationRoute = route,
        ),
      );
    });
  }

  Future<void> _afterActivation() async {
    _activationDialogShown = true;
    _activationShopId = _selected?.id;
    await _refresh();
    if (!mounted) return;
    if (_error != null) throw StateError('activation_refetch_failed');
    if (_selected?.entitlement == ShopEntitlement.active) {
      setState(() {
        _ledgerGeneration++;
        _inventoryGeneration++;
        _traderGeneration++;
        _repairGeneration++;
        _debtGeneration++;
        _customerGeneration++;
      });
      _ticks.apply(ShopSyncScope.values.toSet());
    }
  }

  void _markAccessLost() {
    if (!_accessLost) unawaited(const InvoiceCopyFiles().clear());
    _accessLost = true;
  }

  Future<void> _signOut() async {
    try {
      await const InvoiceCopyFiles().clear();
    } catch (_) {}
    await widget.onSignOut();
  }

  Future<void> _openActivation() async {
    final selected = _selected;
    if (selected == null || !selected.needsActivation) return;
    await showSubscriptionActivationDialog(
      context: context,
      account: selected,
      gateway: widget.gateway,
      onActivated: _afterActivation,
      onRouteCreated: (route) => _activationRoute = route,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final actor = widget.currentUserId?.call();
    final staffGateway = widget.openingGateway;
    if (_accounts?.isEmpty == true &&
        !_accessLost &&
        actor != null &&
        staffGateway is ClosingDelegationGateway) {
      return StaffCountPortal(
        key: ValueKey('staff:$actor'),
        gateway: staffGateway as ClosingDelegationGateway,
        userId: actor,
        onSignOut: _signOut,
        onToggleTheme: widget.onToggleTheme,
      );
    }
    if (selected != null && selected.entitlement != ShopEntitlement.pending) {
      final opening = widget.openingGateway;
      final userId = widget.currentUserId?.call();
      final inventory = opening is InventoryGateway
          ? opening as InventoryGateway
          : null;
      final readOnly = selected.entitlement != ShopEntitlement.active;
      return ShopWorkspace(
        key: ValueKey('${widget.currentUserId?.call()}:${selected.id}'),
        shop: selected,
        gateway: opening,
        store: widget.pendingOpeningStore,
        userId: userId,
        refreshGeneration: _ledgerGeneration,
        syncTicks: _ticks,
        shopImageBytes: _shopImageShopId == selected.id
            ? _shopImageBytes
            : null,
        reportsBuilder: opening is! ReportGateway || userId == null
            ? null
            : (context) => ReportsScreen(
                gateway: opening as ReportGateway,
                userId: userId,
                shopId: selected.id,
                canRead: () =>
                    mounted &&
                    !_accessLost &&
                    widget.currentUserId?.call() == userId &&
                    _selected?.id == selected.id,
                syncTicks: _ticks,
              ),
        closingStaffBuilder:
            opening is ClosingDelegationGateway &&
                opening is FinancialGateway &&
                userId != null
            ? (context) => ClosingStaffScreen(
                gateway: opening as ClosingDelegationGateway,
                dayGateway: opening as FinancialGateway,
                statusGateway: opening as OpeningGateway,
                userId: userId,
                shopId: selected.id,
                canRead: () =>
                    mounted &&
                    widget.currentUserId?.call() == userId &&
                    _selected?.id == selected.id &&
                    !_accessLost,
                canWrite: () =>
                    mounted &&
                    widget.currentUserId?.call() == userId &&
                    _selected?.id == selected.id &&
                    !_accessLost &&
                    _selected?.entitlement == ShopEntitlement.active,
                invalidations: _ticks,
              )
            : null,
        onSignOut: _signOut,
        onToggleTheme: widget.onToggleTheme,
        onActivateSubscription: selected.needsActivation
            ? _openActivation
            : null,
        onboardingStore: widget.onboardingStore,
        shopImageBuilder: widget.shopImageGateway == null
            ? null
            : (context) => ShopImageScreen(
                shop: selected,
                gateway: widget.shopImageGateway!,
                initialBytes: _shopImageShopId == selected.id
                    ? _shopImageBytes
                    : null,
                onChanged: _onShopImageChanged,
              ),
        inventoryBuilder: inventory == null || userId == null
            ? null
            : (context) => InventoryScreen(
                gateway: inventory,
                statusGateway: opening as OpeningGateway,
                dayGateway: opening is FinancialGateway
                    ? opening as FinancialGateway
                    : null,
                userId: userId,
                shopId: selected.id,
                shopName: selected.name,
                readOnly: readOnly,
                onboardingStore: widget.onboardingStore,
                store: const PendingFinancialCommands(),
                refreshGeneration: _inventoryGeneration,
                syncTicks: _ticks,
              ),
        traderBuilder: inventory == null || userId == null
            ? null
            : (context) => TraderScreen(
                gateway: inventory,
                statusGateway: opening as OpeningGateway,
                dayGateway: opening is FinancialGateway
                    ? opening as FinancialGateway
                    : null,
                settlementGateway: opening is PurchaseSettlementGateway
                    ? opening as PurchaseSettlementGateway
                    : null,
                userId: userId,
                shopId: selected.id,
                shopName: selected.name,
                readOnly: readOnly,
                onboardingStore: widget.onboardingStore,
                store: const PendingFinancialCommands(),
                refreshGeneration: _traderGeneration,
                syncTicks: _ticks,
              ),
        repairBuilder: opening is! RepairGateway || userId == null
            ? null
            : (context) => RepairScreen(
                gateway: opening as RepairGateway,
                canWrite: () =>
                    mounted &&
                    widget.currentUserId?.call() == userId &&
                    _selected?.id == selected.id &&
                    _selected?.entitlement == ShopEntitlement.active,
                store: const PendingFinancialCommands(),
                userId: userId,
                shopId: selected.id,
                readOnly: readOnly,
                refreshGeneration: _repairGeneration,
                syncTicks: _ticks,
                onCollected: () {
                  if (!mounted) return;
                  setState(() => _ledgerGeneration++);
                },
              ),
        customerBuilder: opening is! CustomerGateway || userId == null
            ? null
            : (context) => CustomerScreen(
                gateway: opening as CustomerGateway,
                store: const PendingFinancialCommands(),
                userId: userId,
                shopId: selected.id,
                readOnly: readOnly,
                canRead: () =>
                    mounted &&
                    !_accessLost &&
                    widget.currentUserId?.call() == userId &&
                    _selected?.id == selected.id,
                canWrite: () =>
                    mounted &&
                    widget.currentUserId?.call() == userId &&
                    _selected?.id == selected.id &&
                    _selected?.entitlement == ShopEntitlement.active,
                refreshGeneration: _customerGeneration,
                syncTicks: _ticks,
              ),
        debtBuilder: opening is! DebtGateway || userId == null
            ? null
            : (context) => DebtScreen(
                reminders: widget.reminders,
                gateway: opening as DebtGateway,
                canRead: () =>
                    mounted &&
                    widget.currentUserId?.call() == userId &&
                    _selected?.id == selected.id,
                canWrite: () =>
                    mounted &&
                    widget.currentUserId?.call() == userId &&
                    _selected?.id == selected.id &&
                    _selected?.entitlement == ShopEntitlement.active,
                store: const PendingFinancialCommands(),
                userId: userId,
                shopId: selected.id,
                readOnly: readOnly,
                refreshGeneration: _debtGeneration,
                syncTicks: _ticks,
                onMutated: () {
                  if (!mounted) return;
                  setState(() {
                    _ledgerGeneration++;
                    _inventoryGeneration++;
                    _traderGeneration++;
                  });
                },
              ),
        messageBuilder: opening is! InvoiceMessageGateway || userId == null
            ? null
            : (context) => MessageSettingsScreen(
                gateway: opening as InvoiceMessageGateway,
                store: const PendingFinancialCommands(),
                userId: userId,
                shopId: selected.id,
                canRead: () =>
                    mounted &&
                    !_accessLost &&
                    widget.currentUserId?.call() == userId &&
                    _selected?.id == selected.id,
                canWrite: () =>
                    mounted &&
                    !_accessLost &&
                    widget.currentUserId?.call() == userId &&
                    _selected?.id == selected.id &&
                    _selected?.entitlement == ShopEntitlement.active,
                syncTicks: _ticks.messageSettings,
              ),
        appearanceBuilder:
            opening is! InvoiceAppearanceGateway || userId == null
            ? null
            : (context) => InvoiceAppearanceScreen(
                gateway: opening as InvoiceAppearanceGateway,
                store: const PendingFinancialCommands(),
                userId: userId,
                shopId: selected.id,
                shopImageGateway: widget.shopImageGateway,
                canRead: () =>
                    mounted &&
                    !_accessLost &&
                    widget.currentUserId?.call() == userId &&
                    _selected?.id == selected.id,
                canWrite: () =>
                    mounted &&
                    widget.currentUserId?.call() == userId &&
                    _selected?.id == selected.id &&
                    _selected?.entitlement == ShopEntitlement.active,
                syncTicks: _ticks.appearanceSettings,
              ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const BrandLockup(title: ShellCopy.appTitle),
        actions: [
          IconButton(
            key: const Key('shop-theme-toggle'),
            tooltip: Theme.of(context).brightness == Brightness.dark
                ? ShellCopy.toggleToLight
                : ShellCopy.toggleToDark,
            onPressed: () => widget.onToggleTheme(Theme.of(context).brightness),
            icon: Icon(
              Theme.of(context).brightness == Brightness.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
          IconButton(
            tooltip: 'تسجيل الخروج',
            onPressed: _signOut,
            icon: const Icon(Icons.logout),
          ),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              children: [
                if (_loading) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('جارٍ التحقق من حسابات المتجر…'),
                ],
                if (_error != null) ...[
                  Text(
                    _error!,
                    key: const Key('shop-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _refresh,
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
                if (_accessLost)
                  const Text(
                    'لم يعد لديك وصول إلى هذا المتجر. تحقق من عضويتك أو سجل الدخول مجددًا.',
                  ),
                if (selected != null) ...[
                  Text(
                    selected.name,
                    key: Key('shop-${selected.id}'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  _EntitlementCard(
                    account: selected,
                    onActivate: selected.needsActivation
                        ? _openActivation
                        : null,
                  ),
                ] else if (_accounts != null && !_accessLost) ...[
                  const Text(
                    'لا توجد عضويات مرتبطة بهذا الحساب.',
                    key: Key('shop-empty'),
                  ),
                  const SizedBox(height: 12),
                  const Text('سجّل الخروج للدخول بحساب له عضوية قائمة.'),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    key: const Key('shop-empty-sign-out'),
                    onPressed: _signOut,
                    child: const Text('تسجيل الخروج'),
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

class _EntitlementCard extends StatelessWidget {
  const _EntitlementCard({required this.account, this.onActivate});
  final ShopAccount account;
  final VoidCallback? onActivate;

  @override
  Widget build(BuildContext context) {
    final pending = account.entitlement == ShopEntitlement.pending;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _statusLabel(account.entitlement),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              pending
                  ? 'لم يُفعّل اشتراك هذا المتجر بعد. ستتاح بيانات المتجر بعد التفعيل.'
                  : 'انتهى اشتراك هذا المتجر. الوصول الحالي للقراءة فقط، ولا يمكن إجراء تغييرات.',
            ),
            if (onActivate != null) ...[
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('subscription-open'),
                onPressed: onActivate,
                child: const Text(SubscriptionCopy.openAction),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

ShopAccount _preferredShop(List<ShopAccount> accounts) {
  for (final account in accounts) {
    if (account.entitlement == ShopEntitlement.active) return account;
  }
  for (final account in accounts) {
    if (account.entitlement == ShopEntitlement.expired) return account;
  }
  return accounts.first;
}

String _statusLabel(ShopEntitlement status) => switch (status) {
  ShopEntitlement.pending => 'قيد التفعيل',
  ShopEntitlement.active => 'نشط',
  ShopEntitlement.expired => 'منتهي - للقراءة فقط',
};

String _failureText(ShopAccountFailure failure) => switch (failure) {
  ShopAccountFailure.unauthorized =>
    'انتهت الجلسة أو لم يعد لديك وصول. سجّل الدخول مجددًا.',
  ShopAccountFailure.invalidResponse =>
    'تعذر التحقق من بيانات المتجر. حاول مجددًا.',
  ShopAccountFailure.rejected => 'تعذر قبول طلب المتجر. حاول مجددًا.',
  ShopAccountFailure.unavailable => 'خدمة المتاجر غير متاحة الآن. حاول مجددًا.',
};
