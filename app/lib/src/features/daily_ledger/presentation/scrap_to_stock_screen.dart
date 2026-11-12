import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/amount_format.dart';
import '../../../theme/app_outcome.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/gram_input.dart';
import '../../inventory/application/inventory_gateway.dart';
import '../application/daily_ledger_view.dart';
import '../application/financial_gateway.dart';
import '../application/idempotency_key.dart';
import '../application/opening_gateway.dart';
import '../application/pending_financial_command.dart';
import '../data/pending_financial_command.dart';
import '../domain/jewelry_items.dart';
import '../domain/opening_catalog.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';
import 'jewelry_icons.dart';
import 'ledger_form_fields.dart';
import 'trade_item_picker.dart';

class ScrapToStockScreen extends StatefulWidget {
  const ScrapToStockScreen({
    super.key,
    required this.gateway,
    required this.statusGateway,
    required this.userId,
    required this.shopId,
    required this.scrap,
    this.catalog,
  });

  final ScrapToStockGateway gateway;
  final OpeningGateway statusGateway;
  final String userId;
  final String shopId;
  final List<LedgerScrapLine> scrap;
  final InventoryGateway? catalog;

  @override
  State<ScrapToStockScreen> createState() => _ScrapToStockScreenState();
}

class _ScrapItem {
  const _ScrapItem(this.label, this.category, {this.icon, this.other = false});

  final String label;
  final String category;
  final Widget? icon;
  final bool other;
}

class _ScrapToStockScreenState extends State<ScrapToStockScreen> {
  final _grams = TextEditingController();
  final _count = TextEditingController(text: '1');
  final _pending = const PendingFinancialCommands();
  final _otherCatalog = ValueNotifier(const TradeOtherCatalog(choices: []));
  late int _karat;
  String? _itemName;
  String? _itemCategory;
  List<CatalogProduct> _products = const [];
  String? _productCursor;
  bool _productsLoading = false;
  bool _productsFailed = false;
  int _productGeneration = 0;
  Milligrams? _reviewWeight;
  PieceCount? _reviewCount;
  String? _key;
  String? _message;
  bool _busy = false;
  // U20: confirmed conversions show their own outcome page.
  bool _committed = false;
  bool _unknown = false;

  static const _jewelry = <_ScrapItem>[
    _ScrapItem('خواتم', 'worked_jewelry', icon: JewelryGlyph(JewelryKind.ring)),
    _ScrapItem(
      'حلقان',
      'worked_jewelry',
      icon: JewelryGlyph(JewelryKind.earrings),
    ),
    _ScrapItem(
      'سلاسل',
      'worked_jewelry',
      icon: JewelryGlyph(JewelryKind.necklace),
    ),
    _ScrapItem(
      'تعاليق',
      'worked_jewelry',
      icon: JewelryGlyph(JewelryKind.pendant),
    ),
  ];

  List<int> get _availableKarats => orderedKarats([
    for (final line in widget.scrap)
      if (_wireWeight(line) > BigInt.zero) line.karat,
  ]);

  @override
  void initState() {
    super.initState();
    _karat = _availableKarats.isEmpty ? 21 : _availableKarats.first;
    if (widget.catalog == null) {
      _productsFailed = true;
      _publishOthers();
    } else {
      unawaited(_loadProducts(reset: true));
    }
  }

  @override
  void dispose() {
    _grams.dispose();
    _count.dispose();
    _otherCatalog.dispose();
    super.dispose();
  }

  BigInt _availableWeight(int karat) {
    for (final line in widget.scrap) {
      if (line.karat == karat) return _wireWeight(line);
    }
    return BigInt.zero;
  }

  List<_ScrapItem> get _choices {
    final items = <_ScrapItem>[];
    if (StockCategory.workedJewelry.allowsKarat(_karat)) {
      items.addAll(_jewelry);
    }
    if (StockCategory.coin.allowsKarat(_karat)) {
      items.add(
        const _ScrapItem(
          'جنيهات',
          'coin',
          icon: JewelryGlyph(JewelryKind.coin),
        ),
      );
    }
    if (StockCategory.bullion.allowsKarat(_karat)) {
      items.add(
        const _ScrapItem(
          'سبائك',
          'bullion',
          icon: JewelryGlyph(JewelryKind.bullion),
        ),
      );
    }
    if (StockCategory.workedJewelry.allowsKarat(_karat)) {
      items.add(const _ScrapItem('أخرى', 'worked_jewelry', other: true));
    }
    return items;
  }

  void _publishOthers() {
    final reserved = {...jewelryMainTileNames, ...jewelryBuiltIns};
    _otherCatalog.value = TradeOtherCatalog(
      choices: [
        for (final name in tradeOtherJewelryNames)
          TradeItemChoice(name, 'worked_jewelry'),
        for (final product in _products)
          if (product.category == 'worked_jewelry' &&
              product.karat == _karat &&
              !tradeOtherJewelryNames.contains(product.name) &&
              !isPooledOpeningItem(product.name) &&
              !reserved.contains(canonicalJewelryName(product.name)))
            TradeItemChoice(
              canonicalJewelryName(product.name),
              product.category,
            ),
      ],
      loading: _productsLoading,
      failed: widget.catalog == null || _productsFailed,
      hasMore: _productCursor != null,
    );
  }

  Future<void> _loadProducts({required bool reset}) async {
    final gateway = widget.catalog;
    if (gateway == null) {
      setState(() => _productsFailed = true);
      _publishOthers();
      return;
    }
    if (_productsLoading && !reset) return;
    final generation = ++_productGeneration;
    setState(() => _productsLoading = true);
    _publishOthers();
    try {
      final page = await gateway.products(
        callerUserId: widget.userId,
        cursor: reset ? null : _productCursor,
      );
      if (!mounted || generation != _productGeneration) return;
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
        _publishOthers();
      }
    }
  }

  Future<void> _pickOther() async {
    _publishOthers();
    final choice = await showTradeItemPicker(
      context,
      title: 'اختر الصنف',
      mainChoices: const [],
      others: _otherCatalog,
      reservedNames: {
        ...jewelryMainTileNames,
        ...jewelryBuiltIns,
        'جنيهات',
        'سبائك',
        'أخرى',
      },
      onRetry: () => _loadProducts(reset: true),
      onMore: widget.catalog == null ? null : () => _loadProducts(reset: false),
      shopLoadFailureLabel: 'تعذر تحميل أصناف المتجر. إعادة المحاولة',
    );
    if (!mounted || choice == null) return;
    setState(() {
      _itemName = choice.label;
      _itemCategory = choice.category;
      _message = null;
    });
  }

  void _choose(_ScrapItem item) {
    if (item.other) {
      unawaited(_pickOther());
      return;
    }
    setState(() {
      _itemName = item.label;
      _itemCategory = item.category;
      _message = null;
    });
  }

  void _startReview() {
    final name = _itemName?.trim() ?? '';
    if (name.isEmpty || _itemCategory == null) {
      setState(() => _message = 'اختر الصنف.');
      return;
    }
    final weight = Milligrams.parseGrams(_grams.text.trim());
    final count = PieceCount.parseWire(_count.text.trim());
    if (weight is! Accepted<Milligrams> ||
        count is! Accepted<PieceCount> ||
        weight.value.value == BigInt.zero ||
        count.value.value == BigInt.zero ||
        weight.value.value > _availableWeight(_karat) ||
        name.length > 120) {
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
    'category': _itemCategory,
    'karat': _karat,
    'milligrams': _reviewWeight!.wire,
    'count': _reviewCount!.wire,
    'item_name': _itemName!.trim(),
    'note': '',
  };

  Future<void> _submit() async {
    if (_reviewWeight == null || _reviewCount == null || _busy) return;
    final key = _key ?? newIdempotencyKey();
    final payload = _payload();
    var saved = false;
    setState(() {
      _busy = true;
      _key = key;
      _message = 'جارٍ حفظ التحويل…';
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
        if (mounted) setState(() => _committed = true);
      } else if (result is FinancialRejected) {
        await _pending.clear(widget.userId, widget.shopId, key);
        if (!mounted) return;
        setState(() {
          _key = null;
          _message =
              result.code == 'negative_owned_balance' ||
                  result.code == 'insufficient_stock'
              ? 'تغير رصيد الكسر. حدّث الدفتر وراجع الوزن.'
              : 'تعذر حفظ التحويل. راجع البيانات.';
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
        if (mounted) setState(() => _committed = true);
      } else if (status is StatusAbsent) {
        setState(() {
          _unknown = false;
          _message =
              'لم نتأكد من حفظ التحويل. أعد المحاولة دون تغيير البيانات.';
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
    final grams = _reviewWeight == null
        ? ''
        : displayGoldEffect(_reviewWeight!.value);
    return PopScope(
      canPop: !_busy && !_unknown && !_committed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _committed) Navigator.pop(context, true);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('تحويل كسر إلى مخزون')),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(16),
                children: _committed
                    ? [
                        AppOutcome(
                          title: 'تمت إضافة الكسر إلى المخزون',
                          titleKey: const Key('scrap-stock-success'),
                          subtitle: 'أكد الخادم التحويل. النقدية لا تتغير.',
                          figures: [
                            OutcomeFigure('ينقص الكسر · عيار $_karat', grams),
                            OutcomeFigure(
                              'يزيد مخزون $_itemName · عيار $_karat',
                              '$grams · ${_reviewCount!.wire} قطعة',
                            ),
                          ],
                        ),
                      ]
                    : [
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
                          const SizedBox(height: AppTokens.spaceSm + 4),
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
                                _itemName = null;
                                _itemCategory = null;
                              });
                              _publishOthers();
                            },
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'المتاح: ${_gramsText(_availableWeight(_karat).toString())} جرام',
                          ),
                          const SizedBox(height: AppTokens.spaceSm + 4),
                          Text('الصنف', style: theme.textTheme.titleSmall),
                          const SizedBox(height: AppTokens.spaceSm),
                          TradeChoiceGrid(
                            columns: 4,
                            compactColumns: 3,
                            children: [
                              for (final item in _choices)
                                TradeChoiceTile(
                                  key: Key(
                                    item.other
                                        ? 'scrap-stock-item-other'
                                        : 'scrap-stock-item-${item.label}',
                                  ),
                                  label: item.label,
                                  icon: item.icon,
                                  selected:
                                      !item.other &&
                                      _itemName == item.label &&
                                      _itemCategory == item.category,
                                  onTap: () => _choose(item),
                                ),
                            ],
                          ),
                          if (_itemCategory == 'worked_jewelry' &&
                              _itemName != null &&
                              !_jewelry.any((item) => item.label == _itemName))
                            Padding(
                              padding: const EdgeInsets.only(
                                top: AppTokens.spaceSm,
                              ),
                              child: Text('الصنف المختار: $_itemName'),
                            ),
                          const SizedBox(height: AppTokens.spaceSm + 4),
                          LedgerFieldPair(
                            first: ledgerGramsField(
                              key: const Key('scrap-stock-grams'),
                              context: context,
                              controller: _grams,
                              label: 'الوزن بالجرام',
                              helper: 'حتى منزلتين عشريتين',
                              inputFormatters: const [
                                GramInputFormatter(decimalPlaces: 2),
                              ],
                              textInputAction: TextInputAction.next,
                            ),
                            second: ledgerCountField(
                              key: const Key('scrap-stock-count'),
                              context: context,
                              controller: _count,
                              label: 'عدد القطع',
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) =>
                                  FocusScope.of(context).unfocus(),
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
                                  Text('ينقص الكسر: $grams · عيار $_karat'),
                                  Text(
                                    'يزيد مخزون $_itemName عيار $_karat: $grams · ${_reviewCount!.wire} قطعة',
                                  ),
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
                      _committed
                          ? 'scrap-stock-done'
                          : _unknown
                          ? 'scrap-stock-check'
                          : reviewing
                          ? 'scrap-stock-confirm'
                          : 'scrap-stock-review',
                    ),
                    onPressed: _committed
                        ? () => Navigator.pop(context, true)
                        : _busy
                        ? null
                        : _unknown
                        ? _reconcile
                        : reviewing
                        ? _submit
                        : _startReview,
                    child: Text(
                      _committed
                          ? 'العودة إلى الدفتر'
                          : _busy
                          ? 'جارٍ المعالجة...'
                          : _unknown
                          ? 'التحقق من الحالة'
                          : reviewing
                          ? 'تأكيد التحويل'
                          : 'مراجعة العملية',
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
  return parsed is Accepted<Milligrams> ? displayGrams(parsed.value.wire) : '—';
}
