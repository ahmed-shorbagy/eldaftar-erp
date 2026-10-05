import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../application/daily_ledger_view.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';
import '../../../theme/amount_format.dart';
import 'opening_copy.dart';

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
  static const _sections = ['movement', 'cash', 'gold', 'activity'];
  final _visible = <String, bool>{
    for (final section in _sections) section: true,
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
      _visible.updateAll((_, _) => true);
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
      for (final section in _sections) {
        _visible[section] = !savedLayout.contains('hidden:$section');
      }
    });
  }

  void _saveLayout() {
    _layoutEdited = true;
    final key = _preferenceKey;
    final snapshot = [
      ..._order,
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

  @override
  Widget build(BuildContext context) {
    final view = widget.ledger;
    if (view == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final stockWeight = _sum(view.stock.map((line) => line.milligrams));
    final scrapWeight = _sum(view.scrap.map((line) => line.milligrams));
    final goldWeight = stockWeight + scrapWeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ملخص اليوم', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              view.businessDay == null
                  ? 'الأرصدة الحالية'
                  : 'يوم العمل ${formatServerDate(view.businessDay!.businessDate)}',
              key: const Key('ledger-confirmed-status'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final tileWidth = width >= 300 ? (width - 12) / 2 : width;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: tileWidth,
                  child: _SummaryCard(
                    key: const Key('ledger-total-gold'),
                    icon: Icons.scale_outlined,
                    title: 'إجمالي الذهب',
                    value: _grams(goldWeight),
                    unit: 'جرام',
                    detail: 'المخزون والكسر',
                    featured: true,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _SummaryCard(
                    key: const Key('ledger-total-cash'),
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'إجمالي النقدية',
                    value: displayPounds(
                      view.totalCashPounds ?? '—',
                      compact: true,
                    ),
                    unit: 'جنيه',
                    detail: 'جميع طرق الدفع',
                  ),
                ),
              ],
            );
          },
        ),
        _OperationsPanel(
          dayClosed: widget.dayClosed,
          onSale: widget.onSale,
          onPurchase: widget.onPurchase,
          onExpense: widget.onExpense,
          onCashTransfer: widget.onCashTransfer,
          onScrapSale: widget.onScrapSale,
          onScrapToStock: widget.onScrapToStock,
          onCloseDay: widget.onCloseDay,
          onOpenDay: widget.onOpenDay,
          onPendingInvoices: widget.onPendingInvoices,
          onDailyNotes: widget.onDailyNotes,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('ledger-customize'),
            onPressed: () => setState(() => _customizing = !_customizing),
            icon: const Icon(Icons.tune),
            label: Text(_customizing ? 'إغلاق تخصيص العرض' : 'تخصيص العرض'),
          ),
        ),
        if (_customizing) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('الأقسام وترتيبها', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  const Text(
                    'اختر ما يظهر أولاً. يُحفظ هذا الترتيب لهذا المتجر على الجهاز.',
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
              ),
            },
            const SizedBox(height: 12),
          ],
      ],
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.unit,
    required this.detail,
    this.featured = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final String unit;
  final String detail;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = scheme.onSurface;
    final muted = scheme.onSurfaceVariant;
    return Card(
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 6,
              runSpacing: 4,
              children: [
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Text(
                  unit,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: foreground,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              style: theme.textTheme.bodySmall?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
  }
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
      child: Card(
        color: scheme.surfaceContainerLow,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(icon, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(title, style: theme.textTheme.titleSmall),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('$amount جنيه', style: theme.textTheme.titleLarge),
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
  'worked_jewelry' => 'مشغولات',
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
    subtitle: '',
    icon: Icons.payments_outlined,
    child: view.cash.isEmpty
        ? const Text('لا توجد أرصدة نقدية.')
        : Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final line in view.cash)
                Chip(
                  avatar: Icon(_paymentIcon(line.method), size: 18),
                  label: Text(
                    '${line.labelAr} · ${displayPounds(line.pounds)} جنيه',
                  ),
                ),
            ],
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
    return _SectionCard(
      title: 'الذهب حسب العيار',
      subtitle: '',
      icon: Icons.scale_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final karat in karats)
                Chip(
                  label: Text('عيار $karat · ${_grams(byKarat[karat]!)} جرام'),
                ),
            ],
          ),
          ExpansionTile(
            key: const Key('ledger-inventory-details'),
            tilePadding: EdgeInsets.zero,
            title: const Text('المخزون والكسر'),
            children: [
              for (final line in view.stock)
                _DetailLine(
                  label:
                      '${line.labelAr} · عيار ${line.karat} · ${line.count} قطعة',
                  value: '${line.grams} جرام',
                ),
              for (final line in view.scrap)
                _DetailLine(
                  label: 'كسر · عيار ${line.karat}',
                  value: '${line.grams} جرام',
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
  });
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
        ExpansionTile(
          initiallyExpanded: rows.any(
            (line) => line.kind.startsWith('opening_balances'),
          ),
          title: const Text('باقي الحركات'),
          children: [
            for (final line in rows.where(
              (line) =>
                  line.kind != 'sale' &&
                  line.kind != 'purchase' &&
                  !line.isReturn,
            ))
              _OperationCard(
                line: line,
                onTap: onOperation == null ? null : () => onOperation!(line),
              ),
          ],
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
          if (line.weightGrams != null)
            Text(
              '${line.weightGrams} جرام${line.karat == null ? '' : ' · عيار ${line.karat}'}',
            ),
          if (line.paymentLabel != null) Text(line.paymentLabel!),
          Text(formatServerCairoTimestamp(line.displayTime)),
        ],
      ),
      trailing: line.totalPounds == null
          ? (onTap == null ? null : const Icon(Icons.chevron_left))
          : Text(
              '${displayPounds(line.totalPounds!)}\nجنيه',
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            if (subtitle.isNotEmpty)
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 8,
      runSpacing: 4,
      children: [
        Text(label),
        Directionality(textDirection: TextDirection.ltr, child: Text(value)),
      ],
    ),
  );
}

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
