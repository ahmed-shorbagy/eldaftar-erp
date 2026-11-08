import '../../../theme/cash_input.dart';
import 'package:flutter/material.dart';
import '../../../theme/gram_input.dart';

import '../application/financial_gateway.dart';
import '../application/idempotency_key.dart';
import '../application/opening_gateway.dart';
import '../application/pending_financial_command.dart';
import '../data/pending_financial_command.dart';
import '../domain/opening_catalog.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';
import '../domain/closing_count_observation.dart';
import '../domain/closing_item_grid.dart';
import '../../inventory/application/inventory_gateway.dart';
import 'closing_item_grid_view.dart';
import 'ledger_form_fields.dart';
import 'opening_copy.dart';
import 'ledger_correction_screen.dart';
import 'trade_item_picker.dart';

class DailyCloseScreen extends StatefulWidget {
  const DailyCloseScreen({
    super.key,
    required this.gateway,
    required this.statusGateway,
    required this.userId,
    required this.shopId,
    required this.day,
  });

  final FinancialGateway gateway;
  final OpeningGateway statusGateway;
  final String userId;
  final String shopId;
  final FinancialDayState day;

  @override
  State<DailyCloseScreen> createState() => _DailyCloseScreenState();
}

class _DailyCloseScreenState extends State<DailyCloseScreen> {
  final _cash = <String, TextEditingController>{};
  final _stock = <String, List<TextEditingController>>{};
  final _scrap = <int, TextEditingController>{};
  ClosingItemGrid _grid = const ClosingItemGrid(jewelryKarats: [], rows: []);
  final _cellCounts = <String, TextEditingController>{};
  final _cellGrams = <String, TextEditingController>{};
  final _extraNames = <({String name, String category, int karat})>[];
  bool _showWeights = false;
  List<CatalogProduct> _products = const [];
  bool get _namedCounts => widget.gateway is ClosingObservationGateway;
  Map<String, Object?>? _review;
  Map<String, Object?>? _discrepancy;
  String? _error;
  String? _key;
  bool _busy = false;
  bool _unknown = false;
  final _pending = const PendingFinancialCommands();

  @override
  void initState() {
    super.initState();
    final counts = widget.day.counts!;
    final cash = counts['cash'] as Map;
    for (final method in cash.keys) {
      _cash[method as String] = TextEditingController();
    }
    for (final row in counts['stock'] as List) {
      final item = row as Map;
      _stock['${item['category']}:${item['karat']}'] = [
        TextEditingController(),
        TextEditingController(),
      ];
    }
    if (_namedCounts) _rebuildGrid();
    for (final row in counts['scrap'] as List) {
      _scrap[(row as Map)['karat'] as int] = TextEditingController();
    }
    if (_namedCounts) _loadNames();
  }

  Future<void> _loadNames() async {
    final gateway = widget.gateway;
    if (gateway is! InventoryGateway) return;
    try {
      final page = await (gateway as InventoryGateway).products(
        callerUserId: widget.userId,
      );
      if (mounted && page.available) {
        setState(() {
          _products = page.items!;
          _rebuildGrid();
        });
      }
    } catch (_) {
      /* Built-in names remain available; no financial read is invented. */
    }
  }

  @override
  void dispose() {
    for (final field in _cellCounts.values) {
      field.dispose();
    }
    for (final field in _cellGrams.values) {
      field.dispose();
    }
    for (final field in _cash.values) {
      field.dispose();
    }
    for (final fields in _stock.values) {
      for (final field in fields) {
        field.dispose();
      }
    }
    for (final field in _scrap.values) {
      field.dispose();
    }
    super.dispose();
  }

  void _checkCounts() {
    final expected = widget.day.counts!;
    final expectedCash = expected['cash'] as Map;
    final cash = <String, String>{};
    for (final entry in expectedCash.entries) {
      final parsed = Piastres.parsePounds(
        cashInputValue(_cash[entry.key]!.text),
      );
      if (parsed is! Accepted<Piastres>) {
        setState(() => _error = 'أدخل النقد الفعلي لكل وسيلة .');
        return;
      }
      cash[entry.key as String] = parsed.value.wire;
    }
    final stock = <Map<String, Object?>>[];
    if (_namedCounts) {
      final cells = <(String, int), (String, String)>{};
      for (final row in _grid.rows) {
        for (final karat in row.karats) {
          final key = ClosingItemGridView.cellKey(row.name, karat);
          // ASCII digits and no trailing point; an unreadable entry stays as
          // typed so the domain reports it instead of silently dropping it.
          String normalized(String text, int places) =>
              canonicalNumericEntry(text, decimalPlaces: places) ?? text;
          cells[(row.name, karat)] = (
            normalized(_cellCounts[key]?.text ?? '', 0),
            _showWeights ? normalized(_cellGrams[key]?.text ?? '', 3) : '',
          );
        }
      }
      final draft = _grid.toObservations(cells);
      if (draft is ClosingGridRejected) {
        setState(
          () => _error = draft.issue == ClosingGridIssue.weightWithoutCount
              ? 'اكتب العدد قبل الوزن.'
              : 'أدخل عدداً صحيحاً لكل خانة.',
        );
        return;
      }
      stock.addAll((draft as ClosingGridReady).stock);
    } else {
      for (final row in expected['stock'] as List) {
        final item = row as Map;
        final fields = _stock['${item['category']}:${item['karat']}']!;
        final gramsText = canonicalNumericEntry(
          fields[0].text,
          decimalPlaces: 3,
        );
        final countText = canonicalNumericEntry(
          fields[1].text,
          decimalPlaces: 0,
        );
        final grams = gramsText == null || gramsText.isEmpty
            ? null
            : Milligrams.parseGrams(gramsText);
        final count = countText == null || countText.isEmpty
            ? null
            : PieceCount.parseWire(countText);
        if (grams is! Accepted<Milligrams> || count is! Accepted<PieceCount>) {
          setState(() => _error = 'أدخل الوزن والعدد الفعليين لكل صنف.');
          return;
        }
        stock.add({
          'category': item['category'],
          'karat': item['karat'],
          'milligrams': grams.value.wire,
          'count': count.value.wire,
        });
      }
    }
    final scrap = <Map<String, Object?>>[];
    for (final row in expected['scrap'] as List) {
      final item = row as Map;
      final scrapText = canonicalNumericEntry(
        _scrap[item['karat']]!.text,
        decimalPlaces: 3,
      );
      final grams = scrapText == null || scrapText.isEmpty
          ? null
          : Milligrams.parseGrams(scrapText);
      if (grams is! Accepted<Milligrams>) {
        setState(() => _error = 'أدخل وزن الكسر الفعلي لكل عيار.');
        return;
      }
      scrap.add({'karat': item['karat'], 'milligrams': grams.value.wire});
    }
    final counted = <String, Object?>{
      if (_namedCounts) 'version': 2,
      'cash': cash,
      'stock': stock,
      'scrap': scrap,
    };
    if (!(_namedCounts
        ? closingObservationsMatch(counted, expected)
        : _sameCounts(counted, expected))) {
      setState(() {
        _review = null;
        _discrepancy = _namedCounts ? null : counted;
        _error =
            'يوجد فرق بين العد الفعلي والأرصدة المسجلة. صحح الفرق أو اطلب تسوية مدققة قبل التقفيل.';
      });
      return;
    }
    setState(() {
      _review = counted;
      _error = null;
    });
  }

  void _rebuildGrid() {
    final stock = [
      for (final row in widget.day.counts!['stock'] as List)
        Map<String, Object?>.from(row as Map),
    ];
    _grid = ClosingItemGrid.build(
      bookStock: stock,
      shopNames: [
        for (final product in _products)
          (
            name: product.name,
            category: product.category,
            karat: product.karat,
          ),
        ..._extraNames,
      ],
    );
    for (final row in _grid.rows) {
      for (final karat in row.karats) {
        final key = ClosingItemGridView.cellKey(row.name, karat);
        _cellCounts.putIfAbsent(key, TextEditingController.new);
        _cellGrams.putIfAbsent(key, TextEditingController.new);
      }
    }
  }

  Future<void> _addClosingItem() async {
    if (_grid.jewelryKarats.isEmpty) return;
    final choice = await showTradeItemPicker(
      context,
      title: 'إضافة صنف',
      mainChoices: const [],
      others: ValueNotifier(
        TradeOtherCatalog(
          choices: [
            for (final name in tradeOtherJewelryNames)
              TradeItemChoice(name, 'worked_jewelry'),
            for (final product in _products)
              if (product.category == 'worked_jewelry')
                TradeItemChoice(product.name, product.category),
          ],
        ),
      ),
      reservedNames: {for (final row in _grid.rows) row.name},
    );
    if (!mounted || choice == null) return;
    if (_grid.rows.any((row) => row.name == choice.label)) return;
    setState(() {
      _extraNames.add((
        name: choice.label,
        category: 'worked_jewelry',
        karat: _grid.jewelryKarats.first,
      ));
      _rebuildGrid();
    });
  }

  Future<void> _correct() async {
    if (_busy ||
        _unknown ||
        _key != null ||
        _discrepancy == null ||
        widget.gateway is! LedgerCorrectionGateway) {
      return;
    }
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LedgerCorrectionScreen(
          gateway: widget.gateway as LedgerCorrectionGateway,
          statusGateway: widget.statusGateway,
          dayGateway: widget.gateway,
          userId: widget.userId,
          shopId: widget.shopId,
          book: widget.day.counts!,
          counted: _discrepancy!,
        ),
      ),
    );
    // Returning closes this stale count. Opening close-day again obtains a fresh
    // version and blank physical-count fields; a correction never closes the day.
    if (mounted && saved == true) Navigator.pop(context, true);
  }

  bool _sameCounts(
    Map<String, Object?> counted,
    Map<String, Object?> expected,
  ) {
    final cash = counted['cash'] as Map;
    final expectedCash = expected['cash'] as Map;
    for (final key in cash.keys) {
      if (cash[key] != expectedCash[key]) return false;
    }
    for (final section in ['stock', 'scrap']) {
      final actualRows = counted[section] as List;
      final expectedRows = expected[section] as List;
      if (actualRows.length != expectedRows.length) return false;
      for (var index = 0; index < actualRows.length; index++) {
        final actual = actualRows[index] as Map;
        final wanted = expectedRows[index] as Map;
        for (final key in wanted.keys) {
          if (actual[key] != wanted[key]) return false;
        }
      }
    }
    return true;
  }

  Future<void> _submit() async {
    if (_busy || _review == null) return;
    setState(() {
      _busy = true;
      _key ??= newIdempotencyKey();
    });
    try {
      await _pending.save(
        widget.userId,
        widget.shopId,
        PendingFinancialCommand(
          key: _key!,
          kind: 'close_day',
          body: {
            'p_idempotency_key': _key!,
            'p_day_id': widget.day.dayId,
            'p_expected_version': widget.day.dayVersion,
            'p_counts': _review!,
          },
        ),
      );
      final result = await widget.gateway.closeDay(
        callerUserId: widget.userId,
        idempotencyKey: _key!,
        expected: widget.day,
        counted: _review!,
      );
      if (!mounted) return;
      if (result is FinancialCommitted) {
        await _pending.clear(widget.userId, widget.shopId, _key!);
        if (!mounted) return;
        Navigator.pop(context, true);
      } else if (result is FinancialCountMismatch) {
        await _pending.clear(widget.userId, widget.shopId, _key!);
        if (!mounted) return;
        setState(() {
          _review = null;
          _error = 'تغيّر الرصيد المسجل. حدّث الدفتر ثم أعد العد قبل التقفيل.';
          _key = null;
        });
      } else if (result is FinancialRejected) {
        await _pending.clear(widget.userId, widget.shopId, _key!);
        if (!mounted) return;
        setState(() {
          _error = result.code == 'stale_day'
              ? 'تغير يوم العمل. حدّث الدفتر ثم أعد العد.'
              : 'تعذر تقفيل اليومية. تحقق من الأرصدة والصلاحية.';
          _key = null;
        });
      } else {
        await _reconcile();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _unknown = true;
          _error = 'تعذر حفظ طلب التقفيل أو تأكيده. تحقق من الحالة.';
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
        _error = 'لم نتأكد من تقفيل اليومية. أعد المحاولة دون تغيير البيانات.';
      });
    } else {
      setState(() {
        _unknown = true;
        _error = 'حالة التقفيل غير مؤكدة. تحقق من الاتصال ثم راجع الحالة.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = widget.day.counts!;
    return PopScope(
      canPop: !_busy && !_unknown,
      child: Scaffold(
        appBar: AppBar(title: const Text('تقفيل اليومية')),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(16),
                children: [
                  Text('عدّ يوم العمل', style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 4),
                  const Text(
                    'أدخل ما عُدّ فعلياً. يمنع أي فرق التقفيل حتى تتم تسويته.',
                  ),
                  const SizedBox(height: 16),
                  Text('النقدية', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final method in CashMethod.canonicalOrder) ...[
                    TextField(
                      key: Key('close-cash-${method.code}'),
                      controller: _cash[method.code],
                      inputFormatters: const [CashInputFormatter()],
                      readOnly: _review != null,
                      textDirection: TextDirection.ltr,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: ledgerFieldDecoration(
                        context,
                        label: '${cashMethodLabel(method)} ',
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if ((counts['stock'] as List).isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('المخزون', style: theme.textTheme.titleMedium),
                    if (_namedCounts)
                      ClosingItemGridView(
                        grid: _grid,
                        counts: _cellCounts,
                        weights: _cellGrams,
                        showWeights: _showWeights,
                        readOnly: _busy || _unknown || _review != null,
                        onShowWeights: (value) =>
                            setState(() => _showWeights = value),
                        onAddItem: _grid.jewelryKarats.isEmpty
                            ? null
                            : _addClosingItem,
                      ),
                    if (!_namedCounts)
                      for (final row in counts['stock'] as List) ...[
                        const SizedBox(height: 8),
                        Text(
                          '${stockCategoryLabel(StockCategory.byCode((row as Map)['category'] as String)!)} · عيار ${row['karat']}',
                        ),
                        const SizedBox(height: 12),
                        LedgerFieldPair(
                          first: TextField(
                            controller:
                                _stock['${row['category']}:${row['karat']}']![0],
                            readOnly: _review != null,
                            textDirection: TextDirection.ltr,
                            autocorrect: false,
                            enableSuggestions: false,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            inputFormatters: const [
                              GramInputFormatter(decimalPlaces: 3),
                            ],
                            decoration: ledgerFieldDecoration(
                              context,
                              label: 'الوزن بالجرام',
                            ),
                          ),
                          second: TextField(
                            controller:
                                _stock['${row['category']}:${row['karat']}']![1],
                            readOnly: _review != null,
                            textDirection: TextDirection.ltr,
                            autocorrect: false,
                            enableSuggestions: false,
                            keyboardType: TextInputType.number,
                            inputFormatters: const [
                              GramInputFormatter(decimalPlaces: 0),
                            ],
                            decoration: ledgerFieldDecoration(
                              context,
                              label: 'العدد',
                            ),
                          ),
                        ),
                      ],
                  ],
                  if ((counts['scrap'] as List).isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text('الكسر', style: theme.textTheme.titleMedium),
                    for (final karat in orderedKarats([
                      for (final row in counts['scrap'] as List)
                        (row as Map)['karat'] as int,
                    ])) ...[
                      const SizedBox(height: 8),
                      Text('عيار $karat'),
                      const SizedBox(height: 8),
                      TextField(
                        key: Key('close-scrap-$karat'),
                        controller: _scrap[karat],
                        readOnly: _review != null,
                        textDirection: TextDirection.ltr,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: const [
                          GramInputFormatter(decimalPlaces: 3),
                        ],
                        decoration: ledgerFieldDecoration(
                          context,
                          label: 'الوزن بالجرام',
                        ),
                      ),
                    ],
                  ],
                  if (_review != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      color: theme.colorScheme.primaryContainer,
                      child: const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'الأعداد والنقد والكسر والأوزان المدخلة تطابق الدفتر. وزن المخزون الفارغ لم يُقَس. سيُغلق يوم العمل بعد التأكيد؛ لن تتغير الأرصدة.',
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy || _key != null
                          ? null
                          : () => setState(() => _review = null),
                      child: const Text('رجوع للتعديل'),
                    ),
                  ],
                  if (_discrepancy != null &&
                      widget.gateway is LedgerCorrectionGateway)
                    OutlinedButton(
                      key: const Key('close-correct'),
                      onPressed: _busy || _unknown || _key != null
                          ? null
                          : _correct,
                      child: const Text('مراجعة تسوية فرق الجرد'),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton(
              key: Key(
                _unknown
                    ? 'close-check-status'
                    : _review == null
                    ? 'close-review'
                    : 'close-confirm',
              ),
              onPressed: _busy
                  ? null
                  : _unknown
                  ? _reconcile
                  : _review == null
                  ? _checkCounts
                  : _submit,
              child: Text(
                _busy
                    ? 'بانتظار تأكيد الحفظ'
                    : _unknown
                    ? 'التحقق من الحالة'
                    : _review == null
                    ? 'مراجعة العد'
                    : 'تأكيد تقفيل اليومية',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
