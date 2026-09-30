import 'package:flutter/material.dart';

import '../application/financial_gateway.dart';
import '../application/idempotency_key.dart';
import '../application/opening_gateway.dart';
import '../application/pending_financial_command.dart';
import '../data/pending_financial_command.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';

class LinkedReturnScreen extends StatefulWidget {
  const LinkedReturnScreen({
    super.key,
    required this.gateway,
    required this.statusGateway,
    required this.userId,
    required this.shopId,
    required this.operation,
  });

  final LinkedReturnGateway gateway;
  final OpeningGateway statusGateway;
  final String userId;
  final String shopId;
  final Map<String, Object?> operation;

  @override
  State<LinkedReturnScreen> createState() => _LinkedReturnScreenState();
}

class _LinkedReturnScreenState extends State<LinkedReturnScreen> {
  final _note = TextEditingController();
  final _pending = const PendingFinancialCommands();
  bool _reviewing = false;
  bool _busy = false;
  bool _unknown = false;
  String? _key;
  String? _message;

  String get _originalId => widget.operation['operation_id']! as String;
  String get _kind => widget.operation['kind'] == 'purchase'
      ? 'purchase_return'
      : 'sale_return';
  Map<String, Object?> get _payload => Map<String, Object?>.from(
    widget.operation['payload']! as Map,
  );

  String get _cashReturn {
    final total = _parse(_payload['total_piastres']);
    if (_kind == 'sale_return') return _pounds(total);
    final remaining = _parse(
      widget.operation['purchase_payable_remaining_piastres'],
    );
    return _pounds(total - remaining);
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _review() {
    if (_note.text.trim().length > 1000) {
      setState(() => _message = 'الملاحظة أطول من الحد المسموح.');
      return;
    }
    setState(() {
      _reviewing = true;
      _message = null;
    });
  }

  Future<void> _submit() async {
    if (_busy) return;
    final key = _key ?? newIdempotencyKey();
    final body = <String, Object?>{
      'p_idempotency_key': key,
      'p_original_operation_id': _originalId,
      'p_note': _note.text.trim(),
    };
    var saved = false;
    setState(() {
      _busy = true;
      _key = key;
      _message = 'جارٍ تأكيد المرتجع على الخادم...';
    });
    try {
      await _pending.save(
        widget.userId,
        widget.shopId,
        PendingFinancialCommand(key: key, kind: _kind, body: body),
      );
      saved = true;
      final result = await widget.gateway.returnOperation(
        callerUserId: widget.userId,
        idempotencyKey: key,
        originalOperationId: _originalId,
        note: _note.text.trim(),
      );
      if (!mounted) return;
      if (result is FinancialCommitted) {
        await _pending.clear(widget.userId, widget.shopId, key);
        if (mounted) Navigator.pop(context, true);
      } else if (result is FinancialRejected) {
        await _pending.clear(widget.userId, widget.shopId, key);
        if (!mounted) return;
        setState(() {
          _key = null;
          _message = switch (result.code) {
            'already_returned' => 'سُجل مرتجع لهذه العملية بالفعل.',
            'negative_owned_balance' || 'insufficient_stock' =>
              'لا تكفي الأرصدة الحالية لعكس العملية بأمان.',
            'day_closed' => 'افتح يوم عمل قبل تسجيل المرتجع.',
            _ => 'رفض الخادم المرتجع. حدّث العملية وحاول مجددًا.',
          };
        });
      } else {
        await _reconcile();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _unknown = saved;
          if (!saved) _key = null;
          _message = saved
              ? 'حالة المرتجع غير معروفة. تحقق قبل المتابعة.'
              : 'تعذر حفظ طلب المرتجع.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconcile() async {
    final key = _key;
    if (key == null) return;
    setState(() => _busy = true);
    try {
      final status = await widget.statusGateway.status(
        callerUserId: widget.userId,
        idempotencyKey: key,
      );
      if (!mounted) return;
      if (status is StatusCompleted) {
        await _pending.clear(widget.userId, widget.shopId, key);
        if (mounted) Navigator.pop(context, true);
      } else if (status is StatusAbsent) {
        setState(() {
          _unknown = false;
          _message = 'لم يؤكد الخادم المرتجع. أعد المحاولة بالمفتاح نفسه.';
        });
      } else {
        setState(() {
          _unknown = true;
          _message = 'حالة المرتجع غير معروفة. أعد التحقق.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _unknown = true;
          _message = 'تعذر التحقق من المرتجع. أعد المحاولة.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _payload['items'];
    final sequence = widget.operation['shop_sequence'];
    return PopScope(
      canPop: !_busy && !_unknown,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_kind == 'sale_return' ? 'مرتجع بيع' : 'مرتجع شراء'),
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('عكس كامل مرتبط', style: theme.textTheme.headlineSmall),
                  Text('العملية الأصلية رقم $sequence'),
                  const Text(
                    'يسجل الخادم عملية جديدة في اليوم المفتوح ويحافظ على العملية الأصلية للمراجعة.',
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _message!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _unknown
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Card(
                    color: theme.colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('النقد المرتجع: $_cashReturn جنيه'),
                          if (_kind == 'purchase_return' &&
                              _parse(widget.operation[
                                    'purchase_payable_remaining_piastres'
                                  ]) >
                                  BigInt.zero)
                            Text(
                              'يلغى المستحق المتبقي: ${_pounds(_parse(widget.operation['purchase_payable_remaining_piastres']))} جنيه',
                            ),
                          const Text('تعكس كل أوزان الذهب وأعداد القطع الأصلية.'),
                        ],
                      ),
                    ),
                  ),
                  if (items is List)
                    for (final raw in items)
                      if (raw is Map)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${raw['item_name']} · عيار ${raw['karat']}'),
                          subtitle: Text(
                            '${_grams(raw['milligrams'])} جرام${raw['count'] == null ? '' : ' · ${raw['count']} قطعة'}',
                          ),
                        ),
                  if (!_reviewing) ...[
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('return-note'),
                      controller: _note,
                      maxLength: 1000,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'سبب أو ملاحظة اختيارية',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    const Text('بعد التأكيد لا تُحذف العملية الأصلية.'),
                    TextButton.icon(
                      onPressed: _busy || _unknown
                          ? null
                          : () => setState(() => _reviewing = false),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('تعديل الملاحظة'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: Key(
                      _unknown
                          ? 'return-check'
                          : _reviewing
                          ? 'return-confirm'
                          : 'return-review',
                    ),
                    onPressed: _busy
                        ? null
                        : _unknown
                        ? _reconcile
                        : _reviewing
                        ? _submit
                        : _review,
                    child: Text(
                      _busy
                          ? 'جارٍ المعالجة...'
                          : _unknown
                          ? 'التحقق من الحالة'
                          : _reviewing
                          ? 'تأكيد المرتجع الكامل'
                          : 'مراجعة الأثر',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

BigInt _parse(Object? value) {
  if (value is! String) return BigInt.zero;
  final parsed = Piastres.parseWire(value);
  return parsed is Accepted<Piastres> ? parsed.value.value : BigInt.zero;
}

String _pounds(BigInt value) =>
    (Piastres.parseWire(value.toString()) as Accepted<Piastres>)
        .value
        .poundsText;

String _grams(Object? value) {
  if (value is! String) return '—';
  final parsed = Milligrams.parseWire(value);
  return parsed is Accepted<Milligrams> ? parsed.value.gramsText : '—';
}
