import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';

import '../application/confirmed_operation_pdf.dart';
import '../application/financial_gateway.dart';
import '../application/daily_ledger_view.dart';
import '../application/idempotency_key.dart';
import '../application/opening_gateway.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';
import 'opening_copy.dart';
import 'purchase_cash_settlement_screen.dart';
import 'linked_return_screen.dart';

class FinancialOperationScreen extends StatefulWidget {
  const FinancialOperationScreen({
    super.key,
    required this.gateway,
    required this.userId,
    required this.line,
  });

  final FinancialGateway gateway;
  final String userId;
  final LedgerFeedLine line;

  @override
  State<FinancialOperationScreen> createState() =>
      _FinancialOperationScreenState();
}

class _FinancialOperationScreenState extends State<FinancialOperationScreen> {
  Map<String, Object?>? _operation;
  bool _loading = true;
  bool _failed = false;
  InvoiceDispatchState? _dispatch;
  bool _dispatchLoading = false;
  bool _dispatchBusy = false;
  bool _handoffStarted = false;
  String? _dispatchMessage;
  String? _confirmationKey;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final value = await widget.gateway.operation(
        callerUserId: widget.userId,
        operationId: widget.line.operationId,
      );
      if (!mounted) return;
      setState(() => _operation = value);
      if (widget.gateway is InvoiceDispatchGateway &&
          (widget.line.kind == 'sale' || widget.line.kind == 'purchase')) {
        await _loadDispatch();
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadDispatch() async {
    final gateway = widget.gateway;
    if (gateway is! InvoiceDispatchGateway) return;
    setState(() {
      _dispatchLoading = true;
      _dispatchMessage = null;
    });
    try {
      final state = await (gateway as InvoiceDispatchGateway).dispatchState(
        callerUserId: widget.userId,
        operationId: widget.line.operationId,
      );
      if (!mounted) return;
      setState(() {
        _dispatch = state;
        if (state.ownerConfirmed) _confirmationKey = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _dispatchMessage = 'تعذر تحديث حالة إرسال الفاتورة');
      }
    } finally {
      if (mounted) setState(() => _dispatchLoading = false);
    }
  }

  Future<void> _openWhatsapp() async {
    final operation = _operation;
    final payload = operation?['payload'];
    if (operation == null || payload is! Map) return;
    final phone = whatsappPhone(payload['customer_phone']);
    if (phone == null) {
      setState(
        () => _dispatchMessage = 'أضف رقم هاتف صحيحاً للعميل قبل الإرسال',
      );
      return;
    }
    final sequence = operation['shop_sequence'];
    final message =
        'ملخص العملية رقم $sequence\n'
        '${widget.line.labelAr}\n'
        'الإجمالي: ${_pounds(payload['total_piastres'])} جنيه\n'
        'يرجى مراجعة تفاصيل العملية قبل الإرسال.';
    final link = Uri.https('wa.me', '/$phone', {'text': message});
    try {
      final opened = await launchUrl(
        link,
        mode: LaunchMode.externalApplication,
      );
      if (!mounted) return;
      setState(() {
        _handoffStarted = opened;
        _dispatchMessage = opened
            ? 'تم فتح واتساب. أكد الإرسال هنا بعد إرسال الرسالة فعلاً.'
            : 'تعذر فتح واتساب. لم يتم تأكيد الإرسال.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _dispatchMessage = 'تعذر فتح واتساب. لم يتم تأكيد الإرسال.',
        );
      }
    }
  }

  Future<void> _sharePdf() async {
    final operation = _operation;
    if (operation == null || _dispatchBusy) return;
    setState(() {
      _dispatchBusy = true;
      _dispatchMessage = 'جارٍ تجهيز مستند العملية...';
    });
    try {
      final bytes = await buildConfirmedOperationPdf(operation);
      final shared = await Printing.sharePdf(
        bytes: bytes,
        filename: 'eldaftar-operation-${operation['shop_sequence']}.pdf',
      );
      if (!mounted) return;
      setState(() {
        _handoffStarted = shared;
        _dispatchMessage = shared
            ? 'فُتحت مشاركة المستند. أكد الإرسال بعد إرساله في واتساب فعلاً.'
            : 'لم تُفتح مشاركة المستند. لم يتم تأكيد الإرسال.';
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _dispatchMessage = 'تعذر تجهيز المستند. لم يتم تأكيد الإرسال.',
        );
      }
    } finally {
      if (mounted) setState(() => _dispatchBusy = false);
    }
  }

  Future<void> _confirmWhatsappSend() async {
    final gateway = widget.gateway;
    if (gateway is! InvoiceDispatchGateway ||
        _dispatchBusy ||
        !_handoffStarted) {
      return;
    }
    final key = _confirmationKey ?? newIdempotencyKey();
    setState(() {
      _dispatchBusy = true;
      _confirmationKey = key;
      _dispatchMessage = 'جارٍ تأكيد إرسال الفاتورة...';
    });
    try {
      final result = await (gateway as InvoiceDispatchGateway)
          .confirmWhatsappSend(
            callerUserId: widget.userId,
            operationId: widget.line.operationId,
            idempotencyKey: key,
          );
      if (!mounted) return;
      if (result is FinancialCommitted) {
        await _loadDispatch();
        if (mounted && _dispatch?.ownerConfirmed == true) {
          setState(() => _dispatchMessage = 'أكد المالك الإرسال عبر واتساب');
        }
      } else if (result is FinancialRejected) {
        setState(() {
          _dispatchMessage = 'لم يُحفظ تأكيد الإرسال. تحقق وحاول مجدداً.';
          _confirmationKey = null;
        });
      } else {
        setState(
          () => _dispatchMessage =
              'حالة التأكيد غير معروفة. أعد المحاولة بالمفتاح نفسه.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _dispatchMessage =
              'حالة التأكيد غير معروفة. أعد المحاولة بالمفتاح نفسه.',
        );
      }
    } finally {
      if (mounted) setState(() => _dispatchBusy = false);
    }
  }

  Future<void> _settlePurchase() async {
    final gateway = widget.gateway;
    final operation = _operation;
    final shopId = operation?['shop_id'];
    final amount = operation?['purchase_payable_remaining_piastres'];
    if (gateway is! PurchaseSettlementGateway ||
        gateway is! OpeningGateway ||
        shopId is! String ||
        amount is! String) {
      return;
    }
    final parsed = Piastres.parseWire(amount);
    if (parsed is! Accepted<Piastres> || parsed.value.value == BigInt.zero) {
      return;
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PurchaseCashSettlementScreen(
          gateway: gateway as PurchaseSettlementGateway,
          statusGateway: gateway as OpeningGateway,
          userId: widget.userId,
          shopId: shopId,
          purchaseOperationId: widget.line.operationId,
          remaining: parsed.value,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _returnOperation() async {
    final gateway = widget.gateway;
    final operation = _operation;
    final shopId = operation?['shop_id'];
    if (gateway is! LinkedReturnGateway ||
        gateway is! OpeningGateway ||
        operation == null ||
        shopId is! String) {
      return;
    }
    final returnGateway = gateway as LinkedReturnGateway;
    final statusGateway = gateway as OpeningGateway;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LinkedReturnScreen(
          gateway: returnGateway,
          statusGateway: statusGateway,
          userId: widget.userId,
          shopId: shopId,
          operation: operation,
        ),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final operation = _operation;
    final payload = operation?['payload'];
    final details = payload is Map ? payload : const <String, Object?>{};
    final sequence = operation?['shop_sequence'];
    final items = details['items'];
    final tenders = details['tenders'];
    return Scaffold(
      appBar: AppBar(title: Text(widget.line.labelAr)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _failed
                ? Center(
                    child: TextButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('تعذر تحميل العملية. إعادة المحاولة'),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        widget.line.labelAr,
                        style: theme.textTheme.headlineSmall,
                      ),
                      if (sequence is String) Text('رقم العملية: $sequence'),
                      Text(
                        'المسجل: ${operation?['actor_display_name'] ?? widget.line.actorDisplayName}',
                      ),
                      Text(
                        'الوقت: ${formatServerCairoTimestamp(widget.line.occurredAtCairo)}',
                      ),
                      const SizedBox(height: 16),
                      if (details['total_piastres'] is String) ...[
                        Card(
                          color: theme.colorScheme.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(switch (widget.line.kind) {
                                  'sale' || 'scrap_sale' => 'النقد المحصّل',
                                  'purchase' => 'سعر الشراء الكلي',
                                  'sale_return' ||
                                  'purchase_return' => 'قيمة العملية الأصلية',
                                  _ => 'النقد المدفوع',
                                }),
                                Text(
                                  '${_pounds(details['total_piastres'])} جنيه',
                                  textDirection: TextDirection.ltr,
                                  style: theme.textTheme.headlineSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (widget.line.kind == 'cash_transfer' &&
                          details['amount_piastres'] is String) ...[
                        Card(
                          color: theme.colorScheme.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'تحويل ${_pounds(details['amount_piastres'])} جنيه',
                                ),
                                Text('من ${_method(details['from_method'])}'),
                                Text('إلى ${_method(details['to_method'])}'),
                                const Text('إجمالي النقدية والذهب لم يتغيرا.'),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (widget.line.kind == 'scrap_to_stock' &&
                          details['milligrams'] is String) ...[
                        Card(
                          color: theme.colorScheme.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'نقص الكسر: ${_grams(details['milligrams'])} جرام · عيار ${details['karat'] ?? '—'}',
                                ),
                                Text(
                                  'زاد المخزون: ${_grams(details['milligrams'])} جرام · ${details['count'] ?? '—'} قطعة · ${_category(details['category'])}',
                                ),
                                Text('الصنف: ${details['item_name'] ?? '—'}'),
                                const Text('لم تتغير النقدية.'),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (widget.line.kind == 'purchase') ...[
                        Text(
                          'المدفوع عند الشراء: ${_paidPounds(tenders)} جنيه',
                        ),
                        if (operation?['purchase_payable_remaining_piastres']
                            is String)
                          Text(
                            'المستحق للبائع الآن: ${_pounds(operation?['purchase_payable_remaining_piastres'])} جنيه',
                          ),
                        if (widget.gateway is PurchaseSettlementGateway &&
                            widget.gateway is OpeningGateway &&
                            operation?['shop_id'] is String &&
                            _hasPositivePiastres(
                              operation?['purchase_payable_remaining_piastres'],
                            ))
                          OutlinedButton.icon(
                            onPressed: _settlePurchase,
                            icon: const Icon(Icons.payments_outlined),
                            label: const Text('سداد مبلغ مستحق'),
                          ),
                      ],
                      if ((widget.line.kind == 'sale_return' ||
                              widget.line.kind == 'purchase_return') &&
                          details['cash_returned_piastres'] is String) ...[
                        Text(
                          'النقد المرتجع: ${_pounds(details['cash_returned_piastres'])} جنيه',
                        ),
                        Text(
                          'مرتبطة بالعملية رقم ${details['original_sequence'] ?? '—'}',
                        ),
                        if (_hasPositivePiastres(
                          details['cancelled_payable_piastres'],
                        ))
                          Text(
                            'المستحق الملغى: ${_pounds(details['cancelled_payable_piastres'])} جنيه',
                          ),
                      ],
                      if (items is List && items.isNotEmpty) ...[
                        Text('الأصناف', style: theme.textTheme.titleMedium),
                        for (final entry in items)
                          if (entry is Map)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(
                                      '${entry['item_name'] ?? 'صنف'} · عيار ${entry['karat'] ?? '—'}',
                                    ),
                                    Text(_category(entry['category'])),
                                    Text(
                                      '${_grams(entry['milligrams'])} جرام${entry['count'] == null ? '' : ' · ${entry['count']} قطعة'}',
                                    ),
                                    if (entry['line_price_piastres'] is String)
                                      Text(
                                        'سعر الصنف: ${_pounds(entry['line_price_piastres'])} جنيه',
                                      ),
                                  ],
                                ),
                              ),
                            ),
                      ],
                      if (tenders is List && tenders.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('وسائل الدفع', style: theme.textTheme.titleMedium),
                        for (final entry in tenders)
                          if (entry is Map)
                            ListTile(
                              title: Text(_method(entry['method'])),
                              trailing: Text(
                                '${_pounds(entry['piastres'])} جنيه',
                              ),
                            ),
                      ],
                      if (details['description'] is String &&
                          (details['description'] as String).isNotEmpty)
                        Text('الوصف: ${details['description']}'),
                      if (details['customer_name'] is String &&
                          (details['customer_name'] as String).isNotEmpty)
                        Text(
                          '${widget.line.kind == 'purchase' ? 'البائع' : 'العميل'}: ${details['customer_name']}',
                        ),
                      if (details['note'] is String &&
                          (details['note'] as String).isNotEmpty)
                        Text('الملاحظة: ${details['note']}'),
                      if ((widget.line.kind == 'sale' ||
                              widget.line.kind == 'purchase') &&
                          widget.gateway is LinkedReturnGateway &&
                          widget.gateway is OpeningGateway) ...[
                        const SizedBox(height: 20),
                        if (operation?['returned_by_operation_id'] is String)
                          const Text('سُجل مرتجع كامل لهذه العملية.')
                        else
                          OutlinedButton.icon(
                            key: const Key('operation-create-return'),
                            onPressed: _returnOperation,
                            icon: const Icon(Icons.assignment_return_outlined),
                            label: const Text('تسجيل مرتجع كامل'),
                          ),
                      ],
                      if (widget.gateway is InvoiceDispatchGateway &&
                          (widget.line.kind == 'sale' ||
                              widget.line.kind == 'purchase')) ...[
                        const SizedBox(height: 20),
                        Text(
                          'إرسال عبر واتساب',
                          style: theme.textTheme.titleMedium,
                        ),
                        if (_dispatchLoading) const LinearProgressIndicator(),
                        OutlinedButton.icon(
                          onPressed: _dispatchBusy || _operation == null
                              ? null
                              : _sharePdf,
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('مشاركة مستند PDF'),
                        ),
                        if (_dispatch?.ownerConfirmed == true)
                          const Text('أكد المالك الإرسال عبر واتساب')
                        else ...[
                          const Text('لم يؤكد الإرسال'),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed:
                                _dispatchLoading ||
                                    _dispatchBusy ||
                                    _dispatch == null
                                ? null
                                : _openWhatsapp,
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('فتح رسالة واتساب'),
                          ),
                          OutlinedButton.icon(
                            onPressed:
                                _dispatchBusy ||
                                    !_handoffStarted ||
                                    _dispatch == null
                                ? null
                                : _confirmWhatsappSend,
                            icon: const Icon(Icons.check),
                            label: const Text('تأكيد الإرسال بعد إرساله'),
                          ),
                        ],
                        if (_dispatchMessage != null)
                          Text(
                            _dispatchMessage!,
                            style: theme.textTheme.bodySmall,
                          ),
                        TextButton.icon(
                          onPressed: _dispatchLoading || _dispatchBusy
                              ? null
                              : _loadDispatch,
                          icon: const Icon(Icons.refresh),
                          label: const Text('تحديث حالة الإرسال'),
                        ),
                        if (_dispatch?.confirmedAt != null)
                          Text(
                            'وقت التأكيد: '
                            '${MaterialLocalizations.of(context).formatMediumDate(_dispatch!.confirmedAt!.toLocal())} '
                            '${TimeOfDay.fromDateTime(_dispatch!.confirmedAt!.toLocal()).format(context)}',
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

String? whatsappPhone(Object? value) {
  if (value is! String) return null;
  final raw = value.trim().replaceAll(RegExp(r'[\s()-]'), '');
  if (RegExp(r'^01[0-9]{9}$').hasMatch(raw)) return '20${raw.substring(1)}';
  if (RegExp(r'^\+201[0-9]{9}$').hasMatch(raw)) return raw.substring(1);
  if (RegExp(r'^201[0-9]{9}$').hasMatch(raw)) return raw;
  return null;
}

String _pounds(Object? value) {
  if (value is! String) return '—';
  final result = Piastres.parseWire(value);
  return result is Accepted<Piastres> ? result.value.poundsText : '—';
}

String _paidPounds(Object? tenders) {
  if (tenders is! List) return '—';
  var total = BigInt.zero;
  for (final raw in tenders) {
    if (raw is! Map || raw['piastres'] is! String) return '—';
    final parsed = Piastres.parseWire(raw['piastres'] as String);
    if (parsed is! Accepted<Piastres>) return '—';
    total += parsed.value.value;
  }
  return _pounds(total.toString());
}

bool _hasPositivePiastres(Object? value) {
  if (value is! String) return false;
  final parsed = Piastres.parseWire(value);
  return parsed is Accepted<Piastres> && parsed.value.value > BigInt.zero;
}

String _grams(Object? value) {
  if (value is! String) return '—';
  final result = Milligrams.parseWire(value);
  return result is Accepted<Milligrams> ? result.value.gramsText : '—';
}

String _method(Object? value) => switch (value) {
  'cash' => 'نقدي',
  'instant_transfer' => 'تحويل فوري',
  'wallet' => 'محفظة',
  'card' => 'بطاقة',
  _ => 'وسيلة دفع',
};

String _category(Object? value) => switch (value) {
  'worked_jewelry' => 'مشغولات',
  'bullion' => 'سبائك',
  'coin' => 'جنيهات ذهب',
  'scrap' => 'كسر',
  _ => 'صنف',
};
