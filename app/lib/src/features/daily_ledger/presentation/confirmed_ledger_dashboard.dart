import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../application/daily_ledger_view.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';
import 'ledger_home_charts.dart';
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
  final bool dayClosed;

  @override
  State<ConfirmedLedgerDashboard> createState() =>
      _ConfirmedLedgerDashboardState();
}

class _ConfirmedLedgerDashboardState extends State<ConfirmedLedgerDashboard> {
  static const _sections = ['gold', 'cash', 'movement', 'activity'];
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
            Text('نظرة على الدفتر', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              view.businessDay == null
                  ? 'الأرصدة المؤكدة من الخادم'
                  : 'يوم العمل ${formatServerDate(view.businessDay!.businessDate)} · الأرصدة المؤكدة',
              key: const Key('ledger-confirmed-status'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (widget.onSale != null || widget.onOpenDay != null) ...[
          if (widget.dayClosed)
            FilledButton.icon(
              key: const Key('ledger-open-day'),
              onPressed: widget.onOpenDay,
              icon: const Icon(Icons.today_outlined),
              label: const Text('فتح يوم عمل جديد'),
            )
          else ...[
            FilledButton.icon(
              key: const Key('ledger-new-sale'),
              onPressed: widget.onSale,
              icon: const Icon(Icons.add_shopping_cart_outlined),
              label: const Text('إضافة بيع'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('ledger-new-purchase'),
                    onPressed: widget.onPurchase,
                    icon: const Icon(Icons.shopping_bag_outlined),
                    label: const Text('إضافة شراء'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('ledger-new-expense'),
                    onPressed: widget.onExpense,
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('مصروف'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (widget.onCashTransfer != null) ...[
              OutlinedButton.icon(
                key: const Key('ledger-cash-transfer'),
                onPressed: widget.onCashTransfer,
                icon: const Icon(Icons.swap_horiz_outlined),
                label: const Text('تحويل بين وسائل الدفع'),
              ),
              const SizedBox(height: 8),
            ],
            if (widget.onScrapSale != null) ...[
              OutlinedButton.icon(
                key: const Key('ledger-scrap-sale'),
                onPressed: widget.onScrapSale,
                icon: const Icon(Icons.scale_outlined),
                label: const Text('بيع كسر وإضافة نقد'),
              ),
              const SizedBox(height: 8),
            ],
            if (widget.onScrapToStock != null) ...[
              OutlinedButton.icon(
                key: const Key('ledger-scrap-to-stock'),
                onPressed: widget.onScrapToStock,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('تحويل كسر إلى مخزون'),
              ),
              const SizedBox(height: 8),
            ],
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                key: const Key('ledger-close-day'),
                onPressed: widget.onCloseDay,
                icon: const Icon(Icons.lock_clock_outlined),
                label: const Text('تقفيل اليومية'),
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
        if (widget.onPendingInvoices != null) ...[
          TextButton.icon(
            key: const Key('ledger-pending-invoices'),
            onPressed: widget.onPendingInvoices,
            icon: const Icon(Icons.mark_email_unread_outlined),
            label: const Text('فواتير تنتظر تأكيد الإرسال'),
          ),
          const SizedBox(height: 12),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final tileWidth = width >= 480 ? (width - 12) / 2 : width;
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
                    detail: 'المخزون والكسر · وزن مؤكد',
                    featured: true,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _SummaryCard(
                    key: const Key('ledger-total-cash'),
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'إجمالي النقدية',
                    value: view.totalCashPounds ?? '—',
                    unit: 'جنيه',
                    detail: 'جميع طرق الدفع · رصيد مؤكد',
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
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
                onOperation: widget.onOperation,
              ),
            },
            const SizedBox(height: 16),
          ],
      ],
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
    final foreground = featured ? scheme.onPrimary : scheme.onSurface;
    final muted = featured
        ? scheme.onPrimary.withValues(alpha: 0.82)
        : scheme.onSurfaceVariant;
    return Card(
      color: featured ? scheme.primary : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: featured ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: featured ? scheme.onPrimary : scheme.primary),
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
                if (featured)
                  Icon(
                    Icons.verified_outlined,
                    color: scheme.onPrimary,
                    size: 20,
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 6,
              runSpacing: 4,
              children: [
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    value,
                    style: theme.textTheme.headlineMedium?.copyWith(
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
        Text(
          'مبالغ وعمليات أكدها الخادم في هذا اليوم',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
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
            final itemWidth = width >= 640
                ? (width - 24) / 3
                : width >= 480
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
                        child: _GoldMovementSection(summary: summary),
                      ),
                    },
              ],
            );
          },
        ),
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
    final selected = orderedKarats.contains(_selectedKarat)
        ? _selectedKarat!
        : orderedKarats.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('حركة الذهب', style: theme.textTheme.titleMedium),
        Text(
          'إجمالي الوزن حسب العيار، ثم تفاصيل النوع والعدد',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final karat in orderedKarats)
              ChoiceChip(
                key: Key('ledger-karat-$karat'),
                label: Text('عيار $karat'),
                selected: karat == selected,
                onSelected: (_) => setState(() => _selectedKarat = karat),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'إجمالي عيار $selected',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'بيع: ${_grams(widget.summary.goldMilligrams(kind: 'sale', karat: selected))} جرام',
                  key: const Key('ledger-karat-sale-total'),
                ),
                Text(
                  'شراء: ${_grams(widget.summary.goldMilligrams(kind: 'purchase', karat: selected))} جرام',
                  key: const Key('ledger-karat-purchase-total'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        for (final movement in widget.summary.goldByBucket)
          Card(
            child: ListTile(
              key: Key(
                'ledger-gold-${movement.kind}-${movement.category}-${movement.karat}',
              ),
              leading: Icon(
                movement.kind == 'sale' ? Icons.north_east : Icons.south_west,
                color: theme.colorScheme.primary,
              ),
              title: Text(
                '${movement.kind == 'sale' ? 'بيع' : 'شراء'} · '
                '${_goldCategoryLabel(movement.category)} · عيار ${movement.karat}',
              ),
              subtitle: movement.category == 'scrap'
                  ? null
                  : Text('عدد القطع: ${movement.count}'),
              trailing: Text(
                '${_grams(BigInt.parse(movement.milligrams))} جرام',
                textDirection: TextDirection.ltr,
                style: theme.textTheme.titleSmall,
              ),
            ),
          ),
      ],
    );
  }
}

String _money(String wire) {
  final parsed = Piastres.parseWire(wire);
  return parsed is Accepted<Piastres> ? parsed.value.poundsText : '—';
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
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'مقارنة طرق النقدية',
      subtitle: 'الشريط نسبة إلى أعلى رصيد، والنسبة من إجمالي النقدية',
      icon: Icons.payments_outlined,
      child: view.cash.isEmpty
          ? const Text('لا توجد أرصدة نقدية معروضة.')
          : LedgerCompareBars(
              key: const Key('ledger-cash-chart'),
              shareKeyPrefix: 'ledger-cash-share',
              rankLabel: 'أعلى رصيد',
              slices: [
                for (final line in view.cash)
                  LedgerChartSlice(
                    id: line.method,
                    label: line.labelAr,
                    valueLabel: '${line.pounds} جنيه',
                    amount: BigInt.tryParse(line.piastres) ?? BigInt.zero,
                    icon: _paymentIcon(line.method),
                  ),
              ],
            ),
    );
  }
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
        (value) => value + (BigInt.tryParse(line.milligrams) ?? BigInt.zero),
        ifAbsent: () => BigInt.tryParse(line.milligrams) ?? BigInt.zero,
      );
    }
    for (final line in view.scrap) {
      byKarat.update(
        line.karat,
        (value) => value + (BigInt.tryParse(line.milligrams) ?? BigInt.zero),
        ifAbsent: () => BigInt.tryParse(line.milligrams) ?? BigInt.zero,
      );
    }
    final karats = byKarat.keys.toList()..sort((a, b) => b.compareTo(a));
    final total = byKarat.values.fold<BigInt>(
      BigInt.zero,
      (sum, weight) => sum + weight,
    );
    return _SectionCard(
      title: 'الذهب حسب العيار',
      subtitle: 'حصة كل عيار من إجمالي الوزن المؤكد',
      icon: Icons.scale_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (karats.isEmpty)
            const Text('لا يوجد وزن ذهب مسجل في الأرصدة المؤكدة.')
          else ...[
            LedgerShareDonut(
              key: const Key('ledger-gold-chart'),
              shareKeyPrefix: 'ledger-gold-share',
              rankLabel: 'أعلى وزن',
              chartLabel: 'مخطط دائري لحصص العيارات من إجمالي الذهب',
              centerValue: _grams(total),
              centerUnit: 'جرام',
              slices: [
                for (final karat in karats)
                  LedgerChartSlice(
                    id: '$karat',
                    label: 'عيار $karat',
                    valueLabel: '${_grams(byKarat[karat]!)} جرام',
                    amount: byKarat[karat]!,
                  ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (view.stock.isNotEmpty) ...[
            const Divider(),
            Text('المخزون', style: Theme.of(context).textTheme.titleSmall),
            for (final line in view.stock)
              _DetailLine(
                label:
                    '${line.labelAr} · عيار ${line.karat} · ${line.count} قطعة',
                value: '${line.grams} جرام',
              ),
          ],
          if (view.scrap.isNotEmpty) ...[
            const Divider(),
            Text('الكسر', style: Theme.of(context).textTheme.titleSmall),
            for (final line in view.scrap)
              _DetailLine(
                label: '${line.labelAr} · عيار ${line.karat}',
                value: '${line.grams} جرام',
              ),
          ],
        ],
      ),
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({required this.view, this.onOperation});
  final DailyLedgerView view;
  final ValueChanged<LedgerFeedLine>? onOperation;

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'حركة الدفتر',
    subtitle: 'عمليات أكدها الخادم',
    icon: Icons.receipt_long_outlined,
    child: view.feed.isEmpty
        ? const Text('لا توجد عمليات معروضة حتى الآن.')
        : Column(
            children: [
              for (final line in view.feed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.check)),
                  title: Row(
                    children: [
                      Text(line.labelAr),
                      if (line.hasNote) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.sticky_note_2_outlined,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                          semanticLabel: 'توجد ملاحظة',
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    '${line.actorDisplayName} · ${formatServerCairoTimestamp(line.occurredAtCairo)}',
                  ),
                  onTap: onOperation == null ? null : () => onOperation!(line),
                  trailing: onOperation == null
                      ? null
                      : const Icon(Icons.chevron_left),
                ),
            ],
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
        padding: const EdgeInsets.all(20),
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
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
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
