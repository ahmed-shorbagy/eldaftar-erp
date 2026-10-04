import 'package:flutter/material.dart';

import '../../daily_ledger/application/daily_ledger_view.dart';
import '../../daily_ledger/application/financial_gateway.dart';
import '../../daily_ledger/application/opening_gateway.dart';
import '../../daily_ledger/application/pending_financial_command.dart';
import '../../daily_ledger/data/pending_financial_command.dart';
import '../../daily_ledger/domain/opening_catalog.dart';
import '../../daily_ledger/domain/opening_issue.dart';
import '../../daily_ledger/domain/quantities.dart';
import '../../daily_ledger/presentation/ledger_form_fields.dart';
import '../../onboarding/application/onboarding_store.dart';
import '../application/inventory_command_flow.dart';
import '../application/inventory_contract.dart';
import '../application/inventory_gateway.dart';
import '../domain/inventory_models.dart';
import 'inventory_copy.dart';
import 'inventory_forms.dart';
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
  int _guideStep = 0;
  bool _guideVisible = false;
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

  String get _guidePath => 'inventory-help_${widget.userId}_${widget.shopId}';

  bool get _writesEnabled =>
      !widget.readOnly && _day != null && !_otherPending && !_inventoryPending;

  @override
  void initState() {
    super.initState();
    _loadGuide();
    _load();
  }

  @override
  void didUpdateWidget(covariant InventoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.shopId != widget.shopId) {
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _catalogQuery.dispose();
    _searchFocus.dispose();
    _totalsFocus.dispose();
    _classFocus.dispose();
    _addFocus.dispose();
    super.dispose();
  }

  Future<void> _loadGuide() async {
    final store = widget.onboardingStore;
    if (store == null) return;
    final done = await store.isComplete(_guidePath);
    final step = await store.readStep(_guidePath);
    if (!mounted) return;
    setState(() {
      _guideStep = step.clamp(0, inventoryGuideSteps.length - 1);
      _guideVisible = !done;
    });
  }

  void _guideAction() {
    final focus = switch (_guideStep) {
      0 => _searchFocus,
      1 => _totalsFocus,
      2 => _classFocus,
      _ => _addFocus,
    };
    focus.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = focus.context;
      if (mounted && target != null) {
        Scrollable.ensureVisible(target, alignment: .2);
      }
    });
    if (_guideStep >= inventoryGuideSteps.length - 1) {
      setState(() => _guideVisible = false);
      widget.onboardingStore?.markComplete(_guidePath);
      return;
    }
    setState(() => _guideStep++);
    widget.onboardingStore?.saveStep(_guidePath, _guideStep);
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
          message = 'الخادم أكد أمراً كان معلقاً. حدّث القائمة لرؤية الأرصدة.';
        } else if (result is InventoryFailed) {
          inventoryPending = false;
          message = inventoryFailureCopy(result.code);
        } else if (result is InventoryUnconfirmed) {
          message = result.statusUnknown
              ? 'لم يتأكد الحفظ. الطلب محفوظ على الجهاز ولم يُحتسب في الأرصدة.'
              : 'لم يظهر الطلب على الخادم. أعد المحاولة بالمفتاح نفسه دون إنشاء أمر جديد.';
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
    if (!_same(generation, userId, shopId)) return;
    setState(() {
      _loading = false;
      _day = day;
      if (totals != null) _totals = totals;
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
            ? 'الخادم أعاد نتيجة الأمر المحفوظ نفسه. لم يُكرر الأثر.'
            : 'حفظ الخادم الأمر. هذا التأكيد من رد الخادم.';
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
          ? 'لم يُحفظ بعد. الطلب معلّق حتى يؤكد الخادم.'
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
      title: 'المخزون',
      actions: [
        IconButton(
          tooltip: 'تحديث المخزون',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
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
            child: const Text('التحقق من الأمر المعلق بالمفتاح نفسه'),
          ),
        if (_guideVisible) ...[
          InventoryGuide(
            steps: inventoryGuideSteps,
            step: _guideStep,
            onAction: _guideAction,
            onSkip: () {
              setState(() => _guideVisible = false);
              widget.onboardingStore?.saveStep(_guidePath, _guideStep);
            },
          ),
          const SizedBox(height: 12),
        ] else if (widget.onboardingStore != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('inventory-guide-resume'),
              onPressed: () => setState(() => _guideVisible = true),
              child: const Text('استئناف الإرشاد'),
            ),
          ),
        TextField(
          key: const Key('inventory-search'),
          controller: _search,
          focusNode: _searchFocus,
          maxLength: 120,
          textInputAction: TextInputAction.search,
          decoration: ledgerFieldDecoration(context, label: 'بحث في الدفعات'),
          onSubmitted: (_) => _load(),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('inventory-search-go'),
          onPressed: _load,
          child: const Text('بحث'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          key: Key('inventory-category-${_category ?? 'all'}'),
          initialValue: _category,
          isExpanded: true,
          focusNode: null,
          decoration: ledgerFieldDecoration(context, label: 'الفئة'),
          items: [
            const DropdownMenuItem(value: null, child: Text('كل الفئات')),
            for (final category in const [
              'worked_jewelry',
              'bullion',
              'coin',
              'scrap',
            ])
              DropdownMenuItem(
                value: category,
                child: Text(inventoryCategoryLabel(category)),
              ),
          ],
          onChanged: (value) {
            setState(() {
              _category = value;
              final allowed = value == null ? null : karatsFor(value);
              if (allowed != null &&
                  _karat != null &&
                  !allowed.contains(_karat)) {
                _karat = null;
              }
            });
            _load();
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<int?>(
          key: Key('inventory-karat-${_category ?? 'all'}-${_karat ?? 0}'),
          initialValue: _karat,
          isExpanded: true,
          decoration: ledgerFieldDecoration(context, label: 'العيار'),
          items: [
            const DropdownMenuItem(value: null, child: Text('كل العيارات')),
            for (final karat
                in _category == null
                    ? ScrapKarats.allowed
                    : karatsFor(_category!))
              DropdownMenuItem(value: karat, child: Text('$karat')),
          ],
          onChanged: (value) {
            setState(() => _karat = value);
            _load();
          },
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String?>(
          key: const Key('inventory-class'),
          initialValue: _stockClass,
          isExpanded: true,
          focusNode: _classFocus,
          decoration: ledgerFieldDecoration(context, label: 'الحيازة'),
          items: [
            const DropdownMenuItem(value: null, child: Text('كل الحيازات')),
            for (final value in StockClass.values)
              DropdownMenuItem(
                value: value.code,
                child: Text(stockClassLabel(value)),
              ),
          ],
          onChanged: (value) {
            setState(() => _stockClass = value);
            _load();
          },
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
                _bucketCard(
                  'inventory-available',
                  'المتاح للبيع',
                  totals.availableMilligrams,
                  totals.availableCount,
                ),
                _bucketCard(
                  'inventory-pending',
                  'مملوك بانتظار الاعتراف',
                  totals.pendingMilligrams,
                  totals.pendingCount,
                ),
                _bucketCard(
                  'inventory-held',
                  'أمانة تاجر',
                  totals.heldMilligrams,
                  totals.heldCount,
                ),
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
        for (final lot in _lots)
          Card(
            child: ListTile(
              key: Key('lot-row-${lot.id}'),
              minVerticalPadding: 12,
              title: Text(
                '${lot.legacyAggregate ? 'رصيد سابق مجمّع — ' : ''}${lot.displayName}',
              ),
              subtitle: Text(
                '${inventoryCategoryLabel(lot.category)} عيار ${lot.karat}\n'
                '${stockClassLabel(lot.stockClass)}: ${gramsOf(lot.remainingMilligrams)} جرام'
                '${lot.remainingCount == null ? '' : ' — ${lot.remainingCount} قطعة'}'
                '${lotIdentityCopy(lot).isEmpty ? '' : '\n${lotIdentityCopy(lot)}'}',
              ),
              onTap: () => _open(
                LotHistoryPage(
                  gateway: widget.gateway,
                  userId: widget.userId,
                  lot: lot,
                ),
              ),
            ),
          ),
        if (_nextCursor != null)
          OutlinedButton(
            onPressed: _moreLots,
            child: const Text('المزيد من الدفعات'),
          ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('inventory-catalog-search'),
          controller: _catalogQuery,
          maxLength: 120,
          decoration: ledgerFieldDecoration(context, label: 'بحث في الكتالوج'),
          onSubmitted: (_) => _load(),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('inventory-catalog-go'),
          onPressed: _loading ? null : _load,
          child: const Text('بحث في الكتالوج'),
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
        }),
        _action('تصحيح جرد', const Key('inventory-correct'), null, () {
          _open(
            InventoryCorrectionForm(
              scope: _scope,
              lots: _lots,
              cashBalances: _cash,
            ),
          );
        }),
        _action(
          'تحويل فئة مع بقاء العيار',
          const Key('inventory-convert'),
          null,
          () {
            _open(InventoryConversionForm(scope: _scope, lots: _lots));
          },
        ),
        _action('بيع دفعة محددة', const Key('inventory-lot-sale'), null, () {
          _open(
            ExplicitLotSaleForm(
              scope: _scope,
              lots: _lots,
              nextCursor: _nextCursor,
            ),
          );
        }),
        _action('استلام ذهب', const Key('inventory-receipt'), null, () {
          _open(
            InventoryReceiptForm(
              scope: _scope,
              traders: _traders,
              denominations: _denoms,
              coins: _coins,
            ),
          );
        }),
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
        ),
        if (_deferredCursor != null)
          const Text(
            'الاعتراف يعرض صفحة الاستلامات المعلقة فقط. استخدم استلامات أقدم داخل النموذج.',
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
        ),
        _action('شراء مقابل ذهب', const Key('inventory-gold-buy'), null, () {
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
        }),
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
        ),
        if (_goldMissing) const Text('مستحقات الذهب غير متاحة في هذا الاتصال.'),
        _action('منتج في الكتالوج', const Key('inventory-product'), null, () {
          _open(CatalogProductForm(scope: _scope));
        }),
        _action(
          'فئة سبيكة اسمية',
          const Key('inventory-denomination'),
          null,
          () {
            _open(DenominationForm(scope: _scope, coin: false));
          },
        ),
        _action('نوع عملة', const Key('inventory-coin'), null, () {
          _open(DenominationForm(scope: _scope, coin: true));
        }),
      ],
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
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FilledButton(
        key: key,
        focusNode: focusNode,
        onPressed: (enabled ?? _writesEnabled) ? onPressed : null,
        child: Text(label),
      ),
    );
  }

  Widget _bucketCard(
    String keyName,
    String label,
    BigInt milligrams,
    BigInt? count,
  ) {
    return Card(
      key: Key(keyName),
      child: ListTile(
        title: Text(label),
        subtitle: Text(
          '${gramsOf(milligrams)} جرام${count == null ? '' : ' — $count قطعة'}',
        ),
      ),
    );
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
