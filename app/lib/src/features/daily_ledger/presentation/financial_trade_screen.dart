import '../../../theme/cash_input.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../application/daily_ledger_view.dart';
import '../application/financial_gateway.dart';
import '../application/idempotency_key.dart';
import '../application/opening_gateway.dart';
import '../application/pending_financial_command.dart';
import '../data/pending_financial_command.dart';
import '../domain/financial_draft.dart';
import '../domain/nominal_weight_suggestions.dart';
import '../domain/opening_catalog.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';
import '../domain/invoice_pricing.dart';
import '../../inventory/application/inventory_gateway.dart';
import '../../onboarding/application/onboarding_store.dart';
import '../../../theme/amount_format.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_tokens.dart';
import 'financial_operation_screen.dart';
import 'jewelry_icons.dart';
import 'ledger_form_fields.dart';
import '../domain/ledger_compensation.dart';
import 'exchange_effect_review.dart';
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
    this.exchangeReturnPayload,
    this.exchangeReturnReview,
    this.onboardingStore,
    this.sheet = false,
    this.catalog,
    this.inventoryPage,
  });

  final FinancialKind kind;
  final FinancialGateway gateway;
  final OpeningGateway statusGateway;
  final String userId;
  final String shopId;
  final bool practice;
  final Map<String, Object?>? exchangeReturnPayload;
  final PartialReturnReview? exchangeReturnReview;
  final OnboardingStore? onboardingStore;
  final bool sheet;
  final InventoryGateway? catalog;
  final WidgetBuilder? inventoryPage;

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
  bool customName = false;
  int karat;
  final TextEditingController name;
  final FocusNode priceFocus = FocusNode();
  final TextEditingController grams;
  final TextEditingController count;
  final TextEditingController price;

  void dispose() {
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
  bool _committed = false;
  String? _operationId;
  bool _catalogLoading = false;
  bool _catalogFailed = false;
  bool _nominalFailed = false;
  bool _invoiceBusy = false;
  int _catalogGeneration = 0;
  String? _productCursor;
  String? _denomCursor;
  String? _coinCursor;
  List<CatalogProduct> _products = const [];
  List<CatalogDenomination> _denoms = const [];
  List<CatalogCoin> _coins = const [];
  final _pending = const PendingFinancialCommands();
  Map<String, Object?>? _frozenBody;
  final _guideScroll = ScrollController();
  final _gramsFocus = FocusNode();
  final _tenderFocus = FocusNode();
  int _step = 0;

  bool get _fastEntry =>
      widget.exchangeReturnPayload == null &&
      (widget.kind == FinancialKind.sale ||
          widget.kind == FinancialKind.purchase);

  String get _title => widget.exchangeReturnPayload != null
      ? 'البديل في الاستبدال'
      : switch (widget.kind) {
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
    if (widget.kind == FinancialKind.expense) _step = 2;
    if (widget.catalog != null) {
      _catalogLoading = true;
      unawaited(_loadCatalogPages());
    }
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
      final parsed = Piastres.parsePounds(cashInputValue(tender.amount.text));
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
              ? cashInputValue(_purchaseTotal.text)
              : _totalPounds() ?? ''),
      items: [
        for (final item in _items)
          FinancialItemInput(
            category: item.category,
            karat: item.karat,
            grams: item.grams.text,
            count: item.count.text,
            name: item.name.text,
            linePricePounds: cashInputValue(item.price.text),
          ),
      ],
      tenders: [
        for (final tender in _tenders)
          if (widget.kind != FinancialKind.purchase ||
              tender.amount.text.trim().isNotEmpty)
            FinancialTenderInput(
              method: tender.method,
              pounds: cashInputValue(tender.amount.text),
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
    basePounds: cashInputValue(_basePrice.text),
    workmanshipPounds: cashInputValue(_workmanship.text),
    otherChargesPounds: cashInputValue(_otherCharges.text),
    otherChargesLabel: _otherChargesLabel.text,
    discountPounds: cashInputValue(_discount.text),
  );

  Widget _priceField(
    String key,
    String label,
    TextEditingController controller,
  ) => TextField(
    key: Key(key),
    controller: controller,
    inputFormatters: const [CashInputFormatter()],
    textDirection: TextDirection.ltr,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    textInputAction: TextInputAction.next,
    onChanged: (_) => setState(() {
      if (_fastEntry) _priceDetails = true;
    }),
    onSubmitted: (_) => FocusScope.of(context).nextFocus(),
    decoration: ledgerFieldDecoration(context, label: label),
  );

  List<Widget> _pricingFields(ThemeData theme) {
    final result = _composePricing();
    return [
      _priceField('trade-base-price', 'السعر الأساسي ', _basePrice),
      const SizedBox(height: 12),
      LedgerFieldPair(
        first: _priceField('trade-workmanship', 'المصنعية ', _workmanship),
        second: _priceField('trade-discount', 'الخصم ', _discount),
      ),
      const SizedBox(height: 12),
      LedgerFieldPair(
        first: _priceField('trade-other-charges', 'رسوم أخرى ', _otherCharges),
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
        'الإجمالي بعد التعديلات: ${result is Accepted<InvoicePricing> ? displayPounds(result.value.total.poundsText) : '—'}',
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
      final returnSide = widget.exchangeReturnPayload;
      final exchange = returnSide == null
          ? null
          : <String, Object?>{
              'version': 1,
              'kind': 'exchange',
              'expected_day_id': returnSide['expected_day_id'],
              'expected_day_version': returnSide['expected_day_version'],
              'note': returnSide['note'],
              'return': Map<String, Object?>.from(returnSide)
                ..remove('version')
                ..remove('expected_day_id')
                ..remove('expected_day_version'),
              'replacement': draft.toJson(),
            };
      _frozenBody ??= {
        'p_idempotency_key': _key!,
        'p_payload': exchange ?? draft.toJson(),
      };
      await _pending.save(
        widget.userId,
        widget.shopId,
        PendingFinancialCommand(
          key: _key!,
          kind: exchange != null
              ? 'exchange'
              : widget.kind == FinancialKind.scrapSale
              ? 'scrap_sale'
              : widget.kind.name,
          body: _frozenBody!,
        ),
      );
      commandSaved = true;
      final result = exchange != null
          ? await (widget.gateway as ExchangeGateway).postExchange(
              callerUserId: widget.userId,
              idempotencyKey: _key!,
              payload: Map<String, Object?>.from(
                _frozenBody!['p_payload']! as Map,
              ),
            )
          : await widget.gateway.postTrade(
              callerUserId: widget.userId,
              idempotencyKey: _key!,
              draft: draft,
            );
      if (!mounted) return;
      if (result is FinancialCommitted) {
        await _pending.clear(widget.userId, widget.shopId, _key!);
        if (!mounted) return;
        setState(() {
          _committed = true;
          _operationId = result.operationId;
          _unknown = false;
          _error = null;
        });
        return;
      }
      if (result is FinancialRejected) {
        await _pending.clear(widget.userId, widget.shopId, _key!);
        if (!mounted) return;
        setState(() {
          _unknown = false;
          _error = _serverCopy(result.code);
          _key = null;
          _frozenBody = null;
          if (widget.exchangeReturnPayload != null) _review = null;
        });
        return;
      }
      await _reconcile();
    } catch (_) {
      if (mounted) {
        setState(() {
          _unknown = commandSaved;
          if (!commandSaved) {
            _key = null;
            _frozenBody = null;
          }
          _error = commandSaved
              ? 'حالة العملية غير مؤكدة. تحقق من الحالة قبل المتابعة.'
              : 'تعذر حفظ طلب الانتظار. راجع أي عملية معلقة وحاول مجدداً.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkStatus() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _reconcile();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذر التحقق من الحالة. حاول مرة أخرى.');
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
      setState(() {
        _committed = true;
        _operationId = status.operationId;
        _unknown = false;
        _error = null;
      });
    } else if (status is StatusAbsent) {
      setState(() {
        _unknown = false;
        _error = 'لم نتأكد من حفظ العملية. أعد المحاولة دون تغيير البيانات.';
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
          automaticallyImplyLeading: !widget.sheet,
          title: Text(widget.practice ? 'تدريب على أول بيع' : _title),
          actions: [
            if (widget.sheet)
              IconButton(
                key: const Key('trade-sheet-close'),
                tooltip: 'إغلاق',
                onPressed: _busy || _unknown
                    ? null
                    : () => Navigator.pop(context, false),
                icon: const Icon(Icons.close),
              ),
          ],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          _error!,
                          key: const Key('trade-message'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: ListView(
                      controller: _guideScroll,
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                      children: [
                        if (widget.practice) ...[
                          const Text(
                            'مسودة تدريب فقط — لن يُحفظ بيع ولن يتغير النقد أو الذهب.',
                            key: Key('practice-draft-label'),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_committed)
                          ..._successWidgets(theme)
                        else if (_review == null)
                          ..._stepWidgets(theme)
                        else
                          ..._reviewWidgets(theme),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
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
                  child: _committed
                      ? FilledButton(
                          key: const Key('trade-done'),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('العودة إلى الدفتر'),
                        )
                      : _unknown
                      ? FilledButton.icon(
                          key: const Key('trade-check-status'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          onPressed: _busy ? null : _checkStatus,
                          icon: const Icon(Icons.sync),
                          label: const Text('التحقق من الحالة'),
                        )
                      : FilledButton(
                          key: Key(
                            _review != null
                                ? 'trade-confirm'
                                : _fastEntry ||
                                      _step == 3 ||
                                      widget.kind == FinancialKind.expense
                                ? 'trade-review'
                                : 'trade-next',
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          onPressed: _busy
                              ? null
                              : _review == null
                              ? (_fastEntry ? _reviewFast : _nextStep)
                              : _submit,
                          child: Text(
                            _busy
                                ? 'جارٍ حفظ العملية…'
                                : _review == null
                                ? (_fastEntry ||
                                          _step == 3 ||
                                          widget.kind == FinancialKind.expense
                                      ? 'مراجعة العملية'
                                      : 'التالي')
                                : widget.practice
                                ? 'إنهاء التدريب دون حفظ'
                                : widget.exchangeReturnPayload != null
                                ? 'تأكيد الاستبدال'
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

  void _reviewFast() {
    FocusScope.of(context).unfocus();
    if (!_itemsReady()) return;
    _startReview();
  }

  bool _itemsReady() {
    for (final row in _items) {
      if (row.customName && row.name.text.trim().isEmpty) {
        row.name.text = 'أخرى';
      }
    }
    if (_items.any((row) => row.name.text.trim().isEmpty)) {
      setState(() => _error = 'اختر الصنف.');
      return false;
    }
    for (final row in _items) {
      final grams = Milligrams.parseGrams(row.grams.text);
      final count = PieceCount.parseWire(row.count.text);
      if (row.name.text.trim().isEmpty ||
          grams is! Accepted<Milligrams> ||
          grams.value.value == BigInt.zero ||
          (row.category != 'scrap' &&
              (count is! Accepted<PieceCount> ||
                  count.value.value == BigInt.zero))) {
        setState(() => _error = 'راجع اسم الصنف والعدد والوزن.');
        return false;
      }
    }
    return true;
  }

  void _nextStep() {
    FocusScope.of(context).unfocus();
    for (final row in _items) {
      if (row.customName && row.name.text.trim().isEmpty) {
        row.name.text = 'أخرى';
      }
    }
    if (_step == 0 && _items.any((row) => row.name.text.trim().isEmpty)) {
      setState(() => _error = 'اختر الصنف.');
      return;
    }
    if (_step == 1) {
      for (final row in _items) {
        final grams = Milligrams.parseGrams(row.grams.text);
        final count = PieceCount.parseWire(row.count.text);
        if (row.name.text.trim().isEmpty ||
            grams is! Accepted<Milligrams> ||
            grams.value.value == BigInt.zero ||
            (row.category != 'scrap' &&
                (count is! Accepted<PieceCount> ||
                    count.value.value == BigInt.zero))) {
          setState(() => _error = 'راجع اسم الصنف والعدد والوزن.');
          return;
        }
      }
    }
    if (_step == 3 || widget.kind == FinancialKind.expense) {
      _startReview();
      return;
    }
    setState(() {
      _step++;
      _error = null;
    });
    _guideScroll.jumpTo(0);
  }

  Widget _progress(ThemeData theme) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      children: [
        for (var index = 0; index < 5; index++)
          Expanded(
            child: Semantics(
              selected: (_review == null ? _step : 4) == index,
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: (_review == null ? _step : 4) == index
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    foregroundColor: (_review == null ? _step : 4) == index
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurfaceVariant,
                    child: Text(
                      '${index + 1}',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    const [
                      'الصنف',
                      'البيانات',
                      'الدفع',
                      'التفاصيل',
                      'تأكيد',
                    ][index],
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  List<Widget> _stepWidgets(ThemeData theme) {
    if (_fastEntry) return _fastEntryWidgets(theme);
    return [
      if (widget.kind != FinancialKind.expense) _progress(theme),
      if (_step == 0) ...[
        Text('اختر الصنف', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        _categoryChooser(theme),
      ],
      if (_step == 1) ...[
        Text('تفاصيل الأصناف', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        for (var index = 0; index < _items.length; index++) ...[
          _itemCard(index, theme),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          key: const Key('trade-add-item'),
          icon: const Icon(Icons.add),
          label: const Text('إضافة صنف آخر'),
          onPressed: () => setState(() {
            _items.add(
              _ItemEntry(scrap: widget.kind == FinancialKind.scrapSale),
            );
            _step = 0;
          }),
        ),
      ],
      if (_step == 2) ...[
        Text('طرق الدفع', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        if (widget.kind == FinancialKind.expense) ...[
          TextField(
            key: const Key('trade-description'),
            controller: _description,
            decoration: ledgerFieldDecoration(context, label: 'وصف المصروف'),
          ),
          const SizedBox(height: 16),
        ],
        if (widget.kind == FinancialKind.purchase) ...[
          TextField(
            key: const Key('trade-purchase-price'),
            controller: _purchaseTotal,
            inputFormatters: const [CashInputFormatter()],
            textDirection: TextDirection.ltr,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: ledgerFieldDecoration(
              context,
              label: 'سعر الشراء الكلي ',
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('trade-seller-name'),
            controller: _customerName,
            decoration: ledgerFieldDecoration(
              context,
              label: 'اسم العميل (اختياري)',
            ),
          ),
          const SizedBox(height: 16),
        ],
        for (var index = 0; index < _tenders.length; index++) ...[
          _tenderCard(index),
          const SizedBox(height: 12),
        ],
        if (_tenders.length < 4)
          OutlinedButton.icon(
            key: const Key('trade-add-tender'),
            onPressed: () {
              final used = _tenders.map((r) => r.method).toSet();
              setState(
                () => _tenders.add(
                  _TenderEntry(
                    CashMethod.canonicalOrder.firstWhere(
                      (method) => !used.contains(method),
                    ),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('إضافة طريقة دفع'),
          ),
        const SizedBox(height: 16),
        Text(
          'الإجمالي: ${displayPounds(_totalPounds() ?? '—')}',
          style: theme.textTheme.titleLarge,
        ),
        if (widget.kind == FinancialKind.sale ||
            widget.kind == FinancialKind.purchase) ...[
          CheckboxListTile(
            key: const Key('trade-price-details'),
            value: _priceDetails,
            title: const Text('تفصيل السعر والمصنعية'),
            contentPadding: EdgeInsets.zero,
            onChanged: (value) =>
                setState(() => _priceDetails = value ?? false),
          ),
          if (_priceDetails) ..._pricingFields(theme),
        ],
      ],
      if (_step == 3) ...[
        Text('تفاصيل إضافية (اختياري)', style: theme.textTheme.titleLarge),
        const SizedBox(height: 16),
        if (widget.kind != FinancialKind.purchase) ...[
          TextField(
            key: const Key('trade-customer-name'),
            controller: _customerName,
            decoration: ledgerFieldDecoration(context, label: 'اسم العميل'),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          key: const Key('trade-customer-phone'),
          controller: _customerPhone,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.phone,
          decoration: ledgerFieldDecoration(context, label: 'رقم الهاتف'),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('trade-note'),
          controller: _note,
          maxLines: 3,
          decoration: ledgerFieldDecoration(context, label: 'ملاحظات'),
        ),
      ],
      if (_step > 0 && widget.kind != FinancialKind.expense)
        TextButton.icon(
          key: const Key('trade-back'),
          onPressed: () => setState(() {
            _step--;
            _error = null;
          }),
          icon: const Icon(Icons.arrow_back),
          label: const Text('رجوع'),
        ),
    ];
  }

  List<Widget> _fastEntryWidgets(ThemeData theme) => [
    Text('الصنف والوزن والدفع', style: theme.textTheme.titleLarge),
    const SizedBox(height: 8),
    Text(
      'العميل والتفاصيل اختيارية. راجع الأثر قبل التأكيد.',
      style: theme.textTheme.bodyMedium,
    ),
    const SizedBox(height: 12),
    _categoryChooser(theme),
    const SizedBox(height: 12),
    for (var index = 0; index < _items.length; index++) ...[
      _itemCard(index, theme),
      const SizedBox(height: 12),
    ],
    OutlinedButton.icon(
      key: const Key('trade-add-item'),
      icon: const Icon(Icons.add),
      label: const Text('إضافة صنف آخر'),
      onPressed: () => setState(() => _items.add(_ItemEntry(scrap: false))),
    ),
    const SizedBox(height: 16),
    ..._paymentFields(theme),
    ExpansionTile(
      key: const Key('trade-customer-disclosure'),
      title: const Text('تفاصيل العميل (اختياري)'),
      children: [
        TextField(
          key: const Key('trade-customer-name'),
          controller: _customerName,
          decoration: ledgerFieldDecoration(
            context,
            label: 'اسم العميل (اختياري)',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('trade-customer-phone'),
          controller: _customerPhone,
          textDirection: TextDirection.ltr,
          keyboardType: TextInputType.phone,
          decoration: ledgerFieldDecoration(context, label: 'رقم الهاتف'),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('trade-note'),
          controller: _note,
          maxLines: 3,
          decoration: ledgerFieldDecoration(context, label: 'ملاحظات'),
        ),
      ],
    ),
  ];

  Widget _categoryChooser(ThemeData theme) {
    final choices = <(String, String, Widget)>[
      if (widget.kind != FinancialKind.scrapSale) ...[
        ('خاتم', 'worked_jewelry', const JewelryGlyph(JewelryKind.ring)),
        ('حلق', 'worked_jewelry', const JewelryGlyph(JewelryKind.earrings)),
        ('سلسلة', 'worked_jewelry', const JewelryGlyph(JewelryKind.necklace)),
        ('تعليقة', 'worked_jewelry', const JewelryGlyph(JewelryKind.pendant)),
        ('دبلة', 'worked_jewelry', const Icon(Icons.circle_outlined)),
        ('غويشة', 'worked_jewelry', const Icon(Icons.circle_outlined)),
        ('إسورة', 'worked_jewelry', const Icon(Icons.link_outlined)),
        ('خلخال', 'worked_jewelry', const Icon(Icons.link_outlined)),
        ('طقم', 'worked_jewelry', const Icon(Icons.diamond_outlined)),
        ('جنيهات', 'coin', const JewelryGlyph(JewelryKind.coin)),
        ('سبائك', 'bullion', const JewelryGlyph(JewelryKind.bullion)),
      ],
      if (widget.kind == FinancialKind.purchase ||
          widget.kind == FinancialKind.scrapSale)
        ('كسر', 'scrap', const Icon(Icons.content_cut_outlined)),
      if (widget.kind != FinancialKind.scrapSale)
        ('أخرى', 'worked_jewelry', const Icon(Icons.category_outlined)),
    ];
    const extra = {'دبلة', 'غويشة', 'إسورة', 'خلخال', 'طقم'};
    Widget grid(Iterable<(String, String, Widget)> choices) => LayoutBuilder(
      builder: (context, size) {
        final columns = size.maxWidth < 360 ? 3 : 4;
        final width = (size.maxWidth - 8 * (columns - 1)) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final choice in choices)
              SizedBox(
                width: width,
                child: OutlinedButton(
                  key: Key('trade-select-${choice.$1}'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 10,
                    ),
                    minimumSize: const Size(48, 48),
                    backgroundColor: _choiceSelected(choice.$1)
                        ? theme.colorScheme.primaryContainer
                        : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => setState(() {
                    final item = _items.last;
                    item.customName = choice.$1 == 'أخرى';
                    item.name.text = choice.$1;
                    item.category = choice.$2;
                    item.karat = choice.$2 == 'bullion'
                        ? 24
                        : choice.$2 == 'coin'
                        ? 21
                        : 18;
                  }),
                  child: Column(
                    children: [
                      choice.$3,
                      const SizedBox(height: 8),
                      Text(choice.$1, textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_fastEntry)
          grid(choices)
        else ...[
          grid(choices.where((choice) => !extra.contains(choice.$1))),
          ExpansionTile(
            key: const Key('trade-extra-categories'),
            title: const Text('أصناف إضافية'),
            children: [
              grid(choices.where((choice) => extra.contains(choice.$1))),
            ],
          ),
        ],

        if (_items.last.customName) ...[
          const SizedBox(height: 12),
          TextField(
            key: const Key('trade-select-name'),
            controller: _items.last.name,
            decoration: ledgerFieldDecoration(
              context,
              label: 'اسم الصنف (اختياري)',
            ),
          ),
          const SizedBox(height: 8),
          _catalogSection(theme),
        ],
      ],
    );
  }

  bool _choiceSelected(String label) {
    final item = _items.last;
    if (label == 'أخرى') return item.customName;
    if (label == 'جنيهات') return !item.customName && item.category == 'coin';
    if (label == 'سبائك') return !item.customName && item.category == 'bullion';
    return !item.customName && item.name.text == label;
  }

  bool get _canSendInvoice =>
      widget.kind == FinancialKind.sale &&
      widget.gateway is InvoiceDispatchGateway &&
      _operationId != null &&
      _operationId!.isNotEmpty;

  Future<void> _loadCatalogPages() async {
    final gateway = widget.catalog;
    if (gateway == null) {
      if (mounted) setState(() => _catalogLoading = false);
      return;
    }
    final generation = ++_catalogGeneration;
    try {
      final products = await gateway.products(callerUserId: widget.userId);
      final denoms = await gateway.denominations(callerUserId: widget.userId);
      final coins = await gateway.coins(callerUserId: widget.userId);
      if (!mounted || generation != _catalogGeneration) return;
      setState(() {
        _rememberProducts(products, reset: true);
        _nominalFailed = !denoms.available || !coins.available;
        _rememberDenoms(denoms, reset: true);
        _rememberCoins(coins, reset: true);
        _catalogLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _catalogGeneration) return;
      setState(() {
        _catalogLoading = false;
        _catalogFailed = true;
        _nominalFailed = true;
      });
    }
  }

  void _rememberProducts(ReadPage<CatalogProduct> page, {required bool reset}) {
    if (!page.available) {
      _catalogFailed = true;
      return;
    }
    _catalogFailed = false;
    _products = reset
        ? List<CatalogProduct>.of(page.items!)
        : [..._products, ...page.items!];
    _productCursor = page.nextCursor;
  }

  void _rememberDenoms(
    ReadPage<CatalogDenomination> page, {
    required bool reset,
  }) {
    if (!page.available) {
      _nominalFailed = true;
      return;
    }
    _denoms = reset
        ? List<CatalogDenomination>.of(page.items!)
        : [..._denoms, ...page.items!];
    _denomCursor = page.nextCursor;
  }

  void _rememberCoins(ReadPage<CatalogCoin> page, {required bool reset}) {
    if (!page.available) {
      _nominalFailed = true;
      return;
    }
    _coins = reset
        ? List<CatalogCoin>.of(page.items!)
        : [..._coins, ...page.items!];
    _coinCursor = page.nextCursor;
  }

  Future<void> _moreProducts() async {
    final gateway = widget.catalog;
    final cursor = _productCursor;
    if (gateway == null || cursor == null || _catalogLoading) return;
    final generation = _catalogGeneration;
    setState(() => _catalogLoading = true);
    try {
      final page = await gateway.products(
        callerUserId: widget.userId,
        cursor: cursor,
      );
      if (!mounted || generation != _catalogGeneration) return;
      setState(() {
        _catalogLoading = false;
        _rememberProducts(page, reset: false);
      });
    } catch (_) {
      if (!mounted || generation != _catalogGeneration) return;
      setState(() {
        _catalogLoading = false;
        _catalogFailed = true;
      });
    }
  }

  Future<void> _moreNominal(String category) async {
    final gateway = widget.catalog;
    final cursor = category == 'bullion' ? _denomCursor : _coinCursor;
    if (gateway == null || cursor == null || _catalogLoading) return;
    final generation = _catalogGeneration;
    setState(() => _catalogLoading = true);
    try {
      if (category == 'bullion') {
        final page = await gateway.denominations(
          callerUserId: widget.userId,
          cursor: cursor,
        );
        if (!mounted || generation != _catalogGeneration) return;
        setState(() {
          _catalogLoading = false;
          if (page.available) _nominalFailed = false;
          _rememberDenoms(page, reset: false);
        });
      } else {
        final page = await gateway.coins(
          callerUserId: widget.userId,
          cursor: cursor,
        );
        if (!mounted || generation != _catalogGeneration) return;
        setState(() {
          _catalogLoading = false;
          if (page.available) _nominalFailed = false;
          _rememberCoins(page, reset: false);
        });
      }
    } catch (_) {
      if (!mounted || generation != _catalogGeneration) return;
      setState(() {
        _catalogLoading = false;
        _nominalFailed = true;
      });
    }
  }

  Future<void> _openInventory() async {
    final page = widget.inventoryPage;
    if (page == null || _busy || _unknown) return;
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute<void>(builder: page));
    if (!mounted) return;
    setState(() => _catalogLoading = true);
    await _loadCatalogPages();
  }

  bool _productAllowed(CatalogProduct product) {
    if (product.category == 'scrap') {
      return widget.kind == FinancialKind.purchase &&
          ScrapKarats.allowed.contains(product.karat);
    }
    final category = StockCategory.byCode(product.category);
    return category != null && category.karats.contains(product.karat);
  }

  void _applyProduct(CatalogProduct product) {
    if (!_productAllowed(product)) return;
    final item = _items.last;
    setState(() {
      item.customName = true;
      item.name.text = product.name;
      item.category = product.category;
      item.karat = product.karat;
    });
  }

  List<CatalogNominalChoice> _nominalChoices(String category) {
    if (category == 'bullion') {
      return [
        for (final item in _denoms)
          CatalogNominalChoice(
            label: item.label,
            grams: _gramsFromMilligrams(item.nominalMilligrams),
            active: item.active,
          ),
      ];
    }
    if (category == 'coin') {
      return [
        for (final item in _coins)
          CatalogNominalChoice(
            label: item.label,
            grams: item.nominalMilligrams == null
                ? null
                : _gramsFromMilligrams(item.nominalMilligrams!),
            active: item.active,
          ),
      ];
    }
    return const [];
  }

  String? _gramsFromMilligrams(BigInt milligrams) {
    final parsed = Milligrams.parseWire(milligrams.toString());
    return parsed is Accepted<Milligrams> ? parsed.value.gramsText : null;
  }

  List<Widget> _paymentFields(ThemeData theme) => [
    Text('الدفع', style: theme.textTheme.titleLarge),
    const SizedBox(height: 12),
    if (widget.kind == FinancialKind.purchase) ...[
      TextField(
        key: const Key('trade-purchase-price'),
        controller: _purchaseTotal,
        inputFormatters: const [CashInputFormatter()],
        textDirection: TextDirection.ltr,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: (_) => setState(() {}),
        decoration: ledgerFieldDecoration(context, label: 'سعر الشراء الكلي '),
      ),
      const SizedBox(height: 8),
      Text(
        'يمكن ترك المدفوع فارغاً أو أقل من سعر الشراء. يبقى الفرق مستحقاً للعميل.',
        style: theme.textTheme.bodySmall,
      ),
      const SizedBox(height: 12),
    ],
    for (var index = 0; index < _tenders.length; index++) ...[
      _tenderCard(index),
      const SizedBox(height: 12),
    ],
    if (_tenders.length < 4)
      OutlinedButton.icon(
        key: const Key('trade-add-tender'),
        onPressed: () {
          final used = _tenders.map((row) => row.method).toSet();
          setState(
            () => _tenders.add(
              _TenderEntry(
                CashMethod.canonicalOrder.firstWhere(
                  (method) => !used.contains(method),
                ),
              ),
            ),
          );
        },
        icon: const Icon(Icons.add),
        label: const Text('إضافة طريقة دفع'),
      ),
    const SizedBox(height: 12),
    Text(
      widget.kind == FinancialKind.purchase
          ? 'المدفوع الآن: ${displayPounds(_totalPounds() ?? '—')}'
          : 'الإجمالي: ${displayPounds(_totalPounds() ?? '—')}',
      key: const Key('trade-paid-total'),
      style: theme.textTheme.titleLarge,
    ),
  ];

  Widget _catalogSection(ThemeData theme) {
    final products = _products.where(_productAllowed).toList();
    final border = AppSemanticColors.of(context).tableBorder;
    if (widget.catalog == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.inventoryPage != null) _inventoryButton(),
          const Text(
            'قائمة الأصناف غير متاحة. أدخل الاسم والفئة يدوياً.',
            key: Key('trade-catalog-manual'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.inventoryPage != null) ...[
          _inventoryButton(),
          const SizedBox(height: 8),
        ],
        if (_catalogLoading)
          const LinearProgressIndicator(key: Key('trade-catalog-loading')),
        if (_catalogFailed)
          TextButton.icon(
            key: const Key('trade-catalog-retry'),
            onPressed: _catalogLoading
                ? null
                : () {
                    setState(() {
                      _catalogLoading = true;
                      _catalogFailed = false;
                    });
                    unawaited(_loadCatalogPages());
                  },
            icon: const Icon(Icons.refresh),
            label: const Text('تعذر تحميل المنتجات. إعادة المحاولة'),
          )
        else if (products.isEmpty && !_catalogLoading)
          const Text(
            'لا توجد منتجات في الكتالوج. اكتب الاسم والفئة يدوياً.',
            key: Key('trade-catalog-empty'),
          )
        else if (products.isNotEmpty)
          DecoratedBox(
            key: const Key('trade-catalog-table'),
            decoration: BoxDecoration(
              border: Border.all(color: border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('الصنف', style: theme.textTheme.labelLarge),
                      ),
                      Text('الفئة', style: theme.textTheme.labelLarge),
                      const SizedBox(width: 12),
                      Text('العيار', style: theme.textTheme.labelLarge),
                    ],
                  ),
                ),
                for (final product in products)
                  TextButton(
                    key: Key('trade-product-${product.id}'),
                    onPressed: () => _applyProduct(product),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: RoundedRectangleBorder(
                        side: BorderSide(color: border),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(product.name)),
                          Text(_productCategoryLabel(product.category)),
                          const SizedBox(width: 12),
                          Text('${product.karat}'),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (!_catalogFailed && _productCursor != null)
          OutlinedButton(
            key: const Key('trade-catalog-more'),
            onPressed: _catalogLoading ? null : _moreProducts,
            child: const Text('المزيد من المنتجات'),
          ),
      ],
    );
  }

  Widget _inventoryButton() => OutlinedButton.icon(
    key: const Key('trade-open-inventory'),
    onPressed: _busy || _unknown ? null : _openInventory,
    icon: const Icon(Icons.inventory_2_outlined),
    label: const Text('المخزون'),
  );

  String _productCategoryLabel(String code) {
    final category = StockCategory.byCode(code);
    if (category != null) return stockCategoryLabel(category);
    if (code == 'scrap') return 'كسر';
    return 'صنف';
  }

  List<Widget> _nominalWidgets(_ItemEntry row, int index) {
    if (row.category != 'coin' && row.category != 'bullion') return const [];
    final suggestions = nominalSuggestionsFor(
      category: row.category,
      catalog: _nominalChoices(row.category),
    );
    final more = row.category == 'bullion' ? _denomCursor : _coinCursor;
    return [
      const SizedBox(height: 8),
      Text(
        'أوزان مقترحة — الوزن قابل للتعديل.',
        key: Key('trade-nominal-note-$index'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final suggestion in suggestions)
            ActionChip(
              key: Key('trade-nominal-$index-${suggestion.label}'),
              label: Text(
                '${suggestion.label} · ${displayGrams(suggestion.grams)}',
              ),
              onPressed: () => setState(() {
                row.grams.text = suggestion.grams;
                row.name.text = suggestion.label;
              }),
            ),
        ],
      ),
      if (widget.catalog != null && _nominalFailed)
        TextButton.icon(
          key: Key('trade-nominal-retry-$index'),
          onPressed: _catalogLoading
              ? null
              : () {
                  setState(() {
                    _catalogLoading = true;
                    _nominalFailed = false;
                  });
                  unawaited(_loadCatalogPages());
                },
          icon: const Icon(Icons.refresh),
          label: const Text('تعذر تحميل الأوزان الاسمية. إعادة المحاولة'),
        ),
      if (widget.catalog != null && !_nominalFailed && more != null)
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            key: Key('trade-nominal-more-$index'),
            onPressed: _catalogLoading
                ? null
                : () => _moreNominal(row.category),
            child: const Text('المزيد من الأوزان الاسمية'),
          ),
        ),
    ];
  }

  Future<void> _openInvoice() async {
    final operationId = _operationId;
    if (!_canSendInvoice ||
        operationId == null ||
        _invoiceBusy ||
        widget.gateway is! InvoiceDispatchGateway) {
      return;
    }
    setState(() => _invoiceBusy = true);
    try {
      final operation = await widget.gateway.operation(
        callerUserId: widget.userId,
        operationId: operationId,
      );
      if (!mounted) return;
      final line = _confirmedFeedLine(operation, operationId);
      if (line == null) {
        setState(() {
          _error = 'تعذر تحميل بيانات الفاتورة. حاول مرة أخرى.';
        });
        return;
      }
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => FinancialOperationScreen(
            gateway: widget.gateway,
            userId: widget.userId,
            line: line,
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذر تحميل الفاتورة المؤكدة.');
      }
    } finally {
      if (mounted) setState(() => _invoiceBusy = false);
    }
  }

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
            else if (row.customName)
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
                },
              ),
            const SizedBox(height: 12),
            Text(row.name.text, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            if (categoryCode != 'scrap')
              LedgerFieldPair(
                breakpoint:
                    _fastEntry &&
                        MediaQuery.textScalerOf(context).scale(1) <= 1.3
                    ? 240
                    : 440,
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
                    helper: 'دقة 0.001 جرام',
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
                  helper: 'دقة 0.001 جرام',
                ),
              ),
            ..._nominalWidgets(row, index),
            const SizedBox(height: 12),
            if (_fastEntry)
              DropdownButtonFormField<int>(
                key: Key('trade-karat-$index-${row.category}-${row.karat}'),
                initialValue: row.karat,
                isExpanded: true,
                decoration: ledgerFieldDecoration(context, label: 'العيار'),
                items: [
                  for (final karat in karats)
                    DropdownMenuItem(value: karat, child: Text('$karat')),
                ],
                onChanged: (value) =>
                    setState(() => row.karat = value ?? row.karat),
              )
            else
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
                  inputFormatters: const [CashInputFormatter()],
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
                  inputFormatters: const [CashInputFormatter()],
                  focusNode: index == 0 ? _tenderFocus : null,
                  onChanged: (_) => setState(() {}),
                  textDirection: TextDirection.ltr,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  decoration: ledgerFieldDecoration(context, label: 'المبلغ'),
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

  String _reviewMilligrams() => _review!.items
      .fold(
        BigInt.zero,
        (sum, item) => sum + BigInt.parse(item['milligrams'] as String),
      )
      .toString();

  String _reviewWeightEffect() =>
      displayGoldEffect(BigInt.parse(_reviewMilligrams()));

  /// Presentation-only two-decimal gold. Stored milligrams stay exact.
  String _reviewWeightShown() => displayGrams(_reviewMilligrams());

  List<Widget> _successWidgets(ThemeData theme) => [
    const SizedBox(height: 40),
    Icon(Icons.check_circle, size: 72, color: theme.colorScheme.tertiary),
    const SizedBox(height: 20),
    Text(
      'تمت العملية بنجاح',
      key: const Key('trade-success'),
      textAlign: TextAlign.center,
      style: theme.textTheme.headlineSmall,
    ),
    const SizedBox(height: 12),
    Text(
      'الإجمالي: ${displayPounds(_review!.total.poundsText)}',
      textAlign: TextAlign.center,
      style: theme.textTheme.titleLarge,
    ),
    if (_review!.items.isNotEmpty)
      Text(
        'وزن الذهب: ${_reviewWeightShown()} جرام',
        key: const Key('trade-success-weight'),
        textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium,
      ),
    if (_canSendInvoice) ...[
      const SizedBox(height: 16),
      const Text(
        'لا يُرسل التطبيق الفاتورة تلقائياً. افتح الفاتورة المؤكدة ثم أرسلها بنفسك.',
        key: Key('trade-invoice-manual'),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const Key('trade-send-invoice'),
        onPressed: _invoiceBusy ? null : _openInvoice,
        icon: const Icon(Icons.receipt_long_outlined),
        label: const Text('إرسال الفاتورة للعميل'),
      ),
    ],
  ];

  List<Widget> _reviewWidgets(ThemeData theme) {
    final draft = _review!;
    return [
      _progress(theme),
      Text('مراجعة العملية', style: theme.textTheme.headlineSmall),
      const SizedBox(height: 12),
      Card(
        key: const Key('trade-review-summary'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'الإجمالي: ${displayPounds(draft.total.poundsText)}',
                style: theme.textTheme.headlineMedium,
              ),
              if (draft.items.isNotEmpty)
                Text(
                  'وزن الذهب: ${_reviewWeightShown()} جرام',
                  key: const Key('trade-review-weight'),
                  style: theme.textTheme.titleMedium,
                ),
              const Divider(height: 24),
              if (draft.pricing case final pricing?) ...[
                Text(
                  'السعر الأساسي: ${displayPounds(pricing.base.poundsText)}',
                ),
                Text(
                  'المصنعية: ${displayPounds(pricing.workmanship.poundsText)}',
                ),
                Text(
                  'رسوم أخرى${pricing.otherChargesLabel.isEmpty ? '' : ' (${pricing.otherChargesLabel})'}: ${displayPounds(pricing.otherCharges.poundsText)}',
                ),
                Text('الخصم: ${displayPounds(pricing.discount.poundsText)}'),
                Text(
                  'الإجمالي المتفق عليه: ${displayPounds(pricing.total.poundsText)}',
                ),
                const SizedBox(height: 16),
              ],
              if (draft.items.isNotEmpty)
                Text('الأصناف', style: theme.textTheme.titleSmall),
              for (final item in draft.items)
                ListTile(
                  title: Text('${item['item_name']} · عيار ${item['karat']}'),
                  subtitle: Text(
                    item['category'] == 'scrap'
                        ? 'كسر'
                        : '${stockCategoryLabel(StockCategory.byCode(item['category'] as String)!)} · ${item['count']} قطعة',
                  ),
                  trailing: Text(
                    '${displayGrams(item['milligrams'] as String)} جرام',
                  ),
                ),
              if (draft.tenders.isNotEmpty) ...[
                const Divider(height: 24),
                Text('طريقة الدفع', style: theme.textTheme.titleSmall),
              ],
              for (final tender in draft.tenders)
                ListTile(
                  title: Text(
                    cashMethodLabel(
                      CashMethod.canonicalOrder.firstWhere(
                        (method) => method.code == tender['method'],
                      ),
                    ),
                  ),
                  trailing: Text(_poundsText(tender['piastres'] as String)),
                ),
              if (draft.customerName.isNotEmpty)
                Text('العميل: ${draft.customerName}'),
              if (draft.note.isNotEmpty) Text('ملاحظة: ${draft.note}'),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
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
                displayPounds(draft.cashPaid.poundsText),
                textDirection: TextDirection.ltr,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              if (draft.purchasePayable != null) ...[
                Text(
                  'يبقى مستحقاً للعميل: ${displayPounds(draft.purchasePayable!.poundsText)}',
                ),
                Text(
                  'سعر الشراء الكلي: ${displayPounds(draft.total.poundsText)}',
                ),
                if (draft.customerName.isNotEmpty)
                  Text('العميل: ${draft.customerName}'),
                const SizedBox(height: 8),
              ],
              Text(
                key: const Key('trade-review-net'),
                widget.kind == FinancialKind.sale
                    ? 'ينقص المخزون بمقدار ${_reviewWeightEffect()}'
                    : widget.kind == FinancialKind.scrapSale
                    ? 'ينقص الكسر بمقدار ${_reviewWeightEffect()}'
                    : widget.kind == FinancialKind.purchase
                    ? 'تنتقل الملكية إلى المتجر الآن ويزيد الذهب بمقدار ${_reviewWeightEffect()}'
                    : 'لا يتغير الذهب',
              ),
            ],
          ),
        ),
      ),
      if (widget.exchangeReturnReview != null)
        ExchangeEffectReview(
          returnSide: widget.exchangeReturnReview!,
          replacement: draft,
        ),
      const SizedBox(height: 16),
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

/// Sale and purchase entry. The sheet stays at most 84% of the space above
/// the keyboard, and barrier or drag dismissal cannot skip a pending result.
Future<bool?> showFinancialTradeSheet({
  required BuildContext context,
  required FinancialKind kind,
  required FinancialGateway gateway,
  required OpeningGateway statusGateway,
  required String userId,
  required String shopId,
  InventoryGateway? catalog,
  WidgetBuilder? inventoryPage,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
    showDragHandle: false,
    constraints: const BoxConstraints(maxWidth: AppTokens.contentMaxWidth),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (sheetContext) {
      final inset = MediaQuery.viewInsetsOf(sheetContext).bottom;
      return Padding(
        padding: EdgeInsets.only(bottom: inset),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : MediaQuery.sizeOf(context).height - inset;
            return Align(
              alignment: Alignment.bottomCenter,
              heightFactor: 1,
              child: RepaintBoundary(
                key: const Key('trade-sheet-body'),
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: available * 0.84,
                  child: MediaQuery.removeViewInsets(
                    context: context,
                    removeBottom: true,
                    child: FinancialTradeScreen(
                      sheet: true,
                      kind: kind,
                      gateway: gateway,
                      statusGateway: statusGateway,
                      userId: userId,
                      shopId: shopId,
                      catalog: catalog,
                      inventoryPage: inventoryPage,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
  );
}

/// Builds a feed line only from the confirmed operation. A missing server
/// timestamp returns null instead of a locally invented clock value.
LedgerFeedLine? _confirmedFeedLine(
  Map<String, Object?> operation,
  String operationId,
) {
  final id = operation['operation_id'];
  final kind = operation['kind'];
  final actor = operation['actor_display_name'];
  final occurredAt = operation['occurred_at'];
  final cairo = operation['occurred_at_cairo'];
  const labels = {'sale': 'بيع', 'purchase': 'شراء'};
  if (id != operationId ||
      kind is! String ||
      actor is! String ||
      actor.isEmpty ||
      occurredAt is! String ||
      occurredAt.isEmpty ||
      cairo is! String ||
      cairo.isEmpty ||
      !labels.containsKey(kind)) {
    return null;
  }
  final sequence = operation['shop_sequence'];
  return LedgerFeedLine(
    kind: kind,
    labelAr: labels[kind]!,
    operationId: operationId,
    actorDisplayName: actor,
    occurredAt: occurredAt,
    occurredAtCairo: cairo,
    shopSequence: sequence is String && sequence.isNotEmpty ? sequence : null,
  );
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

String _poundsText(String wire) => displayPounds(
  (Piastres.parseWire(wire) as Accepted<Piastres>).value.poundsText,
);
