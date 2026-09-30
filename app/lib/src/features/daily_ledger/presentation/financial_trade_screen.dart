import 'package:flutter/material.dart';

import '../application/financial_gateway.dart';
import '../application/idempotency_key.dart';
import '../application/opening_gateway.dart';
import '../application/pending_financial_command.dart';
import '../data/pending_financial_command.dart';
import '../domain/financial_draft.dart';
import '../domain/opening_catalog.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';
import 'opening_copy.dart';

class FinancialTradeScreen extends StatefulWidget {
  const FinancialTradeScreen({
    super.key,
    required this.kind,
    required this.gateway,
    required this.statusGateway,
    required this.userId,
    required this.shopId,
  });

  final FinancialKind kind;
  final FinancialGateway gateway;
  final OpeningGateway statusGateway;
  final String userId;
  final String shopId;

  @override
  State<FinancialTradeScreen> createState() => _FinancialTradeScreenState();
}

class _ItemEntry {
  _ItemEntry({bool scrap = false})
    : name = TextEditingController(),
      grams = TextEditingController(),
      count = TextEditingController(text: '1'),
      price = TextEditingController(),
      category = scrap ? 'scrap' : 'worked_jewelry',
      karat = 18;

  String category;
  int karat;
  final TextEditingController name;
  final FocusNode nameFocus = FocusNode();
  final FocusNode priceFocus = FocusNode();
  final TextEditingController grams;
  final TextEditingController count;
  final TextEditingController price;

  void dispose() {
    nameFocus.dispose();
    priceFocus.dispose();
    name.dispose();
    grams.dispose();
    count.dispose();
    price.dispose();
  }
}

class _TenderEntry {
  _TenderEntry(this.method) : amount = TextEditingController();
  CashMethod method;
  final TextEditingController amount;
  void dispose() => amount.dispose();
}

class _FinancialTradeScreenState extends State<FinancialTradeScreen> {
  final _items = <_ItemEntry>[];
  final _tenders = <_TenderEntry>[];
  final _description = TextEditingController();
  final _purchaseTotal = TextEditingController();
  final _customerName = TextEditingController();
  final _customerPhone = TextEditingController();
  final _note = TextEditingController();
  FinancialDraft? _review;
  String? _error;
  String? _key;
  bool _busy = false;
  bool _unknown = false;
  final _pending = const PendingFinancialCommands();

  String get _title => switch (widget.kind) {
    FinancialKind.sale => 'إضافة بيع',
    FinancialKind.purchase => 'إضافة شراء',
    FinancialKind.expense => 'إضافة مصروف',
    FinancialKind.scrapSale => 'بيع كسر وإضافة نقد',
  };

  @override
  void initState() {
    super.initState();
    if (widget.kind != FinancialKind.expense) {
      _items.add(_ItemEntry(scrap: widget.kind == FinancialKind.scrapSale));
    }
    _tenders.add(_TenderEntry(CashMethod.cash));
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    for (final tender in _tenders) {
      tender.dispose();
    }
    _description.dispose();
    _purchaseTotal.dispose();
    _customerName.dispose();
    _customerPhone.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _totalPounds() {
    var sum = BigInt.zero;
    for (final tender in _tenders) {
      if (widget.kind == FinancialKind.purchase &&
          tender.amount.text.trim().isEmpty) {
        continue;
      }
      final parsed = Piastres.parsePounds(tender.amount.text.trim());
      if (parsed is! Accepted<Piastres>) return null;
      sum += parsed.value.value;
    }
    final parsed = Piastres.parseWire(sum.toString());
    return parsed is Accepted<Piastres> ? parsed.value.poundsText : null;
  }

  void _startReview() {
    final result = FinancialDraft.compose(
      kind: widget.kind,
      totalPounds: widget.kind == FinancialKind.purchase
          ? _purchaseTotal.text
          : _totalPounds() ?? '',
      items: [
        for (final item in _items)
          FinancialItemInput(
            category: item.category,
            karat: item.karat,
            grams: item.grams.text,
            count: item.count.text,
            name: item.name.text,
            linePricePounds: item.price.text,
          ),
      ],
      tenders: [
        for (final tender in _tenders)
          if (widget.kind != FinancialKind.purchase ||
              tender.amount.text.trim().isNotEmpty)
            FinancialTenderInput(
              method: tender.method,
              pounds: tender.amount.text,
            ),
      ],
      description: _description.text,
      customerName: _customerName.text,
      customerPhone: _customerPhone.text,
      note: _note.text,
    );
    setState(() {
      _error = result.issue == null ? null : _issueCopy(result.issue!);
      _review = result.draft;
    });
  }

  Future<void> _submit() async {
    final draft = _review;
    if (draft == null || _busy) return;
    var commandSaved = false;
    setState(() {
      _busy = true;
      _error = null;
      _key ??= newIdempotencyKey();
    });
    try {
      await _pending.save(
        widget.userId,
        widget.shopId,
        PendingFinancialCommand(
          key: _key!,
          kind: widget.kind == FinancialKind.scrapSale
              ? 'scrap_sale'
              : widget.kind.name,
          body: {'p_idempotency_key': _key!, 'p_payload': draft.toJson()},
        ),
      );
      commandSaved = true;
      final result = await widget.gateway.postTrade(
        callerUserId: widget.userId,
        idempotencyKey: _key!,
        draft: draft,
      );
      if (!mounted) return;
      if (result is FinancialCommitted) {
        await _pending.clear(widget.userId, widget.shopId, _key!);
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }
      if (result is FinancialRejected) {
        await _pending.clear(widget.userId, widget.shopId, _key!);
        if (!mounted) return;
        setState(() {
          _unknown = false;
          _error = _serverCopy(result.code);
          _key = null;
        });
        return;
      }
      await _reconcile();
    } catch (_) {
      if (mounted) {
        setState(() {
          _unknown = commandSaved;
          if (!commandSaved) _key = null;
          _error = commandSaved
              ? 'حالة العملية غير مؤكدة. تحقق من الحالة قبل المتابعة.'
              : 'تعذر حفظ طلب الانتظار. راجع أي عملية معلقة وحاول مجدداً.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconcile() async {
    final key = _key;
    if (key == null) return;
    final status = await widget.statusGateway.status(
      callerUserId: widget.userId,
      idempotencyKey: key,
    );
    if (!mounted) return;
    if (status is StatusCompleted) {
      await _pending.clear(widget.userId, widget.shopId, key);
      if (!mounted) return;
      Navigator.pop(context, true);
    } else if (status is StatusAbsent) {
      setState(() {
        _unknown = false;
        _error = 'لم يؤكد الخادم العملية. يمكنك إعادة المحاولة بالمفتاح نفسه.';
      });
    } else {
      setState(() {
        _unknown = true;
        _error =
            'حالة العملية غير مؤكدة. تحقق من الاتصال ثم اضغط «التحقق من الحالة».';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: !_busy && !_unknown,
      child: Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_review == null)
                    ..._entryWidgets(theme)
                  else
                    ..._reviewWidgets(theme),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      key: const Key('trade-message'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
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
                  child: _unknown
                      ? FilledButton.icon(
                          key: const Key('trade-check-status'),
                          onPressed: _busy ? null : _reconcile,
                          icon: const Icon(Icons.sync),
                          label: const Text('التحقق من الحالة'),
                        )
                      : FilledButton(
                          key: Key(
                            _review == null ? 'trade-review' : 'trade-confirm',
                          ),
                          onPressed: _busy
                              ? null
                              : _review == null
                              ? _startReview
                              : _submit,
                          child: Text(
                            _busy
                                ? 'بانتظار تأكيد الخادم'
                                : _review == null
                                ? 'مراجعة الأثر'
                                : 'تأكيد $_title',
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

  List<Widget> _entryWidgets(ThemeData theme) => [
    Text(_title, style: theme.textTheme.headlineSmall),
    const SizedBox(height: 4),
    const Text('تُحفظ العملية بعد مراجعة أثر النقد والذهب وتأكيد الخادم فقط.'),
    const SizedBox(height: 16),
    if (widget.kind == FinancialKind.expense) ...[
      TextField(
        key: const Key('trade-description'),
        controller: _description,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        decoration: const InputDecoration(
          labelText: 'وصف المصروف',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
    ],
    if (widget.kind != FinancialKind.expense) ...[
      Text('الأصناف', style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      for (var index = 0; index < _items.length; index++) ...[
        _itemCard(index, theme),
        const SizedBox(height: 12),
      ],
      OutlinedButton.icon(
        key: const Key('trade-add-item'),
        onPressed: () => setState(
          () => _items.add(
            _ItemEntry(scrap: widget.kind == FinancialKind.scrapSale),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('إضافة صنف آخر'),
      ),
      const SizedBox(height: 20),
    ],
    if (widget.kind == FinancialKind.purchase) ...[
      TextField(
        key: const Key('trade-purchase-price'),
        controller: _purchaseTotal,
        textDirection: TextDirection.ltr,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        decoration: const InputDecoration(
          labelText: 'سعر الشراء الكلي بالجنيه',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        key: const Key('trade-seller-name'),
        controller: _customerName,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        decoration: const InputDecoration(
          labelText: 'اسم البائع (مطلوب عند وجود مبلغ مستحق)',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 20),
    ],
    Text('الدفع', style: theme.textTheme.titleMedium),
    Text(
      widget.kind == FinancialKind.purchase
          ? 'أدخل ما دفعه المتجر الآن. اترك المبلغ فارغاً إذا لم يُدفع نقد.'
          : 'يمكن تقسيم المبلغ بين أكثر من وسيلة. يُحسب الإجمالي تلقائياً.',
    ),
    const SizedBox(height: 8),
    for (var index = 0; index < _tenders.length; index++) ...[
      _tenderCard(index),
      const SizedBox(height: 8),
    ],
    if (_tenders.length < 4)
      OutlinedButton.icon(
        key: const Key('trade-add-tender'),
        onPressed: () {
          final used = _tenders.map((row) => row.method).toSet();
          final next = CashMethod.canonicalOrder.firstWhere(
            (method) => !used.contains(method),
          );
          setState(() => _tenders.add(_TenderEntry(next)));
        },
        icon: const Icon(Icons.add),
        label: const Text('إضافة وسيلة دفع'),
      ),
    const SizedBox(height: 12),
    Text(
      'إجمالي ${widget.kind == FinancialKind.purchase || widget.kind == FinancialKind.expense ? 'المدفوع' : 'المحصّل'}: ${_totalPounds() ?? '—'} جنيه',
      style: theme.textTheme.titleMedium,
    ),
    if (widget.kind != FinancialKind.expense) ...[
      const SizedBox(height: 20),
      ExpansionTile(
        title: Text(
          widget.kind == FinancialKind.purchase
              ? 'هاتف البائع والملاحظات (اختياري)'
              : 'بيانات العميل والملاحظات (اختياري)',
        ),
        childrenPadding: const EdgeInsets.only(bottom: 12),
        children: [
          if (widget.kind != FinancialKind.purchase)
            TextField(
              controller: _customerName,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              decoration: const InputDecoration(
                labelText: 'اسم العميل',
                border: OutlineInputBorder(),
              ),
            ),
          if (widget.kind != FinancialKind.purchase) const SizedBox(height: 8),
          TextField(
            controller: _customerPhone,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: const InputDecoration(
              labelText: 'رقم الهاتف',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'ملاحظة العملية',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ],
  ];

  Widget _itemCard(int index, ThemeData theme) {
    final row = _items[index];
    final categories = widget.kind == FinancialKind.scrapSale
        ? <StockCategory>[]
        : [...openingCategoryChoices];
    final categoryCode = row.category;
    final karats = categoryCode == 'scrap'
        ? (ScrapKarats.allowed.toList()..sort())
        : (StockCategory.byCode(categoryCode)!.karats.toList()..sort());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'الصنف ${index + 1}',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (_items.length > 1)
                  IconButton(
                    tooltip: 'حذف الصنف ${index + 1}',
                    onPressed: () =>
                        setState(() => _items.removeAt(index).dispose()),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            if (widget.kind == FinancialKind.scrapSale)
              Text('الفئة: كسر', style: theme.textTheme.titleSmall)
            else
              DropdownButtonFormField<String>(
                key: Key('trade-category-$index'),
                initialValue: row.category,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'الفئة',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final category in categories)
                    DropdownMenuItem(
                      value: category.code,
                      child: Text(stockCategoryLabel(category)),
                    ),
                  if (widget.kind == FinancialKind.purchase)
                    const DropdownMenuItem(value: 'scrap', child: Text('كسر')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    row.category = value;
                    final allowed = value == 'scrap'
                        ? ScrapKarats.allowed
                        : StockCategory.byCode(value)!.karats;
                    if (!allowed.contains(row.karat)) {
                      row.karat = (allowed.toList()..sort()).first;
                    }
                  });
                  row.nameFocus.requestFocus();
                },
              ),
            const SizedBox(height: 8),
            TextField(
              key: Key('trade-name-$index'),
              controller: row.name,
              focusNode: row.nameFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              decoration: const InputDecoration(
                labelText: 'اسم الصنف',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            if (categoryCode != 'scrap') ...[
              TextField(
                key: Key('trade-count-$index'),
                controller: row.count,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: const InputDecoration(
                  labelText: 'العدد',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              key: Key('trade-grams-$index'),
              controller: row.grams,
              textDirection: TextDirection.ltr,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              decoration: const InputDecoration(
                labelText: 'الوزن بالجرام',
                helperText: 'حتى ثلاث منازل عشرية',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              key: Key('trade-karat-$index-${row.category}-${row.karat}'),
              initialValue: row.karat,
              decoration: const InputDecoration(
                labelText: 'العيار',
                border: OutlineInputBorder(),
              ),
              items: [
                for (final karat in karats)
                  DropdownMenuItem(value: karat, child: Text('$karat')),
              ],
              onChanged: (value) {
                setState(() => row.karat = value ?? row.karat);
                row.priceFocus.requestFocus();
              },
            ),
            const SizedBox(height: 8),
            TextField(
              key: Key('trade-line-price-$index'),
              controller: row.price,
              focusNode: row.priceFocus,
              textDirection: TextDirection.ltr,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              decoration: const InputDecoration(
                labelText: 'سعر الصنف (اختياري)',
                helperText: 'اتركه فارغاً لسعر الفاتورة الكلي',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tenderCard(int index) {
    final row = _tenders[index];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<CashMethod>(
                    key: Key('trade-tender-method-$index'),
                    initialValue: row.method,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'وسيلة الدفع',
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
                        setState(() => row.method = value ?? row.method),
                  ),
                ),
                if (_tenders.length > 1)
                  IconButton(
                    tooltip: 'حذف وسيلة الدفع ${index + 1}',
                    onPressed: () =>
                        setState(() => _tenders.removeAt(index).dispose()),
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: Key('trade-tender-amount-$index'),
              controller: row.amount,
              onChanged: (_) => setState(() {}),
              textDirection: TextDirection.ltr,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => FocusScope.of(context).unfocus(),
              decoration: const InputDecoration(
                labelText: 'المبلغ بالجنيه',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _reviewWidgets(ThemeData theme) {
    final draft = _review!;
    return [
      Text('مراجعة أثر العملية', style: theme.textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text(
        'لن تظهر العملية محفوظة حتى يؤكدها الخادم. راجع المبلغ والذهب قبل المتابعة.',
      ),
      const SizedBox(height: 16),
      Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.kind == FinancialKind.sale ||
                        widget.kind == FinancialKind.scrapSale
                    ? 'يزيد النقد'
                    : 'ينقص النقد الآن',
                style: theme.textTheme.titleSmall,
              ),
              Text(
                '${draft.cashPaid.poundsText} جنيه',
                textDirection: TextDirection.ltr,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              if (draft.purchasePayable != null) ...[
                Text(
                  'يبقى مستحقاً للبائع: ${draft.purchasePayable!.poundsText} جنيه',
                ),
                Text('سعر الشراء الكلي: ${draft.total.poundsText} جنيه'),
                Text('البائع: ${draft.customerName}'),
                const SizedBox(height: 8),
              ],
              Text(
                widget.kind == FinancialKind.sale
                    ? 'ينقص المخزون بالأوزان أدناه'
                    : widget.kind == FinancialKind.scrapSale
                    ? 'ينقص الكسر بالأوزان أدناه'
                    : widget.kind == FinancialKind.purchase
                    ? 'تنتقل الملكية إلى المتجر الآن ويزيد المخزون أو الكسر بالأوزان أدناه'
                    : 'لا يتغير الذهب',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      for (final item in draft.items)
        ListTile(
          title: Text('${item['item_name']} · عيار ${item['karat']}'),
          subtitle: Text(
            item['category'] == 'scrap'
                ? 'كسر'
                : '${stockCategoryLabel(StockCategory.byCode(item['category'] as String)!)} · ${item['count']} قطعة',
          ),
          trailing: Text('${_gramsText(item['milligrams'] as String)} جرام'),
        ),
      for (final tender in draft.tenders)
        ListTile(
          title: Text(
            cashMethodLabel(
              CashMethod.canonicalOrder.firstWhere(
                (method) => method.code == tender['method'],
              ),
            ),
          ),
          trailing: Text('${_poundsText(tender['piastres'] as String)} جنيه'),
        ),
      if (draft.customerName.isNotEmpty)
        Text(
          '${widget.kind == FinancialKind.purchase ? 'البائع' : 'العميل'}: ${draft.customerName}',
        ),
      if (draft.note.isNotEmpty) Text('ملاحظة: ${draft.note}'),
      const SizedBox(height: 8),
      TextButton.icon(
        key: const Key('trade-edit'),
        onPressed: _busy || _key != null
            ? null
            : () => setState(() => _review = null),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('رجوع للتعديل'),
      ),
    ];
  }
}

String _issueCopy(FinancialIssue issue) => switch (issue) {
  FinancialIssue.invalidTotal => 'أدخل مبلغاً صحيحاً أكبر من صفر.',
  FinancialIssue.invalidTender =>
    'راجع وسائل الدفع ومبالغها؛ لا تكرر الوسيلة نفسها.',
  FinancialIssue.tenderMismatch => 'مجموع وسائل الدفع لا يساوي المبلغ المطلوب.',
  FinancialIssue.invalidItem => 'راجع الصنف والعيار والعدد والوزن والسعر.',
  FinancialIssue.linePriceMismatch => 'أسعار الأصناف لا تساوي السعر الكلي.',
  FinancialIssue.missingDescription => 'أدخل وصفاً للمصروف.',
  FinancialIssue.invalidCustomer => 'راجع بيانات العميل والملاحظة.',
  FinancialIssue.missingSeller => 'أدخل اسم البائع للمبلغ المستحق.',
};

String _serverCopy(String code) => switch (code) {
  'negative_owned_balance' || 'insufficient_stock' =>
    'الرصيد أو المخزون غير كافٍ. حدّث الدفتر وراجع العملية.',
  'stock_pair_mismatch' =>
    'العدد والوزن المتبقيان غير متوافقين. راجع أصناف البيع.',
  'day_closed' => 'أُغلق يوم العمل. افتح يوماً جديداً قبل تسجيل عملية.',
  'shop_not_active' || 'forbidden' => 'لا يُسمح بتسجيل العملية لهذا المتجر.',
  'tender_mismatch' => 'المبلغ المدفوع أكبر من السعر أو لا يساوي المطلوب.',
  'line_price_mismatch' => 'أسعار الأصناف لا تساوي الإجمالي.',
  _ => 'تعذر تأكيد العملية. راجع البيانات والاتصال ثم حاول مرة أخرى.',
};

String _gramsText(String wire) =>
    (Milligrams.parseWire(wire) as Accepted<Milligrams>).value.gramsText;

String _poundsText(String wire) =>
    (Piastres.parseWire(wire) as Accepted<Piastres>).value.poundsText;
