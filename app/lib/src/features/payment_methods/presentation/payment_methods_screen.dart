import 'package:flutter/material.dart';

import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/domain/opening_catalog.dart';
import '../../daily_ledger/domain/payment_method_catalog.dart';
import '../../daily_ledger/presentation/ledger_form_fields.dart';
import '../../daily_ledger/presentation/opening_copy.dart';
import '../application/payment_methods_gateway.dart';

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({
    super.key,
    required this.gateway,
    required this.userId,
    required this.canWrite,
  });

  final PaymentMethodsGateway gateway;
  final String userId;
  final bool Function() canWrite;

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen> {
  final Map<String, TextEditingController> _labels = {
    for (final method in CashMethod.canonicalOrder)
      method.code: TextEditingController(text: cashMethodLabel(method)),
  };
  final Map<String, bool> _archived = {
    for (final method in CashMethod.canonicalOrder) method.code: false,
  };
  bool _loading = true;
  bool _saving = false;
  bool _empty = false;
  String? _message;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _labels.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _message = null;
      _empty = false;
    });
    try {
      final directory = await widget.gateway.listMethods(userId: widget.userId);
      if (!mounted) return;
      if (directory.methods.isEmpty) {
        setState(() {
          _loading = false;
          _empty = true;
          _error = false;
          _message =
              'أكد الأرصدة الافتتاحية أولاً لإنشاء وسائل الدفع الأربع.';
        });
        return;
      }
      for (final method in directory.methods) {
        _labels[method.method]?.text = method.labelAr;
        _archived[method.method] = method.archived;
      }
      PaymentMethodCatalog.applyMethods([
        for (final method in directory.methods)
          (
            method: method.method,
            labelAr: method.labelAr,
            archived: method.archived,
          ),
      ]);
      setState(() {
        _loading = false;
        _error = false;
      });
    } on PaymentMethodsException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
        _message = switch (error.failure) {
          PaymentMethodsFailure.unauthorized =>
            'انتهت الجلسة. سجّل الدخول مجددًا.',
          _ => 'تعذر تحميل وسائل الدفع. حاول مجددًا.',
        };
      });
    }
  }

  Future<void> _save() async {
    if (_saving || _empty || !widget.canWrite()) return;
    final payload = <({String method, String labelAr, bool archived})>[];
    var active = 0;
    for (final method in CashMethod.canonicalOrder) {
      final label = _labels[method.code]!.text.trim();
      final archived = _archived[method.code] ?? false;
      if (label.isEmpty || label.length > 40) {
        setState(() {
          _error = true;
          _message = 'أدخل اسمًا عربيًا لكل وسيلة (من حرف إلى 40).';
        });
        return;
      }
      if (!archived) active += 1;
      payload.add((
        method: method.code,
        labelAr: label,
        archived: archived,
      ));
    }
    if (active < 1) {
      setState(() {
        _error = true;
        _message = 'يجب أن تبقى وسيلة دفع واحدة نشطة على الأقل.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final saved = await widget.gateway.saveMethods(
        userId: widget.userId,
        key: newIdempotencyKey(),
        methods: payload,
      );
      if (!mounted) return;
      for (final method in saved.methods) {
        _labels[method.method]?.text = method.labelAr;
        _archived[method.method] = method.archived;
      }
      PaymentMethodCatalog.applyMethods([
        for (final method in saved.methods)
          (
            method: method.method,
            labelAr: method.labelAr,
            archived: method.archived,
          ),
      ]);
      setState(() {
        _saving = false;
        _error = false;
        _message = 'تم حفظ وسائل الدفع.';
      });
    } on PaymentMethodsException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = true;
        _message = switch (error.failure) {
          PaymentMethodsFailure.unauthorized =>
            'انتهت الجلسة. سجّل الدخول مجددًا.',
          PaymentMethodsFailure.invalidInput =>
            'تحقق من الأسماء وحالة الأرشفة.',
          PaymentMethodsFailure.rejected =>
            'الاشتراك لا يسمح بالتعديل الآن.',
          _ => 'تعذر الحفظ. حاول مجددًا.',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('وسائل الدفع')),
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
                        'أعد تسمية الوسائل الأربع أو أرشفتها. الأرشفة تخفي الوسيلة من الإدخالات الجديدة دون حذف الرصيد أو التاريخ.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 16),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _message!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: _error
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      if (!_empty)
                        for (final method in CashMethod.canonicalOrder) ...[
                          TextField(
                            key: Key('payment-label-${method.code}'),
                            controller: _labels[method.code],
                            enabled: !_saving && widget.canWrite(),
                            decoration: ledgerFieldDecoration(
                              context,
                              label: 'الاسم الظاهر',
                            ),
                            maxLength: 40,
                          ),
                          SwitchListTile(
                            key: Key('payment-archive-${method.code}'),
                            contentPadding: EdgeInsets.zero,
                            title: const Text('مؤرشفة'),
                            subtitle: Text(
                              'الرمز الثابت: ${method.code}',
                              textDirection: TextDirection.ltr,
                            ),
                            value: _archived[method.code] ?? false,
                            onChanged: !_saving && widget.canWrite()
                                ? (value) => setState(
                                    () => _archived[method.code] = value,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 12),
                        ],
                      const SizedBox(height: 8),
                      if (!_empty)
                        FilledButton(
                          key: const Key('payment-methods-save'),
                          onPressed: _saving || !widget.canWrite()
                              ? null
                              : _save,
                          child: Text(_saving ? 'جارٍ الحفظ…' : 'حفظ'),
                        ),
                      if (_error && _empty)
                        TextButton(
                          onPressed: _load,
                          child: const Text('إعادة المحاولة'),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
