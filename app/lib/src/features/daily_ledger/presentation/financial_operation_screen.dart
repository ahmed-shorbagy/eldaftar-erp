import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../../theme/amount_format.dart';
import '../../invoice_message/application/message_gateway.dart';
import '../../invoice_message/data/url_message_launcher.dart';
import '../../invoice_message/domain/message_template.dart';

import '../../invoice_appearance/application/invoice_appearance_gateway.dart';
import '../../invoice_appearance/presentation/invoice_copy_panel.dart';
import 'invoice_pdf_share_dialog.dart';
import '../application/financial_gateway.dart';
import '../application/daily_ledger_view.dart';
import '../application/opening_gateway.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';
import 'opening_copy.dart';
import 'purchase_cash_settlement_screen.dart';
import '../application/ledger_trade_change.dart';
import '../domain/financial_draft.dart';
import 'financial_trade_screen.dart';
import 'ledger_trade_change_screen.dart';
import 'exchange_effect_review.dart';

class FinancialOperationScreen extends StatefulWidget {
  const FinancialOperationScreen({
    super.key,
    required this.gateway,
    required this.userId,
    required this.line,
    this.syncTicks,
    this.shopId,
    this.canRead,
    this.canWrite,
    this.messageLauncher = const UrlMessageLauncher(),
    this.pdfShare,
  });

  final FinancialGateway gateway;
  final String userId;
  final LedgerFeedLine line;
  final Listenable? syncTicks;
  final String? shopId;
  final bool Function()? canRead;
  final bool Function()? canWrite;
  final MessageLauncher messageLauncher;
  final Future<bool> Function(Uint8List bytes, String filename)? pdfShare;

  @override
  State<FinancialOperationScreen> createState() =>
      _FinancialOperationScreenState();
}

class _FinancialOperationScreenState extends State<FinancialOperationScreen> {
  Map<String, Object?>? _operation;
  bool _loading = true;
  bool _syncQueued = false;
  bool _failed = false;
  bool _accessLost = false;
  InvoiceDispatchState? _dispatch;
  bool _dispatchLoading = false;
  bool _dispatchBusy = false;
  String? _dispatchMessage;

  String get _copyKind {
    final loaded = _operation?['kind'];
    return loaded is String ? loaded : widget.line.kind;
  }

  @override
  void initState() {
    super.initState();
    widget.syncTicks?.addListener(_onSync);
    _load();
  }

  @override
  void didUpdateWidget(covariant FinancialOperationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncTicks != widget.syncTicks) {
      oldWidget.syncTicks?.removeListener(_onSync);
      widget.syncTicks?.addListener(_onSync);
    }
  }

  void _onSync() {
    if (!mounted || _dispatchBusy) return;
    if (_loading) {
      _syncQueued = true;
      return;
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.syncTicks?.removeListener(_onSync);
    super.dispose();
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
      setState(() {
        _operation = value;
        _accessLost = false;
      });
      if (widget.gateway is InvoiceDispatchGateway &&
          (widget.line.kind == 'sale' || widget.line.kind == 'purchase')) {
        await _loadDispatch();
      }
    } catch (error) {
      if (mounted &&
          error is LedgerReadException &&
          const {
            'forbidden',
            'unauthenticated',
            'session_expired',
            'shop_unavailable',
          }.contains(error.code)) {
        setState(() {
          _operation = null;
          _dispatch = null;
          _accessLost = true;
        });
      } else if (mounted && _operation == null) {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_syncQueued) {
          _syncQueued = false;
          unawaited(_load());
        }
      }
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
      });
    } catch (_) {
      if (mounted) {
        setState(() => _dispatchMessage = 'تعذر تحديث حالة إرسال الفاتورة');
      }
    } finally {
      if (mounted) setState(() => _dispatchLoading = false);
    }
  }

  Future<void> _sharePdf() async {
    final shop = widget.shopId ?? _operation?['shop_id'];
    if (_dispatchBusy || shop is! String || _operation == null) return;
    setState(() => _dispatchBusy = true);
    try {
      final confirmed = await showInvoicePdfShareDialog(
        context: context,
        gateway: widget.gateway,
        userId: widget.userId,
        shopId: shop,
        operationId: widget.line.operationId,
        canRead: () =>
            mounted && !_accessLost && widget.canRead?.call() != false,
        canWrite: () => mounted && widget.canWrite?.call() != false,
        invalidations: widget.syncTicks,
        share: widget.pdfShare,
      );
      if (confirmed == true && mounted) await _loadDispatch();
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

  bool _changeBusy = false;
  String? _changeError;
  bool get _active => _operation?['trade_change'] == null;

  Future<bool> _reviewChange(
    String action, {
    Map<String, Object?>? replacement,
  }) async {
    final gateway = widget.gateway;
    final shop = widget.shopId ?? _operation?['shop_id'];
    if (gateway is! LedgerTradeChangeGateway ||
        gateway is! OpeningGateway ||
        shop is! String ||
        widget.canRead?.call() == false ||
        widget.canWrite?.call() == false) {
      return false;
    }
    try {
      final review = await (gateway as LedgerTradeChangeGateway)
          .reviewTradeChange(
            userId: widget.userId,
            shopId: shop,
            operationId: widget.line.operationId,
            action: action,
            replacement: replacement,
          );
      if (!mounted ||
          widget.canRead?.call() == false ||
          widget.canWrite?.call() == false) {
        return false;
      }
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => LedgerTradeChangeScreen(
            review: review,
            gateway: gateway as LedgerTradeChangeGateway,
            statusGateway: gateway as OpeningGateway,
            userId: widget.userId,
            replacement: replacement,
            syncTicks: widget.syncTicks,
            canRead: () =>
                mounted && !_accessLost && widget.canRead?.call() != false,
            canWrite: () => mounted && widget.canWrite?.call() != false,
          ),
        ),
      );
      if (saved != true && mounted) await _load();
      return saved == true;
    } catch (e) {
      if (mounted) {
        final message = tradeChangeFailure(
          e is LedgerReadException ? e.code : null,
        );
        setState(() {
          _changeError = message;
          if (e is LedgerReadException &&
              const {
                'forbidden',
                'unauthenticated',
                'session_expired',
                'shop_unavailable',
              }.contains(e.code)) {
            _accessLost = true;
          }
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
      return false;
    }
  }

  Future<void> _changeTrade(String action) async {
    if (_changeBusy || !_active || _loading) return;
    setState(() {
      _changeBusy = true;
      _changeError = null;
    });
    try {
      bool saved;
      if (action == 'edit') {
        final gateway = widget.gateway;
        final shop = widget.shopId ?? _operation?['shop_id'];
        if (gateway is! LedgerTradeChangeGateway ||
            gateway is! OpeningGateway ||
            shop is! String) {
          return;
        }
        final source = await (gateway as LedgerTradeChangeGateway)
            .reviewTradeChange(
              userId: widget.userId,
              shopId: shop,
              operationId: widget.line.operationId,
              action: 'edit',
              replacement: {
                ...Map<String, Object?>.from(_operation!['payload'] as Map),
                if ((_operation!['payload'] as Map)['tenders'] == null)
                  'tenders': <Object?>[],
              },
            );
        if (!mounted ||
            widget.canRead?.call() == false ||
            widget.canWrite?.call() == false) {
          return;
        }
        saved =
            await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => FinancialTradeScreen(
                  kind: source.source['kind'] == 'sale'
                      ? FinancialKind.sale
                      : FinancialKind.purchase,
                  gateway: widget.gateway,
                  statusGateway: gateway as OpeningGateway,
                  userId: widget.userId,
                  shopId: shop,
                  initialPayload: Map<String, Object?>.from(
                    source.source['payload'] as Map,
                  ),
                  canRead: () =>
                      mounted &&
                      !_accessLost &&
                      widget.canRead?.call() != false,
                  canWrite: () => mounted && widget.canWrite?.call() != false,
                  syncTicks: widget.syncTicks,
                  onDraftReviewed: (draft) =>
                      _reviewChange('edit', replacement: draft.toJson()),
                ),
              ),
            ) ==
            true;
      } else {
        saved = await _reviewChange('delete');
      }
      if (saved && mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        if (e is LedgerReadException &&
            const {
              'forbidden',
              'unauthenticated',
              'session_expired',
              'shop_unavailable',
            }.contains(e.code)) {
          _accessLost = true;
          _operation = null;
          _dispatch = null;
        }
        setState(
          () => _changeError = tradeChangeFailure(
            e is LedgerReadException ? e.code : null,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _changeBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_accessLost || widget.canRead?.call() == false) {
      return Scaffold(
        appBar: AppBar(title: const Text('تفاصيل العملية')),
        body: const Center(
          child: Text('لم تعد بيانات العملية متاحة لهذا الحساب.'),
        ),
      );
    }
    final operation = _operation;
    final payload = operation?['payload'];
    final details = payload is Map ? payload : const <String, Object?>{};
    final sequence = operation?['shop_sequence'];
    final items = details['items'];
    final tenders = details['tenders'];
    final pricing = details['pricing'];
    return Scaffold(
      appBar: AppBar(title: Text(widget.line.labelAr)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _loading && _operation == null
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
                        'اسم البائع: ${operation?['actor_display_name'] ?? widget.line.actorDisplayName}',
                      ),
                      Text(
                        'الوقت: ${formatShopTwelveHourTime(widget.line.displayTime)}',
                        key: const Key('operation-time'),
                      ),
                      ..._customerBlock(details),
                      ..._notesBlock(theme, details, widget.line.hasNote),
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
                                  'sale' ||
                                  'scrap_sale' ||
                                  'repair_fee' => 'النقد المحصّل',
                                  'purchase' => 'سعر الشراء الكلي',
                                  'sale_return' || 'purchase_return' =>
                                    details['consideration_piastres'] is String
                                        ? 'المقابل المرتجع المتفق عليه'
                                        : 'قيمة العملية الأصلية',
                                  _ => 'النقد المدفوع',
                                }),
                                Text(
                                  _pounds(details['total_piastres']),
                                  textDirection: TextDirection.ltr,
                                  style: theme.textTheme.headlineSmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (widget.line.kind == 'repair_fee') ...[
                        Text('القطعة: ${details['description'] ?? ''}'),
                        Text(
                          'الأجرة النهائية: ${_pounds(details['final_fee_piastres'])}',
                        ),
                        Text(
                          'المتبقي: ${_pounds(details['outstanding_piastres'])}',
                        ),
                      ],
                      if (operation?['exchange_effects'] is Map)
                        ConfirmedCompensationEffects(
                          effects: Map<String, Object?>.from(
                            operation!['exchange_effects'] as Map,
                          ),
                          exchange: true,
                        ),
                      if (operation?['correction_effects'] is Map) ...[
                        Text('سبب التسوية: ${details['reason'] ?? ''}'),
                        ConfirmedCompensationEffects(
                          effects: Map<String, Object?>.from(
                            operation!['correction_effects'] as Map,
                          ),
                          exchange: false,
                        ),
                      ],
                      if (pricing is Map) ...[
                        Text(
                          'السعر الأساسي: ${_pounds(pricing['base_piastres'])}',
                        ),
                        Text(
                          'المصنعية: ${_pounds(pricing['workmanship_piastres'])}',
                        ),
                        Text(
                          'الرسوم الأخرى (${pricing['other_charges_label'] ?? ''}): ${_pounds(pricing['other_charges_piastres'])}',
                        ),
                        Text('الخصم: ${_pounds(pricing['discount_piastres'])}'),
                        const SizedBox(height: 12),
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
                                  'تحويل ${_pounds(details['amount_piastres'])}',
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
                        Text('المدفوع عند الشراء: ${_paidPounds(tenders)}'),
                        if (operation?['purchase_payable_remaining_piastres']
                            is String)
                          Text(
                            'المستحق للبائع الآن: ${_pounds(operation?['purchase_payable_remaining_piastres'])}',
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
                          'النقد المرتجع: ${_pounds(details['cash_returned_piastres'])}',
                        ),
                        Text(
                          'مرتبطة بالعملية رقم ${details['original_sequence'] ?? '—'}',
                        ),
                        if (_hasPositivePiastres(
                          details['cancelled_payable_piastres'],
                        ))
                          Text(
                            'المستحق الملغى: ${_pounds(details['cancelled_payable_piastres'])}',
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
                                        'سعر الصنف: ${_pounds(entry['line_price_piastres'])}',
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
                              trailing: Text(_pounds(entry['piastres'])),
                            ),
                      ],
                      if (details['description'] is String &&
                          (details['description'] as String).isNotEmpty)
                        Text('الوصف: ${details['description']}'),
                      if (!_active)
                        const Text(
                          'هذه العملية ممسوحة أو مستبدلة؛ سجل التدقيق محفوظ.',
                        ),
                      if (_active &&
                          (widget.line.kind == 'sale' ||
                              widget.line.kind == 'purchase') &&
                          widget.gateway is LedgerTradeChangeGateway &&
                          widget.gateway is OpeningGateway &&
                          widget.canWrite?.call() != false) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'التعديل والمسح لعمليات اليوم المفتوح فقط، دون معاملات لاحقة مرتبطة. تُراجع آثار النقد والمخزون قبل التأكيد.',
                        ),
                        if (_changeBusy) const LinearProgressIndicator(),
                        OutlinedButton.icon(
                          key: const Key('operation-edit'),
                          onPressed: _changeBusy || _loading
                              ? null
                              : () => _changeTrade('edit'),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('تعديل'),
                        ),
                        OutlinedButton.icon(
                          key: const Key('operation-delete'),
                          onPressed: _changeBusy || _loading
                              ? null
                              : () => _changeTrade('delete'),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('مسح العملية'),
                        ),
                        if (_changeError != null)
                          Text(
                            _changeError!,
                            key: const Key('operation-change-error'),
                          ),
                      ],
                      if (_active &&
                          (_copyKind == 'sale' || _copyKind == 'purchase'))
                        InvoiceCopyPanel(
                          operations: widget.gateway,
                          appearance: widget.gateway is InvoiceAppearanceGateway
                              ? widget.gateway as InvoiceAppearanceGateway
                              : null,
                          userId: widget.userId,
                          shopId:
                              widget.shopId ??
                              (_operation?['shop_id'] as String?),
                          operationId: widget.line.operationId,
                          kind: _copyKind,
                          operation: _operation,
                          canRead: widget.canRead ?? () => true,
                          canWrite: widget.canWrite ?? () => true,
                          syncTicks: widget.syncTicks,
                        ),
                      if (_active &&
                          widget.gateway is InvoiceDispatchGateway &&
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

  List<Widget> _customerBlock(Map details) {
    final name = details['customer_name'] is String
        ? (details['customer_name'] as String).trim()
        : '';
    final phone = details['customer_phone'] is String
        ? (details['customer_phone'] as String).trim()
        : '';
    if (name.isEmpty && phone.isEmpty) {
      return const [
        Text('لا توجد بيانات عميل', key: Key('operation-customer-absent')),
      ];
    }
    return [
      Text(
        name.isEmpty ? 'اسم العميل: لا يوجد اسم' : 'اسم العميل: $name',
        key: const Key('operation-customer-name'),
      ),
      Text(
        phone.isEmpty ? 'الجوال: لا يوجد رقم' : 'الجوال: \u2066$phone\u2069',
        key: const Key('operation-customer-phone'),
      ),
    ];
  }

  List<Widget> _notesBlock(ThemeData theme, Map details, bool feedHasNote) {
    final note = details['note'] is String
        ? (details['note'] as String).trim()
        : '';
    final present = note.isNotEmpty || feedHasNote;
    return [
      Text(
        present ? 'توجد ملاحظات' : 'لا توجد ملاحظات',
        key: const Key('operation-notes-flag'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
      if (present)
        ExpansionTile(
          key: const Key('operation-notes'),
          tilePadding: EdgeInsets.zero,
          title: const Text('عرض الملاحظات'),
          children: [
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                note.isEmpty ? 'لا يظهر نص الملاحظة في هذا الاتصال.' : note,
              ),
            ),
          ],
        ),
    ];
  }
}

String? whatsappPhone(Object? value) {
  return messageEgyptianPhone(value);
}

String _pounds(Object? value) {
  if (value is! String) return '—';
  final result = Piastres.parseWire(value);
  return result is Accepted<Piastres>
      ? displayPounds(result.value.poundsText)
      : '—';
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
  return result is Accepted<Milligrams>
      ? displayGrams(result.value.gramsText)
      : '—';
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
