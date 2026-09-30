import 'package:flutter/material.dart';

import '../application/daily_ledger_view.dart';
import '../application/financial_gateway.dart';
import '../application/idempotency_key.dart';
import '../application/opening_gateway.dart';
import '../application/pending_financial_command.dart';
import '../data/pending_financial_command.dart';
import '../domain/opening_catalog.dart';
import '../domain/opening_issue.dart';
import '../domain/postgres_integer.dart';
import '../domain/quantities.dart';
import 'opening_copy.dart';

class CashTransferScreen extends StatefulWidget {
  const CashTransferScreen({
    super.key,
    required this.gateway,
    required this.statusGateway,
    required this.userId,
    required this.shopId,
    required this.cash,
  });

  final CashTransferGateway gateway;
  final OpeningGateway statusGateway;
  final String userId;
  final String shopId;
  final List<LedgerCashLine> cash;

  @override
  State<CashTransferScreen> createState() => _CashTransferScreenState();
}

class _CashTransferScreenState extends State<CashTransferScreen> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _pending = const PendingFinancialCommands();
  CashMethod _from = CashMethod.cash;
  CashMethod _to = CashMethod.instantTransfer;
  Piastres? _review;
  String? _key;
  String? _message;
  bool _busy = false;
  bool _unknown = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Piastres? _balance(CashMethod method) {
    for (final line in widget.cash) {
      if (line.method == method.code) {
        final parsed = Piastres.parseWire(line.piastres);
        return parsed is Accepted<Piastres> ? parsed.value : null;
      }
    }
    return null;
  }

  void _startReview() {
    final amount = Piastres.parsePounds(_amount.text.trim());
    final available = _balance(_from);
    final destination = _balance(_to);
    if (_from == _to ||
        amount is! Accepted<Piastres> ||
        amount.value.value == BigInt.zero ||
        available == null ||
        destination == null ||
        amount.value.value > available.value ||
        PostgresInteger.checkedAdd(destination.value, amount.value.value) ==
            null ||
        _note.text.trim().length > 1000) {
      setState(() => _message = 'راجع الوسيلتين والمبلغ والرصيد والملاحظة.');
      return;
    }
    setState(() {
      _review = amount.value;
      _message = null;
    });
  }

  Map<String, Object?> _body(String key, Piastres amount) => {
    'p_idempotency_key': key,
    'p_payload': {
      'version': 1,
      'kind': 'cash_transfer',
      'from_method': _from.code,
      'to_method': _to.code,
      'amount_piastres': amount.wire,
      'note': _note.text.trim(),
    },
  };

  Future<void> _submit() async {
    final amount = _review;
    if (amount == null || _busy) return;
    final key = _key ?? newIdempotencyKey();
    var commandSaved = false;
    setState(() {
      _busy = true;
      _key = key;
      _message = 'جارٍ تأكيد التحويل على الخادم...';
    });
    try {
      await _pending.save(
        widget.userId,
        widget.shopId,
        PendingFinancialCommand(
          key: key,
          kind: 'cash_transfer',
          body: _body(key, amount),
        ),
      );
      commandSaved = true;
      final result = await widget.gateway.transferCash(
        callerUserId: widget.userId,
        idempotencyKey: key,
        fromMethod: _from.code,
        toMethod: _to.code,
        amountPiastres: amount.wire,
        note: _note.text.trim(),
      );
      if (!mounted) return;
      if (result is FinancialCommitted) {
        await _pending.clear(widget.userId, widget.shopId, key);
        if (mounted) Navigator.pop(context, true);
        return;
      }
      if (result is FinancialRejected) {
        await _pending.clear(widget.userId, widget.shopId, key);
        if (!mounted) return;
        setState(() {
          _key = null;
          _message = result.code == 'negative_owned_balance'
              ? 'تغير الرصيد المتاح. حدّث الدفتر وراجع التحويل.'
              : 'رفض الخادم التحويل. راجع البيانات والرصيد.';
        });
        return;
      }
      await _reconcile();
    } catch (_) {
      if (mounted) {
        setState(() {
          _unknown = commandSaved;
          if (!commandSaved) _key = null;
          _message = commandSaved
              ? 'حالة التحويل غير معروفة. تحقق قبل المتابعة.'
              : 'تعذر حفظ طلب التحويل. راجع أي عملية معلقة.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconcile() async {
    final key = _key;
    if (key == null || _busy) return;
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
          _message = 'لم يؤكد الخادم التحويل. أعد المحاولة بالمفتاح نفسه.';
        });
      } else {
        setState(() {
          _unknown = true;
          _message = 'حالة التحويل غير معروفة. أعد التحقق.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _unknown = true;
          _message = 'تعذر التحقق من التحويل. أعد المحاولة.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = _review;
    final source = _balance(_from);
    final destination = _balance(_to);
    return PopScope(
      canPop: !_busy && !_unknown,
      child: Scaffold(
        appBar: AppBar(title: const Text('تحويل نقدية')),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('بين وسائل الدفع', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  Text(
                    'تحويل داخلي؛ إجمالي النقدية والذهب لا يتغيران.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  if (amount == null) ...[
                    DropdownButtonFormField<CashMethod>(
                      key: const Key('transfer-from'),
                      initialValue: _from,
                      decoration: const InputDecoration(
                        labelText: 'من وسيلة الدفع',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final method in CashMethod.canonicalOrder)
                          DropdownMenuItem(
                            value: method,
                            child: Text(cashMethodLabel(method)),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _from = value ?? _from),
                    ),
                    const SizedBox(height: 8),
                    Text('الرصيد المتاح: ${source?.poundsText ?? '—'} جنيه'),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<CashMethod>(
                      key: const Key('transfer-to'),
                      initialValue: _to,
                      decoration: const InputDecoration(
                        labelText: 'إلى وسيلة الدفع',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final method in CashMethod.canonicalOrder)
                          DropdownMenuItem(
                            value: method,
                            child: Text(cashMethodLabel(method)),
                          ),
                      ],
                      onChanged: (value) => setState(() => _to = value ?? _to),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('transfer-amount'),
                      controller: _amount,
                      textDirection: TextDirection.ltr,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'المبلغ بالجنيه',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('transfer-note'),
                      controller: _note,
                      maxLength: 1000,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'ملاحظة اختيارية',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ] else ...[
                    Card(
                      color: theme.colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('التحويل: ${amount.poundsText} جنيه'),
                            Text('من: ${cashMethodLabel(_from)}'),
                            Text('إلى: ${cashMethodLabel(_to)}'),
                            const SizedBox(height: 12),
                            Text(
                              'بعد التحويل — ${cashMethodLabel(_from)}: '
                              '${_pounds(source!.value - amount.value)} جنيه',
                            ),
                            Text(
                              'بعد التحويل — ${cashMethodLabel(_to)}: '
                              '${_pounds(destination!.value + amount.value)} جنيه',
                            ),
                            const Text('إجمالي النقدية والذهب لا يتغيران.'),
                          ],
                        ),
                      ),
                    ),
                    if (_note.text.trim().isNotEmpty)
                      Text('الملاحظة: ${_note.text.trim()}'),
                    TextButton.icon(
                      onPressed: _busy || _unknown
                          ? null
                          : () => setState(() => _review = null),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('تعديل التحويل'),
                    ),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(_message!, style: theme.textTheme.bodyMedium),
                  ],
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 752),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: Key(
                      _unknown
                          ? 'transfer-check'
                          : amount == null
                          ? 'transfer-review'
                          : 'transfer-confirm',
                    ),
                    onPressed: _busy
                        ? null
                        : _unknown
                        ? _reconcile
                        : amount == null
                        ? _startReview
                        : _submit,
                    child: Text(
                      _busy
                          ? 'جارٍ المعالجة...'
                          : _unknown
                          ? 'التحقق من الحالة'
                          : amount == null
                          ? 'مراجعة التأثير'
                          : 'تأكيد التحويل',
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

String _pounds(BigInt piastres) {
  final whole = piastres ~/ BigInt.from(100);
  final fraction = (piastres % BigInt.from(100)).toString().padLeft(2, '0');
  return '$whole.$fraction';
}
