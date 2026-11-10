import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../daily_ledger/application/daily_ledger_view.dart';
import '../../daily_ledger/application/financial_gateway.dart';
import '../../daily_ledger/application/opening_gateway.dart';
import '../../daily_ledger/application/pending_financial_command.dart';
import '../../daily_ledger/data/pending_financial_command.dart';
import '../../daily_ledger/domain/opening_catalog.dart';
import '../../daily_ledger/domain/opening_issue.dart';
import '../../daily_ledger/domain/quantities.dart';
import '../../daily_ledger/presentation/ledger_form_fields.dart';
import '../../daily_ledger/presentation/opening_copy.dart';
import '../../onboarding/application/onboarding_store.dart';
import '../../../theme/app_tokens.dart';
import '../application/inventory_command_flow.dart';
import '../application/inventory_contract.dart';
import '../application/inventory_gateway.dart';
import '../domain/inventory_models.dart';
import 'inventory_copy.dart';
import 'inventory_figures.dart';
import 'inventory_forms.dart';
import 'inventory_item_grid_view.dart';
import 'inventory_lots_table.dart';
import 'inventory_widgets.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.gateway,
    required this.statusGateway,
    required this.userId,
    required this.shopId,
    required this.shopName,
    required this.readOnly,
    this.dayGateway,
    this.onboardingStore,
    this.store = const PendingFinancialCommands(),
    this.refreshGeneration = 0,
    this.syncTicks,
  });

  final InventoryGateway gateway;
  final OpeningGateway statusGateway;
  final FinancialGateway? dayGateway;
  final String userId;
  final String shopId;
  final String shopName;
  final bool readOnly;
  final OnboardingStore? onboardingStore;
  final FinancialCommandLocker store;
  final int refreshGeneration;
  final Listenable? syncTicks;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _search = TextEditingController();
  final _catalogQuery = TextEditingController();
  final _searchFocus = FocusNode();
  final _totalsFocus = FocusNode();
  final _classFocus = FocusNode();
  final _addFocus = FocusNode();
  late final InventoryCommandFlow _flow = InventoryCommandFlow(
    gateway: widget.gateway,
    statusGateway: widget.statusGateway,
    store: widget.store,
  );
  int _generation = 0;
  bool _reloadInFlight = false;
  bool _reloadPending = false;
  bool _loading = true;
  bool _otherPending = false;
  bool _inventoryPending = false;
  String? _message;
  bool _messageError = false;
  DayAnchor? _day;
  InventoryTotals? _totals;
  final List<LotSnapshot> _lots = [];
  String? _nextCursor;
  List<ReceiptSnapshot> _deferred = const [];
  String? _deferredCursor;
  bool _deferredMissing = false;
  List<ReceiptSnapshot> _custody = const [];
  String? _custodyCursor;
  bool _custodyMissing = false;
  List<CatalogProduct> _products = const [];
  String? _productCursor;
  bool _productsMissing = false;
  List<CatalogDenomination> _denoms = const [];
  String? _denomCursor;
  bool _denomsMissing = false;
  List<CatalogCoin> _coins = const [];
  String? _coinCursor;
  bool _coinsMissing = false;
  List<GoldObligationView> _gold = const [];
  String? _goldCursor;
  bool _goldMissing = false;
  List<TraderSummary> _traders = const [];
  String? _traderCursor;
  Map<String, BigInt> _cash = const {};
  String? _category;
  int? _karat;
  String? _stockClass;
  InventoryItemGrid? _grid;
  bool _gridFailed = false;
  InventoryTotals? _allTotals;
  List<int> _karatOrder = List<int>.from(inventoryDefaultKaratOrder);
  bool _karatExpanded = false;
  final _lotsKey = GlobalKey();

  bool get _writesEnabled =>
      !widget.readOnly && _day != null && !_otherPending && !_inventoryPending;

  @override
  void initState() {
    super.initState();
    widget.syncTicks?.addListener(_onSync);
    unawaited(_loadKaratPreferences());
    _load();
  }

  String get _orderKey => 'inventory_karat_order_${widget.shopId}';
  String get _expandedKey => 'inventory_karat_expanded_${widget.shopId}';

  Future<void> _loadKaratPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final order = parseInventoryKaratOrder(prefs.getStringList(_orderKey));
      final expanded = prefs.getBool(_expandedKey) ?? false;
      if (!mounted) return;
      setState(() {
        _karatOrder = order;
        _karatExpanded = expanded;
      });
    } catch (_) {
      // A device preference failure keeps the default order.
    }
  }

  Future<void> _saveKaratPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_orderKey, [
        for (final karat in _karatOrder) '$karat',
      ]);
      await prefs.setBool(_expandedKey, _karatExpanded);
    } catch (_) {
      // Not saved on this device; the screen keeps the choice for now.
    }
  }

  Future<void> _chooseKaratOrder() async {
    final next = await showInventoryKaratOrder(context, _karatOrder);
    if (next == null || !mounted) return;
    setState(
      () => _karatOrder = parseInventoryKaratOrder([
        for (final karat in next) '$karat',
      ]),
    );
    unawaited(_saveKaratPreferences());
  }

  void _openGridCell(String itemName, int karat) {
    setState(() {
      _category = 'worked_jewelry';
      _karat = karat;
      _search.text = itemName;
    });
    unawaited(_loadAndShowLots());
  }

  Future<void> _loadAndShowLots() async {
    await _load();
    if (!mounted) return;
    final target = _lotsKey.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(target);
    }
  }

  BigInt? _cashPricePiastresPerGram;

  List<InventoryFigure>? get _figures {
    final totals = _allTotals;
    if (totals == null) return null;
    return inventoryFigures(
      [
        for (final bucket in totals.buckets)
          (
            category: bucket.category,
            karat: bucket.karat,
            milligrams: bucket.quantities.availableMilligrams,
            count: bucket.quantities.availableCount,
          ),
      ],
      _cash,
      cashPricePiastresPerGram: _cashPricePiastresPerGram,
    );
  }

  @override
  void didUpdateWidget(covariant InventoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncTicks != widget.syncTicks) {
      oldWidget.syncTicks?.removeListener(_onSync);
      widget.syncTicks?.addListener(_onSync);
    }
    if (oldWidget.userId != widget.userId ||
        oldWidget.shopId != widget.shopId ||
        (widget.syncTicks == null &&
            oldWidget.refreshGeneration != widget.refreshGeneration)) {
      _load();
    }
  }

  void _onSync() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    widget.syncTicks?.removeListener(_onSync);
    _search.dispose();
    _catalogQuery.dispose();
    _searchFocus.dispose();
    _totalsFocus.dispose();
    _classFocus.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  Future<DayAnchor?> _readDay() async {
    final gateway = widget.dayGateway;
    if (gateway == null) return null;
    final state = await gateway.dayState(callerUserId: widget.userId);
    final id = state.dayId;
    final version = state.dayVersion;
    if (!state.isOpen || id == null || version == null || version < 1) {
      return null;
    }
    final parsed = DayAnchor.tryCreate(id, '$version');
    return parsed is InventoryAccepted<DayAnchor> ? parsed.value : null;
  }

  bool _same(int generation, String userId, String shopId) =>
      mounted &&
      generation == _generation &&
      widget.userId == userId &&
      widget.shopId == shopId;

  Future<void> _load() async {
    if (_reloadInFlight) {
      _reloadPending = true;
      return;
    }
    _reloadInFlight = true;
    try {
      final generation = ++_generation;
      final userId = widget.userId;
      final shopId = widget.shopId;
      setState(() {
        _loading = true;
        _message = null;
      });
      DayAnchor? day;
      InventoryTotals? totals;
      LotPage? lots;
      ReceiptPage? deferred;
      ReceiptPage? custody;
      ReadPage<CatalogProduct>? products;
      ReadPage<CatalogDenomination>? denoms;
      ReadPage<CatalogCoin>? coins;
      ReadPage<GoldObligationView>? gold;
      TraderPage? traders;
      var cash = <String, BigInt>{};
      String? message;
      var otherPending = false;
      var inventoryPending = false;
      try {
        day = await _readDay();
      } catch (_) {
        message = 'تعذر قراءة يوم العمل. لم يُرسل أمر.';
      }
      try {
        final pending = await widget.store.read(userId, shopId);
        if (!_same(generation, userId, shopId)) return;
        if (pending != null &&
            ownsInventoryCommand(pending.key, pending.kind, pending.body)) {
          inventoryPending = true;
          final result = await _flow.reconcile(
            userId: userId,
            shopId: shopId,
            command: pending,
            retry: false,
          );
          if (result is InventorySaved) {
            inventoryPending = false;
            message = 'تم تأكيد العملية المعلّقة.';
          } else if (result is InventoryFailed) {
            inventoryPending = false;
            message = inventoryFailureCopy(result.code);
          } else if (result is InventoryUnconfirmed) {
            message = result.statusUnknown
                ? 'لم يتأكد الحفظ. الطلب محفوظ على الجهاز ولم يُحتسب في الأرصدة.'
                : 'لم نتأكد من حفظ العملية. أعد المحاولة دون تغيير البيانات أو بدء عملية جديدة.';
          }
        } else if (pending != null) {
          otherPending = true;
          message =
              'توجد عملية مالية معلّقة من الدفتر. أكملها من الدفتر قبل أي أمر مخزون.';
        }
      } catch (_) {
        message ??= inventoryFailureCopy('storage');
      }
      try {
        final query = _search.text.trim();
        final catalog = _catalogQuery.text.trim();
        totals = await widget.gateway.totals(
          callerUserId: userId,
          category: _category,
          karat: _karat,
        );
        if (!_same(generation, userId, shopId)) return;
        lots = await widget.gateway.lots(
          callerUserId: userId,
          category: _category,
          karat: _karat,
          stockClass: _stockClass,
          query: query.isEmpty ? null : query,
        );
        if (!_same(generation, userId, shopId)) return;
        deferred = await widget.gateway.receipts(
          callerUserId: userId,
          ownerKind: 'shop',
          recognition: 'deferred',
        );
        if (!_same(generation, userId, shopId)) return;
        custody = await widget.gateway.receipts(
          callerUserId: userId,
          ownerKind: 'trader',
          recognition: 'custody',
        );
        if (!_same(generation, userId, shopId)) return;
        products = await widget.gateway.products(
          callerUserId: userId,
          query: catalog.isEmpty ? null : catalog,
        );
        if (!_same(generation, userId, shopId)) return;
        denoms = await widget.gateway.denominations(
          callerUserId: userId,
          query: catalog.isEmpty ? null : catalog,
        );
        if (!_same(generation, userId, shopId)) return;
        coins = await widget.gateway.coins(
          callerUserId: userId,
          query: catalog.isEmpty ? null : catalog,
        );
        if (!_same(generation, userId, shopId)) return;
        gold = await widget.gateway.goldObligations(callerUserId: userId);
        if (!_same(generation, userId, shopId)) return;
        traders = await widget.gateway.traders(callerUserId: userId);
      } on InventoryReadException catch (error) {
        if (!_same(generation, userId, shopId)) return;
        if (error.code == 'discarded') {
          setState(() {
            _loading = false;
            _message = inventoryFailureCopy('discarded');
            _messageError = true;
          });
          return;
        }
        message ??= inventoryFailureCopy(error.code ?? 'unavailable');
      } catch (_) {
        if (!_same(generation, userId, shopId)) return;
        message ??= 'تعذر تحميل المخزون. الأرصدة المعروضة لم تتأكد.';
      }
      try {
        final view = await widget.statusGateway.ledger(callerUserId: userId);
        if (_same(generation, userId, shopId)) cash = _cashMap(view);
      } catch (_) {
        if (!_same(generation, userId, shopId)) return;
      }
      InventoryItemGrid? grid;
      var gridFailed = false;
      try {
        grid = await widget.gateway.itemGrid(callerUserId: userId);
      } catch (_) {
        gridFailed = true;
      }
      if (!_same(generation, userId, shopId)) return;
      InventoryTotals? allTotals = _category == null && _karat == null
          ? totals
          : null;
      if (allTotals == null) {
        try {
          allTotals = await widget.gateway.totals(callerUserId: userId);
        } catch (_) {
          allTotals = null;
        }
        if (!_same(generation, userId, shopId)) return;
      }
      if (!_same(generation, userId, shopId)) return;
      setState(() {
        _loading = false;
        _day = day;
        if (totals != null) _totals = totals;
        if (grid != null) _grid = grid;
        _gridFailed = gridFailed;
        if (allTotals != null) _allTotals = allTotals;
        if (lots != null) {
          _lots
            ..clear()
            ..addAll(lots.items);
          _nextCursor = lots.nextCursor;
        }
        if (deferred != null) {
          _deferredMissing = !deferred.available;
          _deferred = deferred.items ?? _deferred;
          _deferredCursor = deferred.available
              ? deferred.nextCursor
              : _deferredCursor;
        }
        if (custody != null) {
          _custodyMissing = !custody.available;
          _custody = custody.items ?? _custody;
          _custodyCursor = custody.available
              ? custody.nextCursor
              : _custodyCursor;
        }
        if (products != null) {
          _productsMissing = !products.available;
          _products = products.items ?? _products;
          _productCursor = products.available
              ? products.nextCursor
              : _productCursor;
        }
        if (denoms != null) {
          _denomsMissing = !denoms.available;
          _denoms = denoms.items ?? _denoms;
          _denomCursor = denoms.available ? denoms.nextCursor : _denomCursor;
        }
        if (coins != null) {
          _coinsMissing = !coins.available;
          _coins = coins.items ?? _coins;
          _coinCursor = coins.available ? coins.nextCursor : _coinCursor;
        }
        if (gold != null) {
          _goldMissing = !gold.available;
          _gold = gold.items ?? _gold;
          _goldCursor = gold.available ? gold.nextCursor : _goldCursor;
        }
        if (traders != null) {
          _traders = traders.items;
          _traderCursor = traders.nextCursor;
        }
        _cash = cash;
        _otherPending = otherPending;
        _inventoryPending = inventoryPending;
        _message = message ?? _closedCopy(day);
        _messageError = message != null || day == null;
      });
    } finally {
      _reloadInFlight = false;
      final reload = _reloadPending;
      _reloadPending = false;
      if (reload && mounted) unawaited(_load());
    }
  }

  String? _closedCopy(DayAnchor? day) {
    if (widget.readOnly) {
      return 'الاشتراك منتهٍ. المخزون للقراءة ولم يُرسل أمر.';
    }
    if (day == null && widget.dayGateway != null) {
      return 'اليوم مغلق. افتح اليوم من الدفتر قبل أي تعديل.';
    }
    if (day == null) return 'لا يوجد يوم عمل مفتوح.';
    return null;
  }

  Map<String, BigInt> _cashMap(DailyLedgerView view) {
    final map = <String, BigInt>{};
    for (final line in view.cash) {
      final parsed = Piastres.parseWire(line.piastres);
      if (parsed is Accepted<Piastres>) map[line.method] = parsed.value.value;
    }
    return map;
  }

  Future<DayAnchor?> _reloadDay() async {
    try {
      final day = await _readDay();
      if (mounted) setState(() => _day = day);
      return day;
    } catch (_) {
      return _day;
    }
  }

  InventoryFormScope get _scope => InventoryFormScope(
    flow: _flow,
    gateway: widget.gateway,
    userId: widget.userId,
    shopId: widget.shopId,
    readOnly: widget.readOnly || _otherPending,
    day: _day,
    reloadDay: _reloadDay,
    onConfirmed: _load,
  );

  Future<void> _open(Widget page) async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => page));
    if (saved == true) await _load();
  }

  Future<void> _retryPending() async {
    final pending = await widget.store.read(widget.userId, widget.shopId);
    if (pending == null ||
        !ownsInventoryCommand(pending.key, pending.kind, pending.body)) {
      return;
    }
    final result = await _flow.reconcile(
      userId: widget.userId,
      shopId: widget.shopId,
      command: pending,
      retry: true,
    );
    if (!mounted) return;
    if (result is InventorySaved) {
      setState(() {
        _inventoryPending = false;
        _message = result.replayed
            ? 'تم حفظ هذه العملية سابقًا، ولم تتكرر.'
            : 'تم حفظ العملية بنجاح.';
        _messageError = false;
      });
      await _load();
      return;
    }
    setState(() {
      _inventoryPending = result is InventoryUnconfirmed;
      _message = result is InventoryFailed
          ? inventoryFailureCopy(result.code)
          : result is InventoryUnconfirmed
          ? 'لم نتأكد من الحفظ بعد. العملية ما زالت معلّقة.'
          : inventoryFailureCopy('unavailable');
      _messageError = true;
    });
  }

  Future<void> _moreLots() async {
    final cursor = _nextCursor;
    if (cursor == null || _loading) return;
    final generation = _generation;
    final userId = widget.userId;
    final shopId = widget.shopId;
    try {
      final page = await widget.gateway.lots(
        callerUserId: userId,
        category: _category,
        karat: _karat,
        stockClass: _stockClass,
        query: _search.text.trim().isEmpty ? null : _search.text.trim(),
        cursor: cursor,
      );
      if (!_same(generation, userId, shopId)) return;
      setState(() {
        _lots.addAll(page.items);
        _nextCursor = page.nextCursor;
      });
    } on InventoryReadException catch (error) {
      if (!_same(generation, userId, shopId)) return;
      setState(() {
        _message = inventoryFailureCopy(error.code ?? 'unavailable');
        _messageError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = _totals == null ? null : _sum(_totals);
    return InventoryPage(
      title: 'الجرد الفوري',
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_productsMissing || _coinsMissing)
          const InventoryNotice(
            message:
                'تعذر تحميل بعض خيارات الكتالوج. حدّث الاتصال قبل اختيار هوية جديدة.',
            error: true,
          ),
        if (_message != null) ...[
          InventoryNotice(message: _message!, error: _messageError),
          const SizedBox(height: 12),
        ],
        if (_inventoryPending)
          OutlinedButton(
            key: const Key('inventory-retry'),
            onPressed: _retryPending,
            child: const Text('التحقق من العملية المعلّقة'),
          ),
        if (_figures != null) ...[
          InventoryFigureCarousel(
            figures: _figures!,
            onCashPrice: (price) =>
                setState(() => _cashPricePiastresPerGram = price),
          ),
          const SizedBox(height: 16),
        ],
        InventoryItemGridView(
          grid: _grid,
          order: _karatOrder,
          expanded: _karatExpanded,
          loading: _loading,
          failed: _gridFailed,
          onRetry: _load,
          onExpanded: (value) {
            setState(() => _karatExpanded = value);
            unawaited(_saveKaratPreferences());
          },
          onOrder: _chooseKaratOrder,
          onCell: _openGridCell,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('inventory-search'),
          controller: _search,
          focusNode: _searchFocus,
          maxLength: 120,
          textInputAction: TextInputAction.search,
          decoration: ledgerFieldDecoration(context, label: 'بحث في الدفعات')
              .copyWith(
                counterText: '',
                suffixIcon: IconButton(
                  key: const Key('inventory-search-go'),
                  tooltip: 'بحث',
                  onPressed: _load,
                  icon: const Icon(Icons.search),
                ),
              ),
          onSubmitted: (_) => _load(),
        ),
        const SizedBox(height: 16),
        _filterBlock(),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const Key('inventory-new-item'),
          onPressed: _writesEnabled
              ? () => _open(CatalogProductForm(scope: _scope))
              : null,
          icon: const Icon(Icons.add),
          label: const Text('صنف جديد'),
        ),
        const SizedBox(height: 16),
        Focus(
          focusNode: _totalsFocus,
          child: Column(
            key: const Key('inventory-totals'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (totals == null)
                const Text('لم تُحمّل أرصدة مؤكدة في هذه القراءة.')
              else ...[
                _cashCard(),
                const SizedBox(height: AppTokens.spaceSm),
                _quantityBoard(totals),
                if (_totals != null) ...[
                  const SizedBox(height: AppTokens.spaceSm),
                  _metricRowCard(
                    keyName: 'inventory-held-original',
                    label: 'وزنة التجار الأصلية',
                    value: '${gramsOf(_totals!.originalHeldMilligrams)} جرام',
                  ),
                  ..._karatBreakdown(_totals!),
                  if (_totals!.denominationRows.isNotEmpty) ...[
                    const SizedBox(height: AppTokens.spaceSm),
                    _sectionCard(
                      keyName: 'inventory-bullion-section',
                      title: 'السبائك',
                      children: [
                        for (final row in _totals!.denominationRows)
                          _factLine(
                            key: Key(
                              'inventory-bullion-${row.denominationId ?? 'none'}',
                            ),
                            title: row.label,
                            value:
                                '${gramsOf(row.milligrams)} جرام — ${row.count} قطعة'
                                '${row.nominalMilligrams > BigInt.zero ? ' — اسمي ${gramsOf(row.nominalMilligrams)}' : ''}',
                          ),
                      ],
                    ),
                  ],
                  if (_totals!.coinRows.isNotEmpty) ...[
                    const SizedBox(height: AppTokens.spaceSm),
                    _sectionCard(
                      keyName: 'inventory-coin-section',
                      title: 'الجنيهات',
                      children: [
                        for (final row in _totals!.coinRows)
                          _factLine(
                            key: Key(
                              'inventory-coin-${row.coinTypeId ?? 'none'}',
                            ),
                            title: row.label,
                            value:
                                '${gramsOf(row.milligrams)} جرام — ${row.count} قطعة'
                                '${row.nominalMilligrams == null ? '' : ' — اسمي ${gramsOf(row.nominalMilligrams!)}'}',
                          ),
                      ],
                    ),
                  ],
                ],
              ],
            ],
          ),
        ),
        if (_deferredMissing || _custodyMissing)
          const Text(
            'قائمة الاستلام غير متاحة في هذا الاتصال. الاعتراف والربط والنقل متوقفان.',
          ),
        if (_denomsMissing)
          const Text('كتالوج الفئات غير متاح. يمكن الحفظ دون وزن اسمي.'),
        const SizedBox(height: 8),
        Text(
          'الدفعات',
          key: _lotsKey,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (_lots.isEmpty && !_loading)
          Text(
            'لا توجد دفعات مطابقة.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          )
        else if (_lots.isNotEmpty)
          InventoryLotsTable(
            lots: _lots,
            onOpen: (lot) => _open(
              LotHistoryPage(
                gateway: widget.gateway,
                userId: widget.userId,
                lot: lot,
              ),
            ),
          ),
        if (_nextCursor != null) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _moreLots,
            child: const Text('المزيد من الدفعات'),
          ),
        ],
        const SizedBox(height: 20),
        Text('العمليات', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        _action('إضافة مخزون', const Key('inventory-add'), _addFocus, () {
          _open(
            InventoryAdditionForm(
              scope: _scope,
              denominations: _denoms,
              coins: _coins,
              products: _products,
              denominationCursor: _denomCursor,
              coinCursor: _coinCursor,
              productCursor: _productCursor,
            ),
          );
        }),
        _action('إزالة من المتاح', const Key('inventory-remove'), null, () {
          _open(InventoryRemovalForm(scope: _scope, lots: _lots));
        }, filled: false),
        _operationGroup(
          title: 'تعديل المخزون',
          children: [
            _action('تصحيح جرد', const Key('inventory-correct'), null, () {
              _open(
                InventoryCorrectionForm(
                  scope: _scope,
                  lots: _lots,
                  cashBalances: _cash,
                ),
              );
            }, filled: false),
            _action(
              'تحويل فئة مع بقاء العيار',
              const Key('inventory-convert'),
              null,
              () {
                _open(InventoryConversionForm(scope: _scope, lots: _lots));
              },
              filled: false,
            ),
            _action(
              'بيع دفعة محددة',
              const Key('inventory-lot-sale'),
              null,
              () {
                _open(
                  ExplicitLotSaleForm(
                    scope: _scope,
                    lots: _lots,
                    nextCursor: _nextCursor,
                  ),
                );
              },
              filled: false,
            ),
          ],
        ),
        _operationGroup(
          title: 'التجار والأمانات',
          children: [
            _action('استلام ذهب', const Key('inventory-receipt'), null, () {
              _open(
                InventoryReceiptForm(
                  scope: _scope,
                  traders: _traders,
                  denominations: _denoms,
                  coins: _coins,
                ),
              );
            }, filled: false),
            _action(
              'اعتراف بكمية معلقة',
              const Key('inventory-recognize'),
              null,
              () {
                _open(
                  InventoryRecognitionForm(
                    scope: _scope,
                    receipts: _deferred,
                    nextCursor: _deferredCursor,
                    loadOlder: (cursor) => widget.gateway.receipts(
                      callerUserId: widget.userId,
                      ownerKind: 'shop',
                      recognition: 'deferred',
                      cursor: cursor,
                    ),
                  ),
                );
              },
              enabled: _writesEnabled && !_deferredMissing,
              filled: false,
            ),
            if (_deferredCursor != null)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'الاعتراف يعرض صفحة الاستلامات المعلقة فقط. استخدم استلامات أقدم داخل النموذج.',
                ),
              ),
            _action(
              'ربط يدوي باستلام',
              const Key('inventory-link'),
              null,
              () {
                _open(
                  InventoryManualLinkForm(
                    scope: _scope,
                    receipts: _deferred,
                    lots: _lots,
                    nextCursor: _deferredCursor,
                    loadOlder: (cursor) => widget.gateway.receipts(
                      callerUserId: widget.userId,
                      ownerKind: 'shop',
                      recognition: 'deferred',
                      cursor: cursor,
                    ),
                  ),
                );
              },
              enabled: _writesEnabled && !_deferredMissing,
              filled: false,
            ),
            _action(
              'نقل ملكية الأمانة',
              const Key('inventory-transfer'),
              null,
              () {
                _open(
                  OwnershipTransferForm(
                    scope: _scope,
                    receipts: _custody,
                    nextCursor: _custodyCursor,
                    loadOlder: (cursor) => widget.gateway.receipts(
                      callerUserId: widget.userId,
                      ownerKind: 'trader',
                      recognition: 'custody',
                      cursor: cursor,
                    ),
                  ),
                );
              },
              enabled: _writesEnabled && !_custodyMissing,
              filled: false,
            ),
            _action(
              'شراء مقابل ذهب',
              const Key('inventory-gold-buy'),
              null,
              () {
                _open(
                  GoldAcquisitionForm(
                    scope: _scope,
                    traders: _traders,
                    traderCursor: _traderCursor,
                    loadTraders: (cursor) => widget.gateway.traders(
                      callerUserId: widget.userId,
                      cursor: cursor,
                    ),
                  ),
                );
              },
              filled: false,
            ),
            _action(
              'تسوية مستحق ذهبي',
              const Key('inventory-gold-settle'),
              null,
              () {
                _open(
                  GoldSettlementForm(
                    scope: _scope,
                    obligations: _gold,
                    lots: _lots,
                    nextCursor: _goldCursor,
                    loadOlder: (cursor) => widget.gateway.goldObligations(
                      callerUserId: widget.userId,
                      cursor: cursor,
                    ),
                  ),
                );
              },
              enabled: _writesEnabled && !_goldMissing,
              filled: false,
            ),
            if (_goldMissing)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('مستحقات الذهب غير متاحة في هذا الاتصال.'),
              ),
          ],
        ),
        _operationGroup(
          title: 'الكتالوج',
          children: [
            TextField(
              key: const Key('inventory-catalog-search'),
              controller: _catalogQuery,
              maxLength: 120,
              textInputAction: TextInputAction.search,
              decoration:
                  ledgerFieldDecoration(
                    context,
                    label: 'بحث في الكتالوج',
                  ).copyWith(
                    counterText: '',
                    suffixIcon: IconButton(
                      key: const Key('inventory-catalog-go'),
                      tooltip: 'بحث في الكتالوج',
                      onPressed: _loading ? null : _load,
                      icon: const Icon(Icons.search),
                    ),
                  ),
              onSubmitted: (_) => _load(),
            ),
            OlderPageControl(
              count: _products.length,
              noun: 'منتجات',
              nextCursor: _productCursor,
              onOlder: () => _moreCatalog(_MoreCatalog.products),
              controlKey: const Key('inventory-products-older'),
            ),
            OlderPageControl(
              count: _denoms.length,
              noun: 'فئات سبائك',
              nextCursor: _denomCursor,
              onOlder: () => _moreCatalog(_MoreCatalog.denominations),
              controlKey: const Key('inventory-denoms-older'),
            ),
            OlderPageControl(
              count: _coins.length,
              noun: 'عملات',
              nextCursor: _coinCursor,
              onOlder: () => _moreCatalog(_MoreCatalog.coins),
              controlKey: const Key('inventory-coins-older'),
            ),
            const SizedBox(height: 8),
            _action(
              'فئة سبيكة اسمية',
              const Key('inventory-denomination'),
              null,
              () {
                _open(DenominationForm(scope: _scope, coin: false));
              },
              filled: false,
            ),
            _action('نوع عملة', const Key('inventory-coin'), null, () {
              _open(DenominationForm(scope: _scope, coin: true));
            }, filled: false),
          ],
        ),
      ],
    );
  }

  Widget _filterBlock() {
    final karats = karatsFor(_category ?? 'scrap');
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('تصفية الدفعات', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppTokens.spaceSm),
        Text(
          'الفئة',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        _chipWrap(
          key: Key('inventory-category-${_category ?? 'all'}'),
          children: [
            _choiceChip(
              label: 'الكل',
              selected: _category == null,
              onSelected: () => _selectCategory(null),
            ),
            for (final category in const [
              'worked_jewelry',
              'bullion',
              'coin',
              'scrap',
            ])
              _choiceChip(
                label: inventoryCategoryLabel(category),
                selected: _category == category,
                onSelected: () => _selectCategory(category),
              ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceSm),
        Text(
          'العيار',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        _chipWrap(
          key: Key('inventory-karat-${_category ?? 'all'}-${_karat ?? 0}'),
          children: [
            _choiceChip(
              label: 'الكل',
              selected: _karat == null,
              onSelected: () => _selectKarat(null),
            ),
            for (final karat in karats)
              _choiceChip(
                label: '$karat',
                selected: _karat == karat,
                onSelected: () => _selectKarat(karat),
              ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceSm),
        Text(
          'الحيازة',
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        _chipWrap(
          key: const Key('inventory-class'),
          focusNode: _classFocus,
          children: [
            _choiceChip(
              label: 'الكل',
              selected: _stockClass == null,
              onSelected: () => _selectClass(null),
            ),
            _choiceChip(
              label: 'متاح',
              selected: _stockClass == StockClass.ownedAvailable.code,
              onSelected: () => _selectClass(StockClass.ownedAvailable.code),
            ),
            _choiceChip(
              label: 'معلق',
              selected: _stockClass == StockClass.ownedPending.code,
              onSelected: () => _selectClass(StockClass.ownedPending.code),
            ),
            _choiceChip(
              label: 'أمانة',
              selected: _stockClass == StockClass.traderCustody.code,
              onSelected: () => _selectClass(StockClass.traderCustody.code),
            ),
          ],
        ),
      ],
    );
  }

  void _selectCategory(String? value) {
    setState(() {
      _category = value;
      final allowed = value == null ? null : karatsFor(value);
      if (allowed != null && _karat != null && !allowed.contains(_karat)) {
        _karat = null;
      }
    });
    _load();
  }

  void _selectKarat(int? value) {
    setState(() => _karat = value);
    _load();
  }

  void _selectClass(String? value) {
    setState(() => _stockClass = value);
    _load();
  }

  Widget _chipWrap({
    required Key key,
    required List<Widget> children,
    FocusNode? focusNode,
  }) {
    final chips = Wrap(key: key, spacing: 8, runSpacing: 8, children: children);
    if (focusNode == null) return chips;
    return Focus(
      focusNode: focusNode,
      canRequestFocus: false,
      skipTraversal: true,
      child: chips,
    );
  }

  Widget _choiceChip({
    required String label,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Widget _operationGroup({
    required String title,
    required List<Widget> children,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          title: Text(title),
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppTokens.spaceMd,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppTokens.spaceMd,
            0,
            AppTokens.spaceMd,
            AppTokens.spaceMd,
          ),
          children: children,
        ),
      ),
    );
  }

  Future<void> _moreCatalog(_MoreCatalog kind) async {
    final userId = widget.userId;
    final generation = _generation;
    try {
      switch (kind) {
        case _MoreCatalog.products:
          final page = await widget.gateway.products(
            callerUserId: userId,
            query: _catalogQuery.text.trim().isEmpty
                ? null
                : _catalogQuery.text.trim(),
            cursor: _productCursor,
          );
          if (!_same(generation, userId, widget.shopId) || !page.available) {
            return;
          }
          setState(() {
            _products = [..._products, ...?page.items];
            _productCursor = page.nextCursor;
          });
        case _MoreCatalog.denominations:
          final page = await widget.gateway.denominations(
            callerUserId: userId,
            query: _catalogQuery.text.trim().isEmpty
                ? null
                : _catalogQuery.text.trim(),
            cursor: _denomCursor,
          );
          if (!_same(generation, userId, widget.shopId) || !page.available) {
            return;
          }
          setState(() {
            _denoms = [..._denoms, ...?page.items];
            _denomCursor = page.nextCursor;
          });
        case _MoreCatalog.coins:
          final page = await widget.gateway.coins(
            callerUserId: userId,
            query: _catalogQuery.text.trim().isEmpty
                ? null
                : _catalogQuery.text.trim(),
            cursor: _coinCursor,
          );
          if (!_same(generation, userId, widget.shopId) || !page.available) {
            return;
          }
          setState(() {
            _coins = [..._coins, ...?page.items];
            _coinCursor = page.nextCursor;
          });
      }
    } on InventoryReadException catch (error) {
      if (!_same(generation, userId, widget.shopId)) return;
      if (error.code == 'discarded') {
        setState(() {
          _message = inventoryFailureCopy('discarded');
          _messageError = true;
        });
      }
    }
  }

  Widget _action(
    String label,
    Key key,
    FocusNode? focusNode,
    VoidCallback onPressed, {
    bool? enabled,
    bool filled = true,
  }) {
    final callback = (enabled ?? _writesEnabled) ? onPressed : null;
    final child = Text(label);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: filled
          ? FilledButton(
              key: key,
              focusNode: focusNode,
              onPressed: callback,
              child: child,
            )
          : OutlinedButton(
              key: key,
              focusNode: focusNode,
              onPressed: callback,
              child: child,
            ),
    );
  }

  Widget _cashCard() {
    final theme = Theme.of(context);
    final methods = CashMethod.canonicalOrder;
    return Card(
      key: const Key('inventory-cash'),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('النقدية المتاحة', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppTokens.spaceMd),
            for (var row = 0; row < methods.length; row += 2) ...[
              if (row > 0) const SizedBox(height: AppTokens.spaceMd),
              Row(
                children: [
                  Expanded(child: _cashCell(methods[row])),
                  const SizedBox(width: AppTokens.spaceMd),
                  Expanded(
                    child: row + 1 < methods.length
                        ? _cashCell(methods[row + 1])
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cashCell(CashMethod method) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          cashMethodLabel(method),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          poundsOf(_cash[method.code] ?? BigInt.zero),
          key: Key('inventory-cash-${method.code}'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _quantityBoard(QuantityTriple totals) {
    final theme = Theme.of(context);
    final rows = [
      (
        'inventory-available',
        'المتاح للبيع',
        totals.availableMilligrams,
        totals.availableCount,
      ),
      (
        'inventory-pending',
        'بانتظار الاعتراف',
        totals.pendingMilligrams,
        totals.pendingCount,
      ),
      (
        'inventory-held',
        'أمانة التجار الحالية',
        totals.heldMilligrams,
        totals.heldCount,
      ),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('أرصدة الذهب', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppTokens.spaceSm),
            for (var index = 0; index < rows.length; index++) ...[
              if (index > 0) ...[
                const SizedBox(height: AppTokens.spaceSm),
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceSm),
              ],
              _goldMetricRow(
                keyName: rows[index].$1,
                label: rows[index].$2,
                milligrams: rows[index].$3,
                count: rows[index].$4,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _goldMetricRow({
    required String keyName,
    required String label,
    required BigInt milligrams,
    required BigInt? count,
  }) {
    final theme = Theme.of(context);
    return KeyedSubtree(
      key: Key(keyName),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
            ),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${gramsOf(milligrams)} جرام',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (count != null)
                Text(
                  '$count قطعة',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricRowCard({
    required String keyName,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Card(
      key: Key(keyName),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Row(
          children: [
            Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
            const SizedBox(width: AppTokens.spaceSm),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _factLine({
    required Key key,
    required String title,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Padding(
      key: key,
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
            ),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String keyName,
    required String title,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    return Card(
      key: Key(keyName),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            for (var index = 0; index < children.length; index++) ...[
              if (index > 0)
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.7,
                  ),
                ),
              children[index],
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _karatBreakdown(InventoryTotals totals) {
    final jewelry = [
      for (final bucket in totals.buckets)
        if (bucket.category == 'worked_jewelry' &&
            bucket.quantities.availableMilligrams > BigInt.zero)
          bucket,
    ];
    final scrap = [
      for (final bucket in totals.buckets)
        if (bucket.category == 'scrap' &&
            (bucket.quantities.availableMilligrams > BigInt.zero ||
                bucket.quantities.heldMilligrams > BigInt.zero))
          bucket,
    ];
    if (jewelry.isEmpty && scrap.isEmpty) return const [];
    return [
      if (jewelry.isNotEmpty) ...[
        const SizedBox(height: AppTokens.spaceSm),
        _sectionCard(
          keyName: 'inventory-jewelry-section',
          title: 'الأصناف حسب العيار — تفصيل',
          children: [
            for (final bucket in jewelry)
              _factLine(
                key: Key('inventory-jewelry-${bucket.karat}'),
                title: 'عيار ${bucket.karat}',
                value:
                    '${gramsOf(bucket.quantities.availableMilligrams)} جرام'
                    '${bucket.quantities.availableCount == null ? '' : ' — ${bucket.quantities.availableCount} قطعة'}',
              ),
          ],
        ),
      ],
      if (scrap.isNotEmpty) ...[
        const SizedBox(height: AppTokens.spaceSm),
        _sectionCard(
          keyName: 'inventory-scrap-section',
          title: 'الكسر',
          children: [
            for (final bucket in scrap)
              _factLine(
                key: Key('inventory-scrap-${bucket.karat}'),
                title: 'كسر عيار ${bucket.karat}',
                value:
                    'متاح ${gramsOf(bucket.quantities.availableMilligrams)} جرام'
                    '${bucket.quantities.heldMilligrams > BigInt.zero ? ' — أمانة ${gramsOf(bucket.quantities.heldMilligrams)}' : ''}',
              ),
          ],
        ),
      ],
    ];
  }
}

QuantityTriple _sum(InventoryTotals? totals) {
  var available = BigInt.zero;
  var pending = BigInt.zero;
  var held = BigInt.zero;
  BigInt? availableCount;
  BigInt? pendingCount;
  BigInt? heldCount;
  for (final bucket in totals?.buckets ?? const <InventoryBucket>[]) {
    final row = bucket.quantities;
    available += row.availableMilligrams;
    pending += row.pendingMilligrams;
    held += row.heldMilligrams;
    availableCount = _addCount(availableCount, row.availableCount);
    pendingCount = _addCount(pendingCount, row.pendingCount);
    heldCount = _addCount(heldCount, row.heldCount);
  }
  return QuantityTriple(
    availableMilligrams: available,
    pendingMilligrams: pending,
    heldMilligrams: held,
    availableCount: availableCount,
    pendingCount: pendingCount,
    heldCount: heldCount,
  );
}

enum _MoreCatalog { products, denominations, coins }

BigInt? _addCount(BigInt? total, BigInt? next) {
  if (next == null) return total;
  return (total ?? BigInt.zero) + next;
}

class LotHistoryPage extends StatefulWidget {
  const LotHistoryPage({
    super.key,
    required this.gateway,
    required this.userId,
    required this.lot,
  });

  final InventoryGateway gateway;
  final String userId;
  final LotSnapshot lot;

  @override
  State<LotHistoryPage> createState() => _LotHistoryPageState();
}

class _LotHistoryPageState extends State<LotHistoryPage> {
  List<MovementLine> _items = const [];
  String? _message;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final page = await widget.gateway.movements(
        callerUserId: widget.userId,
        lotId: widget.lot.id,
      );
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _loading = false;
        _message = page.items.isEmpty
            ? 'لا توجد حركة مسجلة لهذه الدفعة.'
            : null;
      });
    } on InventoryReadException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = inventoryFailureCopy(error.code ?? 'unavailable');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lot = widget.lot;
    return InventoryPage(
      title: 'حركة الدفعة',
      children: [
        Text(lot.displayName, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '${stockClassLabel(lot.stockClass)} — المتبقي ${gramsOf(lot.remainingMilligrams)} جرام'
          '${lot.remainingCount == null ? '' : ' و${lot.remainingCount} قطعة'}',
        ),
        if (lotIdentityCopy(lot).isNotEmpty) Text(lotIdentityCopy(lot)),
        const SizedBox(height: 12),
        if (_loading) const LinearProgressIndicator(),
        if (_message != null)
          InventoryNotice(message: _message!, error: _items.isEmpty),
        for (final line in _items)
          ListTile(
            key: Key('movement-${line.id}'),
            title: Text('${line.movementKind} — ${line.allocationMode}'),
            subtitle: Text(
              '${gramsOf(line.deltaMilligrams)} جرام'
              '${line.deltaCount == BigInt.zero ? '' : ' — العدد ${line.deltaCount}'}'
              '\n${line.createdAt}',
            ),
          ),
      ],
    );
  }
}
