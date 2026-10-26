import 'package:flutter/material.dart';

import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/presentation/ledger_form_fields.dart';
import '../../shop_accounts/domain/shop_account.dart';
import '../application/shop_staff_gateway.dart';

class ShopStaffScreen extends StatefulWidget {
  const ShopStaffScreen({
    super.key,
    required this.gateway,
    required this.userId,
    required this.shopId,
    required this.canWrite,
  });

  final ShopStaffGateway gateway;
  final String userId;
  final String shopId;
  final bool Function() canWrite;

  @override
  State<ShopStaffScreen> createState() => _ShopStaffScreenState();
}

class _ShopStaffScreenState extends State<ShopStaffScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String _role = 'employee';
  final _selected = <ShopPermission>{ShopPermission.sale};
  ShopStaffDirectory? _directory;
  bool _loading = true;
  bool _busy = false;
  String? _message;
  bool _error = false;

  static const _labels = {
    ShopPermission.sale: 'البيع',
    ShopPermission.purchase: 'الشراء',
    ShopPermission.inventory: 'الجرد',
    ShopPermission.expense: 'المصروفات',
    ShopPermission.reports: 'التقارير',
    ShopPermission.invoiceSend: 'إرسال الفواتير',
  };

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final directory = await widget.gateway.listStaff(
        userId: widget.userId,
        shopId: widget.shopId,
      );
      if (!mounted) return;
      setState(() {
        _directory = directory;
        _loading = false;
      });
    } on ShopStaffException {
      if (!mounted) return;
      setState(() {
        _directory = null;
        _loading = false;
        _error = true;
        _message = 'تعذر تحميل الموظفين. حاول مجددًا.';
      });
    }
  }

  Future<void> _create() async {
    if (_busy || !widget.canWrite()) return;
    final name = _name.text.trim();
    final phone = _phone.text.trim().replaceFirst(RegExp(r'^\+'), '');
    final password = _password.text;
    if (name.isEmpty ||
        phone.isEmpty ||
        password.length < 8 ||
        _selected.isEmpty) {
      setState(() {
        _error = true;
        _message =
            'أدخل الاسم والهاتف وكلمة مرور لا تقل عن 8 أحرف وصلاحية واحدة.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.gateway.createStaff(
        userId: widget.userId,
        key: newIdempotencyKey(),
        name: name,
        phone: phone,
        password: password,
        role: _role,
        grants: Set.of(_selected),
      );
      if (!mounted) return;
      _name.clear();
      _phone.clear();
      _password.clear();
      setState(() {
        _busy = false;
        _error = false;
        _message = 'تم إنشاء حساب الموظف.';
      });
      await _refresh();
    } on ShopStaffException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = true;
        _message = switch (error.failure) {
          ShopStaffFailure.identifierTaken => 'رقم الهاتف مستخدم مسبقًا.',
          ShopStaffFailure.staffLimit => 'وصلت إلى حد عدد الموظفين.',
          ShopStaffFailure.unauthorized => 'انتهت الجلسة. سجّل الدخول مجددًا.',
          _ => 'تعذر إنشاء الموظف. حاول مجددًا.',
        };
      });
    }
  }

  Future<void> _revoke(ShopStaffMember member) async {
    if (_busy || !widget.canWrite()) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('إيقاف الموظف'),
        content: Text('إيقاف ${member.displayName} من الوصول للمتجر؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('إيقاف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.gateway.revokeStaff(
        userId: widget.userId,
        key: newIdempotencyKey(),
        memberUserId: member.userId,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = false;
        _message = 'تم إيقاف الموظف.';
      });
      await _refresh();
    } on ShopStaffException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = true;
        _message = 'تعذر إيقاف الموظف.';
      });
    }
  }

  Future<void> _editGrants(ShopStaffMember member) async {
    final draft = Set<ShopPermission>.of(member.grants);
    final saved = await showDialog<Set<ShopPermission>>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('صلاحيات ${member.displayName}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final permission in ShopPermission.values)
                  CheckboxListTile(
                    value: draft.contains(permission),
                    title: Text(_labels[permission]!),
                    onChanged: (value) => setLocal(() {
                      if (value == true) {
                        draft.add(permission);
                      } else {
                        draft.remove(permission);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: draft.isEmpty
                  ? null
                  : () => Navigator.pop(dialog, Set.of(draft)),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (saved == null || !widget.canWrite()) return;
    setState(() => _busy = true);
    try {
      await widget.gateway.setGrants(
        userId: widget.userId,
        key: newIdempotencyKey(),
        memberUserId: member.userId,
        grants: saved,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = false;
        _message = 'تم تحديث الصلاحيات.';
      });
      await _refresh();
    } on ShopStaffException {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = true;
        _message = 'تعذر تحديث الصلاحيات.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('الموظفون والصلاحيات')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        'إضافة موظف أو شريك',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _name,
                        enabled: !_busy && widget.canWrite(),
                        decoration: ledgerFieldDecoration(
                          context,
                          label: 'الاسم',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _phone,
                        enabled: !_busy && widget.canWrite(),
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        decoration: ledgerFieldDecoration(
                          context,
                          label: 'رقم الهاتف',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _password,
                        enabled: !_busy && widget.canWrite(),
                        obscureText: true,
                        decoration: ledgerFieldDecoration(
                          context,
                          label: 'كلمة المرور الابتدائية',
                        ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'employee', label: Text('موظف')),
                          ButtonSegment(value: 'partner', label: Text('شريك')),
                        ],
                        selected: {_role},
                        onSelectionChanged: _busy || !widget.canWrite()
                            ? null
                            : (value) => setState(() => _role = value.first),
                      ),
                      const SizedBox(height: 8),
                      for (final permission in ShopPermission.values)
                        CheckboxListTile(
                          value: _selected.contains(permission),
                          title: Text(_labels[permission]!),
                          onChanged: _busy || !widget.canWrite()
                              ? null
                              : (value) => setState(() {
                                  if (value == true) {
                                    _selected.add(permission);
                                  } else {
                                    _selected.remove(permission);
                                  }
                                }),
                        ),
                      FilledButton(
                        key: const Key('shop-staff-create'),
                        onPressed: _busy || !widget.canWrite() ? null : _create,
                        child: Text(_busy ? 'جارٍ الحفظ…' : 'إنشاء الحساب'),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _message!,
                          style: TextStyle(
                            color: _error ? scheme.error : scheme.primary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        'الحسابات الحالية',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      if (_directory == null || _directory!.members.isEmpty)
                        const Text('لا يوجد موظفون بعد.')
                      else
                        for (final member in _directory!.members)
                          Card(
                            child: ListTile(
                              title: Text(member.displayName),
                              subtitle: Text(
                                '${member.role == 'partner' ? 'شريك' : 'موظف'}'
                                '${member.phone == null ? '' : ' · ${member.phone}'}'
                                '\n${member.grants.map((g) => _labels[g]).join('، ')}',
                              ),
                              isThreeLine: true,
                              trailing: Wrap(
                                spacing: 4,
                                children: [
                                  IconButton(
                                    tooltip: 'الصلاحيات',
                                    onPressed: _busy || !widget.canWrite()
                                        ? null
                                        : () => _editGrants(member),
                                    icon: const Icon(Icons.tune),
                                  ),
                                  IconButton(
                                    tooltip: 'إيقاف',
                                    onPressed: _busy || !widget.canWrite()
                                        ? null
                                        : () => _revoke(member),
                                    icon: const Icon(Icons.person_off_outlined),
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
