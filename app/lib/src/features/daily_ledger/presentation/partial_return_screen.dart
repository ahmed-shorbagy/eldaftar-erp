import 'package:flutter/material.dart';

import '../application/financial_gateway.dart';
import '../application/idempotency_key.dart';
import '../application/opening_gateway.dart';
import '../application/pending_financial_command.dart';
import '../data/pending_financial_command.dart';
import '../domain/ledger_compensation.dart';
import '../domain/opening_catalog.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';
import 'ledger_form_fields.dart';
import 'financial_trade_screen.dart';
import '../domain/financial_draft.dart';
import '../../../theme/amount_format.dart';

class PartialReturnScreen extends StatefulWidget {
  const PartialReturnScreen({
    super.key,
    required this.gateway,
    required this.statusGateway,
    required this.dayGateway,
    required this.userId,
    required this.shopId,
    required this.remainder,
    this.shopBalances = const {},
    this.writesEnabled = true,
  });

  final PartialReturnGateway gateway;
  final OpeningGateway statusGateway;
  final FinancialGateway dayGateway;
  final String userId;
  final String shopId;
  final Map<String, Object?> remainder;
  final Map<String, String> shopBalances;
  final bool writesEnabled;

  @override
  State<PartialReturnScreen> createState() => _PartialReturnScreenState();
}

class _LineFields {
  _LineFields(this.item)
    : grams = TextEditingController(text: _gramsText(item.remainderMilligrams)),
      count = TextEditingController(
        text: item.scrap ? '' : '${item.remainderCount ?? ''}',
      ),
      include = true;

  final ReturnRemainderItem item;
  final TextEditingController grams;
  final TextEditingController count;
  bool include;

  void dispose() {
    grams.dispose();
    count.dispose();
  }
}

class _PartialReturnScreenState extends State<PartialReturnScreen> {
  final _consideration = TextEditingController();
  final _tender = TextEditingController();
  final _note = TextEditingController();
  final _extraTenders = {
    for (final method in CashMethod.canonicalOrder.where(
      (m) => m != CashMethod.cash,
    ))
      method.code: TextEditingController(text: '0'),
  };
  final _base = TextEditingController();
  final _work = TextEditingController();
  final _other = TextEditingController();
  final _discount = TextEditingController();
  final _otherLabel = TextEditingController();
  final _pending = const PendingFinancialCommands();
  final _lines = <_LineFields>[];
  ReturnRemainder? _bounds;
  String? _parseError;
  PartialReturnReview? _review;
  String? _dayId;
  int? _dayVersion;

  String? _key;
  String? _message;
  bool _busy = false;
  bool _unknown = false;
  bool _blocked = false;
  bool _restoring = true;

  @override
  void initState() {
    super.initState();
    final parsed = parseReturnRemainder(widget.remainder);
    if (parsed is! CompensationAccepted<ReturnRemainder>) {
      _parseError = 'تعذر قراءة الكميات المتبقية.';
    } else {
      _bounds = parsed.value;
      _otherLabel.text = parsed.value.otherChargesLabel;
      for (final item in parsed.value.items) {
        if (item.remainderMilligrams > BigInt.zero ||
            (item.remainderCount ?? BigInt.zero) > BigInt.zero) {
          _lines.add(_LineFields(item));
        }
      }
    }
    _loadPending();
  }

  Future<void> _loadPending() async {
    try {
      final existing = await _pending.read(widget.userId, widget.shopId);
      if (!mounted) return;
      setState(() {
        _restoring = false;
        if (existing == null) return;
        if (existing.kind != 'linked_return' ||
            (existing.body['p_payload'] as Map)['original_operation_id'] !=
                _bounds?.operationId) {
          _blocked = true;
          _message =
              'عملية مالية أخرى بانتظار تأكيد الخادم. ارجع إلى الدفتر للتحقق.';
          return;
        }
        _key = existing.key;
        _unknown = true;
        _message = 'طلب محفوظ. تحقق من حالته قبل إعادة الإرسال.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _restoring = false;
          _blocked = true;
          _message = 'تعذر قراءة الطلب المحفوظ. ارجع إلى الدفتر وأعد التحقق.';
        });
      }
    }
  }

  @override
  void dispose() {
    _consideration.dispose();
    _tender.dispose();
    for (final field in _extraTenders.values) {
      field.dispose();
    }
    _note.dispose();
    _base.dispose();
    _work.dispose();
    _other.dispose();
    _discount.dispose();
    _otherLabel.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> _prepareReview() async {
    final bounds = _bounds;
    if (_busy ||
        _restoring ||
        _unknown ||
        _blocked ||
        !widget.writesEnabled ||
        bounds == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final consideration = Piastres.parsePounds(_consideration.text.trim());
      final tender = Piastres.parsePounds(_tender.text.trim());
      if (consideration is! Accepted<Piastres> ||
          tender is! Accepted<Piastres>) {
        setState(() => _message = 'أدخل المقابل والنقد المتفق عليهما .');
        return;
      }
      final tenders = <String, BigInt>{};
      if (tender.value.value > BigInt.zero) {
        tenders['cash'] = tender.value.value;
      }
      for (final entry in _extraTenders.entries) {
        final parsed = Piastres.parsePounds(entry.value.text.trim());
        if (parsed is! Accepted<Piastres>) {
          setState(() => _message = 'راجع توزيع النقد المرتجع.');
          return;
        }
        if (parsed.value.value > BigInt.zero) {
          tenders[entry.key] = parsed.value.value;
        }
      }
      final lines = <ReturnLineInput>[];
      for (final field in _lines) {
        if (!field.include) continue;
        final grams = Milligrams.parseGrams(field.grams.text.trim());
        if (grams is! Accepted<Milligrams>) {
          setState(() => _message = 'أدخل وزن الصنف المختار بالجرام.');
          return;
        }
        var count = BigInt.zero;
        if (!field.item.scrap) {
          final parsed = PieceCount.parseWire(field.count.text.trim());
          if (parsed is! Accepted<PieceCount>) {
            setState(() => _message = 'أدخل عدد القطع المختارة.');
            return;
          }
          count = parsed.value.value;
        }
        lines.add(
          ReturnLineInput(
            itemIndex: field.item.itemIndex,
            category: field.item.category,
            karat: field.item.karat,
            scrap: field.item.scrap,
            milligrams: grams.value.value,
            count: count,
            remainderMilligrams: field.item.remainderMilligrams,
            remainderCount: field.item.remainderCount ?? BigInt.zero,
          ),
        );
      }
      PriceComponents? pricing;
      if (bounds.hasPricing) {
        final parts = [
          Piastres.parsePounds(_base.text.trim()),
          Piastres.parsePounds(_work.text.trim()),
          Piastres.parsePounds(_other.text.trim()),
          Piastres.parsePounds(_discount.text.trim()),
        ];
        if (parts.any((part) => part is! Accepted<Piastres>)) {
          setState(() => _message = 'أدخل مكوّنات السعر المتفق عليها.');
          return;
        }
        final remainders = bounds.pricingRemainder ?? const {};
        pricing = PriceComponents(
          base: (parts[0] as Accepted<Piastres>).value.value,
          workmanship: (parts[1] as Accepted<Piastres>).value.value,
          otherCharges: (parts[2] as Accepted<Piastres>).value.value,
          discount: (parts[3] as Accepted<Piastres>).value.value,
          otherChargesLabel: _otherLabel.text,
          remainderBase: remainders['base_piastres'] ?? BigInt.zero,
          remainderWorkmanship:
              remainders['workmanship_piastres'] ?? BigInt.zero,
          remainderOtherCharges:
              remainders['other_charges_piastres'] ?? BigInt.zero,
          remainderDiscount: remainders['discount_piastres'] ?? BigInt.zero,
        );
      }
      final reviewed = reviewPartialReturn(
        kind: bounds.kind == 'purchase' ? 'purchase_return' : 'sale_return',
        consideration: consideration.value.value,
        remainderConsideration: bounds.remainderConsideration,
        payableRemaining: bounds.payableRemaining,
        quantityRemains: bounds.quantityRemains,
        lines: lines,
        tenders: tenders,
        refundableByMethod: bounds.refundableByMethod,
        shopBalances: widget.shopBalances.isEmpty
            ? null
            : {
                for (final entry in widget.shopBalances.entries)
                  entry.key: _amount(entry.value),
              },
        pricingRequired: bounds.hasPricing,
        pricing: pricing,
      );
      if (reviewed is! CompensationAccepted<PartialReturnReview>) {
        setState(() {
          _review = null;
          _message = _copy(
            (reviewed as CompensationRejected<PartialReturnReview>).code,
          );
        });
        return;
      }
      try {
        final day = await widget.dayGateway.dayState(
          callerUserId: widget.userId,
        );
        if (!mounted) return;
        if (!day.isOpen || day.dayId == null || day.dayVersion == null) {
          setState(() => _message = 'افتح يوم عمل قبل تسجيل المرتجع.');
          return;
        }
        setState(() {
          _review = reviewed.value;
          _dayId = day.dayId;
          _dayVersion = day.dayVersion;
          _message = null;
        });
      } catch (_) {
        if (mounted) setState(() => _message = 'تعذر قراءة يوم العمل.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, Object?> _payload(PartialReturnReview review) {
    final payload = <String, Object?>{
      'version': 1,
      'kind': review.kind,
      'original_operation_id': _bounds!.operationId,
      'expected_day_id': _dayId,
      'expected_day_version': '$_dayVersion',
      'note': _note.text.trim(),
      'items': [
        for (final line in review.lines)
          {
            'item_index': '${line.itemIndex}',
            'milligrams': line.milligrams.toString(),
            if (!line.scrap) 'count': line.count.toString(),
          },
      ],
      'consideration_piastres': review.consideration.toString(),
      'tenders': [
        for (final entry in review.tenders.entries)
          {'method': entry.key, 'piastres': entry.value.toString()},
      ],
    };
    final pricing = review.pricing;
    if (pricing != null) {
      payload['pricing'] = {
        'base_piastres': pricing.base.toString(),
        'workmanship_piastres': pricing.workmanship.toString(),
        'other_charges_piastres': pricing.otherCharges.toString(),
        'other_charges_label': pricing.otherChargesLabel.trim(),
        'discount_piastres': pricing.discount.toString(),
      };
    }
    return payload;
  }

  bool _isFullRemaining(PartialReturnReview review) {
    final bounds = _bounds!;
    if (review.consideration != bounds.remainderConsideration) return false;
    final remaining = bounds.items
        .where(
          (item) =>
              item.remainderMilligrams > BigInt.zero ||
              (item.remainderCount ?? BigInt.zero) > BigInt.zero,
        )
        .toList();
    if (remaining.length != review.lines.length) return false;
    return remaining.every(
      (item) => review.lines.any(
        (line) =>
            line.itemIndex == item.itemIndex &&
            line.milligrams == item.remainderMilligrams &&
            (item.scrap || line.count == item.remainderCount),
      ),
    );
  }

  void _fillRemaining() {
    final bounds = _bounds!;
    setState(() {
      _consideration.text = signedPoundsText(bounds.remainderConsideration);
      for (final field in _lines) {
        field.include = true;
        field.grams.text = signedGramsText(field.item.remainderMilligrams);
        if (!field.item.scrap) {
          field.count.text = '${field.item.remainderCount}';
        }
      }
      if (bounds.hasPricing) {
        _base.text = signedPoundsText(
          bounds.pricingRemainder!['base_piastres']!,
        );
        _work.text = signedPoundsText(
          bounds.pricingRemainder!['workmanship_piastres']!,
        );
        _other.text = signedPoundsText(
          bounds.pricingRemainder!['other_charges_piastres']!,
        );
        _discount.text = signedPoundsText(
          bounds.pricingRemainder!['discount_piastres']!,
        );
      }
      _message = 'أدخل توزيع النقد المرتجع ثم راجع كامل المتبقي.';
    });
  }

  Future<void> _exchange() async {
    final review = _review;
    if (review == null || _busy || _unknown || _key != null) return;
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FinancialTradeScreen(
          kind: review.kind == 'sale_return'
              ? FinancialKind.sale
              : FinancialKind.purchase,
          gateway: widget.dayGateway,
          statusGateway: widget.statusGateway,
          userId: widget.userId,
          shopId: widget.shopId,
          exchangeReturnPayload: _payload(review),
          exchangeReturnReview: review,
        ),
      ),
    );
    if (mounted && saved == true) Navigator.pop(context, true);
  }

  Future<void> _submit() async {
    final review = _review;
    if (_busy || review == null || _dayId == null) return;
    final key = _key ?? newIdempotencyKey();
    final payload = _payload(review);
    var saved = false;
    setState(() {
      _busy = true;
      _key = key;
      _message = 'بانتظار تأكيد الخادم';
    });
    try {
      await _pending.save(
        widget.userId,
        widget.shopId,
        PendingFinancialCommand(
          key: key,
          kind: 'linked_return',
          body: {'p_idempotency_key': key, 'p_payload': payload},
        ),
      );
      saved = true;
      final result = await widget.gateway.postPartialReturn(
        callerUserId: widget.userId,
        idempotencyKey: key,
        payload: payload,
      );
      if (!mounted) return;
      await _apply(result, key);
    } catch (_) {
      if (!mounted) return;
      if (!saved) {
        setState(() {
          _key = null;
          _message = 'تعذر حفظ طلب المرتجع.';
        });
        return;
      }
      await _readStatus(key, retryIfAbsent: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconcile() async {
    final key = _key;
    if (key == null) return;
    setState(() => _busy = true);
    try {
      await _readStatus(key, retryIfAbsent: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _readStatus(String key, {required bool retryIfAbsent}) async {
    try {
      final status = await widget.statusGateway.status(
        callerUserId: widget.userId,
        idempotencyKey: key,
      );
      if (!mounted) return;
      if (status is StatusCompleted) {
        await _pending.clear(widget.userId, widget.shopId, key);
        if (mounted) Navigator.pop(context, true);
        return;
      }
      if (status is StatusAbsent && retryIfAbsent) {
        final command = await _pending.read(widget.userId, widget.shopId);
        if (!mounted || command == null || command.key != key) return;
        final result = await widget.dayGateway.retryPending(
          callerUserId: widget.userId,
          command: command,
        );
        if (!mounted) return;
        await _apply(result, key);
        return;
      }
      setState(() {
        _unknown = true;
        _message = status is StatusAbsent
            ? 'لم يؤكد الخادم المرتجع. أعد المحاولة بالمفتاح نفسه.'
            : 'حالة المرتجع غير معروفة. أعد التحقق.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _unknown = true;
          _message = 'تعذر التحقق من المرتجع. أعد المحاولة.';
        });
      }
    }
  }

  Future<void> _apply(FinancialCommandResult result, String key) async {
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
        _review = null;
        _unknown = false;
        _message = _copy(result.code);
      });
      return;
    }
    await _readStatus(key, retryIfAbsent: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bounds = _bounds;
    final review = _review;
    final locked =
        review != null ||
        _unknown ||
        _blocked ||
        _busy ||
        _restoring ||
        !widget.writesEnabled;
    final purchase = bounds?.kind == 'purchase';
    return PopScope(
      canPop: !_busy && !_unknown,
      child: Scaffold(
        appBar: AppBar(title: Text(purchase ? 'مرتجع شراء' : 'مرتجع بيع')),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('مرتجع مرتبط', style: theme.textTheme.headlineSmall),
                  if (bounds != null)
                    OutlinedButton(
                      onPressed: locked ? null : _fillRemaining,
                      child: const Text('إرجاع كامل المتبقي'),
                    ),
                  const Text(
                    'المقابل يكتبه المالك كما اتُفق عليه. العملية الأصلية تبقى دون تعديل.',
                  ),
                  if (!widget.writesEnabled)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('الاشتراك منتهٍ. العرض للقراءة فقط.'),
                    ),
                  if (_parseError != null) Text(_parseError!),
                  if (_message != null)
                    Text(
                      _message!,
                      key: const Key('partial-message'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  if (bounds != null) ...[
                    Text(
                      'المتبقي من المقابل: ${displayPounds(signedPoundsText(bounds.remainderConsideration))}',
                    ),
                    if (purchase)
                      Text(
                        'المستحق للبائع: ${displayPounds(signedPoundsText(bounds.payableRemaining))}',
                      ),
                    for (var index = 0; index < _lines.length; index++) ...[
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        value: _lines[index].include,
                        onChanged: locked
                            ? null
                            : (value) => setState(
                                () => _lines[index].include = value ?? false,
                              ),
                        title: Text(_lines[index].item.itemName),
                        contentPadding: EdgeInsets.zero,
                      ),
                      Text(
                        '${_lines[index].item.itemName} · عيار ${_lines[index].item.karat} · المتبقي ${_gramsText(_lines[index].item.remainderMilligrams)} جرام',
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: Key('partial-grams-$index'),
                        controller: _lines[index].grams,
                        readOnly: locked,
                        textDirection: TextDirection.ltr,
                        decoration: ledgerFieldDecoration(
                          context,
                          label: 'الوزن المرتجع بالجرام',
                        ),
                      ),
                      if (!_lines[index].item.scrap) ...[
                        const SizedBox(height: 8),
                        TextField(
                          key: Key('partial-count-$index'),
                          controller: _lines[index].count,
                          readOnly: locked,
                          textDirection: TextDirection.ltr,
                          decoration: ledgerFieldDecoration(
                            context,
                            label: 'عدد القطع المرتجعة',
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('partial-consideration'),
                      controller: _consideration,
                      readOnly: locked,
                      textDirection: TextDirection.ltr,
                      decoration: ledgerFieldDecoration(
                        context,
                        label: 'المقابل المتفق عليه ',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'وزّع النقد المرتجع صراحة على وسائل الدفع. أدخل صفرًا عند إلغاء المستحق فقط.',
                    ),
                    for (final method in CashMethod.canonicalOrder) ...[
                      const SizedBox(height: 8),
                      TextField(
                        key: Key(
                          method == CashMethod.cash
                              ? 'partial-tender'
                              : 'partial-tender-${method.code}',
                        ),
                        controller: method == CashMethod.cash
                            ? _tender
                            : _extraTenders[method.code],
                        readOnly: locked,
                        textDirection: TextDirection.ltr,
                        decoration: ledgerFieldDecoration(
                          context,
                          label: 'النقد المرتجع · ${_methodLabel(method.code)}',
                        ),
                      ),
                    ],
                    if (bounds.hasPricing) ...[
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('partial-base'),
                        controller: _base,
                        readOnly: locked,
                        textDirection: TextDirection.ltr,
                        decoration: ledgerFieldDecoration(
                          context,
                          label: 'السعر الأساسي المرتجع',
                        ),
                      ),
                      TextField(
                        key: const Key('partial-work'),
                        controller: _work,
                        readOnly: locked,
                        textDirection: TextDirection.ltr,
                        decoration: ledgerFieldDecoration(
                          context,
                          label: 'المصنعية المرتجعة',
                        ),
                      ),
                      TextField(
                        key: const Key('partial-other'),
                        controller: _other,
                        readOnly: locked,
                        textDirection: TextDirection.ltr,
                        decoration: ledgerFieldDecoration(
                          context,
                          label: 'الرسوم الأخرى المرتجعة',
                        ),
                      ),
                      TextField(
                        key: const Key('partial-discount'),
                        controller: _discount,
                        readOnly: locked,
                        textDirection: TextDirection.ltr,
                        decoration: ledgerFieldDecoration(
                          context,
                          label: 'الخصم المرتجع',
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('partial-note'),
                      controller: _note,
                      readOnly: locked,
                      maxLength: 1000,
                      decoration: ledgerFieldDecoration(
                        context,
                        label: 'ملاحظة',
                      ),
                    ),
                  ],
                  if (review != null)
                    Card(
                      color: theme.colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'المقابل: ${displayPounds(signedPoundsText(review.consideration))}',
                            ),
                            if (purchase) ...[
                              Text(
                                'يُلغى من المستحق: ${displayPounds(signedPoundsText(review.cancelledPayable))}',
                              ),
                              Text(
                                'نقد من البائع: ${displayPounds(signedPoundsText(review.cashRefund))}',
                              ),
                            ] else
                              Text(
                                'نقد للعميل: ${displayPounds(signedPoundsText(review.cashRefund))}',
                              ),
                            for (final line in review.lines)
                              Text(
                                '${line.category == 'scrap' ? 'الكسر' : 'المخزون'} عيار ${line.karat}: ${signedGramsText(review.kind == 'sale_return' ? line.milligrams : -line.milligrams)} جرام${line.scrap ? '' : ' · ${review.kind == 'sale_return' ? line.count : -line.count} قطعة'}',
                              ),
                            for (final entry in review.tenders.entries)
                              Text(
                                '${_methodLabel(entry.key)}: ${_signedCashLabel(review.kind == 'sale_return' ? -entry.value : entry.value)}',
                              ),
                            TextButton(
                              onPressed: _busy || _unknown || _key != null
                                  ? null
                                  : () => setState(() => _review = null),
                              child: const Text('رجوع للتعديل'),
                            ),
                            if (widget.dayGateway is ExchangeGateway)
                              OutlinedButton(
                                key: const Key('partial-exchange'),
                                onPressed: _busy || _unknown || _key != null
                                    ? null
                                    : _exchange,
                                child: const Text(
                                  'إضافة البديل ومراجعة الاستبدال',
                                ),
                              ),
                            const Text(
                              'المقابل متفق عليه صراحة وليس نسبة من الوزن.',
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
        bottomNavigationBar: widget.writesEnabled && !_blocked && bounds != null
            ? SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton(
                    key: Key(
                      _unknown
                          ? 'partial-check-status'
                          : review == null
                          ? 'partial-review'
                          : 'partial-confirm',
                    ),
                    onPressed: _busy
                        ? null
                        : _unknown
                        ? _reconcile
                        : review == null
                        ? _prepareReview
                        : _submit,
                    child: Text(
                      _busy
                          ? 'بانتظار تأكيد الخادم'
                          : _unknown
                          ? 'التحقق من الحالة'
                          : review == null
                          ? 'مراجعة المرتجع'
                          : _isFullRemaining(review)
                          ? 'تأكيد مرتجع المتبقي بالكامل'
                          : 'تأكيد المرتجع الجزئي',
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

String _gramsText(BigInt milligrams) => signedGramsText(milligrams);

BigInt _amount(String wire) => BigInt.tryParse(wire) ?? BigInt.zero;

String _methodLabel(String code) => switch (code) {
  'cash' => 'نقدي',
  'instant_transfer' => 'تحويل فوري',
  'wallet' => 'محفظة',
  'card' => 'بطاقة',
  _ => code,
};

String _copy(String code) => switch (code) {
  'stale_day' ||
  'stale_version' => 'تغيّرت الأرصدة أو يوم العمل. حدّث الدفتر وأعد المراجعة.',
  'return_exceeds_original' =>
    'الكمية أو المقابل يتجاوز المتبقي من العملية الأصلية.',
  'stock_pair_mismatch' => 'الوزن والعدد يجب أن يتحرّكا معًا للقطع.',
  'tender_mismatch' => 'وسائل الدفع لا تطابق النقد المتفق عليه.',
  'pricing_mismatch' => 'مكوّنات السعر لا تساوي المقابل المتفق عليه.',
  'negative_owned_balance' => 'رصيد المتجر لا يكفي لهذا المرتجع.',
  'already_returned' => 'سُجل مرتجع لهذه العملية بالفعل.',
  _ => 'راجع الحقول ثم أعد المراجعة.',
};

String _signedCashLabel(BigInt value) =>
    '\u2066${displayPounds(signedPoundsText(value))}\u2069';
