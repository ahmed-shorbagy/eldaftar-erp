import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../application/daily_ledger_view.dart';
import '../application/ledger_activity.dart';
import '../application/ledger_home_metrics.dart';
import '../application/ledger_line_items.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/detail_surface.dart';
import 'ledger_balance_sections.dart';
import 'ledger_metric_specs.dart';
import 'ledger_journal_table.dart';
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
    this.canReturn = false,
    this.loadItems,
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
  final bool canReturn;
  final Future<List<LedgerLineItem>?> Function(String operationId)? loadItems;

  @override
  State<ConfirmedLedgerDashboard> createState() =>
      _ConfirmedLedgerDashboardState();
}

class _ConfirmedLedgerDashboardState extends State<ConfirmedLedgerDashboard> {
  static const _sections = ['metrics', 'activity'];
  LedgerMetricLayout _metricLayout = migrateLedgerMetricLayout(null);
  bool _showReturns = true;
  final _visible = <String, bool>{
    for (final section in _sections) section: true,
  };
  final _order = List<String>.of(_sections);
  final _detailRevision = ValueNotifier<int>(0);
  BuildContext? _detailContext;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _detailRevision.value++;
    });
    if (oldWidget.shopId != widget.shopId) {
      _dismissDetails();
      _order.setAll(0, _sections);
      _visible.updateAll((_, _) => true);
      _metricLayout = migrateLedgerMetricLayout(null);
      _showReturns = true;
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
      _metricLayout = migrateLedgerMetricLayout(savedLayout);
      _showReturns = !savedLayout.contains('hidden:returns');
      for (final section in _sections) {
        _visible[section] =
            section == 'metrics' || !savedLayout.contains('hidden:$section');
      }
    });
  }

  void _saveLayout() {
    _detailRevision.value++;
    _layoutEdited = true;
    final key = _preferenceKey;
    final snapshot = [
      ..._order,
      ...encodeLedgerMetricLayout(_metricLayout),
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
      if (mounted && key == _preferenceKey) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'تعذر حفظ تخصيص الدفتر على الجهاز. يسري اختيارك في هذه الجلسة.',
            ),
          ),
        );
      }
    }
  }

  void _move(String section, int direction) {
    final next = _order.indexOf(section) + direction;
    if (next < 0 || next >= _order.length) return;
    setState(() {
      final index = _order.indexOf(section);
      final neighbor = _order[next];
      _order[index] = neighbor;
      _order[next] = section;
    });
    _saveLayout();
  }

  void _dismissDetails() {
    final surface = _detailContext;
    _detailContext = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (surface != null &&
          surface.mounted &&
          ModalRoute.of(surface)?.isCurrent == true) {
        Navigator.of(surface).pop();
      }
    });
  }

  @override
  void dispose() {
    _dismissDetails();
    _detailRevision.dispose();
    super.dispose();
  }

  Future<void> _details(String title, WidgetBuilder builder) async {
    final shop = widget.shopId;
    await showDetailSurface(
      context,
      title: title,
      builder: (surface) {
        _detailContext = surface;
        return ValueListenableBuilder<int>(
          valueListenable: _detailRevision,
          builder: (context, _, child) =>
              widget.ledger == null || widget.shopId != shop
              ? const Text(
                  'بيانات الدفتر غير متاحة. أغلق النافذة وحدّث الصفحة.',
                )
              : builder(surface),
        );
      },
    );
    _detailContext = null;
  }

  void _showCashMethods() =>
      _details('وسائل الدفع', (_) => LedgerCashBreakdown(view: widget.ledger!));

  void _showSoldGold() => _details(
    'ذهب مباع',
    (_) => LedgerSoldGoldBreakdown(view: widget.ledger!),
  );

  void _showAllMetrics() =>
      _details('ملخص الأرقام', (_) => _allMetrics(widget.ledger!));

  Widget _allMetrics(DailyLedgerView view) {
    final values = ledgerMetricValues(view, _metricLayout.normalizationKarat);
    final ids = _metricLayout.availableIds;
    return LayoutBuilder(
      builder: (context, size) {
        final columns = size.maxWidth >= 520
            ? 3
            : size.maxWidth >= 340
            ? 2
            : 1;
        const gap = 10.0;
        final width = columns == 1
            ? size.maxWidth
            : (size.maxWidth - gap * (columns - 1)) / columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'كل خانات ملخص اليوم.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              key: const Key('ledger-all-metrics'),
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final id in ids)
                  SizedBox(width: width, child: _metricTile(id, values[id]!)),
              ],
            ),
          ],
        );
      },
    );
  }

  void _showHistory([String filter = 'all']) => _details(
    'حركة الدفتر',
    (surface) => _ActivitySection(
      key: const Key('ledger-history'),
      view: widget.ledger!,
      lines: widget.activityLines,
      showReturns: _showReturns,
      initialFilter: filter,
      loadingOlder: widget.loadingOlder,
      onLoadOlder: widget.onLoadOlder,
      loadItems: widget.loadItems,
      onOperation: widget.onOperation == null
          ? null
          : (line) {
              Navigator.of(surface).pop();
              widget.onOperation!(line);
            },
    ),
  );

  Widget _customization(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LedgerNormalizationControl(
          value: _metricLayout.normalizationKarat,
          onChanged: (karat) {
            setState(
              () => _metricLayout = _metricLayout.copyWith(
                normalizationKarat: karat,
              ),
            );
            _saveLayout();
          },
        ),
        const SizedBox(height: 16),
        Text('الأرقام الظاهرة', style: theme.textTheme.titleMedium),
        Text(
          'اختر ست خانات للملخص. تظهر بقية الأرقام في المزيد.',
          style: theme.textTheme.bodySmall,
        ),
        for (final (slot, id) in _metricLayout.homeIds.indexed) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: ValueKey('ledger-slot-$slot-$id'),
            initialValue: id,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'الخانة ${slot + 1}'),
            items: [
              for (final metric in _metricLayout.availableIds)
                DropdownMenuItem(
                  value: metric,
                  child: Text(ledgerMetricLabel(metric)),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(
                () => _metricLayout = selectMetricForSlot(
                  _metricLayout,
                  slot,
                  value,
                ),
              );
              _saveLayout();
            },
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'عيارات الكسر في الملخص وإدخال العمليات الجديدة',
          style: theme.textTheme.titleSmall,
        ),
        for (final karat in [14, 22])
          SwitchListTile(
            key: Key('ledger-scrap-karat-$karat'),
            title: Text('إظهار كسر عيار $karat'),
            value: !_metricLayout.hiddenScrapKarats.contains(karat),
            onChanged: (shown) {
              final hidden = {..._metricLayout.hiddenScrapKarats};
              if (shown) {
                hidden.remove(karat);
              } else {
                hidden.add(karat);
              }
              setState(
                () => _metricLayout = _metricLayout.copyWith(
                  hiddenScrapKarats: hidden,
                ),
              );
              _saveLayout();
            },
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
        for (final section in _order.where((s) => s != 'metrics'))
          _SectionControl(
            section: section,
            visible: _visible[section]!,
            first: _order.where((s) => s != 'metrics').first == section,
            last: _order.where((s) => s != 'metrics').last == section,
            onChanged: (value) {
              setState(() => _visible[section] = value);
              _saveLayout();
            },
            onUp: () => _move(section, -1),
            onDown: () => _move(section, 1),
          ),
      ],
    );
  }

  Widget _metrics(DailyLedgerView view) {
    final values = ledgerMetricValues(view, _metricLayout.normalizationKarat);
    final shown = _metricLayout.homeIds;
    return LayoutBuilder(
      builder: (context, size) {
        final minimum = size.maxWidth < 390 ? 148.0 : 168.0;
        var width = minimum;
        for (final id in shown) {
          final needed = _metricWidth(
            context,
            values[id]!.value,
            minimum,
            label: values[id]!.label,
            hasAction: id == 'total_cash' || id == 'sale_gold',
          );
          if (needed > width) width = needed;
        }
        return SingleChildScrollView(
          key: const Key('ledger-metric-strip'),
          scrollDirection: Axis.horizontal,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final id in shown)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: SizedBox(
                      width: width,
                      child: _metricTile(id, values[id]!),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _metricTile(String id, LedgerMetricSpec spec) {
    final open = switch (id) {
      'total_cash' => (
        onOpen: _showCashMethods,
        tooltip: 'وسائل الدفع',
        key: const Key('ledger-cash-methods'),
      ),
      'sale_gold' => (
        onOpen: _showSoldGold,
        tooltip: 'أوزان الذهب المباع',
        key: const Key('ledger-sale-gold-weights'),
      ),
      _ => null,
    };
    return LedgerMetricTile(
      key: Key(id == 'total_cash' ? 'ledger-total-cash' : 'ledger-metric-$id'),
      label: spec.label,
      value: spec.value,
      unit: spec.unit,
      icon: spec.icon,
      tone: spec.tone,
      compact: true,
      onOpen: open?.onOpen,
      openTooltip: open?.tooltip,
      openKey: open?.key,
    );
  }

  double _metricWidth(
    BuildContext context,
    String value,
    double minimum, {
    required String label,
    required bool hasAction,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final width = painter.width + 24;
    painter.dispose();
    final header = TextPainter(
      text: TextSpan(
        text: label,
        style: Theme.of(context).textTheme.labelLarge,
      ),
      textDirection: TextDirection.rtl,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final headerWidth = header.width + (hasAction ? 110 : 62);
    header.dispose();
    return [width, headerWidth, minimum].reduce((a, b) => a > b ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.ledger;
    if (view == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return LedgerQuickActions(
      shopId: widget.shopId,
      enabled: [
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
          for (final section in [
            'metrics',
            ..._order.where((s) => s != 'metrics'),
          ])
            if (_visible[section]!) ...[
              if (section == 'metrics') ...[
                KeyedSubtree(
                  key: const Key('ledger-confirmed-status'),
                  child: _metrics(view),
                ),
                Row(
                  children: [
                    TextButton.icon(
                      key: const Key('ledger-more-metrics'),
                      onPressed: _showAllMetrics,
                      icon: const Icon(Icons.grid_view_rounded, size: 18),
                      label: const Text('عرض المزيد'),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      key: const Key('ledger-customize'),
                      tooltip: 'إعدادات الملخص',
                      visualDensity: VisualDensity.compact,
                      iconSize: 20,
                      onPressed: () =>
                          _details('إعدادات الملخص', _customization),
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
                if (widget.dayClosed) ...[
                  const SizedBox(height: 8),
                  Text(
                    'يوم العمل مغلق',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
              if (section == 'activity') ...[
                const SizedBox(height: 12),
                _JournalPreview(
                  rows: widget.activityLines ?? view.feed,
                  onViewAll: _showHistory,
                  onOperation: widget.onOperation,
                  onSale: widget.onSale,
                  onPurchase: widget.onPurchase,
                  loadItems: widget.loadItems,
                ),
                if (_showReturns)
                  _CompactBookRow(
                    label: 'دفتر المرتجعات',
                    book: 'returns',
                    count:
                        view.journalContext?.returnCount ??
                        (view.feedCursor?.hasMore == true
                            ? null
                            : view.feed.where((line) => line.isReturn).length),
                    alert: true,
                    onTap: () => _showHistory('return'),
                  ),
                _CompactBookRow(
                  label: 'المصروفات',
                  book: 'expenses',
                  count: view.daySummary?.expenseCount,
                  onTap: () => _showHistory('expense'),
                ),
                _CompactBookRow(
                  label: 'الملاحظات',
                  book: 'notes',
                  count:
                      view.journalContext?.noteCount ??
                      (view.feedCursor?.hasMore == true
                          ? null
                          : view.feed.where((line) => line.isDailyNote).length),
                  onTap: widget.onDailyNotes,
                ),
              ],
            ],
          if (!_visible['activity']!)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: _showHistory,
                child: const Text('عرض حركة الدفتر'),
              ),
            ),
        ],
      ),
    );
  }
}

class _CompactBookRow extends StatelessWidget {
  const _CompactBookRow({
    required this.label,
    required this.book,
    required this.count,
    this.alert = false,
    this.onTap,
  });
  final String label, book;
  final int? count;
  final bool alert;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final attention = alert && count != null && count! > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          key: Key('ledger-book-$book'),
          title: Text(label),
          leading: Semantics(
            label: count == null ? 'العدد غير متاح' : '$count',
            child: Container(
              constraints: const BoxConstraints(minWidth: 36),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: attention
                    ? scheme.errorContainer
                    : scheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                count?.toString() ?? '—',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: attention
                      ? scheme.onErrorContainer
                      : scheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          onTap: onTap,
        ),
      ),
    );
  }
}

/// Separate, bounded journals keep the owner's books visible on home.
class _JournalPreview extends StatefulWidget {
  const _JournalPreview({
    required this.rows,
    required this.onViewAll,
    this.onOperation,
    this.onSale,
    this.onPurchase,
    this.loadItems,
  });
  final List<LedgerFeedLine> rows;
  final void Function([String filter]) onViewAll;
  final ValueChanged<LedgerFeedLine>? onOperation;
  final VoidCallback? onSale;
  final VoidCallback? onPurchase;
  final Future<List<LedgerLineItem>?> Function(String operationId)? loadItems;

  @override
  State<_JournalPreview> createState() => _JournalPreviewState();
}

class _JournalPreviewState extends State<_JournalPreview> {
  bool _newestFirst = true;
  final _details = <String, bool>{};

  @override
  Widget build(BuildContext context) {
    final ordered = sortLedgerHistory(widget.rows, newestFirst: _newestFirst);
    final journals = <(String, String, List<LedgerFeedLine>, VoidCallback?)>[
      (
        'sale',
        'دفتر البيع',
        ordered.where((e) => e.kind == 'sale').toList(),
        widget.onSale,
      ),
      (
        'purchase',
        'دفتر الشراء',
        ordered.where((e) => e.kind == 'purchase').toList(),
        widget.onPurchase,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Wrap(
            key: const Key('ledger-journal-sort'),
            spacing: 6,
            runSpacing: 6,
            children: [
              _ledgerFilterChip(
                context,
                label: 'الأحدث',
                selected: _newestFirst,
                onSelected: () => setState(() => _newestFirst = true),
              ),
              _ledgerFilterChip(
                context,
                label: 'الأقدم',
                selected: !_newestFirst,
                onSelected: () => setState(() => _newestFirst = false),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (final (index, journal) in journals.indexed) ...[
          if (index > 0)
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 24),
              child: Divider(
                key: const Key('ledger-journal-divider'),
                height: 1,
                thickness: 1.5,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          Padding(
            padding: EdgeInsets.only(
              bottom: index == journals.length - 1 ? 24 : 4,
            ),
            child: Column(
              key: Key('ledger-journal-${journal.$1}'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        journal.$2,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (journal.$3.isNotEmpty)
                      IconButton(
                        key: Key('ledger-journal-details-${journal.$1}'),
                        tooltip: (_details[journal.$1] ?? false)
                            ? 'إخفاء التفاصيل'
                            : 'عرض التفاصيل',
                        visualDensity: VisualDensity.compact,
                        iconSize: 20,
                        onPressed: () => setState(
                          () => _details[journal.$1] =
                              !(_details[journal.$1] ?? false),
                        ),
                        icon: Icon(
                          (_details[journal.$1] ?? false)
                              ? Icons.unfold_less_rounded
                              : Icons.unfold_more_rounded,
                        ),
                      ),
                    TextButton(
                      key: Key('ledger-journal-all-${journal.$1}'),
                      onPressed: () => widget.onViewAll(journal.$1),
                      child: const Text('عرض الكل'),
                    ),
                  ],
                ),
                if (journal.$3.isEmpty)
                  _JournalEmptyState(book: journal.$1, onAdd: journal.$4)
                else ...[
                  if (journal.$4 != null) ...[
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FilledButton.tonalIcon(
                        key: Key(
                          journal.$1 == 'sale'
                              ? 'ledger-new-sale'
                              : 'ledger-new-purchase',
                        ),
                        onPressed: journal.$4,
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(
                          journal.$1 == 'sale' ? 'إضافة بيع' : 'إضافة شراء',
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  for (final (row, line)
                      in journal.$3
                          .take(journal.$1 == 'return' ? 1 : 3)
                          .indexed)
                    LedgerOperationTable(
                      key: ValueKey('${line.kind}-${line.operationId}'),
                      line: line,
                      position: row + 1,
                      showDetails: _details[journal.$1] ?? false,
                      loadItems: widget.loadItems,
                      onOpen: widget.onOperation == null
                          ? null
                          : () => widget.onOperation!(line),
                    ),
                ],
              ],
            ),
          ),
        ],
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton.icon(
            key: const Key('ledger-other-movements'),
            onPressed: () => widget.onViewAll(),
            icon: const Icon(Icons.history),
            label: const Text('عرض حركة الدفتر', key: Key('ledger-view-all')),
          ),
        ),
      ],
    );
  }
}

class _OperationsPanel extends StatelessWidget {
  const _OperationsPanel({
    required this.dayClosed,
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
  final VoidCallback? onExpense,
      onCashTransfer,
      onScrapSale,
      onScrapToStock,
      onCloseDay,
      onOpenDay,
      onPendingInvoices,
      onDailyNotes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actions = <(String, IconData, VoidCallback?, String)>[
      if (!dayClosed) ...[
        ('مصروف', Icons.receipt_long_outlined, onExpense, 'ledger-new-expense'),
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
      ] else
        (
          'فتح يوم جديد',
          Icons.lock_open_outlined,
          onOpenDay,
          'ledger-open-day',
        ),
      (
        'ملاحظات اليوم',
        Icons.sticky_note_2_outlined,
        onDailyNotes,
        'ledger-daily-notes',
      ),
    ].where((a) => a.$3 != null).toList();
    final dayActions = <(String, IconData, VoidCallback?, String)>[
      (
        'الفواتير المعلقة',
        Icons.mark_email_unread_outlined,
        onPendingInvoices,
        'ledger-pending-invoices',
      ),
      (
        'تقفيل اليومية',
        Icons.lock_clock_outlined,
        onCloseDay,
        'ledger-close-day',
      ),
    ].where((a) => a.$3 != null).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (dayClosed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('اليوم مغلق', style: theme.textTheme.titleSmall),
          ),
        LayoutBuilder(
          builder: (context, bounds) {
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final columns = scale > 1.5 || bounds.maxWidth < 260
                ? 1
                : bounds.maxWidth >= 600
                ? 3
                : 2;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final action in actions)
                  SizedBox(
                    width: (bounds.maxWidth - 12 * (columns - 1)) / columns,
                    child: OutlinedButton(
                      key: Key(action.$4),
                      onPressed: action.$3,
                      style: OutlinedButton.styleFrom(
                        backgroundColor: theme.colorScheme.primary.withValues(
                          alpha: 0.06,
                        ),
                        side: BorderSide(
                          color: AppSemanticColors.of(context).goldFrame,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 16,
                        ),
                        minimumSize: const Size(48, 88),
                      ),
                      child: Column(
                        children: [
                          Icon(action.$2, size: 24),
                          const SizedBox(height: 8),
                          Text(action.$1, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (dayActions.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Divider(),
          for (final action in dayActions)
            ListTile(
              key: Key(action.$4),
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              leading: Icon(action.$2, color: theme.colorScheme.primary),
              title: Text(action.$1),
              trailing: const Icon(Icons.chevron_left),
              onTap: action.$3,
            ),
        ],
      ],
    );
  }
}

String _label(String section) => switch (section) {
  'metrics' => 'ملخص الأرقام',
  'total_cash' ||
  'sale' ||
  'purchase' ||
  'sale_gold' ||
  'purchase_gold' ||
  'expense' => ledgerMetricLabel(section),
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
  final ValueChanged<bool>? onChanged;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: onChanged == null
            ? ListTile(
                key: Key('ledger-show-$section'),
                contentPadding: EdgeInsets.zero,
                title: Text(_label(section)),
              )
            : SwitchListTile.adaptive(
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

class _ActivitySection extends StatefulWidget {
  const _ActivitySection({
    super.key,
    required this.view,
    this.lines,
    this.onOperation,
    this.onLoadOlder,
    this.loadingOlder = false,
    this.showReturns = true,
    this.initialFilter = 'all',
    this.loadItems,
  });
  final String initialFilter;
  final bool showReturns;
  final DailyLedgerView view;
  final List<LedgerFeedLine>? lines;
  final ValueChanged<LedgerFeedLine>? onOperation;
  final VoidCallback? onLoadOlder;
  final bool loadingOlder;
  final Future<List<LedgerLineItem>?> Function(String operationId)? loadItems;
  @override
  State<_ActivitySection> createState() => _ActivitySectionState();
}

class _ActivitySectionState extends State<_ActivitySection> {
  late String _filter = widget.initialFilter;
  bool _newestFirst = true;
  bool _showDetails = false;
  @override
  Widget build(BuildContext context) {
    final rows = widget.lines ?? widget.view.feed;
    final filters = <(String, String)>[
      ('all', 'الكل'),
      ('sale', 'دفتر البيع'),
      ('purchase', 'دفتر الشراء'),
      if (widget.showReturns) ('return', 'دفتر المرتجعات'),
      ('expense', 'المصروفات'),
      ('other', 'الحركات الأخرى'),
    ];
    final selected = filters.any((e) => e.$1 == _filter) ? _filter : 'all';
    final filtered = rows
        .where(
          (line) => switch (selected) {
            'sale' => line.kind == 'sale',
            'purchase' => line.kind == 'purchase',
            'return' => line.isReturn,
            'expense' => line.kind == 'expense',
            'other' =>
              line.kind != 'sale' && line.kind != 'purchase' && !line.isReturn,
            _ => true,
          },
        )
        .toList();
    final shown = sortLedgerHistory(filtered, newestFirst: _newestFirst);
    final historyOpen = widget.onLoadOlder != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final filter in filters)
              _ledgerFilterChip(
                context,
                key: Key('ledger-filter-${filter.$1}'),
                label: filter.$2,
                selected: selected == filter.$1,
                onSelected: () => setState(() => _filter = filter.$1),
              ),
            _ledgerFilterChip(
              context,
              key: const Key('ledger-sort-newest'),
              label: 'الأحدث',
              selected: _newestFirst,
              onSelected: () => setState(() => _newestFirst = true),
            ),
            _ledgerFilterChip(
              context,
              key: const Key('ledger-sort-oldest'),
              label: 'الأقدم',
              selected: !_newestFirst,
              onSelected: () => setState(() => _newestFirst = false),
            ),
            IconButton(
              key: const Key('ledger-history-details'),
              tooltip: _showDetails ? 'إخفاء التفاصيل' : 'عرض التفاصيل',
              visualDensity: VisualDensity.compact,
              iconSize: 20,
              onPressed: () => setState(() => _showDetails = !_showDetails),
              icon: Icon(
                _showDetails
                    ? Icons.unfold_less_rounded
                    : Icons.unfold_more_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          historyOpen
              ? 'الترتيب للعمليات المعروضة. حمّل المزيد لعرض عمليات أقدم.'
              : 'ترتيب العمليات المعروضة.',
          key: const Key('ledger-history-order-note'),
        ),
        const SizedBox(height: 16),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('لا توجد عمليات حتى الآن.'),
          ),
        for (final (index, line) in shown.indexed)
          LedgerOperationTable(
            key: ValueKey('${line.kind}-${line.operationId}'),
            line: line,
            position: index + 1,
            showDetails: _showDetails,
            loadItems: widget.loadItems,
            onOpen: widget.onOperation == null
                ? null
                : () => widget.onOperation!(line),
          ),
        if (widget.onLoadOlder != null) ...[
          const SizedBox(height: 16),
          OutlinedButton(
            key: const Key('ledger-load-older'),
            onPressed: widget.loadingOlder ? null : widget.onLoadOlder,
            child: Text(
              widget.loadingOlder
                  ? 'جارٍ تحميل عمليات أقدم'
                  : 'تحميل عمليات أقدم',
            ),
          ),
        ],
      ],
    );
  }
}

class _JournalEmptyState extends StatelessWidget {
  const _JournalEmptyState({required this.book, this.onAdd});

  final String book;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final sale = book == 'sale';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'لا توجد عمليات حتى الآن.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  key: Key(sale ? 'ledger-new-sale' : 'ledger-new-purchase'),
                  onPressed:
                      onAdd ??
                      () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تعذر إضافة العملية الآن.'),
                          ),
                        );
                      },
                  icon: const Icon(Icons.add),
                  label: Text(sale ? 'إضافة بيع' : 'إضافة شراء'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact ledger filter. Filters stay buttons; entry fields stay fields.
ChoiceChip _ledgerFilterChip(
  BuildContext context, {
  Key? key,
  required String label,
  required bool selected,
  required VoidCallback onSelected,
}) {
  final scheme = Theme.of(context).colorScheme;
  return ChoiceChip(
    key: key,
    label: Text(label),
    selected: selected,
    showCheckmark: false,
    visualDensity: const VisualDensity(horizontal: -2, vertical: -4),
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    labelPadding: const EdgeInsets.symmetric(horizontal: 2),
    padding: const EdgeInsets.symmetric(horizontal: 6),
    labelStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
      height: 1.1,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
    ),
    selectedColor: scheme.primaryContainer,
    backgroundColor: scheme.surface.withValues(alpha: 0),
    side: BorderSide(color: selected ? scheme.primary : scheme.outlineVariant),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    onSelected: (_) => onSelected(),
  );
}
