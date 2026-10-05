import '../../../theme/amount_format.dart';
import 'package:flutter/material.dart';

import '../application/financial_gateway.dart';
import '../application/idempotency_key.dart';
import '../application/opening_gateway.dart';
import '../application/pending_financial_command.dart';
import '../data/pending_financial_command.dart';
import '../domain/opening_catalog.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';
import 'opening_copy.dart';

class PurchaseCashSettlementScreen extends StatefulWidget {
  const PurchaseCashSettlementScreen({
    super.key,
    required this.gateway,
    required this.statusGateway,
    required this.userId,
    required this.shopId,
    required this.purchaseOperationId,
    required this.remaining,
  });

  final PurchaseSettlementGateway gateway;
  final OpeningGateway statusGateway;
  final String userId;
  final String shopId;
  final String purchaseOperationId;
  final Piastres remaining;

  @override
  State<PurchaseCashSettlementScreen> createState() =>
      _PurchaseCashSettlementScreenState();
}

class _PurchaseCashSettlementScreenState
    extends State<PurchaseCashSettlementScreen> {
  final _amount = TextEditingController();
  final _pending = const PendingFinancialCommands();
  CashMethod _method = CashMethod.cash;
  Piastres? _review;
  String? _key;
  String? _message;
  bool _busy = false;
  bool _unknown = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _startReview() {
    final parsed = Piastres.parsePounds(_amount.text.trim());
    if (parsed is! Accepted<Piastres> ||
        parsed.value.value == BigInt.zero ||
        parsed.value.value > widget.remaining.value) {
      setState(() => _message = 'أدخل مبلغاً أكبر من صفر ولا يتجاوز المستحق.');
      return;
    }
    setState(() {
      _review = parsed.value;
      _message = null;
    });
  }

  Future<void> _submit() async {
    final amount = _review;
    if (amount == null || _busy) return;
    var commandSaved = false;
    final key = _key ?? newIdempotencyKey();
    final tenders = <Map<String, Object?>>[
      {'method': _method.code, 'piastres': amount.wire},
    ];
    setState(() {
      _busy = true;
      _key = key;
      _message = null;
    });
    try {
      await _pending.save(
        widget.userId,
        widget.shopId,
        PendingFinancialCommand(
          key: key,
          kind: 'purchase_settlement',
          body: {
            'p_idempotency_key': key,
            'p_purchase_operation_id': widget.purchaseOperationId,
            'p_tenders': tenders,
          },
        ),
      );
      commandSaved = true;
      final result = await widget.gateway.settlePurchaseCash(
        callerUserId: widget.userId,
        idempotencyKey: key,
        purchaseOperationId: widget.purchaseOperationId,
        tenders: tenders,
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
          _message = result.code == 'settlement_exceeds_obligation'
              ? 'تغير المبلغ المستحق. حدّث العملية وراجع السداد.'
              : 'رفض الخادم السداد. راجع الرصيد والاتصال.';
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
              ? 'حالة السداد غير معروفة. تحقق قبل المتابعة.'
              : 'تعذر حفظ طلب السداد. راجع أي عملية معلقة وحاول مجدداً.';
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
          _message =
              'لم يؤكد الخادم السداد. يمكنك إعادة المحاولة بالمفتاح نفسه.';
        });
      } else {
        setState(() {
          _unknown = true;
          _message = 'حالة السداد غير معروفة. أعد التحقق.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _unknown = true;
          _message = 'تعذر التحقق من السداد. أعد المحاولة.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final review = _review;
    final after = review == null ? null : widget.remaining.value - review.value;
    return PopScope(
      canPop: !_busy && !_unknown,
      child: Scaffold(
        appBar: AppBar(title: const Text('سداد مستحق شراء')),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('المستحق الحالي', style: theme.textTheme.titleMedium),
                  Text(
                    displayPounds(widget.remaining.poundsText),
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 20),
                  if (review == null) ...[
                    DropdownButtonFormField<CashMethod>(
                      initialValue: _method,
                      decoration: const InputDecoration(
                        labelText: 'وسيلة السداد',
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
                          setState(() => _method = value ?? _method),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('settlement-amount'),
                      controller: _amount,
                      textDirection: TextDirection.ltr,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'المبلغ المدفوع الآن ',
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
                            Text(
                              'ينقص النقد: ${displayPounds(review.poundsText)}',
                            ),
                            Text('يبقى مستحقاً: ${_pounds(after!)}'),
                            const Text('لا يتغير الذهب أو عدد القطع.'),
                          ],
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _review = null),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('تعديل السداد'),
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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              key: Key(
                _unknown
                    ? 'settlement-check'
                    : review == null
                    ? 'settlement-review'
                    : 'settlement-confirm',
              ),
              onPressed: _busy
                  ? null
                  : _unknown
                  ? _reconcile
                  : review == null
                  ? _startReview
                  : _submit,
              child: Text(
                _busy
                    ? 'بانتظار تأكيد الخادم'
                    : _unknown
                    ? 'التحقق من الحالة'
                    : review == null
                    ? 'مراجعة العملية'
                    : 'تأكيد السداد',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _pounds(BigInt piastres) {
  final parsed = Piastres.parseWire(piastres.toString());
  return parsed is Accepted<Piastres>
      ? displayPounds(parsed.value.poundsText)
      : '—';
}
