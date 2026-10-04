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
import '../domain/invoice_pricing.dart';
import '../../onboarding/application/onboarding_store.dart';
import '../../onboarding/presentation/guide_card.dart';
import 'ledger_form_fields.dart';
import 'opening_copy.dart';

class FinancialTradeScreen extends StatefulWidget {
  const FinancialTradeScreen({
    super.key,
    required this.kind,
    required this.gateway,
    required this.statusGateway,
    required this.userId,
    required this.shopId,
    this.practice = false,
    this.onboardingStore,
  });

  final FinancialKind kind;
  final FinancialGateway gateway;
  final OpeningGateway statusGateway;
  final String userId;
  final String shopId;
  final bool practice;
  final OnboardingStore? onboardingStore;

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
  final _basePrice = TextEditingController();
  final _workmanship = TextEditingController(text: '0');
  final _otherCharges = TextEditingController(text: '0');
  final _otherChargesLabel = TextEditingController();
  final _discount = TextEditingController(text: '0');
  bool _priceDetails = false;
  FinancialDraft? _review;
  String? _error;
  String? _key;
  bool _busy = false;
  bool _unknown = false;
  final _pending = const PendingFinancialCommands();
  final _guideScroll = ScrollController();
  final _gramsFocus = FocusNode();
  final _tenderFocus = FocusNode();
  bool _guideVisible = false;
  int _guideStep = 0;
  String get _guidePath => 'first_sale_${widget.userId}_${widget.shopId}';

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
    if (widget.practice) _loadPracticeGuide();
  }

  Future<void> _loadPracticeGuide() async {
    final step = await widget.onboardingStore?.readStep(_guidePath) ?? 0;
    if (mounted) {
      setState(() {
        _guideStep = step.clamp(0, 3);
        _guideVisible = true;
      });
    }
  }

  void _guideAction() {
    final focus = switch (_guideStep) {
      0 => _items.first.nameFocus,
      1 => _gramsFocus,
      2 => _tenderFocus,
      _ => null,
    };
    if (focus == null) {
      _startReview();
      return;
    }
    focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = focus.context;
      if (mounted && target != null) {
        Scrollable.ensureVisible(target, alignment: .25);
      }
    });
    setState(() => _guideStep++);
    widget.onboardingStore?.saveStep(_guidePath, _guideStep);
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
    _basePrice.dispose();
    _workmanship.dispose();
    _otherCharges.dispose();
    _otherChargesLabel.dispose();
    _discount.dispose();
    _guideScroll.dispose();
    _gramsFocus.dispose();
    _tenderFocus.dispose();
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
    InvoicePricing? pricing;
    if (_priceDetails) {
      final result = _composePricing();
      if (result is! Accepted<InvoicePricing>) {
        setState(() {
          _error =
              'راجع السعر الأساسي والمصنعية والرسوم واسمها والخصم. يجب أن يكون الإجمالي أكبر من صفر.';
          _review = null;
        });
        return;
      }
      pricing = result.value;
    }
    final result = FinancialDraft.compose(
      kind: widget.kind,
      pricing: pricing,
      totalPounds:
          pricing?.total.poundsText ??
          (widget.kind == FinancialKind.purchase
              ? _purchaseTotal.text
              : _totalPounds() ?? ''),
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

  DomainResult<InvoicePricing> _composePricing() => InvoicePricing.compose(
    basePounds: _basePrice.text,
    workmanshipPounds: _workmanship.text,
    otherChargesPounds: _otherCharges.text,
    otherChargesLabel: _otherChargesLabel.text,
    discountPounds: _discount.text,
  );

  Widget _priceField(
    String key,
    String label,
    TextEditingController controller,
  ) => TextField(
    key: Key(key),
    controller: controller,
    textDirection: TextDirection.ltr,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textInputAction: TextInputAction.next,
    onChanged: (_) => setState(() {}),
    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
    decoration: ledgerFieldDecoration(context, label: label),
  );

  List<Widget> _pricingFields(ThemeData theme) {
    final result = _composePricing();
    return [
      _priceField('trade-base-price', 'السعر الأساسي بالجنيه', _basePrice),
      const SizedBox(height: 12),
      LedgerFieldPair(
        first: _priceField(
          'trade-workmanship',
          'المصنعية بالجنيه',
          _workmanship,
        ),
        second: _priceField('trade-discount', 'الخصم بالجنيه', _discount),
      ),
      const SizedBox(height: 12),
      LedgerFieldPair(
        first: _priceField(
          'trade-other-charges',
          'رسوم أخرى بالجنيه',
          _otherCharges,
        ),
        second: TextField(
          key: const Key('trade-other-label'),
          controller: _otherChargesLabel,
          maxLength: 120,
          textInputAction: TextInputAction.next,
          onChanged: (_) => setState(() {}),
          decoration: ledgerFieldDecoration(
            context,
            label: 'اسم الرسوم الأخرى',
          ),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        'الإجمالي بعد التعديلات: ${result is Accepted<InvoicePricing> ? result.value.total.poundsText : '—'} جنيه',
        key: const Key('trade-adjusted-total'),
        style: theme.textTheme.titleMedium,
      ),
      const SizedBox(height: 20),
    ];
  }

  Future<void> _submit() async {
    final draft = _review;
    if (draft == null || _busy) return;
    // Practice is a local draft. This guard precedes keys, persistence and RPCs.
    if (widget.practice) {
      await widget.onboardingStore?.markComplete(_guidePath);
      if (mounted) Navigator.pop(context, false);
      return;
    }
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
        appBar: AppBar(
          title: Text(widget.practice ? 'تدريب على أول بيع' : _title),
          actions: [
            if (widget.practice)
              IconButton(
                tooltip: 'استئناف الإرشاد',
                onPressed: () => setState(() => _guideVisible = true),
                icon: const Icon(Icons.help_outline),
              ),
          ],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                controller: _guideScroll,
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                children: [
                  if (widget.practice) ...[
                    const Text(
                      'مسودة تدريب فقط — لن يُحفظ بيع ولن يتغير النقد أو الذهب.',
                      key: Key('practice-draft-label'),
                    ),
                    const SizedBox(height: 12),
                    if (_guideVisible && _review == null)
                      GuideCard(
                        title: 'جرّب أدوات البيع',
                        description: const [
                          'ابدأ باسم الصنف في الحقل الحقيقي أدناه.',
                          'أدخل الوزن حتى ثلاث منازل عشرية، ثم راجع العدد والعيار.',
                          'أدخل المبلغ في وسيلة الدفع. يمكنك إضافة وسيلة أخرى لتقسيمه.',
                          'راجع أثر النقد والذهب. زر إنهاء التدريب لا يرسل أي عملية.',
                        ][_guideStep],
                        progress: '${_guideStep + 1} / 4',
                        actionLabel: _guideStep == 3
                            ? 'مراجعة المسودة'
                            : 'الانتقال إلى الحقل',
                        onAction: _guideAction,
                        onSkip: () {
                          setState(() => _guideVisible = false);
                          widget.onboardingStore?.saveStep(
                            _guidePath,
                            _guideStep,
                          );
                        },
                      ),
                  ],
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
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: _unknown
                      ? FilledButton.icon(
                          key: const Key('trade-check-status'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          onPressed: _busy ? null : _reconcile,
                          icon: const Icon(Icons.sync),
                          label: const Text('التحقق من الحالة'),
                        )
                      : FilledButton(
                          key: Key(
                            _review == null ? 'trade-review' : 'trade-confirm',
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
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
                                : widget.practice
                                ? 'إنهاء التدريب دون حفظ'
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
    const SizedBox(height: 6),
    Text(
      widget.practice
          ? 'استخدم الحقول للمراجعة والتجربة. تبقى البيانات داخل هذه المسودة.'
          : 'تُحفظ العملية بعد مراجعة أثر النقد والذهب وتأكيد الخادم فقط.',
    ),
    const SizedBox(height: 20),
    if (widget.kind == FinancialKind.expense) ...[
      TextField(
        key: const Key('trade-description'),
        controller: _description,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        decoration: ledgerFieldDecoration(context, label: 'وصف المصروف'),
      ),
      const SizedBox(height: 20),
    ],
    if (widget.kind != FinancialKind.expense) ...[
      Text('الأصناف', style: theme.textTheme.titleMedium),
      const SizedBox(height: 12),
      for (var index = 0; index < _items.length; index++) ...[
        _itemCard(index, theme),
        const SizedBox(height: 16),
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
    if (widget.kind == FinancialKind.sale ||
        widget.kind == FinancialKind.purchase) ...[
      CheckboxListTile(
        key: const Key('trade-price-details'),
        value: _priceDetails,
        title: const Text('تفصيل السعر والمصنعية والرسوم والخصم'),
        contentPadding: EdgeInsets.zero,
        onChanged: (value) => setState(() => _priceDetails = value ?? false),
      ),
      if (_priceDetails) ..._pricingFields(theme),
    ],
    if (widget.kind == FinancialKind.purchase) ...[
      if (!_priceDetails) ...[
        TextField(
          key: const Key('trade-purchase-price'),
          controller: _purchaseTotal,
          textDirection: TextDirection.ltr,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          decoration: ledgerFieldDecoration(
            context,
            label: 'سعر الشراء الكلي بالجنيه',
          ),
        ),
        const SizedBox(height: 16),
      ],
      TextField(
        key: const Key('trade-seller-name'),
        controller: _customerName,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        decoration: ledgerFieldDecoration(
          context,
          label: 'اسم البائع (مطلوب عند وجود مبلغ مستحق)',
        ),
      ),
      const SizedBox(height: 20),
    ],
    Text('الدفع', style: theme.textTheme.titleMedium),
    const SizedBox(height: 4),
    Text(
      widget.kind == FinancialKind.purchase
          ? 'أدخل ما دفعه المتجر الآن. اترك المبلغ فارغاً إذا لم يُدفع نقد.'
          : 'يمكن تقسيم المبلغ بين أكثر من وسيلة. يُحسب الإجمالي تلقائياً.',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        height: 1.5,
      ),
    ),
    const SizedBox(height: 12),
    for (var index = 0; index < _tenders.length; index++) ...[
      _tenderCard(index),
      const SizedBox(height: 12),
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
        childrenPadding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
        children: [
          if (widget.kind != FinancialKind.purchase)
            TextField(
              controller: _customerName,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              decoration: ledgerFieldDecoration(context, label: 'اسم العميل'),
            ),
          if (widget.kind != FinancialKind.purchase) const SizedBox(height: 12),
          TextField(
            controller: _customerPhone,
            textDirection: TextDirection.ltr,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => FocusScope.of(context).nextFocus(),
            decoration: ledgerFieldDecoration(context, label: 'رقم الهاتف'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: ledgerFieldDecoration(context, label: 'ملاحظة العملية'),
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
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'الصنف ${index + 1}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
            const SizedBox(height: 12),
            if (widget.kind == FinancialKind.scrapSale)
              Text('الفئة: كسر', style: theme.textTheme.titleSmall)
            else
              DropdownButtonFormField<String>(
                key: Key('trade-category-$index'),
                initialValue: row.category,
                isExpanded: true,
                decoration: ledgerFieldDecoration(context, label: 'الفئة'),
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
            const SizedBox(height: 12),
            TextField(
              key: Key('trade-name-$index'),
              controller: row.name,
              focusNode: row.nameFocus,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => FocusScope.of(context).nextFocus(),
              decoration: ledgerFieldDecoration(context, label: 'اسم الصنف'),
            ),
            const SizedBox(height: 12),
            if (categoryCode != 'scrap')
              LedgerFieldPair(
                first: TextField(
                  key: Key('trade-count-$index'),
                  controller: row.count,
                  textDirection: TextDirection.ltr,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  decoration: ledgerFieldDecoration(context, label: 'العدد'),
                ),
                second: TextField(
                  key: Key('trade-grams-$index'),
                  controller: row.grams,
                  focusNode: index == 0 ? _gramsFocus : null,
                  textDirection: TextDirection.ltr,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                  decoration: ledgerFieldDecoration(
                    context,
                    label: 'الوزن بالجرام',
                    helper: 'حتى ثلاث منازل عشرية',
                  ),
                ),
              )
            else
              TextField(
                key: Key('trade-grams-$index'),
                controller: row.grams,
                focusNode: index == 0 ? _gramsFocus : null,
                textDirection: TextDirection.ltr,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: ledgerFieldDecoration(
                  context,
                  label: 'الوزن بالجرام',
                  helper: 'حتى ثلاث منازل عشرية',
                ),
              ),
            const SizedBox(height: 12),
            LedgerFieldPair(
              first: DropdownButtonFormField<int>(
                key: Key('trade-karat-$index-${row.category}-${row.karat}'),
                initialValue: row.karat,
                isExpanded: true,
                decoration: ledgerFieldDecoration(context, label: 'العيار'),
                items: [
                  for (final karat in karats)
                    DropdownMenuItem(value: karat, child: Text('$karat')),
                ],
                onChanged: (value) {
                  setState(() => row.karat = value ?? row.karat);
                  row.priceFocus.requestFocus();
                },
              ),
              second: TextField(
                key: Key('trade-line-price-$index'),
                controller: row.price,
                focusNode: row.priceFocus,
                textDirection: TextDirection.ltr,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => FocusScope.of(context).nextFocus(),
                decoration: ledgerFieldDecoration(
                  context,
                  label: _priceDetails
                      ? 'السعر الأساسي للصنف (اختياري)'
                      : 'سعر الصنف (اختياري)',
                  helper: _priceDetails
                      ? 'مجموع أسعار الأصناف يساوي السعر الأساسي'
                      : 'اتركه فارغاً لسعر الفاتورة الكلي',
                ),
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
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LedgerFieldPair(
                first: DropdownButtonFormField<CashMethod>(
                  key: Key('trade-tender-method-$index'),
                  initialValue: row.method,
                  isExpanded: true,
                  decoration: ledgerFieldDecoration(
                    context,
                    label: 'وسيلة الدفع',
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
                second: TextField(
                  key: Key('trade-tender-amount-$index'),
                  controller: row.amount,
                  focusNode: index == 0 ? _tenderFocus : null,
                  onChanged: (_) => setState(() {}),
                  textDirection: TextDirection.ltr,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  decoration: ledgerFieldDecoration(
                    context,
                    label: 'المبلغ بالجنيه',
                  ),
                ),
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
      ),
    );
  }

  List<Widget> _reviewWidgets(ThemeData theme) {
    final draft = _review!;
    return [
      Text('مراجعة أثر العملية', style: theme.textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(
        widget.practice
            ? 'هذه آثار افتراضية للمراجعة فقط. إنهاء التدريب لا يرسل الطلب.'
            : 'لن تظهر العملية محفوظة حتى يؤكدها الخادم. راجع المبلغ والذهب قبل المتابعة.',
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
      if (draft.pricing case final pricing?) ...[
        Text('السعر الأساسي: ${pricing.base.poundsText} جنيه'),
        Text('المصنعية: ${pricing.workmanship.poundsText} جنيه'),
        Text(
          'رسوم أخرى${pricing.otherChargesLabel.isEmpty ? '' : ' (${pricing.otherChargesLabel})'}: ${pricing.otherCharges.poundsText} جنيه',
        ),
        Text('الخصم: ${pricing.discount.poundsText} جنيه'),
        Text('الإجمالي المتفق عليه: ${pricing.total.poundsText} جنيه'),
        const SizedBox(height: 16),
      ],
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
  FinancialIssue.pricingMismatch =>
    'راجع السعر الأساسي والمصنعية والرسوم والخصم وإجمالي الدفع.',
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
