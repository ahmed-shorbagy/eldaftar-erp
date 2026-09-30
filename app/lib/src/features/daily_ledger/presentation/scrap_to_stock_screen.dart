import 'package:flutter/material.dart';

import '../application/daily_ledger_view.dart';
import '../application/financial_gateway.dart';
import '../application/idempotency_key.dart';
import '../application/opening_gateway.dart';
import '../application/pending_financial_command.dart';
import '../data/pending_financial_command.dart';
import '../domain/opening_catalog.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';
import 'ledger_form_fields.dart';
import 'opening_copy.dart';

class ScrapToStockScreen extends StatefulWidget {
  const ScrapToStockScreen({
    super.key,
    required this.gateway,
    required this.statusGateway,
    required this.userId,
    required this.shopId,
    required this.scrap,
  });

  final ScrapToStockGateway gateway;
  final OpeningGateway statusGateway;
  final String userId;
  final String shopId;
  final List<LedgerScrapLine> scrap;

  @override
  State<ScrapToStockScreen> createState() => _ScrapToStockScreenState();
}

class _ScrapToStockScreenState extends State<ScrapToStockScreen> {
  final _grams = TextEditingController();
  final _count = TextEditingController(text: '1');
  final _name = TextEditingController();
  final _note = TextEditingController();
  final _pending = const PendingFinancialCommands();
  late int _karat;
  late StockCategory _category;
  Milligrams? _reviewWeight;
  PieceCount? _reviewCount;
  String? _key;
  String? _message;
  bool _busy = false;
  bool _unknown = false;

  List<int> get _availableKarats => [
    for (final line in widget.scrap)
      if (_wireWeight(line) > BigInt.zero) line.karat,
  ]..sort();

  List<StockCategory> get _categories => [
    for (final category in StockCategory.canonicalOrder)
      if (category.allowsKarat(_karat)) category,
  ];

  @override
  void initState() {
    super.initState();
    _karat = _availableKarats.isEmpty ? 21 : _availableKarats.first;
    _category = _categories.first;
  }

  @override
  void dispose() {
    _grams.dispose();
    _count.dispose();
    _name.dispose();
    _note.dispose();
    super.dispose();
  }

  BigInt _availableWeight(int karat) {
    for (final line in widget.scrap) {
      if (line.karat == karat) return _wireWeight(line);
    }
    return BigInt.zero;
  }

  void _startReview() {
    final weight = Milligrams.parseGrams(_grams.text.trim());
    final count = PieceCount.parseWire(_count.text.trim());
    if (weight is! Accepted<Milligrams> ||
        count is! Accepted<PieceCount> ||
        weight.value.value == BigInt.zero ||
        count.value.value == BigInt.zero ||
        weight.value.value > _availableWeight(_karat) ||
        _name.text.trim().isEmpty ||
        _name.text.trim().length > 120 ||
        _note.text.trim().length > 1000) {
      setState(() => _message = 'راجع الوزن المتاح والعدد واسم الصنف.');
      return;
    }
    setState(() {
      _reviewWeight = weight.value;
      _reviewCount = count.value;
      _message = null;
    });
  }

  Map<String, Object?> _payload() => {
    'version': 1,
    'kind': 'scrap_to_stock',
    'category': _category.code,
    'karat': _karat,
    'milligrams': _reviewWeight!.wire,
    'count': _reviewCount!.wire,
    'item_name': _name.text.trim(),
    'note': _note.text.trim(),
  };

  Future<void> _submit() async {
    if (_reviewWeight == null || _reviewCount == null || _busy) return;
    final key = _key ?? newIdempotencyKey();
    final payload = _payload();
    var saved = false;
    setState(() {
      _busy = true;
      _key = key;
      _message = 'جارٍ تأكيد التحويل على الخادم...';
    });
    try {
      final command = PendingFinancialCommand(
        key: key,
        kind: 'scrap_to_stock',
        body: {'p_idempotency_key': key, 'p_payload': payload},
      );
      await _pending.save(widget.userId, widget.shopId, command);
      saved = true;
      final result = await widget.gateway.convertScrapToStock(
        callerUserId: widget.userId,
        idempotencyKey: key,
        payload: payload,
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
          _message =
              result.code == 'negative_owned_balance' ||
                  result.code == 'insufficient_stock'
              ? 'تغير رصيد الكسر. حدّث الدفتر وراجع الوزن.'
              : 'رفض الخادم التحويل. راجع البيانات.';
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
              ? 'حالة التحويل غير معروفة. تحقق قبل المتابعة.'
              : 'تعذر حفظ الطلب. راجع أي عملية معلقة.';
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
    final reviewing = _reviewWeight != null;
    return PopScope(
      canPop: !_busy && !_unknown,
      child: Scaffold(
        appBar: AppBar(title: const Text('تحويل كسر إلى مخزون')),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'تحويل داخلي للذهب',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const Text(
                    'يخرج نفس العيار والوزن من الكسر ويدخل المخزون دون أثر نقدي.',
                  ),
                  const SizedBox(height: 20),
                  if (_message != null) ...[
                    Text(
                      _message!,
                      key: const Key('scrap-stock-message'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: _unknown
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (!reviewing) ...[
                    DropdownButtonFormField<int>(
                      key: const Key('scrap-stock-karat'),
                      initialValue: _karat,
                      isExpanded: true,
                      decoration: ledgerFieldDecoration(
                        context,
                        label: 'عيار الكسر',
                      ),
                      items: [
                        for (final karat in _availableKarats)
                          DropdownMenuItem(
                            value: karat,
                            child: Text('عيار $karat'),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _karat = value;
                          _category = _categories.first;
                        });
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'المتاح: ${_gramsText(_availableWeight(_karat).toString())} جرام',
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<StockCategory>(
                      key: ValueKey('scrap-stock-category-$_karat'),
                      initialValue: _category,
                      isExpanded: true,
                      decoration: ledgerFieldDecoration(
                        context,
                        label: 'فئة المخزون الجديدة',
                      ),
                      items: [
                        for (final category in _categories)
                          DropdownMenuItem(
                            value: category,
                            child: Text(stockCategoryLabel(category)),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _category = value ?? _category),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('scrap-stock-name'),
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: ledgerFieldDecoration(
                        context,
                        label: 'اسم الصنف الجديد',
                      ),
                    ),
                    const SizedBox(height: 12),
                    LedgerFieldPair(
                      first: TextField(
                        key: const Key('scrap-stock-grams'),
                        controller: _grams,
                        textDirection: TextDirection.ltr,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textInputAction: TextInputAction.next,
                        decoration: ledgerFieldDecoration(
                          context,
                          label: 'الوزن بالجرام',
                          helper: 'حتى ثلاث منازل عشرية',
                        ),
                      ),
                      second: TextField(
                        key: const Key('scrap-stock-count'),
                        controller: _count,
                        textDirection: TextDirection.ltr,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.next,
                        decoration: ledgerFieldDecoration(
                          context,
                          label: 'عدد القطع الجديدة',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _note,
                      maxLength: 1000,
                      maxLines: 3,
                      decoration: ledgerFieldDecoration(
                        context,
                        label: 'ملاحظة اختيارية',
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
                              'ينقص الكسر: ${_reviewWeight!.gramsText} جرام · عيار $_karat',
                            ),
                            Text(
                              'يزيد المخزون: ${_reviewWeight!.gramsText} جرام · '
                              '${_reviewCount!.wire} قطعة · ${stockCategoryLabel(_category)}',
                            ),
                            Text('الصنف: ${_name.text.trim()}'),
                            const Text('النقدية لا تتغير.'),
                          ],
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _busy || _unknown
                          ? null
                          : () => setState(() {
                              _reviewWeight = null;
                              _reviewCount = null;
                            }),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('تعديل التحويل'),
                    ),
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
                          ? 'scrap-stock-check'
                          : reviewing
                          ? 'scrap-stock-confirm'
                          : 'scrap-stock-review',
                    ),
                    onPressed: _busy
                        ? null
                        : _unknown
                        ? _reconcile
                        : reviewing
                        ? _submit
                        : _startReview,
                    child: Text(
                      _busy
                          ? 'جارٍ المعالجة...'
                          : _unknown
                          ? 'التحقق من الحالة'
                          : reviewing
                          ? 'تأكيد التحويل'
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

BigInt _wireWeight(LedgerScrapLine line) =>
    (Milligrams.parseWire(line.milligrams) as Accepted<Milligrams>).value.value;

String _gramsText(String value) {
  final parsed = Milligrams.parseWire(value);
  return parsed is Accepted<Milligrams> ? parsed.value.gramsText : '—';
}
