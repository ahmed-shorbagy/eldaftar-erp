import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../application/daily_ledger_view.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';
import '../../../theme/amount_format.dart';
import 'opening_copy.dart';
import 'ledger_quick_actions.dart';

/// Displays only figures returned by the confirmed server read model.
class ConfirmedLedgerDashboard extends StatefulWidget {
  const ConfirmedLedgerDashboard({
    super.key,
    required this.ledger,
    required this.shopId,
    this.onSale,
    this.onPurchase,
    this.onExpense,
    this.onCashTransfer,
    this.onScrapSale,
    this.onScrapToStock,
    this.onCloseDay,
    this.onOpenDay,
    this.onOperation,
    this.onPendingInvoices,
    this.onDailyNotes,
    this.onLoadOlder,
    this.loadingOlder = false,
    this.activityLines,
    this.dayClosed = false,
  });

  final DailyLedgerView? ledger;
  final String shopId;
  final VoidCallback? onSale;
  final VoidCallback? onPurchase;
  final VoidCallback? onExpense;
  final VoidCallback? onCashTransfer;
  final VoidCallback? onScrapSale;
  final VoidCallback? onScrapToStock;
  final VoidCallback? onCloseDay;
  final VoidCallback? onOpenDay;
  final ValueChanged<LedgerFeedLine>? onOperation;
  final VoidCallback? onPendingInvoices;
  final VoidCallback? onDailyNotes;
  final VoidCallback? onLoadOlder;
  final bool loadingOlder;
  final List<LedgerFeedLine>? activityLines;
  final bool dayClosed;

  @override
  State<ConfirmedLedgerDashboard> createState() =>
      _ConfirmedLedgerDashboardState();
}

class _ConfirmedLedgerDashboardState extends State<ConfirmedLedgerDashboard> {
  static const _sections = ['metrics', 'movement', 'cash', 'gold', 'activity'];
  static const _metricIds = [
    'total_cash',
    'sale',
    'purchase',
    'total_gold',
    'sale_gold',
    'purchase_gold',
    'expense',
    'operations',
  ];
  final _metricOrder = List<String>.of(_metricIds);
  final _metricVisible = <String, bool>{for (final id in _metricIds) id: true};
  bool _showMoreMetrics = false;
  bool _showReturns = true;
  final _visible = <String, bool>{
    for (final section in _sections) section: section != 'movement',
  };
  final _order = List<String>.of(_sections);
  bool _customizing = false;
  bool _layoutEdited = false;
  Future<void> _saveTail = Future<void>.value();

  String get _preferenceKey => 'ledger_layout_${widget.shopId}';

  @override
  void initState() {
    super.initState();
    _loadLayout();
  }

  @override
  void didUpdateWidget(covariant ConfirmedLedgerDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shopId != widget.shopId) {
      _order.setAll(0, _sections);
      _visible.updateAll((section, _) => section != 'movement');
      _metricOrder.setAll(0, _metricIds);
      _metricVisible.updateAll((_, _) => true);
      _showReturns = true;
      _showMoreMetrics = false;
      _layoutEdited = false;
      _loadLayout();
    }
  }

  Future<void> _loadLayout() async {
    final key = _preferenceKey;
    List<String>? saved;
    try {
      final preferences = await SharedPreferences.getInstance();
      saved = preferences.getStringList(key);
    } catch (_) {
      // The confirmed ledger remains readable if local preferences fail.
      return;
    }
    if (!mounted || key != _preferenceKey || _layoutEdited || saved == null) {
      return;
    }
    final savedLayout = saved;
    final ordered = savedLayout.where(_sections.contains).toSet().toList();
    ordered.addAll(_sections.where((section) => !ordered.contains(section)));
    setState(() {
      _order.setAll(0, ordered);
      final metricOrder = savedLayout
          .where((key) => key.startsWith('metric:'))
          .map((key) => key.substring(7))
          .where(_metricIds.contains)
          .toSet()
          .toList();
      metricOrder.addAll(_metricIds.where((id) => !metricOrder.contains(id)));
      _metricOrder.setAll(0, metricOrder);
      for (final id in _metricIds) {
        _metricVisible[id] = !savedLayout.contains('hidden:metric:$id');
      }
      _showReturns = !savedLayout.contains('hidden:returns');
      for (final section in _sections) {
        _visible[section] = !savedLayout.contains('hidden:$section');
        if (section == 'movement' && !savedLayout.contains('metrics')) {
          _visible[section] = false;
        }
      }
    });
  }

  void _saveLayout() {
    _layoutEdited = true;
    final key = _preferenceKey;
    final snapshot = [
      ..._order,
      for (final id in _metricOrder) 'metric:$id',
      for (final id in _metricIds)
        if (!_metricVisible[id]!) 'hidden:metric:$id',
      if (!_showReturns) 'hidden:returns',
      for (final section in _sections)
        if (!_visible[section]!) 'hidden:$section',
    ];
    _saveTail = _saveTail.then((_) => _writeLayout(key, snapshot));
  }

  Future<void> _writeLayout(String key, List<String> snapshot) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList(key, snapshot);
    } catch (_) {
      // The visible choice still applies for the current session.
    }
  }

  void _move(String section, int direction) {
    final index = _order.indexOf(section);
    final next = index + direction;
    if (next < 0 || next >= _order.length) return;
    setState(() {
      _order.removeAt(index);
      _order.insert(next, section);
    });
    _saveLayout();
  }

  void _moveMetric(String id, int direction) {
    final index = _metricOrder.indexOf(id);
    final next = index + direction;
    if (next < 0 || next >= _metricOrder.length) return;
    setState(() {
      _metricOrder.removeAt(index);
      _metricOrder.insert(next, id);
    });
    _saveLayout();
  }

  Widget _metrics(DailyLedgerView view, BigInt gold) {
    final summary = view.daySummary;
    String money(String? wire) => wire == null
        ? '—'
        : displayPounds(
            (Piastres.parseWire(wire) as Accepted<Piastres>).value.poundsText,
            compact: true,
          );
    BigInt weight(String kind) =>
        summary?.goldByBucket
            .where((row) => row.kind == kind)
            .fold<BigInt>(
              BigInt.zero,
              (sum, row) => sum + BigInt.parse(row.milligrams),
            ) ??
        BigInt.zero;
    final values = <String, _MetricSpec>{
      'total_cash': _MetricSpec(
        'إجمالي النقدية',
        displayPounds(view.totalCashPounds ?? '—', compact: true),
        '',
        Icons.account_balance_wallet_outlined,
        _MetricTone.primary,
      ),
      'total_gold': _MetricSpec(
        'إجمالي الذهب',
        _grams(gold),
        'جرام',
        Icons.diamond_outlined,
        _MetricTone.primary,
      ),
      'sale': _MetricSpec(
        'إجمالي البيع',
        money(summary?.salePiastres),
        '',
        Icons.trending_up,
        _MetricTone.positive,
      ),
      'purchase': _MetricSpec(
        'إجمالي الشراء',
        money(summary?.purchasePiastres),
        '',
        Icons.trending_down,
        _MetricTone.negative,
      ),
      'expense': _MetricSpec(
        'المصروفات',
        money(summary?.expensePiastres),
        '',
        Icons.receipt_long_outlined,
        _MetricTone.neutral,
      ),
      'operations': _MetricSpec(
        'عدد العمليات',
        summary == null
            ? '—'
            : '${summary.saleCount + summary.purchaseCount + summary.expenseCount}',
        '',
        Icons.tag_outlined,
        _MetricTone.neutral,
      ),
      'sale_gold': _MetricSpec(
        'ذهب مباع',
        _grams(weight('sale')),
        'جرام',
        Icons.south_west,
        _MetricTone.positive,
      ),
      'purchase_gold': _MetricSpec(
        'ذهب مشترى',
        _grams(weight('purchase')),
        'جرام',
        Icons.south_east,
        _MetricTone.negative,
      ),
    };
    final visible = _metricOrder.where((id) => _metricVisible[id]!).toList();
    final shown = _showMoreMetrics ? visible : visible.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, size) {
            final columns =
                size.maxWidth >= 260 &&
                    MediaQuery.textScalerOf(context).scale(12) <= 16
                ? 3
                : 2;
            final gap = 10.0;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final id in shown)
                  SizedBox(
                    width: (size.maxWidth - gap * (columns - 1)) / columns,
                    child: _MetricTile(
                      key: Key(
                        id == 'total_cash'
                            ? 'ledger-total-cash'
                            : id == 'total_gold'
                            ? 'ledger-total-gold'
                            : 'ledger-metric-$id',
                      ),
                      spec: values[id]!,
                    ),
                  ),
              ],
            );
          },
        ),
        if (visible.length > 6)
          TextButton(
            key: const Key('ledger-more-metrics'),
            onPressed: () =>
                setState(() => _showMoreMetrics = !_showMoreMetrics),
            child: Text(_showMoreMetrics ? 'عرض أقل' : 'عرض المزيد'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.ledger;
    if (view == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final stockWeight = _sum(view.stock.map((line) => line.milligrams));
    final scrapWeight = _sum(view.scrap.map((line) => line.milligrams));
    final goldWeight = stockWeight + scrapWeight;
    return LedgerQuickActions(
      shopId: widget.shopId,
      enabled: [
        widget.onSale,
        widget.onPurchase,
        widget.onExpense,
        widget.onCashTransfer,
        widget.onScrapSale,
        widget.onScrapToStock,
        widget.onCloseDay,
        widget.onOpenDay,
        widget.onPendingInvoices,
        widget.onDailyNotes,
      ].any((action) => action != null),
      panelBuilder: (sheet) {
        VoidCallback? action(VoidCallback? callback) => callback == null
            ? null
            : () {
                Navigator.of(sheet).pop();
                callback();
              };
        return _OperationsPanel(
          dayClosed: widget.dayClosed,
          onSale: action(widget.onSale),
          onPurchase: action(widget.onPurchase),
          onExpense: action(widget.onExpense),
          onCashTransfer: action(widget.onCashTransfer),
          onScrapSale: action(widget.onScrapSale),
          onScrapToStock: action(widget.onScrapToStock),
          onCloseDay: action(widget.onCloseDay),
          onOpenDay: action(widget.onOpenDay),
          onPendingInvoices: action(widget.onPendingInvoices),
          onDailyNotes: action(widget.onDailyNotes),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ملخص اليوم',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      view.businessDay == null
                          ? 'الأرصدة الحالية'
                          : 'يوم العمل ${formatServerDate(view.businessDay!.businessDate)}',
                      key: const Key('ledger-confirmed-status'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              ActionChip(
                key: const Key('ledger-customize'),
                avatar: Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                label: Text(
                  _customizing ? 'إغلاق' : 'تخصيص',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: () => setState(() => _customizing = !_customizing),
                shape: StadiumBorder(
                  side: BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.35),
                  ),
                ),
                backgroundColor: theme.colorScheme.primaryContainer.withValues(
                  alpha: 0.45,
                ),
              ),
            ],
          ),
          if (_customizing) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'الأقسام وترتيبها',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text('الأرقام الظاهرة', style: theme.textTheme.titleMedium),
                    for (final id in _metricOrder)
                      _SectionControl(
                        section: id,
                        visible: _metricVisible[id]!,
                        first: _metricOrder.first == id,
                        last: _metricOrder.last == id,
                        onChanged: (value) {
                          setState(() => _metricVisible[id] = value);
                          _saveLayout();
                        },
                        onUp: () => _moveMetric(id, -1),
                        onDown: () => _moveMetric(id, 1),
                      ),
                    SwitchListTile(
                      key: const Key('ledger-show-returns'),
                      title: const Text('دفتر المرتجعات'),
                      value: _showReturns,
                      onChanged: (value) {
                        setState(() => _showReturns = value);
                        _saveLayout();
                      },
                    ),
                    for (final section in _order)
                      _SectionControl(
                        section: section,
                        visible: _visible[section]!,
                        first: _order.first == section,
                        last: _order.last == section,
                        onChanged: (value) {
                          setState(() => _visible[section] = value);
                          _saveLayout();
                        },
                        onUp: () => _move(section, -1),
                        onDown: () => _move(section, 1),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          for (final section in _order)
            if (_visible[section]!) ...[
              switch (section) {
                'metrics' => _metrics(view, goldWeight),
                'movement' =>
                  view.daySummary == null
                      ? const SizedBox.shrink()
                      : _DailyMovementSection(
                          summary: view.daySummary!,
                          shopId: widget.shopId,
                        ),
                'cash' => _CashSection(view: view),
                'gold' => _GoldSection(view: view),
                _ => _ActivitySection(
                  view: view,
                  lines: widget.activityLines,
                  onOperation: widget.onOperation,
                  onLoadOlder: widget.onLoadOlder,
                  loadingOlder: widget.loadingOlder,
                  showReturns: _showReturns,
                ),
              },
              const SizedBox(height: 12),
            ],
        ],
      ),
    );
  }
}

class _OperationsPanel extends StatelessWidget {
  const _OperationsPanel({
    required this.dayClosed,
    this.onSale,
    this.onPurchase,
    this.onExpense,
    this.onCashTransfer,
    this.onScrapSale,
    this.onScrapToStock,
    this.onCloseDay,
    this.onOpenDay,
    this.onPendingInvoices,
    this.onDailyNotes,
  });
  final bool dayClosed;
  final VoidCallback? onSale,
      onPurchase,
      onExpense,
      onCashTransfer,
      onScrapSale,
      onScrapToStock,
      onCloseDay,
      onOpenDay,
      onPendingInvoices,
      onDailyNotes;

  @override
  Widget build(BuildContext context) {
    final actions = <(String, IconData, VoidCallback?, String)>[
      if (!dayClosed) ...[
        ('بيع', Icons.shopping_cart_outlined, onSale, 'ledger-new-sale'),
        (
          'شراء',
          Icons.shopping_bag_outlined,
          onPurchase,
          'ledger-new-purchase',
        ),
        ('مصروف', Icons.receipt_long_outlined, onExpense, 'ledger-new-expense'),
      ] else
        (
          'فتح يوم جديد',
          Icons.lock_open_outlined,
          onOpenDay,
          'ledger-open-day',
        ),
    ].where((a) => a.$3 != null).toList();
    final more = <(String, IconData, VoidCallback?, String)>[
      if (!dayClosed) ...[
        (
          'بيع كسر',
          Icons.content_cut_outlined,
          onScrapSale,
          'ledger-new-scrap-sale',
        ),
        (
          'تحويل نقدية',
          Icons.swap_horiz,
          onCashTransfer,
          'ledger-new-cash-transfer',
        ),
        (
          'تحويل الكسر إلى مخزون',
          Icons.inventory_2_outlined,
          onScrapToStock,
          'ledger-new-scrap-to-stock',
        ),
      ],
      (
        'ملاحظات اليوم',
        Icons.sticky_note_2_outlined,
        onDailyNotes,
        'ledger-daily-notes',
      ),
      (
        'تقفيل اليومية',
        Icons.lock_clock_outlined,
        onCloseDay,
        'ledger-close-day',
      ),
      (
        'الفواتير المعلقة',
        Icons.mark_email_unread_outlined,
        onPendingInvoices,
        'ledger-pending-invoices',
      ),
    ].where((a) => a.$3 != null).toList();
    if (actions.isEmpty && more.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                dayClosed ? 'اليوم مغلق' : 'إجراءات سريعة',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, size) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final action in actions)
                      SizedBox(
                        width: size.maxWidth >= 300
                            ? (size.maxWidth - 16) / 3
                            : (size.maxWidth - 8) / 2,
                        child: OutlinedButton(
                          key: Key(action.$4),
                          onPressed: action.$3,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(action.$2, size: 22),
                              const SizedBox(height: 6),
                              Text(action.$1),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (more.isNotEmpty)
                ExpansionTile(
                  key: const Key('ledger-more-actions'),
                  tilePadding: EdgeInsets.zero,
                  title: const Text('المزيد من الإجراءات'),
                  children: [
                    for (final action in more)
                      ListTile(
                        key: Key(action.$4),
                        leading: Icon(action.$2),
                        title: Text(action.$1),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: action.$3,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _label(String section) => switch (section) {
  'metrics' => 'ملخص الأرقام',
  'total_cash' => 'إجمالي النقدية',
  'total_gold' => 'إجمالي الذهب',
  'sale_gold' => 'ذهب مباع',
  'purchase_gold' => 'ذهب مشترى',
  'operations' => 'عدد العمليات',

  'movement' => 'حركة اليوم',
  'sale' => 'المبيعات',
  'purchase' => 'المشتريات',
  'expense' => 'المصروفات',
  'gold_movement' => 'حركة الذهب',
  'cash' => 'النقدية',
  'gold' => 'الذهب',
  _ => 'حركة الدفتر',
};

class _SectionControl extends StatelessWidget {
  const _SectionControl({
    required this.section,
    required this.visible,
    required this.first,
    required this.last,
    required this.onChanged,
    required this.onUp,
    required this.onDown,
  });

  final String section;
  final bool visible;
  final bool first;
  final bool last;
  final ValueChanged<bool> onChanged;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: SwitchListTile.adaptive(
          key: Key('ledger-show-$section'),
          contentPadding: EdgeInsets.zero,
          title: Text(_label(section)),
          value: visible,
          onChanged: onChanged,
        ),
      ),
      IconButton(
        tooltip: 'نقل ${_label(section)} إلى الأعلى',
        onPressed: first ? null : onUp,
        icon: const Icon(Icons.arrow_upward),
      ),
      IconButton(
        tooltip: 'نقل ${_label(section)} إلى الأسفل',
        onPressed: last ? null : onDown,
        icon: const Icon(Icons.arrow_downward),
      ),
    ],
  );
}

class _DailyMovementSection extends StatefulWidget {
  const _DailyMovementSection({required this.summary, required this.shopId});
  final LedgerDaySummary summary;
  final String shopId;

  @override
  State<_DailyMovementSection> createState() => _DailyMovementSectionState();
}

class _DailyMovementSectionState extends State<_DailyMovementSection> {
  static const _cards = ['sale', 'purchase', 'expense', 'gold_movement'];
  final _order = List<String>.of(_cards);
  final _visible = <String, bool>{for (final card in _cards) card: true};
  bool _customizing = false;
  bool _layoutEdited = false;
  Future<void> _saveTail = Future<void>.value();

  String get _key => 'ledger_movement_layout_${widget.shopId}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _DailyMovementSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shopId != widget.shopId) {
      _order.setAll(0, _cards);
      _visible.updateAll((_, _) => true);
      _layoutEdited = false;
      _load();
    }
  }

  Future<void> _load() async {
    final key = _key;
    List<String>? saved;
    try {
      saved = (await SharedPreferences.getInstance()).getStringList(key);
    } catch (_) {
      return;
    }
    if (!mounted || key != _key || _layoutEdited || saved == null) return;
    final order = saved.where(_cards.contains).toSet().toList();
    order.addAll(_cards.where((card) => !order.contains(card)));
    setState(() {
      _order.setAll(0, order);
      for (final card in _cards) {
        _visible[card] = !saved!.contains('hidden:$card');
      }
    });
  }

  void _save() {
    _layoutEdited = true;
    final key = _key;
    final snapshot = [
      ..._order,
      for (final card in _cards)
        if (!_visible[card]!) 'hidden:$card',
    ];
    _saveTail = _saveTail.then((_) async {
      try {
        await (await SharedPreferences.getInstance()).setStringList(
          key,
          snapshot,
        );
      } catch (_) {
        // The current screen still reflects the owner's choice.
      }
    });
  }

  void _move(String card, int direction) {
    final available = _order
        .where(
          (entry) =>
              entry != 'gold_movement' ||
              widget.summary.goldByBucket.isNotEmpty,
        )
        .toList();
    final from = available.indexOf(card);
    final to = from + direction;
    if (to < 0 || to >= available.length) return;
    final first = _order.indexOf(card);
    final second = _order.indexOf(available[to]);
    setState(() {
      _order[first] = available[to];
      _order[second] = card;
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = widget.summary;
    final cards = _order
        .where(
          (card) => card != 'gold_movement' || summary.goldByBucket.isNotEmpty,
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('حركة يوم العمل', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'المبيعات والمشتريات',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('ledger-customize-movement'),
            onPressed: () => setState(() => _customizing = !_customizing),
            icon: const Icon(Icons.tune),
            label: Text(
              _customizing ? 'إغلاق ترتيب البطاقات' : 'ترتيب البطاقات',
            ),
          ),
        ),
        if (_customizing)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  for (final card in cards)
                    _SectionControl(
                      section: card,
                      visible: _visible[card]!,
                      first: cards.first == card,
                      last: cards.last == card,
                      onChanged: (value) {
                        setState(() => _visible[card] = value);
                        _save();
                      },
                      onUp: () => _move(card, -1),
                      onDown: () => _move(card, 1),
                    ),
                ],
              ),
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final itemWidth = width >= 540
                ? (width - 24) / 3
                : width >= 300
                ? (width - 12) / 2
                : width;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final card in cards)
                  if (_visible[card]!)
                    switch (card) {
                      'sale' => _DailyMovementCard(
                        key: const Key('ledger-movement-sale'),
                        width: itemWidth,
                        title: 'المبيعات',
                        amount: _money(summary.salePiastres),
                        count: summary.saleCount,
                        icon: Icons.trending_up,
                      ),
                      'purchase' => _DailyMovementCard(
                        key: const Key('ledger-movement-purchase'),
                        width: itemWidth,
                        title: 'المشتريات',
                        amount: _money(summary.purchasePiastres),
                        count: summary.purchaseCount,
                        icon: Icons.inventory_2_outlined,
                      ),
                      'expense' => _DailyMovementCard(
                        key: const Key('ledger-movement-expense'),
                        width: itemWidth,
                        title: 'المصروفات',
                        amount: _money(summary.expensePiastres),
                        count: summary.expenseCount,
                        icon: Icons.receipt_long_outlined,
                      ),
                      _ => SizedBox(
                        width: width,
                        child: ExpansionTile(
                          title: const Text('حركة الذهب'),
                          children: [_GoldMovementSection(summary: summary)],
                        ),
                      ),
                    },
              ],
            );
          },
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _DailyMovementCard extends StatelessWidget {
  const _DailyMovementCard({
    super.key,
    required this.width,
    required this.title,
    required this.amount,
    required this.count,
    required this.icon,
  });

  final double width;
  final String title;
  final String amount;
  final int count;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(icon, size: 18, color: scheme.primary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleSmall),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                amount,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'عدد العمليات: $count',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoldMovementSection extends StatefulWidget {
  const _GoldMovementSection({required this.summary});
  final LedgerDaySummary summary;

  @override
  State<_GoldMovementSection> createState() => _GoldMovementSectionState();
}

class _GoldMovementSectionState extends State<_GoldMovementSection> {
  int? _selectedKarat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final karats = widget.summary.goldByBucket.map((line) => line.karat).toSet()
      ..removeWhere((karat) => !const {14, 18, 21, 22, 24}.contains(karat));
    final orderedKarats = karats.toList()..sort();
    if (orderedKarats.isEmpty) return const SizedBox.shrink();
    final selected = orderedKarats.contains(_selectedKarat)
        ? _selectedKarat!
        : orderedKarats.first;
    final lines = [
      for (final movement in widget.summary.goldByBucket)
        if (movement.karat == selected) movement,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text('حركة الذهب', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'اختر العيار لعرض وزن البيع والشراء، ثم تفاصيل النوع والعدد',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < orderedKarats.length; index++) ...[
                if (index > 0) const SizedBox(width: 8),
                ChoiceChip(
                  key: Key('ledger-karat-${orderedKarats[index]}'),
                  label: Text('عيار ${orderedKarats[index]}'),
                  selected: orderedKarats[index] == selected,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  onSelected: (_) =>
                      setState(() => _selectedKarat = orderedKarats[index]),
                ),
              ],
            ],
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
                  'إجمالي عيار $selected',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'بيع: ${_grams(widget.summary.goldMilligrams(kind: 'sale', karat: selected))} جرام',
                  key: const Key('ledger-karat-sale-total'),
                ),
                const SizedBox(height: 6),
                Text(
                  'شراء: ${_grams(widget.summary.goldMilligrams(kind: 'purchase', karat: selected))} جرام',
                  key: const Key('ledger-karat-purchase-total'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (lines.isEmpty)
          Text(
            'لا تفاصيل لهذا العيار في حركة اليوم.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        else
          for (var index = 0; index < lines.length; index++) ...[
            if (index > 0) const SizedBox(height: 10),
            _GoldMovementLine(movement: lines[index]),
          ],
      ],
    );
  }
}

class _GoldMovementLine extends StatelessWidget {
  const _GoldMovementLine({required this.movement});

  final LedgerGoldMovement movement;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sale = movement.kind == 'sale';
    return Card(
      key: Key(
        'ledger-gold-${movement.kind}-${movement.category}-${movement.karat}',
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 14, 16, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              sale ? Icons.north_east : Icons.south_west,
              color: scheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${sale ? 'بيع' : 'شراء'} · '
                    '${_goldCategoryLabel(movement.category)} · عيار ${movement.karat}',
                    style: theme.textTheme.titleSmall,
                  ),
                  if (movement.category != 'scrap') ...[
                    const SizedBox(height: 4),
                    Text(
                      'عدد القطع: ${movement.count}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${_grams(BigInt.parse(movement.milligrams))} جرام',
              textDirection: TextDirection.ltr,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _money(String wire) {
  final parsed = Piastres.parseWire(wire);
  return parsed is Accepted<Piastres>
      ? displayPounds(parsed.value.poundsText)
      : '—';
}

String _goldCategoryLabel(String category) => switch (category) {
  'worked_jewelry' || 'jewelry' => 'مشغولات',
  'bullion' => 'سبائك',
  'coin' => 'جنيهات',
  'scrap' => 'كسر',
  _ => 'ذهب',
};

class _CashSection extends StatelessWidget {
  const _CashSection({required this.view});
  final DailyLedgerView view;
  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'النقدية',
    subtitle: 'توزيع الأرصدة حسب وسيلة الدفع',
    icon: Icons.payments_outlined,
    child: view.cash.isEmpty
        ? const Text('لا توجد أرصدة نقدية.')
        : LayoutBuilder(
            builder: (context, size) {
              final columns = size.maxWidth >= 360 ? 2 : 1;
              final gap = 10.0;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final line in view.cash)
                    SizedBox(
                      width: columns == 1
                          ? size.maxWidth
                          : (size.maxWidth - gap) / 2,
                      child: _FlagTile(
                        accent: Theme.of(context).colorScheme.primary,
                        icon: _paymentIcon(line.method),
                        title: line.labelAr,
                        value: displayPounds(line.pounds),
                      ),
                    ),
                ],
              );
            },
          ),
  );
}

class _GoldSection extends StatelessWidget {
  const _GoldSection({required this.view});
  final DailyLedgerView view;
  @override
  Widget build(BuildContext context) {
    final byKarat = <int, BigInt>{};
    for (final line in view.stock) {
      byKarat.update(
        line.karat,
        (v) => v + BigInt.parse(line.milligrams),
        ifAbsent: () => BigInt.parse(line.milligrams),
      );
    }
    for (final line in view.scrap) {
      byKarat.update(
        line.karat,
        (v) => v + BigInt.parse(line.milligrams),
        ifAbsent: () => BigInt.parse(line.milligrams),
      );
    }
    final karats = byKarat.keys.toList()..sort((a, b) => b.compareTo(a));
    final groups = <String, List<({int karat, String grams, String? count})>>{};
    final labels = <String, String>{};
    for (final line in view.stock) {
      labels.putIfAbsent(
        line.category,
        () => line.labelAr.isNotEmpty
            ? line.labelAr
            : _goldCategoryLabel(line.category),
      );
      groups.putIfAbsent(line.category, () => []).add((
        karat: line.karat,
        grams: line.grams,
        count: line.count,
      ));
    }
    if (view.scrap.isNotEmpty) {
      labels['scrap'] = _goldCategoryLabel('scrap');
      groups['scrap'] = [
        for (final line in view.scrap)
          (karat: line.karat, grams: line.grams, count: null),
      ];
    }
    final categoryOrder = [
      'worked_jewelry',
      'jewelry',
      'bullion',
      'coin',
      'scrap',
      ...groups.keys.where(
        (key) => !const {
          'worked_jewelry',
          'jewelry',
          'bullion',
          'coin',
          'scrap',
        }.contains(key),
      ),
    ].where(groups.containsKey).toList();

    return _SectionCard(
      title: 'الذهب حسب العيار',
      subtitle: 'إجمالي المخزون والكسر لكل عيار',
      icon: Icons.scale_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (karats.isEmpty)
            const Text('لا توجد أرصدة ذهب.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final karat in karats)
                  _KaratFlag(
                    karat: karat,
                    weight: '${_grams(byKarat[karat]!)} جرام',
                  ),
              ],
            ),
          ExpansionTile(
            key: const Key('ledger-inventory-details'),
            tilePadding: EdgeInsets.zero,
            title: const Text('المخزون والكسر'),
            children: [
              for (final category in categoryOrder)
                _InventoryCategoryBlock(
                  category: category,
                  label: labels[category] ?? _goldCategoryLabel(category),
                  items: groups[category]!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({
    required this.view,
    this.lines,
    this.onOperation,
    this.onLoadOlder,
    this.loadingOlder = false,
    this.showReturns = true,
  });
  final bool showReturns;
  final DailyLedgerView view;
  final List<LedgerFeedLine>? lines;
  final ValueChanged<LedgerFeedLine>? onOperation;
  final VoidCallback? onLoadOlder;
  final bool loadingOlder;

  @override
  Widget build(BuildContext context) {
    final rows = lines ?? view.feed;
    final groups = <(String, String, bool)>[
      ('sale', 'دفتر البيع', true),
      ('purchase', 'دفتر الشراء', true),
      if (showReturns && rows.any((line) => line.isReturn))
        ('return', 'دفتر المرتجعات', false),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final group in groups)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Card(
              child: ExpansionTile(
                key: PageStorageKey('journal-${group.$1}'),
                initiallyExpanded: group.$3,
                title: Text(
                  group.$2,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [
                  if (!rows.any(
                    (line) => group.$1 == 'return'
                        ? line.isReturn
                        : line.kind == group.$1,
                  ))
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('لا توجد عمليات حتى الآن.'),
                    ),
                  for (final line in rows.where(
                    (line) => group.$1 == 'return'
                        ? line.isReturn
                        : line.kind == group.$1,
                  ))
                    _OperationCard(
                      line: line,
                      onTap: onOperation == null
                          ? null
                          : () => onOperation!(line),
                    ),
                ],
              ),
            ),
          ),
        if (rows.any(
          (line) =>
              line.kind != 'sale' && line.kind != 'purchase' && !line.isReturn,
        ))
          TextButton(
            key: const Key('ledger-other-movements'),
            child: const Text('عرض الحركات الأخرى'),
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              useSafeArea: true,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (sheet) => SizedBox(
                height: MediaQuery.sizeOf(sheet).height * .65,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'الحركات الأخرى',
                      style: Theme.of(sheet).textTheme.titleLarge,
                    ),
                    for (final line in rows.where(
                      (line) =>
                          line.kind != 'sale' &&
                          line.kind != 'purchase' &&
                          !line.isReturn,
                    ))
                      _OperationCard(
                        line: line,
                        onTap: onOperation == null
                            ? null
                            : () {
                                Navigator.of(sheet).pop();
                                onOperation!(line);
                              },
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (onLoadOlder != null)
          OutlinedButton(
            key: const Key('ledger-load-older'),
            onPressed: loadingOlder ? null : onLoadOlder,
            child: Text(
              loadingOlder ? 'جارٍ تحميل عمليات أقدم' : 'تحميل عمليات أقدم',
            ),
          ),
      ],
    );
  }
}

class _OperationCard extends StatelessWidget {
  const _OperationCard({required this.line, this.onTap});
  final LedgerFeedLine line;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      leading: Icon(
        line.isReturn ? Icons.undo_outlined : Icons.receipt_long_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        line.partyName == null || line.partyName!.isEmpty
            ? line.labelAr
            : '${line.labelAr} · ${line.partyName}',
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'المسجل: ${line.actorDisplayName}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          if (line.itemSummary != null || line.pieceCount != null)
            Text(
              [
                if (line.itemSummary != null) line.itemSummary!,
                if (line.pieceCount != null) 'عدد القطع: ${line.pieceCount}',
              ].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          if (line.weightGrams != null)
            Text(
              '${line.weightGrams} جرام${line.karat == null ? '' : ' · عيار ${line.karat}'}',
            ),
          Text(
            [
              if (line.paymentLabel != null) line.paymentLabel!,
              formatServerCairoTimestamp(line.displayTime),
            ].join(' · '),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      trailing: line.totalPounds == null
          ? (onTap == null ? null : const Icon(Icons.chevron_left))
          : Text(
              displayPounds(line.totalPounds!),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
      onTap: onTap,
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Icon(icon, size: 20, color: scheme.primary),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

enum _MetricTone { primary, positive, negative, neutral }

class _MetricSpec {
  const _MetricSpec(this.label, this.value, this.unit, this.icon, this.tone);

  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final _MetricTone tone;
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({super.key, required this.spec});

  final _MetricSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (Color accent, Color wash) = switch (spec.tone) {
      _MetricTone.primary => (
        scheme.primary,
        scheme.primary.withValues(alpha: 0.14),
      ),
      _MetricTone.positive => (
        scheme.tertiary,
        scheme.tertiary.withValues(alpha: 0.16),
      ),
      _MetricTone.negative => (
        scheme.error,
        scheme.error.withValues(alpha: 0.12),
      ),
      _MetricTone.neutral => (
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest.withValues(alpha: 0.7),
      ),
    };
    return Semantics(
      label: [
        spec.label,
        spec.value,
        if (spec.unit.isNotEmpty) spec.unit,
      ].join(' '),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.55),
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: wash,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(spec.icon, size: 18, color: accent),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      spec.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.25,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 30,
                child: FittedBox(
                  alignment: AlignmentDirectional.centerStart,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    spec.value,
                    maxLines: 1,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
              if (spec.unit.isNotEmpty)
                Text(
                  spec.unit,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FlagTile extends StatelessWidget {
  const _FlagTile({
    required this.accent,
    required this.icon,
    required this.title,
    required this.value,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadiusDirectional.only(
                  topStart: Radius.circular(20),
                  bottomStart: Radius.circular(20),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 18, color: accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      value,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KaratFlag extends StatelessWidget {
  const _KaratFlag({required this.karat, required this.weight});

  final int karat;
  final String weight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: 'عيار $karat $weight',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _KaratBadge(karat: karat, fill: scheme.primary),
              const SizedBox(height: 8),
              Text(
                weight,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KaratBadge extends StatelessWidget {
  const _KaratBadge({required this.karat, required this.fill});

  final int karat;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onFill = fill == scheme.error
        ? scheme.onError
        : fill == scheme.tertiary
        ? scheme.onTertiary
        : fill == scheme.secondary
        ? scheme.onSecondary
        : scheme.onPrimary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          'عيار $karat',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: onFill,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _InventoryCategoryBlock extends StatelessWidget {
  const _InventoryCategoryBlock({
    required this.category,
    required this.label,
    required this.items,
  });

  final String category;
  final String label;
  final List<({int karat, String grams, String? count})> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = _categoryAccent(scheme, category);
    final icon = _categoryIcon(category);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(icon, size: 18, color: accent),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const SizedBox(width: 18, height: 8),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in items)
                _InventoryPiece(
                  accent: accent,
                  karat: item.karat,
                  grams: item.grams,
                  count: item.count,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InventoryPiece extends StatelessWidget {
  const _InventoryPiece({
    required this.accent,
    required this.karat,
    required this.grams,
    this.count,
  });

  final Color accent;
  final int karat;
  final String grams;
  final String? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: [
        'عيار $karat',
        if (count != null) '$count قطعة',
        '$grams جرام',
      ].join(' '),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _KaratBadge(karat: karat, fill: accent),
              const SizedBox(height: 8),
              Text(
                '$grams جرام',
                textDirection: TextDirection.ltr,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (count != null)
                Text(
                  '$count قطعة',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _categoryAccent(ColorScheme scheme, String category) =>
    switch (category) {
      'worked_jewelry' || 'jewelry' => scheme.primary,
      'bullion' => scheme.tertiary,
      'coin' => scheme.secondary,
      'scrap' => scheme.error,
      _ => scheme.onSurfaceVariant,
    };

IconData _categoryIcon(String category) => switch (category) {
  'worked_jewelry' || 'jewelry' => Icons.diamond_outlined,
  'bullion' => Icons.view_in_ar_outlined,
  'coin' => Icons.monetization_on_outlined,
  'scrap' => Icons.content_cut_outlined,
  _ => Icons.category_outlined,
};

BigInt _sum(Iterable<String> values) => values.fold(
  BigInt.zero,
  (sum, value) => sum + (BigInt.tryParse(value) ?? BigInt.zero),
);

String _grams(BigInt milligrams) {
  final whole = milligrams ~/ BigInt.from(1000);
  final fraction = (milligrams % BigInt.from(1000)).toString().padLeft(3, '0');
  return '$whole.$fraction';
}

IconData _paymentIcon(String method) => switch (method) {
  'cash' => Icons.payments_outlined,
  'card' => Icons.credit_card_outlined,
  'wallet' => Icons.account_balance_wallet_outlined,
  'instant_transfer' => Icons.bolt_outlined,
  _ => Icons.savings_outlined,
};
