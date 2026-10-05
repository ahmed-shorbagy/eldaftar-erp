import 'package:flutter/material.dart';

import '../../daily_ledger/domain/opening_catalog.dart';
import '../../daily_ledger/presentation/ledger_form_fields.dart';
import '../../daily_ledger/presentation/opening_copy.dart';
import '../application/inventory_command_flow.dart';
import '../application/inventory_gateway.dart';
import '../domain/inventory_models.dart';
import 'command_host.dart';
import 'inventory_copy.dart';
import 'inventory_input.dart';
import 'inventory_widgets.dart';

const _categories = ['worked_jewelry', 'bullion', 'coin', 'scrap'];

List<int> karatsFor(String category) => category == 'scrap'
    ? ScrapKarats.allowed.toList()
    : (StockCategory.byCode(category)?.karats.toList() ?? const []);

class InventoryFormScope {
  const InventoryFormScope({
    required this.flow,
    required this.userId,
    required this.shopId,
    required this.readOnly,
    required this.day,
    required this.reloadDay,
    this.gateway,
  });

  final InventoryCommandFlow flow;
  final InventoryGateway? gateway;
  final String userId;
  final String shopId;
  final bool readOnly;
  final DayAnchor? day;
  final Future<DayAnchor?> Function() reloadDay;
}

class InventoryAdditionForm extends StatefulWidget {
  const InventoryAdditionForm({
    super.key,
    required this.scope,
    this.denominations = const [],
    this.coins = const [],
    this.products = const [],
    this.denominationCursor,
    this.coinCursor,
    this.productCursor,
  });

  final InventoryFormScope scope;
  final List<CatalogDenomination> denominations;
  final List<CatalogCoin> coins;
  final List<CatalogProduct> products;
  final String? denominationCursor;
  final String? coinCursor;
  final String? productCursor;

  @override
  State<InventoryAdditionForm> createState() => _InventoryAdditionFormState();
}

class _InventoryAdditionFormState extends State<InventoryAdditionForm>
    with InvalidatesReview {
  final _name = TextEditingController();
  final _grams = TextEditingController();
  final _count = TextEditingController(text: '1');
  final _reason = TextEditingController();
  String _category = 'worked_jewelry';
  int _karat = 21;
  String? _denominationId;
  String? _coinId;
  String? _productId;
  final _catalogQuery = TextEditingController();
  late List<CatalogDenomination> _denoms;
  late List<CatalogCoin> _coins;
  late List<CatalogProduct> _products;
  String? _denomCursor;
  String? _coinCursor;
  String? _productCursor;
  bool _catalogMissing = false;

  @override
  void initState() {
    super.initState();
    bindReview([_name, _grams, _count, _reason, _catalogQuery]);
    _denoms = [...widget.denominations];
    _coins = [...widget.coins];
    _products = [...widget.products];
    _denomCursor = widget.denominationCursor;
    _coinCursor = widget.coinCursor;
    _productCursor = widget.productCursor;
  }

  @override
  void dispose() {
    revision.dispose();
    _catalogQuery.dispose();
    _name.dispose();
    _grams.dispose();
    _count.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scrap = _category == 'scrap';
    final nominal = _nominal;
    return CommandHost(
      title: 'إضافة مخزون',
      readOnly: widget.scope.readOnly,
      flow: widget.scope.flow,
      userId: widget.scope.userId,
      shopId: widget.scope.shopId,
      day: widget.scope.day,
      reloadDay: widget.scope.reloadDay,
      watched: [revision],
      fields: [
        inventoryField(
          context: context,
          controller: _name,
          label: 'اسم الصنف',
          fieldKey: const Key('add-name'),
        ),
        const SizedBox(height: 12),
        InventoryCategoryKarat(
          category: _category,
          karat: _karat,
          categoryKey: const Key('add-category'),
          karatKey: Key('add-karat-$_category'),
          onCategory: (value) {
            final next = karatsFor(value);
            setState(() {
              _category = value;
              _karat = next.contains(_karat) ? _karat : next.first;
              _denominationId = null;
              _coinId = null;
            });
          },
          onKarat: (value) => setState(() => _karat = value),
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _grams,
          label: 'الوزن الفعلي بالجرام',
          fieldKey: const Key('add-grams'),
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        if (!scrap) ...[
          const SizedBox(height: 12),
          inventoryField(
            context: context,
            controller: _count,
            label: 'العدد',
            fieldKey: const Key('add-count'),
            keyboard: TextInputType.number,
          ),
        ],
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _catalogQuery,
          label: 'بحث في هوية الكتالوج',
          fieldKey: const Key('add-catalog-search'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('add-catalog-go'),
          onPressed: _searchCatalog,
          child: const Text('بحث في الكتالوج'),
        ),
        if (_catalogMissing)
          const Text('كتالوج الفئات غير متاح. يمكن الحفظ دون وزن اسمي.'),
        if (_products.isNotEmpty) ...[
          const SizedBox(height: 12),
          _identityMenu(
            label: 'منتج الكتالوج',
            value: _productId,
            entries: [
              for (final item in _products)
                (item.id, '${item.id} — ${item.name}'),
            ],
            onChanged: (value) {
              CatalogProduct? selected;
              for (final item in _products) {
                if (item.id == value) selected = item;
              }
              final name = selected?.name;
              setState(() {
                _productId = value;
                if (name != null) _name.text = name;
              });
            },
          ),
          OlderPageControl(
            count: _products.length,
            noun: 'منتجات',
            nextCursor: _productCursor,
            onOlder: () => _moreProducts(false),
            controlKey: const Key('add-products-older'),
          ),
        ],
        if (_category == 'bullion' && _denoms.isNotEmpty) ...[
          const SizedBox(height: 12),
          _identityMenu(
            label: 'فئة السبيكة الاسمية',
            value: _denominationId,
            entries: [
              for (final item in _denoms.where((item) => item.active))
                (
                  item.id,
                  '${item.id} — ${item.label} الاسمي ${gramsOf(item.nominalMilligrams)} جرام',
                ),
            ],
            onChanged: (value) => setState(() => _denominationId = value),
          ),
          OlderPageControl(
            count: _denoms.length,
            noun: 'فئات سبائك',
            nextCursor: _denomCursor,
            onOlder: () => _moreDenoms(false),
            controlKey: const Key('add-denoms-older'),
          ),
        ],
        if (_category == 'coin' && _coins.isNotEmpty) ...[
          const SizedBox(height: 12),
          _identityMenu(
            label: 'نوع العملة',
            value: _coinId,
            entries: [
              for (final item in _coins.where((item) => item.active))
                (
                  item.id,
                  item.nominalMilligrams == null
                      ? '${item.id} — ${item.label}'
                      : '${item.id} — ${item.label} الاسمي ${gramsOf(item.nominalMilligrams!)} جرام',
                ),
            ],
            onChanged: (value) => setState(() => _coinId = value),
          ),
          OlderPageControl(
            count: _coins.length,
            noun: 'عملات',
            nextCursor: _coinCursor,
            onOlder: () => _moreCoins(false),
            controlKey: const Key('add-coins-older'),
          ),
        ],
        if (nominal != null) ...[
          const SizedBox(height: 8),
          Text(
            'الوزن الاسمي ${gramsOf(nominal)} جرام لا يُسجل مخزوناً. يُرسل الوزن الفعلي فقط.',
            key: const Key('nominal-note'),
          ),
        ],
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _reason,
          label: 'سبب الإضافة',
          fieldKey: const Key('add-reason'),
          action: TextInputAction.done,
          maxLength: 1000,
        ),
      ],
      onReview: (day) => reviewAddition(
        day: day,
        reason: _reason.text,
        lines: [
          AdditionLine(
            itemName: _name.text,
            category: _category,
            karat: _karat,
            milligrams: readGrams(_grams.text) ?? BigInt.zero,
            count: scrap ? null : readCount(_count.text),
            denominationId: _category == 'bullion' ? _denominationId : null,
            nominalMilligrams: _category == 'bullion' ? nominal : null,
            coinTypeId: _category == 'coin' ? _coinId : null,
            coinNominalMilligrams: _category == 'coin' ? nominal : null,
          ),
        ],
      ),
    );
  }

  BigInt? get _nominal {
    if (_category == 'bullion') {
      for (final item in _denoms) {
        if (item.id == _denominationId) return item.nominalMilligrams;
      }
    }
    if (_category == 'coin') {
      for (final item in _coins) {
        if (item.id == _coinId) return item.nominalMilligrams;
      }
    }
    return null;
  }

  String? get _query {
    final text = _catalogQuery.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _searchCatalog() async {
    await _moreDenoms(true);
    await _moreCoins(true);
    await _moreProducts(true);
  }

  Future<void> _moreDenoms(bool replace) async {
    final gateway = widget.scope.gateway;
    if (gateway == null) return;
    if (!replace && _denomCursor == null) return;
    try {
      final page = await gateway.denominations(
        callerUserId: widget.scope.userId,
        query: _query,
        cursor: replace ? null : _denomCursor,
      );
      if (!mounted) return;
      setState(() {
        _catalogMissing = !page.available;
        if (!page.available || page.items == null) return;
        _denoms = replace ? page.items! : [..._denoms, ...page.items!];
        _denomCursor = page.nextCursor;
      });
    } on InventoryReadException catch (error) {
      if (!mounted || error.code == 'discarded') return;
      setState(() => _catalogMissing = true);
    }
  }

  Future<void> _moreCoins(bool replace) async {
    final gateway = widget.scope.gateway;
    if (gateway == null) return;
    if (!replace && _coinCursor == null) return;
    try {
      final page = await gateway.coins(
        callerUserId: widget.scope.userId,
        query: _query,
        cursor: replace ? null : _coinCursor,
      );
      if (!mounted) return;
      setState(() {
        if (!page.available || page.items == null) {
          _catalogMissing = true;
          return;
        }
        _coins = replace ? page.items! : [..._coins, ...page.items!];
        _coinCursor = page.nextCursor;
      });
    } on InventoryReadException catch (error) {
      if (!mounted || error.code == 'discarded') return;
      setState(() => _catalogMissing = true);
    }
  }

  Future<void> _moreProducts(bool replace) async {
    final gateway = widget.scope.gateway;
    if (gateway == null) return;
    if (!replace && _productCursor == null) return;
    try {
      final page = await gateway.products(
        callerUserId: widget.scope.userId,
        query: _query,
        cursor: replace ? null : _productCursor,
      );
      if (!mounted) return;
      setState(() {
        if (!page.available || page.items == null) return;
        _products = replace ? page.items! : [..._products, ...page.items!];
        _productCursor = page.nextCursor;
      });
    } on InventoryReadException catch (error) {
      if (!mounted || error.code == 'discarded') return;
    }
  }
}

class InventoryRemovalForm extends StatefulWidget {
  const InventoryRemovalForm({
    super.key,
    required this.scope,
    required this.lots,
  });
  final InventoryFormScope scope;
  final List<LotSnapshot> lots;

  @override
  State<InventoryRemovalForm> createState() => _InventoryRemovalFormState();
}

class _InventoryRemovalFormState extends State<InventoryRemovalForm>
    with InvalidatesReview {
  final _grams = TextEditingController();
  final _count = TextEditingController(text: '1');
  final _reason = TextEditingController();
  String? _lotId;

  @override
  void initState() {
    super.initState();
    bindReview([_grams, _count, _reason]);
  }

  @override
  void dispose() {
    revision.dispose();
    _grams.dispose();
    _count.dispose();
    _reason.dispose();
    super.dispose();
  }

  List<LotSnapshot> get _available => [
    for (final lot in widget.lots)
      if (lot.stockClass == StockClass.ownedAvailable &&
          lot.remainingMilligrams > BigInt.zero)
        lot,
  ];

  @override
  Widget build(BuildContext context) {
    final lot = _selected;
    return CommandHost(
      title: 'صرف من المتاح',
      readOnly: widget.scope.readOnly,
      flow: widget.scope.flow,
      userId: widget.scope.userId,
      shopId: widget.scope.shopId,
      day: widget.scope.day,
      reloadDay: widget.scope.reloadDay,
      watched: [revision],
      canReview: lot != null,
      fields: [
        if (_available.isEmpty)
          const InventoryNotice(message: 'لا توجد كمية متاحة للبيع للصرف منها.')
        else
          _lotMenu(_available, (value) => setState(() => _lotId = value)),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _grams,
          label: 'الوزن المصروف بالجرام',
          fieldKey: const Key('remove-grams'),
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        if (lot?.tracksCount ?? true) ...[
          const SizedBox(height: 12),
          inventoryField(
            context: context,
            controller: _count,
            label: 'العدد المصروف',
            fieldKey: const Key('remove-count'),
            keyboard: TextInputType.number,
          ),
        ],
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _reason,
          label: 'سبب الصرف',
          fieldKey: const Key('remove-reason'),
          action: TextInputAction.done,
          maxLength: 1000,
        ),
      ],
      onReview: (day) {
        final selected = _selected;
        if (selected == null) {
          return const InventoryRejected(InventoryIssueCode.emptyCommand);
        }
        return reviewRemoval(
          day: day,
          reason: _reason.text,
          lines: [
            (
              lot: selected,
              milligrams: readGrams(_grams.text) ?? BigInt.zero,
              count: selected.tracksCount ? readCount(_count.text) : null,
            ),
          ],
        );
      },
    );
  }

  LotSnapshot? get _selected {
    for (final lot in _available) {
      if (lot.id == _lotId) return lot;
    }
    return _available.isEmpty ? null : _available.first;
  }
}

class InventoryCorrectionForm extends StatefulWidget {
  const InventoryCorrectionForm({
    super.key,
    required this.scope,
    required this.lots,
    required this.cashBalances,
  });

  final InventoryFormScope scope;
  final List<LotSnapshot> lots;
  final Map<String, BigInt> cashBalances;

  @override
  State<InventoryCorrectionForm> createState() =>
      _InventoryCorrectionFormState();
}

class _InventoryCorrectionFormState extends State<InventoryCorrectionForm>
    with InvalidatesReview {
  final _cash = TextEditingController();
  final _grams = TextEditingController();
  final _count = TextEditingController();
  final _name = TextEditingController();
  final _reason = TextEditingController();
  String _method = 'cash';
  bool _increase = false;
  String _category = 'worked_jewelry';
  int _karat = 21;
  String? _lotId;

  @override
  void initState() {
    super.initState();
    bindReview([_cash, _grams, _count, _name, _reason]);
  }

  @override
  void dispose() {
    revision.dispose();
    _cash.dispose();
    _grams.dispose();
    _count.dispose();
    _name.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = [
      for (final lot in widget.lots)
        if (lot.stockClass == StockClass.ownedAvailable) lot,
    ];
    return CommandHost(
      title: 'تصحيح جرد',
      readOnly: widget.scope.readOnly,
      flow: widget.scope.flow,
      userId: widget.scope.userId,
      shopId: widget.scope.shopId,
      day: widget.scope.day,
      reloadDay: widget.scope.reloadDay,
      watched: [revision],
      fields: [
        DropdownButtonFormField<String>(
          key: const Key('correct-method'),
          initialValue: _method,
          isExpanded: true,
          decoration: ledgerFieldDecoration(context, label: 'وسيلة النقد'),
          items: [
            for (final method in CashMethod.canonicalOrder)
              DropdownMenuItem(
                value: method.code,
                child: Text(cashMethodLabel(method)),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _method = value);
          },
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _cash,
          label: 'فرق النقد، والسالب بين قوسين بعلامة -',
          fieldKey: const Key('correct-cash'),
          keyboard: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          key: const Key('correct-increase'),
          contentPadding: EdgeInsets.zero,
          title: const Text('زيادة قطعة جديدة بدل إنقاص دفعة'),
          value: _increase,
          onChanged: (value) => setState(() => _increase = value),
        ),
        if (_increase) ...[
          inventoryField(
            context: context,
            controller: _name,
            label: 'اسم القطعة الجديدة',
            fieldKey: const Key('correct-name'),
          ),
          const SizedBox(height: 12),
          InventoryCategoryKarat(
            category: _category,
            karat: _karat,
            categoryKey: const Key('correct-category'),
            karatKey: Key('correct-karat-$_category'),
            onCategory: (value) {
              final next = karatsFor(value);
              setState(() {
                _category = value;
                _karat = next.contains(_karat) ? _karat : next.first;
              });
            },
            onKarat: (value) => setState(() => _karat = value),
          ),
          const SizedBox(height: 12),
        ] else if (available.isNotEmpty)
          _lotMenu(available, (value) => setState(() => _lotId = value)),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _grams,
          label: _increase ? 'وزن الزيادة بالجرام' : 'وزن الإنقاص بالجرام',
          fieldKey: const Key('correct-grams'),
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _count,
          label: 'العدد',
          fieldKey: const Key('correct-count'),
          keyboard: TextInputType.number,
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _reason,
          label: 'سبب التصحيح',
          fieldKey: const Key('correct-reason'),
          action: TextInputAction.done,
          maxLength: 1000,
        ),
      ],
      onReview: (day) => _review(day, available),
    );
  }

  InventoryResult<ReviewedCommand> _review(
    DayAnchor day,
    List<LotSnapshot> available,
  ) {
    final cashText = _cash.text.trim();
    final cash = cashText.isEmpty ? null : readSignedPounds(cashText);
    final grams = readGrams(_grams.text);
    final count = readCount(_count.text);
    final metal = <MetalDelta>[];
    if (grams != null) {
      if (_increase) {
        metal.add(
          MetalIncrease(
            itemName: _name.text,
            category: _category,
            karat: _karat,
            milligrams: grams,
            count: _category == 'scrap' ? null : count,
          ),
        );
      } else {
        LotSnapshot? lot;
        for (final item in available) {
          if (item.id == _lotId || (_lotId == null && lot == null)) lot = item;
          if (item.id == _lotId) {
            lot = item;
            break;
          }
        }
        if (lot == null) {
          return const InventoryRejected(InventoryIssueCode.emptyCommand);
        }
        metal.add(
          MetalDecrease(
            lot: lot,
            milligrams: -grams,
            count: lot.tracksCount && count != null ? -count : null,
          ),
        );
      }
    }
    return reviewCorrection(
      day: day,
      reason: _reason.text,
      cashDeltas: cash == null || cash == BigInt.zero
          ? const []
          : [
              CashDelta(
                method: _method,
                piastres: cash,
                knownBalance: widget.cashBalances.containsKey(_method)
                    ? widget.cashBalances[_method]
                    : null,
              ),
            ],
      metalDeltas: metal,
    );
  }
}

class InventoryConversionForm extends StatefulWidget {
  const InventoryConversionForm({
    super.key,
    required this.scope,
    required this.lots,
  });
  final InventoryFormScope scope;
  final List<LotSnapshot> lots;

  @override
  State<InventoryConversionForm> createState() =>
      _InventoryConversionFormState();
}

class _InventoryConversionFormState extends State<InventoryConversionForm>
    with InvalidatesReview {
  final _grams = TextEditingController();
  final _sourceCount = TextEditingController(text: '1');
  final _destCount = TextEditingController(text: '1');
  final _name = TextEditingController();
  final _reason = TextEditingController();
  String? _lotId;
  String _destination = 'scrap';

  @override
  void initState() {
    super.initState();
    bindReview([_grams, _sourceCount, _destCount, _name, _reason]);
  }

  @override
  void dispose() {
    revision.dispose();
    _grams.dispose();
    _sourceCount.dispose();
    _destCount.dispose();
    _name.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available = [
      for (final lot in widget.lots)
        if (lot.stockClass == StockClass.ownedAvailable &&
            lot.remainingMilligrams > BigInt.zero)
          lot,
    ];
    return CommandHost(
      title: 'تحويل فئة بنفس العيار',
      readOnly: widget.scope.readOnly,
      flow: widget.scope.flow,
      userId: widget.scope.userId,
      shopId: widget.scope.shopId,
      day: widget.scope.day,
      reloadDay: widget.scope.reloadDay,
      watched: [revision],
      fields: [
        if (available.isEmpty)
          const InventoryNotice(message: 'لا توجد كمية متاحة للتحويل.')
        else
          _lotMenu(available, (value) => setState(() => _lotId = value)),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('convert-destination'),
          initialValue: _destination,
          isExpanded: true,
          decoration: ledgerFieldDecoration(context, label: 'الفئة الجديدة'),
          items: [
            for (final category in _categories)
              DropdownMenuItem(
                value: category,
                child: Text(inventoryCategoryLabel(category)),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _destination = value);
          },
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _name,
          label: 'اسم الناتج',
          fieldKey: const Key('convert-name'),
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _grams,
          label: 'الوزن المحوّل بالجرام',
          fieldKey: const Key('convert-grams'),
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _sourceCount,
          label: 'عدد المصدر',
          fieldKey: const Key('convert-source-count'),
          keyboard: TextInputType.number,
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _destCount,
          label: 'عدد الناتج',
          fieldKey: const Key('convert-dest-count'),
          keyboard: TextInputType.number,
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _reason,
          label: 'سبب التحويل',
          fieldKey: const Key('convert-reason'),
          action: TextInputAction.done,
          maxLength: 1000,
        ),
      ],
      onReview: (day) {
        LotSnapshot? lot;
        for (final item in available) {
          if (item.id == _lotId) lot = item;
        }
        lot ??= available.isEmpty ? null : available.first;
        if (lot == null) {
          return const InventoryRejected(InventoryIssueCode.emptyCommand);
        }
        return reviewConversion(
          day: day,
          reason: _reason.text,
          source: lot,
          destinationCategory: _destination,
          itemName: _name.text,
          milligrams: readGrams(_grams.text) ?? BigInt.zero,
          sourceCount: lot.tracksCount ? readCount(_sourceCount.text) : null,
          destinationCount: _destination == 'scrap'
              ? null
              : readCount(_destCount.text),
        );
      },
    );
  }
}

class InventoryReceiptForm extends StatefulWidget {
  const InventoryReceiptForm({
    super.key,
    required this.scope,
    this.traders = const [],
    this.denominations = const [],
    this.coins = const [],
  });

  final InventoryFormScope scope;
  final List<TraderSummary> traders;
  final List<CatalogDenomination> denominations;
  final List<CatalogCoin> coins;

  @override
  State<InventoryReceiptForm> createState() => _InventoryReceiptFormState();
}

class _InventoryReceiptFormState extends State<InventoryReceiptForm>
    with InvalidatesReview {
  final _party = TextEditingController();
  final _product = TextEditingController();
  final _grams = TextEditingController();
  final _count = TextEditingController(text: '1');
  final _note = TextEditingController();
  String _owner = 'shop';
  String _recognition = 'immediate';
  String _category = 'worked_jewelry';
  int _karat = 21;
  String? _traderId;
  String? _denominationId;
  String? _coinId;

  @override
  void initState() {
    super.initState();
    bindReview([_party, _product, _grams, _count, _note]);
  }

  @override
  void dispose() {
    revision.dispose();
    _party.dispose();
    _product.dispose();
    _grams.dispose();
    _count.dispose();
    _note.dispose();
    super.dispose();
  }

  BigInt? get _receiptNominal {
    if (_category == 'bullion') {
      for (final item in widget.denominations) {
        if (item.id == _denominationId) return item.nominalMilligrams;
      }
    }
    if (_category == 'coin') {
      for (final item in widget.coins) {
        if (item.id == _coinId) return item.nominalMilligrams;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scrap = _category == 'scrap';
    return CommandHost(
      title: 'استلام ذهب',
      readOnly: widget.scope.readOnly,
      flow: widget.scope.flow,
      userId: widget.scope.userId,
      shopId: widget.scope.shopId,
      day: widget.scope.day,
      reloadDay: widget.scope.reloadDay,
      watched: [revision],
      fields: [
        DropdownButtonFormField<String>(
          key: const Key('receipt-owner'),
          initialValue: _owner,
          isExpanded: true,
          decoration: ledgerFieldDecoration(context, label: 'المالك'),
          items: const [
            DropdownMenuItem(value: 'shop', child: Text('ملك المحل')),
            DropdownMenuItem(value: 'trader', child: Text('ملك تاجر — أمانة')),
          ],
          onChanged: (value) {
            if (value == null) return;
            setState(() {
              _owner = value;
              _recognition = value == 'trader' ? 'custody' : 'immediate';
            });
          },
        ),
        const SizedBox(height: 12),
        if (_owner == 'shop')
          DropdownButtonFormField<String>(
            key: const Key('receipt-recognition'),
            initialValue: _recognition == 'custody'
                ? 'immediate'
                : _recognition,
            isExpanded: true,
            decoration: ledgerFieldDecoration(context, label: 'الاعتراف'),
            items: const [
              DropdownMenuItem(
                value: 'immediate',
                child: Text('فوري إلى المتاح للبيع'),
              ),
              DropdownMenuItem(
                value: 'deferred',
                child: Text('معلق بانتظار الاعتراف'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _recognition = value);
            },
          )
        else if (widget.traders.isEmpty)
          const InventoryNotice(
            message: 'احفظ تاجراً أولاً قبل تسجيل أمانة باسمه.',
            error: true,
          )
        else
          DropdownButtonFormField<String>(
            key: const Key('receipt-trader'),
            initialValue: _traderId ?? widget.traders.first.id,
            isExpanded: true,
            decoration: ledgerFieldDecoration(context, label: 'التاجر المالك'),
            items: [
              for (final trader in widget.traders.where((item) => item.active))
                DropdownMenuItem(
                  value: trader.id,
                  child: Text(trader.displayName),
                ),
            ],
            onChanged: (value) => setState(() => _traderId = value),
          ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _party,
          label: 'اسم الطرف',
          fieldKey: const Key('receipt-party'),
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _product,
          label: 'اسم الصنف',
          fieldKey: const Key('receipt-product'),
        ),
        const SizedBox(height: 12),
        InventoryCategoryKarat(
          category: _category,
          karat: _karat,
          categoryKey: const Key('receipt-category'),
          karatKey: Key('receipt-karat-$_category'),
          onCategory: (value) {
            final next = karatsFor(value);
            setState(() {
              _category = value;
              _karat = next.contains(_karat) ? _karat : next.first;
              _denominationId = null;
              _coinId = null;
            });
          },
          onKarat: (value) => setState(() => _karat = value),
        ),
        if (_category == 'bullion' && widget.denominations.isNotEmpty) ...[
          const SizedBox(height: 12),
          _identityMenu(
            label: 'فئة السبيكة الاسمية',
            value: _denominationId,
            entries: [
              for (final item in widget.denominations.where(
                (item) => item.active,
              ))
                (
                  item.id,
                  '${item.id} — ${item.label} الاسمي ${gramsOf(item.nominalMilligrams)} جرام',
                ),
            ],
            onChanged: (value) => setState(() => _denominationId = value),
          ),
        ],
        if (_category == 'coin' && widget.coins.isNotEmpty) ...[
          const SizedBox(height: 12),
          _identityMenu(
            label: 'نوع العملة',
            value: _coinId,
            entries: [
              for (final item in widget.coins.where((item) => item.active))
                (
                  item.id,
                  item.nominalMilligrams == null
                      ? '${item.id} — ${item.label}'
                      : '${item.id} — ${item.label} الاسمي ${gramsOf(item.nominalMilligrams!)} جرام',
                ),
            ],
            onChanged: (value) => setState(() => _coinId = value),
          ),
        ],
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _grams,
          label: 'الوزن الفعلي بالجرام',
          fieldKey: const Key('receipt-grams'),
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        if (!scrap) ...[
          const SizedBox(height: 12),
          inventoryField(
            context: context,
            controller: _count,
            label: 'العدد',
            fieldKey: const Key('receipt-count'),
            keyboard: TextInputType.number,
          ),
        ],
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _note,
          label: 'ملاحظة',
          fieldKey: const Key('receipt-note'),
          action: TextInputAction.done,
          maxLength: 1000,
        ),
      ],
      onReview: (day) => reviewReceipt(
        day: day,
        ownerKind: _owner,
        traderId: _owner == 'trader'
            ? (_traderId ??
                  (widget.traders.isEmpty ? null : widget.traders.first.id))
            : null,
        counterpartyName: _party.text,
        productName: _product.text,
        category: _category,
        karat: _karat,
        milligrams: readGrams(_grams.text) ?? BigInt.zero,
        count: scrap ? null : readCount(_count.text),
        recognition: _owner == 'trader' ? 'custody' : _recognition,
        note: _note.text,
        denominationId: _category == 'bullion' ? _denominationId : null,
        nominalMilligrams: _receiptNominal,
        coinTypeId: _category == 'coin' ? _coinId : null,
      ),
    );
  }
}

class InventoryRecognitionForm extends StatefulWidget {
  const InventoryRecognitionForm({
    super.key,
    required this.scope,
    required this.receipts,
    this.nextCursor,
    this.loadOlder,
  });

  final InventoryFormScope scope;
  final List<ReceiptSnapshot> receipts;
  final String? nextCursor;
  final Future<ReceiptPage> Function(String? cursor)? loadOlder;

  @override
  State<InventoryRecognitionForm> createState() =>
      _InventoryRecognitionFormState();
}

class _InventoryRecognitionFormState extends State<InventoryRecognitionForm>
    with InvalidatesReview {
  final _grams = TextEditingController();
  final _count = TextEditingController(text: '1');
  final _reason = TextEditingController();
  String? _receiptId;
  late List<ReceiptSnapshot> _receipts;
  String? _cursor;

  @override
  void initState() {
    super.initState();
    bindReview([_grams, _count, _reason]);
    _receipts = [...widget.receipts];
    _cursor = widget.nextCursor;
  }

  @override
  void dispose() {
    revision.dispose();
    _grams.dispose();
    _count.dispose();
    _reason.dispose();
    super.dispose();
  }

  List<ReceiptSnapshot> get _pending => [
    for (final receipt in _receipts)
      if (receipt.policy == 'deferred' &&
          receipt.remainingMilligrams > BigInt.zero)
        receipt,
  ];

  @override
  Widget build(BuildContext context) {
    final receipt = _selected;
    return CommandHost(
      title: 'اعتراف جزئي أو كامل',
      readOnly: widget.scope.readOnly,
      flow: widget.scope.flow,
      userId: widget.scope.userId,
      shopId: widget.scope.shopId,
      day: widget.scope.day,
      reloadDay: widget.scope.reloadDay,
      watched: [revision],
      fields: [
        if (_pending.isEmpty)
          const InventoryNotice(
            message: 'لا يوجد استلام مملوك بانتظار الاعتراف.',
          )
        else
          DropdownButtonFormField<String>(
            key: const Key('recognize-receipt'),
            initialValue: receipt?.id,
            isExpanded: true,
            decoration: ledgerFieldDecoration(
              context,
              label: 'الاستلام المعلق',
            ),
            items: [
              for (final item in _pending)
                DropdownMenuItem(
                  value: item.id,
                  child: Text(receiptOptionLabel(item)),
                ),
            ],
            onChanged: (value) => setState(() => _receiptId = value),
          ),
        OlderPageControl(
          count: _pending.length,
          noun: 'استلامات معلقة',
          nextCursor: _cursor,
          onOlder: _olderReceipts,
          controlKey: const Key('recognize-older'),
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _grams,
          label: 'الوزن المعترف به بالجرام',
          fieldKey: const Key('recognize-grams'),
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _count,
          label: 'العدد',
          fieldKey: const Key('recognize-count'),
          keyboard: TextInputType.number,
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _reason,
          label: 'سبب الاعتراف',
          fieldKey: const Key('recognize-reason'),
          action: TextInputAction.done,
          maxLength: 1000,
        ),
      ],
      onReview: (day) {
        final selected = _selected;
        if (selected == null) {
          return const InventoryRejected(InventoryIssueCode.emptyCommand);
        }
        return reviewRecognition(
          day: day,
          reason: _reason.text,
          receipt: selected,
          milligrams: readGrams(_grams.text) ?? BigInt.zero,
          count: selected.category == 'scrap' ? null : readCount(_count.text),
        );
      },
    );
  }

  ReceiptSnapshot? get _selected {
    for (final receipt in _pending) {
      if (receipt.id == _receiptId) return receipt;
    }
    return _pending.isEmpty ? null : _pending.first;
  }

  Future<void> _olderReceipts() async {
    final load = widget.loadOlder;
    final cursor = _cursor;
    if (load == null || cursor == null) return;
    try {
      final page = await load(cursor);
      if (!mounted || !page.available || page.items == null) return;
      setState(() {
        _receipts = [..._receipts, ...page.items!];
        _cursor = page.nextCursor;
      });
    } on InventoryReadException {
      if (!mounted) return;
    }
  }
}

class InventoryManualLinkForm extends StatefulWidget {
  const InventoryManualLinkForm({
    super.key,
    required this.scope,
    required this.receipts,
    required this.lots,
    this.nextCursor,
    this.loadOlder,
  });

  final InventoryFormScope scope;
  final List<ReceiptSnapshot> receipts;
  final List<LotSnapshot> lots;
  final String? nextCursor;
  final Future<ReceiptPage> Function(String? cursor)? loadOlder;

  @override
  State<InventoryManualLinkForm> createState() =>
      _InventoryManualLinkFormState();
}

class _InventoryManualLinkFormState extends State<InventoryManualLinkForm>
    with InvalidatesReview {
  final _reason = TextEditingController();
  String? _receiptId;
  String? _lotId;
  late List<ReceiptSnapshot> _receipts;
  String? _cursor;

  @override
  void initState() {
    super.initState();
    bindReview([_reason]);
    _receipts = [...widget.receipts];
    _cursor = widget.nextCursor;
  }

  @override
  void dispose() {
    revision.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final receipts = [
      for (final receipt in _receipts)
        if (receipt.policy == 'deferred' &&
            receipt.remainingMilligrams > BigInt.zero)
          receipt,
    ];
    final receipt = _pick(receipts, _receiptId);
    final matches = [
      for (final lot in widget.lots)
        if (receipt != null &&
            lot.originOperationId != null &&
            lot.stockClass == StockClass.ownedAvailable &&
            lot.productId == receipt.productId &&
            lot.category == receipt.category &&
            lot.karat == receipt.karat &&
            lot.remainingMilligrams == lot.originalMilligrams)
          lot,
    ];
    return CommandHost(
      title: 'ربط يدوي بإضافة مؤكدة',
      readOnly: widget.scope.readOnly,
      flow: widget.scope.flow,
      userId: widget.scope.userId,
      shopId: widget.scope.shopId,
      day: widget.scope.day,
      reloadDay: widget.scope.reloadDay,
      watched: [revision],
      fields: [
        if (receipts.isEmpty)
          const InventoryNotice(
            message: 'لا يوجد استلام مملوك معلّق يمكن ربطه.',
          )
        else
          DropdownButtonFormField<String>(
            key: const Key('link-receipt'),
            initialValue: receipt?.id,
            isExpanded: true,
            decoration: ledgerFieldDecoration(context, label: 'الاستلام'),
            items: [
              for (final item in receipts)
                DropdownMenuItem(
                  value: item.id,
                  child: Text(receiptOptionLabel(item)),
                ),
            ],
            onChanged: (value) => setState(() {
              _receiptId = value;
              _lotId = null;
            }),
          ),
        OlderPageControl(
          count: receipts.length,
          noun: 'استلامات معلقة',
          nextCursor: _cursor,
          onOlder: _olderReceipts,
          controlKey: const Key('link-older'),
        ),
        const SizedBox(height: 12),
        if (matches.isEmpty)
          const InventoryNotice(
            message: 'لا توجد إضافة مؤكدة مطابقة للفئة والعيار والوزن الكامل.',
          )
        else
          _lotMenu(matches, (value) => setState(() => _lotId = value)),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _reason,
          label: 'سبب الربط',
          fieldKey: const Key('link-reason'),
          action: TextInputAction.done,
          maxLength: 1000,
        ),
      ],
      onReview: (day) {
        final selectedReceipt = _pick(receipts, _receiptId);
        LotSnapshot? lot;
        for (final item in matches) {
          if (item.id == _lotId) lot = item;
        }
        lot ??= matches.isEmpty ? null : matches.first;
        if (selectedReceipt == null || lot?.originOperationId == null) {
          return const InventoryRejected(InventoryIssueCode.invalidInput);
        }
        return reviewManualLink(
          day: day,
          reason: _reason.text,
          receipt: selectedReceipt,
          lot: lot!,
          manualOperationId: lot.originOperationId!,
        );
      },
    );
  }

  Future<void> _olderReceipts() async {
    final load = widget.loadOlder;
    final cursor = _cursor;
    if (load == null || cursor == null) return;
    try {
      final page = await load(cursor);
      if (!mounted || !page.available || page.items == null) return;
      setState(() {
        _receipts = [..._receipts, ...page.items!];
        _cursor = page.nextCursor;
      });
    } on InventoryReadException {
      if (!mounted) return;
    }
  }
}

class OwnershipTransferForm extends StatefulWidget {
  const OwnershipTransferForm({
    super.key,
    required this.scope,
    required this.receipts,
    this.nextCursor,
    this.loadOlder,
  });

  final InventoryFormScope scope;
  final List<ReceiptSnapshot> receipts;
  final String? nextCursor;
  final Future<ReceiptPage> Function(String? cursor)? loadOlder;

  @override
  State<OwnershipTransferForm> createState() => _OwnershipTransferFormState();
}

class _OwnershipTransferFormState extends State<OwnershipTransferForm>
    with InvalidatesReview {
  final _grams = TextEditingController();
  final _count = TextEditingController(text: '1');
  final _price = TextEditingController();
  final _paid = TextEditingController();
  final _gold = TextEditingController();
  final _reason = TextEditingController();
  String? _receiptId;
  String _unit = 'egp';
  String _method = 'cash';
  late List<ReceiptSnapshot> _receipts;
  String? _cursor;

  @override
  void initState() {
    super.initState();
    bindReview([_grams, _count, _price, _paid, _gold, _reason]);
    _receipts = [...widget.receipts];
    _cursor = widget.nextCursor;
  }

  @override
  void dispose() {
    revision.dispose();
    _grams.dispose();
    _count.dispose();
    _price.dispose();
    _paid.dispose();
    _gold.dispose();
    _reason.dispose();
    super.dispose();
  }

  List<ReceiptSnapshot> get _custody => [
    for (final receipt in _receipts)
      if (receipt.policy == 'custody' &&
          receipt.remainingMilligrams > BigInt.zero)
        receipt,
  ];

  @override
  Widget build(BuildContext context) {
    final receipt = _pick(_custody, _receiptId);
    return CommandHost(
      title: 'نقل ملكية الأمانة',
      readOnly: widget.scope.readOnly,
      flow: widget.scope.flow,
      userId: widget.scope.userId,
      shopId: widget.scope.shopId,
      day: widget.scope.day,
      reloadDay: widget.scope.reloadDay,
      watched: [revision],
      fields: [
        if (_custody.isEmpty)
          const InventoryNotice(message: 'لا توجد أمانة متبقية لنقل ملكيتها.')
        else
          DropdownButtonFormField<String>(
            key: const Key('transfer-receipt'),
            initialValue: receipt?.id,
            isExpanded: true,
            decoration: ledgerFieldDecoration(context, label: 'إيصال الأمانة'),
            items: [
              for (final item in _custody)
                DropdownMenuItem(
                  value: item.id,
                  child: Text(receiptOptionLabel(item)),
                ),
            ],
            onChanged: (value) => setState(() => _receiptId = value),
          ),
        OlderPageControl(
          count: _custody.length,
          noun: 'إيصالات أمانة',
          nextCursor: _cursor,
          onOlder: _olderReceipts,
          controlKey: const Key('transfer-older'),
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _grams,
          label: 'الوزن المنقول بالجرام',
          fieldKey: const Key('transfer-grams'),
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        if (receipt?.category != 'scrap')
          inventoryField(
            context: context,
            controller: _count,
            label: 'العدد',
            fieldKey: const Key('transfer-count'),
            keyboard: TextInputType.number,
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('transfer-unit'),
          initialValue: _unit,
          isExpanded: true,
          decoration: ledgerFieldDecoration(
            context,
            label: 'وحدة الالتزام الواحدة',
          ),
          items: const [
            DropdownMenuItem(value: 'egp', child: Text('نقد')),
            DropdownMenuItem(
              value: 'gold',
              child: Text('ذهب من العيار نفسه فقط'),
            ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _unit = value);
          },
        ),
        const SizedBox(height: 12),
        if (_unit == 'egp') ...[
          inventoryField(
            context: context,
            controller: _price,
            label: 'سعر الشراء ',
            fieldKey: const Key('transfer-price'),
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('transfer-method'),
            initialValue: _method,
            isExpanded: true,
            decoration: ledgerFieldDecoration(context, label: 'وسيلة الدفع'),
            items: [
              for (final method in CashMethod.canonicalOrder)
                DropdownMenuItem(
                  value: method.code,
                  child: Text(cashMethodLabel(method)),
                ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _method = value);
            },
          ),
          const SizedBox(height: 12),
          inventoryField(
            context: context,
            controller: _paid,
            label: 'المدفوع الآن ',
            fieldKey: const Key('transfer-paid'),
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
        ] else ...[
          Text('عيار الالتزام: ${receipt?.karat ?? '—'}، وهو عيار القطعة.'),
          const SizedBox(height: 12),
          inventoryField(
            context: context,
            controller: _gold,
            label: 'وزن الذهب المستحق بالجرام',
            fieldKey: const Key('transfer-gold'),
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _reason,
          label: 'سبب نقل الملكية',
          fieldKey: const Key('transfer-reason'),
          action: TextInputAction.done,
          maxLength: 1000,
        ),
      ],
      onReview: (day) {
        final selected = _pick(_custody, _receiptId);
        if (selected == null) {
          return const InventoryRejected(InventoryIssueCode.emptyCommand);
        }
        final TransferObligation obligation;
        if (_unit == 'gold') {
          obligation = GoldObligationDraft(
            karat: selected.karat,
            milligrams: readGrams(_gold.text) ?? BigInt.zero,
          );
        } else {
          final paid = _paid.text.trim().isEmpty
              ? null
              : readPounds(_paid.text);
          obligation = EgpObligation(
            pricePiastres: readPounds(_price.text) ?? BigInt.zero,
            tenders: paid == null
                ? const []
                : [TenderDraft(method: _method, piastres: paid)],
          );
        }
        return reviewOwnershipTransfer(
          day: day,
          reason: _reason.text,
          receipt: selected,
          milligrams: readGrams(_grams.text) ?? BigInt.zero,
          count: selected.category == 'scrap' ? null : readCount(_count.text),
          obligation: obligation,
        );
      },
    );
  }

  Future<void> _olderReceipts() async {
    final load = widget.loadOlder;
    final cursor = _cursor;
    if (load == null || cursor == null) return;
    try {
      final page = await load(cursor);
      if (!mounted || !page.available || page.items == null) return;
      setState(() {
        _receipts = [..._receipts, ...page.items!];
        _cursor = page.nextCursor;
      });
    } on InventoryReadException {
      if (!mounted) return;
    }
  }
}

class GoldAcquisitionForm extends StatefulWidget {
  const GoldAcquisitionForm({
    super.key,
    required this.scope,
    this.traders = const [],
    this.traderCursor,
    this.loadTraders,
  });

  final InventoryFormScope scope;
  final List<TraderSummary> traders;
  final String? traderCursor;
  final Future<TraderPage> Function(String? cursor)? loadTraders;

  @override
  State<GoldAcquisitionForm> createState() => _GoldAcquisitionFormState();
}

class _GoldAcquisitionFormState extends State<GoldAcquisitionForm>
    with InvalidatesReview {
  final _name = TextEditingController();
  final _party = TextEditingController();
  final _grams = TextEditingController();
  final _count = TextEditingController(text: '1');
  final _owed = TextEditingController();
  final _note = TextEditingController();
  String _category = 'worked_jewelry';
  int _karat = 21;
  int _owedKarat = 21;
  String? _traderId;
  late List<TraderSummary> _traders;
  String? _traderCursor;

  @override
  void initState() {
    super.initState();
    bindReview([_name, _party, _grams, _count, _owed, _note]);
    _traders = [...widget.traders];
    _traderCursor = widget.traderCursor;
  }

  @override
  void dispose() {
    revision.dispose();
    _name.dispose();
    _party.dispose();
    _grams.dispose();
    _count.dispose();
    _owed.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommandHost(
      title: 'شراء مقابل ذهب',
      readOnly: widget.scope.readOnly,
      flow: widget.scope.flow,
      userId: widget.scope.userId,
      shopId: widget.scope.shopId,
      day: widget.scope.day,
      reloadDay: widget.scope.reloadDay,
      watched: [revision],
      fields: [
        inventoryField(
          context: context,
          controller: _name,
          label: 'اسم الصنف الوارد',
          fieldKey: const Key('gold-buy-name'),
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _party,
          label: 'اسم الطرف',
          fieldKey: const Key('gold-buy-party'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          key: const Key('gold-buy-trader'),
          initialValue: _traderId,
          isExpanded: true,
          decoration: ledgerFieldDecoration(
            context,
            label: 'تاجر مربوط أو بدون ربط',
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('بدون ربط بتاجر')),
            for (final trader in _traders.where((item) => item.active))
              DropdownMenuItem(
                value: trader.id,
                child: Text('${trader.displayName} — ${trader.id}'),
              ),
          ],
          onChanged: (value) => setState(() => _traderId = value),
        ),
        OlderPageControl(
          count: _traders.length,
          noun: 'تجار',
          nextCursor: _traderCursor,
          onOlder: _olderTraders,
          controlKey: const Key('gold-buy-traders-older'),
        ),
        const SizedBox(height: 12),
        InventoryCategoryKarat(
          category: _category,
          karat: _karat,
          categoryKey: const Key('gold-buy-category'),
          karatKey: Key('gold-buy-karat-$_category'),
          onCategory: (value) {
            final next = karatsFor(value);
            setState(() {
              _category = value;
              _karat = next.contains(_karat) ? _karat : next.first;
            });
          },
          onKarat: (value) => setState(() => _karat = value),
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _grams,
          label: 'الوزن الفعلي الوارد بالجرام',
          fieldKey: const Key('gold-buy-grams'),
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        if (_category != 'scrap')
          inventoryField(
            context: context,
            controller: _count,
            label: 'العدد',
            fieldKey: const Key('gold-buy-count'),
            keyboard: TextInputType.number,
          ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          key: const Key('gold-buy-owed-karat'),
          initialValue: _owedKarat,
          isExpanded: true,
          decoration: ledgerFieldDecoration(
            context,
            label: 'عيار الذهب المستحق',
          ),
          items: [
            for (final karat in ScrapKarats.allowed)
              DropdownMenuItem(value: karat, child: Text('$karat')),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _owedKarat = value);
          },
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _owed,
          label: 'وزن الذهب المستحق بالجرام',
          fieldKey: const Key('gold-buy-owed'),
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _note,
          label: 'ملاحظة',
          fieldKey: const Key('gold-buy-note'),
          action: TextInputAction.done,
          maxLength: 1000,
        ),
      ],
      onReview: (day) => reviewGoldAcquisition(
        day: day,
        itemName: _name.text,
        category: _category,
        karat: _karat,
        milligrams: readGrams(_grams.text) ?? BigInt.zero,
        count: _category == 'scrap' ? null : readCount(_count.text),
        obligationKarat: _owedKarat,
        obligationMilligrams: readGrams(_owed.text) ?? BigInt.zero,
        counterpartyName: _party.text,
        note: _note.text,
        traderId: _traderId,
      ),
    );
  }

  Future<void> _olderTraders() async {
    final load = widget.loadTraders;
    final cursor = _traderCursor;
    if (load == null || cursor == null) return;
    try {
      final page = await load(cursor);
      if (!mounted) return;
      setState(() {
        _traders = [..._traders, ...page.items];
        _traderCursor = page.nextCursor;
      });
    } on InventoryReadException {
      if (!mounted) return;
    }
  }
}

class GoldSettlementForm extends StatefulWidget {
  const GoldSettlementForm({
    super.key,
    required this.scope,
    required this.obligations,
    required this.lots,
    this.nextCursor,
    this.loadOlder,
  });

  final InventoryFormScope scope;
  final List<GoldObligationView> obligations;
  final List<LotSnapshot> lots;
  final String? nextCursor;
  final Future<ReadPage<GoldObligationView>> Function(String? cursor)?
  loadOlder;

  @override
  State<GoldSettlementForm> createState() => _GoldSettlementFormState();
}

class _GoldSettlementFormState extends State<GoldSettlementForm>
    with InvalidatesReview {
  final _grams = TextEditingController();
  final _count = TextEditingController(text: '1');
  final _reason = TextEditingController();
  String? _obligationId;
  String? _lotId;
  late List<GoldObligationView> _obligations;
  String? _cursor;

  @override
  void initState() {
    super.initState();
    bindReview([_grams, _count, _reason]);
    _obligations = [...widget.obligations];
    _cursor = widget.nextCursor;
  }

  @override
  void dispose() {
    revision.dispose();
    _grams.dispose();
    _count.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = [
      for (final item in _obligations)
        if (item.remainingMilligrams > BigInt.zero) item,
    ];
    final obligation = _obligation(open);
    final lots = [
      for (final lot in widget.lots)
        if (obligation != null &&
            lot.stockClass == StockClass.ownedAvailable &&
            lot.karat == obligation.karat &&
            lot.remainingMilligrams > BigInt.zero)
          lot,
    ];
    return CommandHost(
      title: 'تسوية مستحق ذهبي',
      readOnly: widget.scope.readOnly,
      flow: widget.scope.flow,
      userId: widget.scope.userId,
      shopId: widget.scope.shopId,
      day: widget.scope.day,
      reloadDay: widget.scope.reloadDay,
      watched: [revision],
      fields: [
        if (open.isEmpty)
          const InventoryNotice(message: 'لا يوجد مستحق ذهبي مفتوح.')
        else
          DropdownButtonFormField<String>(
            key: const Key('gold-settle-obligation'),
            initialValue: obligation?.operationId,
            isExpanded: true,
            decoration: ledgerFieldDecoration(context, label: 'المستحق'),
            items: [
              for (final item in open)
                DropdownMenuItem(
                  value: item.operationId,
                  child: Text(
                    '${item.operationId} — عيار ${item.karat} — المتبقي ${gramsOf(item.remainingMilligrams)}'
                    '${item.traderId == null ? ' — غير مربوط بتاجر' : ' — تاجر ${item.traderId}'}',
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _obligationId = value),
          ),
        OlderPageControl(
          count: open.length,
          noun: 'مستحقات ذهب',
          nextCursor: _cursor,
          onOlder: _olderObligations,
          controlKey: const Key('gold-settle-older'),
        ),
        const SizedBox(height: 12),
        if (lots.isEmpty)
          const InventoryNotice(message: 'لا توجد دفعة مملوكة من عيار المستحق.')
        else
          _lotMenu(lots, (value) => setState(() => _lotId = value)),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _grams,
          label: 'الوزن المسلّم بالجرام',
          fieldKey: const Key('gold-settle-grams'),
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _count,
          label: 'العدد إن كانت القطعة معدودة',
          fieldKey: const Key('gold-settle-count'),
          keyboard: TextInputType.number,
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _reason,
          label: 'سبب التسوية',
          fieldKey: const Key('gold-settle-reason'),
          action: TextInputAction.done,
          maxLength: 1000,
        ),
      ],
      onReview: (day) {
        final selected = _obligation(open);
        LotSnapshot? lot;
        for (final item in lots) {
          if (item.id == _lotId) lot = item;
        }
        lot ??= lots.isEmpty ? null : lots.first;
        if (selected == null || lot == null) {
          return const InventoryRejected(InventoryIssueCode.emptyCommand);
        }
        return reviewGoldSettlement(
          day: day,
          reason: _reason.text,
          obligationOperationId: selected.operationId,
          obligationKarat: selected.karat,
          remainingMilligrams: selected.remainingMilligrams,
          deliveries: [
            DeliveryDraft(
              lot: lot,
              milligrams: readGrams(_grams.text) ?? BigInt.zero,
              count: lot.tracksCount ? readCount(_count.text) : null,
            ),
          ],
        );
      },
    );
  }

  GoldObligationView? _obligation(List<GoldObligationView> open) {
    for (final item in open) {
      if (item.operationId == _obligationId) return item;
    }
    return open.isEmpty ? null : open.first;
  }

  Future<void> _olderObligations() async {
    final load = widget.loadOlder;
    final cursor = _cursor;
    if (load == null || cursor == null) return;
    try {
      final page = await load(cursor);
      if (!mounted || !page.available || page.items == null) return;
      setState(() {
        _obligations = [..._obligations, ...page.items!];
        _cursor = page.nextCursor;
      });
    } on InventoryReadException {
      if (!mounted) return;
    }
  }
}

class CatalogProductForm extends StatefulWidget {
  const CatalogProductForm({super.key, required this.scope});
  final InventoryFormScope scope;

  @override
  State<CatalogProductForm> createState() => _CatalogProductFormState();
}

class _CatalogProductFormState extends State<CatalogProductForm>
    with InvalidatesReview {
  final _name = TextEditingController();
  String _category = 'worked_jewelry';
  int _karat = 21;

  @override
  void initState() {
    super.initState();
    bindReview([_name]);
  }

  @override
  void dispose() {
    revision.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommandHost(
      title: 'منتج في الكتالوج',
      readOnly: widget.scope.readOnly,
      flow: widget.scope.flow,
      userId: widget.scope.userId,
      shopId: widget.scope.shopId,
      day: widget.scope.day,
      reloadDay: widget.scope.reloadDay,
      watched: [revision],
      fields: [
        inventoryField(
          context: context,
          controller: _name,
          label: 'اسم المنتج',
          fieldKey: const Key('product-name'),
          action: TextInputAction.done,
        ),
        const SizedBox(height: 12),
        InventoryCategoryKarat(
          category: _category,
          karat: _karat,
          categoryKey: const Key('product-category'),
          karatKey: Key('product-karat-$_category'),
          onCategory: (value) {
            final next = karatsFor(value);
            setState(() {
              _category = value;
              _karat = next.contains(_karat) ? _karat : next.first;
            });
          },
          onKarat: (value) => setState(() => _karat = value),
        ),
        const SizedBox(height: 8),
        const Text('الحفظ لا يضيف وزناً ولا نقداً.'),
      ],
      onReview: (day) => reviewProduct(
        day: day,
        name: _name.text,
        category: _category,
        karat: _karat,
      ),
    );
  }
}

class DenominationForm extends StatefulWidget {
  const DenominationForm({super.key, required this.scope, required this.coin});
  final InventoryFormScope scope;
  final bool coin;

  @override
  State<DenominationForm> createState() => _DenominationFormState();
}

class _DenominationFormState extends State<DenominationForm>
    with InvalidatesReview {
  final _label = TextEditingController();
  final _grams = TextEditingController();
  bool _active = true;
  bool _withoutNominal = false;

  @override
  void initState() {
    super.initState();
    bindReview([_label, _grams]);
  }

  @override
  void dispose() {
    revision.dispose();
    _label.dispose();
    _grams.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommandHost(
      title: widget.coin ? 'نوع عملة' : 'فئة سبيكة',
      readOnly: widget.scope.readOnly,
      flow: widget.scope.flow,
      userId: widget.scope.userId,
      shopId: widget.scope.shopId,
      day: widget.scope.day,
      reloadDay: widget.scope.reloadDay,
      watched: [revision],
      fields: [
        inventoryField(
          context: context,
          controller: _label,
          label: 'الاسم',
          fieldKey: const Key('denom-label'),
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _grams,
          label: 'الوزن الاسمي بالجرام',
          fieldKey: const Key('denom-grams'),
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        if (widget.coin)
          SwitchListTile(
            key: const Key('denom-no-nominal'),
            contentPadding: EdgeInsets.zero,
            title: const Text('بدون وزن اسمي'),
            value: _withoutNominal,
            onChanged: (value) => setState(() => _withoutNominal = value),
          ),
        SwitchListTile(
          key: const Key('denom-active'),
          contentPadding: EdgeInsets.zero,
          title: const Text('نشط في الكتالوج'),
          value: _active,
          onChanged: (value) => setState(() => _active = value),
        ),
        const Text('الوزن الاسمي لا يصبح وزن مخزون.'),
      ],
      onReview: (day) {
        final nominal = _withoutNominal ? null : readGrams(_grams.text);
        if (widget.coin) {
          return reviewCoinType(
            day: day,
            label: _label.text,
            nominalMilligrams: nominal,
            active: _active,
          );
        }
        return reviewBullionDenomination(
          day: day,
          label: _label.text,
          nominalMilligrams: nominal ?? BigInt.zero,
          active: _active,
        );
      },
    );
  }
}

class TraderSaveForm extends StatefulWidget {
  const TraderSaveForm({
    super.key,
    required this.scope,
    this.nameFocus,
    this.embedded = false,
    this.onFinished,
  });

  final InventoryFormScope scope;
  final FocusNode? nameFocus;
  final bool embedded;
  final VoidCallback? onFinished;

  @override
  State<TraderSaveForm> createState() => _TraderSaveFormState();
}

class _TraderSaveFormState extends State<TraderSaveForm>
    with InvalidatesReview {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  bool _active = true;

  @override
  void initState() {
    super.initState();
    bindReview([_name, _phone, _note]);
  }

  @override
  void dispose() {
    revision.dispose();
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommandHost(
      title: 'حفظ تاجر',
      readOnly: widget.scope.readOnly,
      flow: widget.scope.flow,
      userId: widget.scope.userId,
      shopId: widget.scope.shopId,
      day: widget.scope.day,
      reloadDay: widget.scope.reloadDay,
      watched: [revision],
      embedded: widget.embedded,
      onFinished: widget.onFinished,
      fields: [
        inventoryField(
          context: context,
          controller: _name,
          label: 'اسم التاجر',
          fieldKey: const Key('trader-name'),
          focusNode: widget.nameFocus,
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _phone,
          label: 'الهاتف',
          fieldKey: const Key('trader-phone'),
          keyboard: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _note,
          label: 'ملاحظة',
          fieldKey: const Key('trader-note'),
          action: TextInputAction.done,
          maxLength: 1000,
        ),
        SwitchListTile(
          key: const Key('trader-active'),
          contentPadding: EdgeInsets.zero,
          title: const Text('التاجر نشط'),
          value: _active,
          onChanged: (value) => setState(() => _active = value),
        ),
      ],
      onReview: (day) => reviewTraderSave(
        day: day,
        displayName: _name.text,
        phone: _phone.text,
        note: _note.text,
        active: _active,
      ),
    );
  }
}

class InventoryCategoryKarat extends StatelessWidget {
  const InventoryCategoryKarat({
    super.key,
    required this.category,
    required this.karat,
    required this.categoryKey,
    required this.karatKey,
    required this.onCategory,
    required this.onKarat,
  });

  final String category;
  final int karat;
  final Key categoryKey;
  final Key karatKey;
  final ValueChanged<String> onCategory;
  final ValueChanged<int> onKarat;

  @override
  Widget build(BuildContext context) {
    final karats = karatsFor(category);
    final selected = karats.contains(karat) ? karat : karats.first;
    return LedgerFieldPair(
      first: DropdownButtonFormField<String>(
        key: categoryKey,
        initialValue: category,
        isExpanded: true,
        decoration: ledgerFieldDecoration(context, label: 'الفئة'),
        items: [
          for (final item in _categories)
            DropdownMenuItem(
              value: item,
              child: Text(inventoryCategoryLabel(item)),
            ),
        ],
        onChanged: (value) {
          if (value != null) onCategory(value);
        },
      ),
      second: DropdownButtonFormField<int>(
        key: karatKey,
        initialValue: selected,
        isExpanded: true,
        decoration: ledgerFieldDecoration(context, label: 'العيار'),
        items: [
          for (final item in karats)
            DropdownMenuItem(value: item, child: Text('$item')),
        ],
        onChanged: (value) {
          if (value != null) onKarat(value);
        },
      ),
    );
  }
}

Widget _lotMenu(List<LotSnapshot> lots, ValueChanged<String?> onChanged) {
  final first = lots.first.id;
  return Builder(
    builder: (context) => DropdownButtonFormField<String>(
      key: const Key('lot-menu'),
      initialValue: first,
      isExpanded: true,
      decoration: ledgerFieldDecoration(context, label: 'الدفعة'),
      items: [
        for (final lot in lots)
          DropdownMenuItem(
            value: lot.id,
            child: Text(
              '${lot.legacyAggregate ? 'رصيد سابق مجمّع — ' : ''}${lot.displayName} ${gramsOf(lot.remainingMilligrams)} جرام ${stockClassLabel(lot.stockClass)}'
              '${lot.denominationId == null ? '' : ' — سبيكة ${lot.denominationId}'}'
              '${lot.coinTypeId == null ? '' : ' — عملة ${lot.coinTypeId}'}',
            ),
          ),
      ],
      onChanged: onChanged,
    ),
  );
}

Widget _identityMenu({
  required String label,
  required String? value,
  required List<(String, String)> entries,
  required ValueChanged<String?> onChanged,
}) {
  return Builder(
    builder: (context) => DropdownButtonFormField<String>(
      key: Key(label),
      initialValue: value,
      isExpanded: true,
      decoration: ledgerFieldDecoration(context, label: label),
      items: [
        const DropdownMenuItem(value: null, child: Text('بدون هوية اسمية')),
        for (final entry in entries)
          DropdownMenuItem(value: entry.$1, child: Text(entry.$2)),
      ],
      onChanged: onChanged,
    ),
  );
}

T? _pick<T>(List<T> items, String? id) {
  for (final item in items) {
    if (item is ReceiptSnapshot && item.id == id) return item;
  }
  return items.isEmpty ? null : items.first;
}

class OlderPageControl extends StatelessWidget {
  const OlderPageControl({
    super.key,
    required this.count,
    required this.noun,
    required this.nextCursor,
    required this.onOlder,
    this.controlKey,
  });

  final int count;
  final String noun;
  final String? nextCursor;
  final VoidCallback? onOlder;
  final Key? controlKey;

  @override
  Widget build(BuildContext context) {
    final older = nextCursor != null;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            older
                ? 'المعروض $count $noun. توجد صفوف أقدم ولم تُعرض القائمة كلها.'
                : 'المعروض $count $noun. لا يوجد مؤشر لصف أقدم.',
          ),
          if (older)
            OutlinedButton(
              key: controlKey,
              onPressed: onOlder,
              child: Text('$noun أقدم'),
            ),
        ],
      ),
    );
  }
}

class ExplicitLotSaleForm extends StatefulWidget {
  const ExplicitLotSaleForm({
    super.key,
    required this.scope,
    required this.lots,
    this.nextCursor,
  });

  final InventoryFormScope scope;
  final List<LotSnapshot> lots;
  final String? nextCursor;

  @override
  State<ExplicitLotSaleForm> createState() => _ExplicitLotSaleFormState();
}

class _ExplicitLotSaleFormState extends State<ExplicitLotSaleForm>
    with InvalidatesReview {
  final _grams = TextEditingController();
  final _count = TextEditingController(text: '1');
  final _total = TextEditingController();
  final _paid = TextEditingController();
  final _description = TextEditingController();
  final _customer = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  final _base = TextEditingController();
  final _work = TextEditingController();
  final _other = TextEditingController();
  final _otherLabel = TextEditingController();
  final _discount = TextEditingController();
  String? _lotId;
  String _method = 'cash';
  bool _priced = false;
  late List<LotSnapshot> _lots;
  String? _cursor;

  @override
  void initState() {
    super.initState();
    bindReview([
      _grams,
      _count,
      _total,
      _paid,
      _description,
      _customer,
      _phone,
      _note,
      _base,
      _work,
      _other,
      _otherLabel,
      _discount,
    ]);
    _lots = [
      for (final lot in widget.lots)
        if (lot.stockClass == StockClass.ownedAvailable &&
            lot.remainingMilligrams > BigInt.zero)
          lot,
    ];
    _cursor = widget.nextCursor;
  }

  @override
  void dispose() {
    revision.dispose();
    for (final controller in [
      _grams,
      _count,
      _total,
      _paid,
      _description,
      _customer,
      _phone,
      _note,
      _base,
      _work,
      _other,
      _otherLabel,
      _discount,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  List<LotSnapshot> get _available => _lots;

  LotSnapshot? get _selected {
    for (final lot in _available) {
      if (lot.id == _lotId) return lot;
    }
    return _available.isEmpty ? null : _available.first;
  }

  @override
  Widget build(BuildContext context) {
    final lot = _selected;
    final identity = lot == null ? '' : lotIdentityCopy(lot);
    return CommandHost(
      title: 'بيع دفعة محددة',
      readOnly: widget.scope.readOnly,
      flow: widget.scope.flow,
      userId: widget.scope.userId,
      shopId: widget.scope.shopId,
      day: widget.scope.day,
      reloadDay: widget.scope.reloadDay,
      watched: [revision],
      canReview: lot != null,
      fields: [
        if (_available.isEmpty)
          const InventoryNotice(
            message:
                'لا توجد دفعة مملوكة متاحة للبيع. بيع الدفتر القديم يبقى منفصلاً.',
          )
        else
          _lotMenu(_available, (value) => setState(() => _lotId = value)),
        if (identity.isNotEmpty)
          Text(identity, key: const Key('lot-sale-identity')),
        OlderPageControl(
          count: _available.length,
          noun: 'دفعات متاحة',
          nextCursor: _cursor,
          onOlder: _olderLots,
          controlKey: const Key('lot-sale-older'),
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _grams,
          label: 'الوزن المبيع بالجرام',
          fieldKey: const Key('lot-sale-grams'),
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        if (lot?.tracksCount ?? true) ...[
          const SizedBox(height: 12),
          inventoryField(
            context: context,
            controller: _count,
            label: 'العدد',
            fieldKey: const Key('lot-sale-count'),
            keyboard: TextInputType.number,
          ),
        ],
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _total,
          label: 'سعر البيع ',
          fieldKey: const Key('lot-sale-total'),
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const Key('lot-sale-method'),
          initialValue: _method,
          isExpanded: true,
          decoration: ledgerFieldDecoration(context, label: 'وسيلة القبض'),
          items: [
            for (final method in CashMethod.canonicalOrder)
              DropdownMenuItem(
                value: method.code,
                child: Text(cashMethodLabel(method)),
              ),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _method = value);
          },
        ),
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _paid,
          label: 'المبلغ المقبوض ',
          fieldKey: const Key('lot-sale-paid'),
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        SwitchListTile(
          key: const Key('lot-sale-priced'),
          contentPadding: EdgeInsets.zero,
          title: const Text('تفصيل السعر'),
          value: _priced,
          onChanged: (value) => setState(() => _priced = value),
        ),
        if (_priced) ...[
          inventoryField(
            context: context,
            controller: _base,
            label: 'أساس السعر ',
            fieldKey: const Key('lot-sale-base'),
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
          inventoryField(
            context: context,
            controller: _work,
            label: 'المصنعية ',
            fieldKey: const Key('lot-sale-work'),
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
          inventoryField(
            context: context,
            controller: _other,
            label: 'رسوم أخرى ',
            fieldKey: const Key('lot-sale-other'),
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
          inventoryField(
            context: context,
            controller: _otherLabel,
            label: 'بيان الرسوم',
            fieldKey: const Key('lot-sale-other-label'),
          ),
          inventoryField(
            context: context,
            controller: _discount,
            label: 'الخصم ',
            fieldKey: const Key('lot-sale-discount'),
            keyboard: const TextInputType.numberWithOptions(decimal: true),
          ),
        ],
        const SizedBox(height: 12),
        inventoryField(
          context: context,
          controller: _description,
          label: 'وصف العملية',
          fieldKey: const Key('lot-sale-description'),
          maxLength: 300,
        ),
        inventoryField(
          context: context,
          controller: _customer,
          label: 'اسم العميل',
          fieldKey: const Key('lot-sale-customer'),
        ),
        inventoryField(
          context: context,
          controller: _phone,
          label: 'هاتف العميل',
          fieldKey: const Key('lot-sale-phone'),
          keyboard: TextInputType.phone,
        ),
        inventoryField(
          context: context,
          controller: _note,
          label: 'ملاحظة',
          fieldKey: const Key('lot-sale-note'),
          action: TextInputAction.done,
          maxLength: 1000,
        ),
      ],
      onReview: (day) {
        final selected = _selected;
        if (selected == null) {
          return const InventoryRejected(InventoryIssueCode.emptyCommand);
        }
        final total = readPounds(_total.text);
        final paid = readPounds(_paid.text);
        if (total == null || paid == null) {
          return const InventoryRejected(InventoryIssueCode.invalidInput);
        }
        return reviewExplicitLotSale(
          day: day,
          lot: selected,
          milligrams: readGrams(_grams.text) ?? BigInt.zero,
          count: selected.tracksCount ? readCount(_count.text) : null,
          totalPiastres: total,
          tenders: [TenderDraft(method: _method, piastres: paid)],
          description: _description.text,
          customerName: _customer.text,
          customerPhone: _phone.text,
          note: _note.text,
          pricing: _priced
              ? {
                  'base_piastres': (readPounds(_base.text) ?? BigInt.zero)
                      .toString(),
                  'workmanship_piastres':
                      (readPounds(_work.text) ?? BigInt.zero).toString(),
                  'other_charges_piastres':
                      (readPounds(_other.text) ?? BigInt.zero).toString(),
                  'other_charges_label': _otherLabel.text,
                  'discount_piastres':
                      (readPounds(_discount.text) ?? BigInt.zero).toString(),
                }
              : null,
        );
      },
    );
  }

  Future<void> _olderLots() async {
    final gateway = widget.scope.gateway;
    final cursor = _cursor;
    if (gateway == null || cursor == null) return;
    try {
      final page = await gateway.lots(
        callerUserId: widget.scope.userId,
        stockClass: StockClass.ownedAvailable.code,
        cursor: cursor,
      );
      if (!mounted) return;
      setState(() {
        _lots = [
          ..._lots,
          for (final lot in page.items)
            if (lot.stockClass == StockClass.ownedAvailable &&
                lot.remainingMilligrams > BigInt.zero &&
                _lots.every((item) => item.id != lot.id))
              lot,
        ];
        _cursor = page.nextCursor;
      });
    } on InventoryReadException {
      if (!mounted) return;
    }
  }
}
