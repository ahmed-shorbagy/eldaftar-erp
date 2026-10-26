import 'package:flutter/material.dart';

import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/presentation/ledger_form_fields.dart';
import '../application/shop_profile_gateway.dart';

class ShopProfileScreen extends StatefulWidget {
  const ShopProfileScreen({
    super.key,
    required this.gateway,
    required this.userId,
    required this.canWrite,
  });

  final ShopProfileGateway gateway;
  final String userId;
  final bool Function() canWrite;

  @override
  State<ShopProfileScreen> createState() => _ShopProfileScreenState();
}

class _ShopProfileScreenState extends State<ShopProfileScreen> {
  final _name = TextEditingController();
  final _owner = TextEditingController();
  final _phone = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _message;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _owner.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final profile = await widget.gateway.getProfile(userId: widget.userId);
      if (!mounted) return;
      _name.text = profile.name;
      _owner.text = profile.ownerDisplayName;
      _phone.text = profile.phone;
      setState(() => _loading = false);
    } on ShopProfileException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
        _message = switch (error.failure) {
          ShopProfileFailure.unauthorized =>
            'انتهت الجلسة. سجّل الدخول مجددًا.',
          _ => 'تعذر تحميل بيانات المتجر. حاول مجددًا.',
        };
      });
    }
  }

  Future<void> _save() async {
    if (_saving || !widget.canWrite()) return;
    final name = _name.text.trim();
    final owner = _owner.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty || owner.isEmpty || phone.isEmpty) {
      setState(() {
        _error = true;
        _message = 'أكمل اسم المتجر واسم المالك ورقم الهاتف.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final saved = await widget.gateway.updateProfile(
        userId: widget.userId,
        key: newIdempotencyKey(),
        name: name,
        ownerDisplayName: owner,
        phone: phone,
      );
      if (!mounted) return;
      _name.text = saved.name;
      _owner.text = saved.ownerDisplayName;
      _phone.text = saved.phone;
      setState(() {
        _saving = false;
        _error = false;
        _message = 'تم حفظ بيانات المتجر.';
      });
    } on ShopProfileException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = true;
        _message = switch (error.failure) {
          ShopProfileFailure.identifierTaken => 'رقم الهاتف مستخدم لحساب آخر.',
          ShopProfileFailure.invalidInput => 'تحقق من صحة البيانات المدخلة.',
          ShopProfileFailure.unauthorized =>
            'انتهت الجلسة. سجّل الدخول مجددًا.',
          ShopProfileFailure.rejected => 'الاشتراك لا يسمح بالتعديل الآن.',
          _ => 'تعذر الحفظ. حاول مجددًا.',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('بيانات المتجر')),
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
                      TextField(
                        controller: _name,
                        enabled: !_saving && widget.canWrite(),
                        textInputAction: TextInputAction.next,
                        decoration: ledgerFieldDecoration(
                          context,
                          label: 'اسم المتجر',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _owner,
                        enabled: !_saving && widget.canWrite(),
                        textInputAction: TextInputAction.next,
                        decoration: ledgerFieldDecoration(
                          context,
                          label: 'اسم صاحب الحساب',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _phone,
                        enabled: !_saving && widget.canWrite(),
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        decoration: ledgerFieldDecoration(
                          context,
                          label: 'رقم الهاتف',
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _message!,
                            style: TextStyle(
                              color: _error ? scheme.error : scheme.primary,
                            ),
                          ),
                        ),
                      FilledButton(
                        key: const Key('shop-profile-save'),
                        onPressed: _saving || !widget.canWrite() ? null : _save,
                        child: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ'),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
