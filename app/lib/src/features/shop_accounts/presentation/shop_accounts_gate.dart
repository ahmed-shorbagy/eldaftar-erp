import 'dart:async';
import 'dart:math';

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
  bool _setupConfirmed = false;
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

  Future<void> _created(String shopId) async {
    setState(() => _setupConfirmed = true);
    await _refresh();
    if (!mounted) return;
    final matches = _accounts?.where((item) => item.id == shopId);
    if (matches != null && matches.isNotEmpty) {
      setState(() => _selected = matches.first);
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
                if (_setupConfirmed) ...[
                  const Text('تم إنشاء المتجر وتأكيده. التفعيل قيد الانتظار.'),
                  const SizedBox(height: 12),
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
                  Text(
                    'اختر المتجر',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  if (_accounts!.isEmpty) ...[
                    const Text('ليس لديك متجر بعد. أدخل بيانات متجرك للبدء.'),
                    const SizedBox(height: 16),
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
                  if (_accounts!.isEmpty)
                    ShopSetupForm(
                      key: const ValueKey('shop-setup-form'),
                      gateway: widget.gateway,
                      onCreated: _created,
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
  ShopAccountFailure.rejected =>
    'تعذر حفظ بيانات المتجر. راجع البيانات وحاول مجددًا.',
  ShopAccountFailure.unavailable => 'خدمة المتاجر غير متاحة الآن. حاول مجددًا.',
};

class ShopSetupForm extends StatefulWidget {
  const ShopSetupForm({
    super.key,
    required this.gateway,
    required this.onCreated,
  });
  final ShopAccountGateway gateway;
  final Future<void> Function(String) onCreated;

  @override
  State<ShopSetupForm> createState() => _ShopSetupFormState();
}

class _ShopSetupFormState extends State<ShopSetupForm> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _ownerName = TextEditingController();
  final _phone = TextEditingController();
  final _timeZone = TextEditingController(text: 'Africa/Cairo');
  ShopSetupRequest? _request;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _ownerName.dispose();
    _phone.dispose();
    _timeZone.dispose();
    super.dispose();
  }

  String _newRequestKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((part) => part.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  Future<void> _submit() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final request =
        _request ??
        ShopSetupRequest(
          name: _name.text.trim(),
          ownerDisplayName: _ownerName.text.trim(),
          phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          timeZone: _timeZone.text.trim(),
          requestKey: _newRequestKey(),
        );
    setState(() {
      _request = request;
      _busy = true;
      _error = null;
    });
    try {
      final shopId = await widget.gateway.createShopAccount(request);
      if (!mounted) return;
      await widget.onCreated(shopId);
    } on ShopAccountException catch (error) {
      if (mounted) setState(() => _error = _failureText(error.failure));
    } catch (_) {
      if (mounted) {
        setState(() => _error = _failureText(ShopAccountFailure.unavailable));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _busy || _request != null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'إعداد متجر جديد',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const Key('shop-name'),
                controller: _name,
                enabled: !locked,
                decoration: const InputDecoration(labelText: 'اسم المتجر'),
                validator: (value) =>
                    value == null ||
                        value.trim().isEmpty ||
                        value.trim().length > 120
                    ? 'أدخل اسم متجر من ١ إلى ١٢٠ حرفًا'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('owner-name'),
                controller: _ownerName,
                enabled: !locked,
                decoration: const InputDecoration(
                  labelText: 'اسم المالك المعروض',
                ),
                validator: (value) =>
                    value == null ||
                        value.trim().isEmpty ||
                        value.trim().length > 120
                    ? 'أدخل اسم المالك من ١ إلى ١٢٠ حرفًا'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('shop-phone'),
                controller: _phone,
                enabled: !locked,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف (اختياري)',
                ),
                validator: (value) => value != null && value.trim().length > 30
                    ? 'رقم الهاتف طويل جدًا'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('shop-time-zone'),
                controller: _timeZone,
                enabled: !locked,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'المنطقة الزمنية'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'أدخل منطقة زمنية'
                    : null,
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Text(
                  _error!,
                  key: const Key('shop-setup-error'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 12),
              ],
              FilledButton(
                key: const Key('shop-setup-submit'),
                onPressed: _busy ? null : _submit,
                child: Text(
                  _busy
                      ? 'جارٍ إنشاء المتجر…'
                      : _request == null
                      ? 'إنشاء المتجر'
                      : 'إعادة المحاولة',
                ),
              ),
              if (_request != null && !_busy)
                TextButton(
                  onPressed: () => setState(() {
                    _request = null;
                    _error = null;
                  }),
                  child: const Text('تعديل البيانات'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
