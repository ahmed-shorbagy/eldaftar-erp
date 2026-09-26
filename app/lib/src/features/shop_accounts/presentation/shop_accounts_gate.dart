import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/supabase_startup.dart';
import '../../../shell/home_shell.dart';
import '../../../shell/shell_copy.dart';
import '../../../theme/app_tokens.dart';
import '../domain/shop_account.dart';
import '../domain/shop_account_gateway.dart';

class ShopAccountsGate extends StatefulWidget {
  const ShopAccountsGate({
    super.key,
    required this.gateway,
    required this.onSignOut,
    required this.onToggleTheme,
  });

  final ShopAccountGateway gateway;
  final Future<void> Function() onSignOut;
  final Future<void> Function(Brightness) onToggleTheme;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refresh(),
    );
  }

  @override
  void didUpdateWidget(covariant ShopAccountsGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gateway != widget.gateway) {
      _accounts = null;
      _selected = null;
      _accessLost = false;
      _refresh();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final accounts = await widget.gateway.listMyShopAccounts();
      if (!mounted) return;
      setState(() {
        if (_accounts != null && _accounts!.isNotEmpty && accounts.isEmpty) {
          _accessLost = true;
        }
        _accounts = accounts;
        if (accounts.isNotEmpty) _accessLost = false;
        if (_selected != null) {
          final matching = accounts.where((item) => item.id == _selected!.id);
          if (matching.isEmpty) {
            _selected = null;
            _accessLost = true;
          } else {
            _selected = matching.first;
          }
        }
      });
    } on ShopAccountException catch (error) {
      if (!mounted) return;
      setState(() {
        _selected = null;
        _accounts = null;
        _accessLost = error.failure == ShopAccountFailure.unauthorized;
        _error = _failureText(error.failure);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _selected = null;
        _accounts = null;
        _error = 'تعذر تحميل المتاجر. تحقق من الاتصال وحاول مجددًا.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selected?.entitlement == ShopEntitlement.active) {
      return HomeShell(
        supabaseStatus: SupabaseStartupStatus.ready,
        onToggleTheme: widget.onToggleTheme,
        onSignOut: widget.onSignOut,
        shopName: _selected!.name,
        onChangeShop: () => setState(() => _selected = null),
      );
    }
    final selected = _selected;
    return Scaffold(
      appBar: AppBar(
        title: const Text(ShellCopy.appTitle),
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
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  _EntitlementCard(account: selected),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => setState(() => _selected = null),
                    child: const Text('اختيار متجر آخر'),
                  ),
                ] else if (_accounts != null && !_accessLost) ...[
                  if (_accounts!.isNotEmpty) ...[
                    Text(
                      'اختر المتجر',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_accounts!.isEmpty) ...[
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
                  for (final account in _accounts!) ...[
                    Card(
                      child: ListTile(
                        key: Key('shop-${account.id}'),
                        title: Text(account.name),
                        subtitle: Text(_statusLabel(account.entitlement)),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () => setState(() => _selected = account),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
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
