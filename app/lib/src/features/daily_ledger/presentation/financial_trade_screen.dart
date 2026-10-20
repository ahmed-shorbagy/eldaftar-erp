import '../../../theme/cash_input.dart';
import '../../../theme/gram_input.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../application/ledger_home_metrics.dart';

import '../application/financial_gateway.dart';
import '../application/confirmed_operation_pdf.dart';
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
import '../../../theme/app_tokens.dart';
import 'invoice_pdf_share_dialog.dart';
import 'jewelry_icons.dart';
import 'ledger_form_fields.dart';
import '../domain/ledger_compensation.dart';
import 'exchange_effect_review.dart';
import 'opening_copy.dart';
import 'trade_nominal_picker.dart';

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
    this.initialPayload,
    this.onDraftReviewed,
    this.canRead,
    this.canWrite,
    this.syncTicks,
  });

  final FinancialKind kind;
  final FinancialGateway gateway;
  final OpeningGateway statusGateway;
  final String userId;
  final String shopId;
  final bool Function()? canRead, canWrite;
  final Listenable? syncTicks;
  final bool practice;
  final Map<String, Object?>? exchangeReturnPayload;
  final PartialReturnReview? exchangeReturnReview;
  final OnboardingStore? onboardingStore;
  final bool sheet;
  final InventoryGateway? catalog;
  final WidgetBuilder? inventoryPage;
  final Map<String, Object?>? initialPayload;
  final Future<bool> Function(FinancialDraft draft)? onDraftReviewed;

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
  String? originalMilligrams;
  int karat;
  final TextEditingController name;
  final FocusNode priceFocus = FocusNode();
  final TextEditingController grams;
  final TextEditingController count;
  final TextEditingController price;
  final GlobalKey anchor = GlobalKey();

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
  bool _nominalFailed = false;
  bool _invoiceBusy = false;
  int _catalogGeneration = 0;
  String? _denomCursor;
  String? _coinCursor;
  List<CatalogDenomination> _denoms = const [];
  List<CatalogCoin> _coins = const [];
  List<CatalogProduct> _products = const [];
  String? _productCursor;
  bool _productsFailed = false;
  bool _productsLoading = false;
  int _productGeneration = 0;
  final _pending = const PendingFinancialCommands();
  Map<String, Object?>? _frozenBody;
  final _guideScroll = ScrollController();
  final _gramsFocus = FocusNode();
  final _tenderFocus = FocusNode();
  int _step = 0;
  bool _showOther = false;
  Set<int> _hiddenScrapKarats = const {};

  bool get _fastEntry =>
      widget.exchangeReturnPayload == null &&
      (widget.kind == FinancialKind.sale ||
          widget.kind == FinancialKind.purchase);

  String get _title => widget.initialPayload != null
      ? 'تعديل العملية'
      : widget.exchangeReturnPayload != null
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
    widget.syncTicks?.addListener(_accessChanged);
    unawaited(_loadScrapPreferences());
    if (widget.kind != FinancialKind.expense) {
      _items.add(_ItemEntry(scrap: widget.kind == FinancialKind.scrapSale));
    }
    _tenders.add(_TenderEntry(CashMethod.cash));
    final initial = widget.initialPayload;
    if (initial != null) _prefill(initial);
    if (widget.kind == FinancialKind.expense) _step = 2;
    if (widget.kind == FinancialKind.scrapSale) {
      _step = 1;
      _items.first.name.text = 'كسر';
    }
    if (widget.catalog != null) {
      _catalogLoading = true;
      unawaited(_loadCatalogPages());
    }
  }

  void _prefill(Map<String, Object?> initial) {
    String pounds(Object? wire) {
      final value = wire is String ? Piastres.parseWire(wire) : null;
      return value is Accepted<Piastres> ? value.value.poundsText : '';
    }

    for (final row in _items) {
      row.dispose();
    }
    _items.clear();
    for (final raw in (initial['items'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final row = _ItemEntry(scrap: raw['category'] == 'scrap');
      row.category = raw['category'] as String;
      row.karat = raw['karat'] as int;
      row.name.text = raw['item_name'] as String? ?? '';
      row.customName = true;
      row.originalMilligrams = raw['milligrams'] as String;
      final weight = Milligrams.parseWire(row.originalMilligrams!);
      if (weight is Accepted<Milligrams>) {
        row.grams.text = weight.value.gramsText;
      }
      row.count.text = raw['count'] as String? ?? '1';
      row.price.text = pounds(raw['line_price_piastres']);
      _items.add(row);
    }
    for (final row in _tenders) {
      row.dispose();
    }
    _tenders.clear();
    for (final raw in (initial['tenders'] as List? ?? const [])) {
      if (raw is! Map) continue;
      final method = CashMethod.byCode(raw['method'] as String? ?? '');
      if (method != null) {
        _tenders.add(
          _TenderEntry(method)..amount.text = pounds(raw['piastres']),
        );
      }
    }
    if (_tenders.isEmpty) _tenders.add(_TenderEntry(CashMethod.cash));
    _purchaseTotal.text = pounds(initial['total_piastres']);
    _customerName.text = initial['customer_name'] as String? ?? '';
    _customerPhone.text = initial['customer_phone'] as String? ?? '';
    _note.text = initial['note'] as String? ?? '';
    _description.text = initial['description'] as String? ?? '';
    final pricing = initial['pricing'];
    if (pricing is Map) {
      _priceDetails = true;
      _basePrice.text = pounds(pricing['base_piastres']);
      _workmanship.text = pounds(pricing['workmanship_piastres']);
      _otherCharges.text = pounds(pricing['other_charges_piastres']);
      _discount.text = pounds(pricing['discount_piastres']);
      _otherChargesLabel.text = pricing['other_charges_label'] as String? ?? '';
    }
  }

  Future<void> _reviewEditedDraft(FinancialDraft draft) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final saved = await widget.onDraftReviewed!(draft);
      if (mounted && saved) Navigator.of(context).pop(true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _loadScrapPreferences() async {
    final shop = widget.shopId;
    try {
      final prefs = await SharedPreferences.getInstance();
      final layout = migrateLedgerMetricLayout(
        prefs.getStringList('ledger_layout_$shop'),
      );
      if (mounted && widget.shopId == shop) {
        setState(() => _hiddenScrapKarats = layout.hiddenScrapKarats);
      }
    } catch (_) {
      // Existing measured entries remain available if local preferences fail.
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
    widget.syncTicks?.removeListener(_accessChanged);
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

  void _accessChanged() {
    if (mounted) setState(() {});
  }

  void _startReview() {
    if (widget.canRead?.call() == false ||
        widget.canWrite?.call() == false ||
        _busy) {
      return;
    }
    if (widget.kind != FinancialKind.expense) {
      for (final row in _items) {
        final grams = gramEntryValue(row.grams.text, decimalPlaces: 2);
        if (grams == null) {
          final inherited = Milligrams.parseGrams(row.grams.text);
          if (row.originalMilligrams != null &&
              inherited is Accepted<Milligrams> &&
              inherited.value.wire == row.originalMilligrams) {
            continue;
          }
          setState(() => _error = 'أدخل الوزن بمنزلتين عشريتين كحد أقصى.');
          return;
        }
        row.grams.text = grams;
      }
    }
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
    if (result.draft != null && widget.onDraftReviewed != null) {
      unawaited(_reviewEditedDraft(result.draft!));
      return;
    }
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
    if (widget.canRead?.call() == false) {
      return Scaffold(
        appBar: AppBar(title: const Text('تعديل العملية')),
        body: const Center(
          child: Text('لم تعد بيانات العملية متاحة لهذا الحساب.'),
        ),
      );
    }
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
                                      (widget.kind == FinancialKind.scrapSale &&
                                          _step == 2) ||
                                      widget.kind == FinancialKind.expense
                                ? 'trade-review'
                                : 'trade-next',
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                          ),
                          onPressed: _busy || widget.canWrite?.call() == false
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
                                          (widget.kind ==
                                                  FinancialKind.scrapSale &&
                                              _step == 2) ||
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
    if (_step == 3 ||
        widget.kind == FinancialKind.expense ||
        (widget.kind == FinancialKind.scrapSale && _step == 2)) {
      _startReview();
      return;
    }
    setState(() {
      _step++;
      _error = null;
    });
    _guideScroll.jumpTo(0);
  }

  Widget _progress(ThemeData theme) {
    if (widget.kind == FinancialKind.scrapSale) {
      final active = _review != null
          ? 2
          : _step == 1
          ? 0
          : 1;
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            for (final entry in const [
              'الوزن والعيار',
              'الدفع',
              'التأكيد',
            ].indexed)
              Expanded(
                child: Semantics(
                  selected: entry.$1 == active,
                  child: Text(
                    entry.$2,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: entry.$1 == active
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return Padding(
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
  }

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
          onPressed: _addAnotherItem,
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
        if (widget.kind == FinancialKind.scrapSale)
          TextField(
            key: const Key('trade-note'),
            controller: _note,
            maxLines: 3,
            decoration: ledgerFieldDecoration(
              context,
              label: 'ملاحظات (اختياري)',
            ),
          ),
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
      if (_step > (widget.kind == FinancialKind.scrapSale ? 1 : 0) &&
          widget.kind != FinancialKind.expense)
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
      onPressed: _addAnotherItem,
    ),
    const SizedBox(height: 16),
    ..._paymentFields(theme),
    if (widget.initialPayload?['pricing'] is Map) ..._pricingFields(theme),
    if (widget.kind == FinancialKind.sale)
      ExpansionTile(
        key: const Key('trade-customer-disclosure'),
        title: const Text('تفاصيل العميل (اختياري)'),
        children: [
          if (widget.initialPayload != null) ...[
            TextField(
              key: const Key('trade-edit-description'),
              controller: _description,
              decoration: ledgerFieldDecoration(context, label: 'الوصف'),
            ),
            const SizedBox(height: 12),
          ],
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
    if (widget.kind != FinancialKind.sale)
      ExpansionTile(
        key: const Key('trade-notes-disclosure'),
        title: const Text('ملاحظات (اختياري)'),
        children: [
          TextField(
            key: const Key('trade-note'),
            controller: _note,
            maxLines: 3,
            decoration: ledgerFieldDecoration(context, label: 'ملاحظات'),
          ),
        ],
      ),
  ];

  static const _otherJewelry = <(String, String)>[
    ('دبلة', 'worked_jewelry'),
    ('غويشة', 'worked_jewelry'),
    ('إسورة', 'worked_jewelry'),
    ('خلخال', 'worked_jewelry'),
    ('طقم', 'worked_jewelry'),
  ];

  List<(String, String)> get _otherChoices {
    final seen = <String>{'خاتم', 'حلق', 'سلسلة', 'تعليقة'};
    return [
      ..._otherJewelry,
      for (final product in _products)
        if (product.category == 'worked_jewelry' &&
            !_otherJewelry.any((choice) => choice.$1 == product.name) &&
            seen.add(product.name))
          (product.name, product.category),
    ];
  }

  int _categoryKarat(String name) {
    for (final product in _products) {
      if (product.category == 'worked_jewelry' && product.name == name) {
        return product.karat;
      }
    }
    return 18;
  }

  Widget _categoryChooser(ThemeData theme) {
    final choices = <(String, String, Widget)>[
      if (widget.kind != FinancialKind.scrapSale) ...[
        ('خاتم', 'worked_jewelry', const JewelryGlyph(JewelryKind.ring)),
        ('حلق', 'worked_jewelry', const JewelryGlyph(JewelryKind.earrings)),
        ('سلسلة', 'worked_jewelry', const JewelryGlyph(JewelryKind.necklace)),
        ('تعليقة', 'worked_jewelry', const JewelryGlyph(JewelryKind.pendant)),
        ('جنيهات', 'coin', const JewelryGlyph(JewelryKind.coin)),
        ('سبائك', 'bullion', const JewelryGlyph(JewelryKind.bullion)),
      ],
      if (widget.kind == FinancialKind.purchase ||
          widget.kind == FinancialKind.scrapSale)
        ('كسر', 'scrap', const Icon(Icons.content_cut_outlined)),
      if (widget.kind != FinancialKind.scrapSale)
        ('أخرى', 'worked_jewelry', const Icon(Icons.category_outlined)),
    ];
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
                  onPressed: () => _chooseCategory(choice.$1, choice.$2),
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
        grid(choices),
        if (_showOther) ...[
          const SizedBox(height: 12),
          Text('أصناف أخرى', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _otherCategoryGrid(theme),
          if (_productsLoading) const LinearProgressIndicator(),
          if (_productsFailed)
            TextButton(
              onPressed: _productsLoading
                  ? null
                  : () => _loadProducts(reset: true),
              child: const Text('تعذر تحميل أصناف المتجر. إعادة المحاولة'),
            ),
          if (_productCursor != null)
            TextButton(
              onPressed: _productsLoading
                  ? null
                  : () => _loadProducts(reset: false),
              child: const Text('المزيد من أصناف المتجر'),
            ),
        ],
      ],
    );
  }

  Widget _otherCategoryGrid(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, size) {
        final columns = size.maxWidth < 360 ? 2 : 3;
        final width = (size.maxWidth - 8 * (columns - 1)) / columns;
        return Wrap(
          key: const Key('trade-other-grid'),
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final choice in _otherChoices)
              SizedBox(
                width: width,
                child: OutlinedButton(
                  key: Key('trade-select-${choice.$1}'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    minimumSize: const Size(48, 48),
                    backgroundColor: _items.last.name.text == choice.$1
                        ? theme.colorScheme.primaryContainer
                        : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => setState(() {
                    final item = _items.last;
                    item.customName = false;
                    _showOther = true;
                    item.name.text = choice.$1;
                    item.category = choice.$2;
                    item.karat = _categoryKarat(choice.$1);
                  }),
                  child: Text(choice.$1, textAlign: TextAlign.center),
                ),
              ),
          ],
        );
      },
    );
  }

  bool _choiceSelected(String label) {
    final item = _items.last;
    if (label == 'أخرى') return _showOther;
    if (label == 'جنيهات') return item.category == 'coin';
    if (label == 'سبائك') return item.category == 'bullion';
    return item.name.text == label;
  }

  Future<void> _addAnotherItem() async {
    if (_busy || _unknown || widget.canWrite?.call() == false) return;
    if (widget.kind == FinancialKind.scrapSale) {
      final row = _ItemEntry(scrap: true)..name.text = 'كسر';
      setState(() => _items.add(row));
      _scrollToItem(row);
      return;
    }
    final choices = <(String, String)>[
      ('خاتم', 'worked_jewelry'),
      ('حلق', 'worked_jewelry'),
      ('سلسلة', 'worked_jewelry'),
      ('تعليقة', 'worked_jewelry'),
      ('جنيهات', 'coin'),
      ('سبائك', 'bullion'),
      if (widget.kind == FinancialKind.purchase) ('كسر', 'scrap'),
      ..._otherChoices,
    ];
    final choice = await showDialog<(String, String)>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('اختر صنفاً آخر'),
        content: SizedBox(
          width: AppTokens.contentMaxWidth,
          child: SingleChildScrollView(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final choice in choices)
                  OutlinedButton(
                    key: Key('trade-new-category-${choice.$1}'),
                    onPressed: () => Navigator.pop(dialog, choice),
                    child: Text(choice.$1),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    await _chooseCategory(choice.$1, choice.$2, add: true);
  }

  Future<void> _chooseCategory(
    String label,
    String category, {
    _ItemEntry? target,
    bool add = false,
  }) async {
    if (_busy || _unknown || widget.canWrite?.call() == false) return;
    final row = add
        ? _ItemEntry(scrap: category == 'scrap')
        : target ?? _items.last;
    if (category == 'coin' || category == 'bullion') {
      final selected = await showTradeNominalPicker(
        context,
        category: category,
        suggestions: nominalSuggestionsFor(
          category: category,
          catalog: _nominalChoices(category),
        ),
      );
      if (!mounted ||
          selected == null ||
          widget.canRead?.call() == false ||
          widget.canWrite?.call() == false) {
        if (add) row.dispose();
        return;
      }
      if (!add && !_items.contains(row)) return;
      setState(() {
        if (add) _items.add(row);
        final position = _items.indexOf(row);
        for (final entry in selected.indexed) {
          final line = entry.$1 == 0 ? row : _ItemEntry();
          line.category = category;
          line.customName = false;
          line.karat = category == 'coin' ? 21 : 24;
          line.name.text = entry.$2.suggestion.label;
          line.count.text = entry.$2.count.wire;
          line.grams.text =
              gramEntryValue(entry.$2.milligrams.gramsText, decimalPlaces: 2) ??
              entry.$2.milligrams.gramsText;
          if (entry.$1 > 0) _items.insert(position + entry.$1, line);
        }
        _showOther = false;
        _error = null;
        if (!_fastEntry) _step = 1;
      });
    } else {
      setState(() {
        if (add) _items.add(row);
        row.customName = false;
        row.name.text = label == 'أخرى' ? '' : label;
        row.category = category;
        row.karat = _categoryKarat(label);
        _showOther =
            label == 'أخرى' ||
            _otherChoices.any((choice) => choice.$1 == label);
        _error = null;
        if (add && !_fastEntry) _step = 1;
      });
    }
    _scrollToItem(row);
  }

  void _scrollToItem(_ItemEntry row) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = row.anchor.currentContext;
      if (!mounted || target == null) return;
      Scrollable.ensureVisible(
        target,
        alignment: .15,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
      );
    });
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
    unawaited(_loadProducts(reset: true));
    try {
      final denoms = await gateway.denominations(callerUserId: widget.userId);
      final coins = await gateway.coins(callerUserId: widget.userId);
      if (!mounted || generation != _catalogGeneration) return;
      setState(() {
        _nominalFailed = !denoms.available || !coins.available;
        _rememberDenoms(denoms, reset: true);
        _rememberCoins(coins, reset: true);
        _catalogLoading = false;
      });
    } catch (_) {
      if (!mounted || generation != _catalogGeneration) return;
      setState(() {
        _catalogLoading = false;
        _nominalFailed = true;
      });
    }
  }

  Future<void> _loadProducts({required bool reset}) async {
    final gateway = widget.catalog;
    if (gateway == null ||
        (_productsLoading && !reset) ||
        widget.canRead?.call() == false) {
      return;
    }
    final generation = ++_productGeneration;
    setState(() => _productsLoading = true);
    try {
      final page = await gateway.products(
        callerUserId: widget.userId,
        cursor: reset ? null : _productCursor,
      );
      if (!mounted ||
          generation != _productGeneration ||
          widget.canRead?.call() == false) {
        return;
      }
      setState(() {
        _productsFailed = !page.available;
        if (page.available) {
          _products = reset
              ? List.of(page.items!)
              : [..._products, ...page.items!];
          _productCursor = page.nextCursor;
        }
      });
    } catch (_) {
      if (mounted && generation == _productGeneration) {
        setState(() => _productsFailed = true);
      }
    } finally {
      if (mounted && generation == _productGeneration) {
        setState(() => _productsLoading = false);
      }
    }
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

  // Keep the connected catalog table for Instant Inventory access from
  // other sale/purchase paths; أصناف أخرى uses the predefined text grid.
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
      OutlinedButton.icon(
        key: Key('trade-nominals-$index'),
        onPressed: suggestions.isEmpty
            ? null
            : () => _chooseCategory(
                row.category == 'coin' ? 'جنيهات' : 'سبائك',
                row.category,
                target: row,
              ),
        icon: const Icon(Icons.checklist_outlined),
        label: const Text('اختيار الأنواع والأعداد'),
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
      if (!validConfirmedInvoiceFacts(
        operation,
        operationId: operationId,
        shopId: widget.shopId,
      )) {
        throw const FormatException('invoice');
      }
      await showInvoicePdfShareDialog(
        context: context,
        gateway: widget.gateway,
        userId: widget.userId,
        shopId: widget.shopId,
        operationId: operationId,
        canRead: () => mounted && widget.canRead?.call() != false,
        canWrite: () => mounted && widget.canWrite?.call() != false,
        invalidations: widget.syncTicks,
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
        ? (ScrapKarats.allowed
              .where(
                (karat) =>
                    !_hiddenScrapKarats.contains(karat) || karat == row.karat,
              )
              .toList()
            ..sort())
        : (StockCategory.byCode(categoryCode)!.karats.toList()..sort());
    return Card(
      key: row.anchor,
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
                  inputFormatters: [GramInputFormatter(decimalPlaces: 2)],
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
                    helper: 'دقة 0.01 جرام · منزلتان عشريتان كحد أقصى',
                  ),
                ),
              )
            else
              TextField(
                key: Key('trade-grams-$index'),
                controller: row.grams,
                inputFormatters: [GramInputFormatter(decimalPlaces: 2)],
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
                  helper: 'دقة 0.01 جرام · منزلتان عشريتان كحد أقصى',
                ),
              ),
            if (_fastEntry &&
                widget.initialPayload != null &&
                (widget.initialPayload!['items'] as List).any(
                  (item) => item is Map && item['line_price_piastres'] != null,
                ))
              TextField(
                key: Key('trade-edit-line-price-$index'),
                controller: row.price,
                inputFormatters: const [CashInputFormatter()],
                textDirection: TextDirection.ltr,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: ledgerFieldDecoration(context, label: 'قيمة الصنف'),
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
      Column(
        key: const Key('trade-success-weight'),
        children: [
          for (final item in _review!.items)
            Text(
              '${item['item_name']} · عيار ${item['karat']}: ${displayGoldEffect(BigInt.parse(item['milligrams'] as String))}',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
        ],
      ),
    if (_canSendInvoice) ...[
      const SizedBox(height: 16),
      const Text(
        'شارك PDF مع العميل، ثم أكد الإرسال بعد إرساله فعلاً.',
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
              Column(
                key: const Key('trade-review-net'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.kind == FinancialKind.purchase)
                    const Text('تنتقل الملكية إلى المتجر للأصناف المذكورة.'),
                  if (draft.items.isEmpty) const Text('لا يتغير الذهب'),
                  for (final item in draft.items)
                    Text(
                      '${widget.kind == FinancialKind.purchase ? 'يزيد' : 'ينقص'} '
                      '${item['category'] == 'scrap' ? 'كسر' : 'مخزون ${item['item_name']}'} '
                      'عيار ${item['karat']}: '
                      '${displayGoldEffect(BigInt.parse(item['milligrams'] as String))}'
                      '${item['category'] == 'scrap' ? '' : ' · ${item['count']} قطعة'}',
                    ),
                ],
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
  bool Function()? canRead,
  bool Function()? canWrite,
  Listenable? syncTicks,
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
                      canRead: canRead,
                      canWrite: canWrite,
                      syncTicks: syncTicks,
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
