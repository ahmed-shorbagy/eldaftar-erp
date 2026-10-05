import 'dart:async';

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
import '../../onboarding/application/onboarding_store.dart';
import '../domain/shop_account.dart';
import '../domain/shop_account_gateway.dart';

class ShopAccountsGate extends StatefulWidget {
  const ShopAccountsGate({
    super.key,
    required this.gateway,
    required this.onSignOut,
    required this.onToggleTheme,
    this.openingGateway,
    this.pendingOpeningStore,
    this.currentUserId,
    this.onboardingStore,
  });

  final ShopAccountGateway gateway;
  final Future<void> Function() onSignOut;
  final Future<void> Function(Brightness) onToggleTheme;
  final OpeningGateway? openingGateway;
  final PendingOpeningStore? pendingOpeningStore;
  final String? Function()? currentUserId;
  final OnboardingStore? onboardingStore;

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
  int _ledgerGeneration = 0;
  int _requestGeneration = 0;
  String? _userId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _userId = widget.currentUserId?.call();
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
    if (oldWidget.gateway != widget.gateway || nextUser != _userId) {
      _requestGeneration++;
      _userId = nextUser;
      _accounts = null;
      _selected = null;
      _accessLost = false;
      _loading = false;
      _error = null;
      _ledgerGeneration++;
      _refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _requestGeneration++;
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
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
      setState(() {
        if (_accounts != null && _accounts!.isNotEmpty && accounts.isEmpty) {
          _accessLost = true;
        }
        _accounts = accounts;
        if (_selected != null) {
          final matching = accounts.where((item) => item.id == _selected!.id);
          if (matching.isEmpty) {
            _selected = null;
            _accessLost = true;
          } else {
            _selected = matching.first;
          }
        }
        // One owner owns one shop: enter the ledger without a selection step.
        if (_selected == null && accounts.isNotEmpty) {
          _selected = _preferredShop(accounts);
          _accessLost = false;
        } else if (accounts.isNotEmpty) {
          _accessLost = false;
        }
        _ledgerGeneration++;
      });
    } on ShopAccountException catch (error) {
      if (!isCurrent()) return;
      setState(() {
        _selected = null;
        _accounts = null;
        _accessLost = error.failure == ShopAccountFailure.unauthorized;
        _error = _failureText(error.failure);
      });
    } catch (_) {
      if (!isCurrent()) return;
      setState(() {
        _selected = null;
        _accounts = null;
        _error = 'تعذر تحميل المتاجر. تحقق من الاتصال وحاول مجددًا.';
      });
    } finally {
      if (isCurrent()) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
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
        onSignOut: widget.onSignOut,
        onToggleTheme: widget.onToggleTheme,
        onRefreshShops: _refresh,
        onboardingStore: widget.onboardingStore,
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
              ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const BrandLockup(title: ShellCopy.appTitle),
        actions: [
          IconButton(
            tooltip: 'تحديث المتاجر',
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
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
            onPressed: widget.onSignOut,
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
                  _EntitlementCard(account: selected),
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
                    onPressed: widget.onSignOut,
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
  const _EntitlementCard({required this.account});
  final ShopAccount account;

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
