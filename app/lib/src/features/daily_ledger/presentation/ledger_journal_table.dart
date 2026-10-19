import 'package:flutter/material.dart';

import '../../../theme/amount_format.dart';
import '../../../theme/app_theme.dart';
import '../application/daily_ledger_view.dart';
import '../application/ledger_line_items.dart';
import 'opening_copy.dart';

/// Horizontal item table for one confirmed operation.
///
/// Structured items come from [loadItems]. A missing or failed read does not
/// turn the lossy item summary into rows.
class LedgerOperationTable extends StatefulWidget {
  const LedgerOperationTable({
    super.key,
    required this.line,
    required this.showDetails,
    this.loadItems,
    this.onOpen,
    this.position = 1,
  });

  final LedgerFeedLine line;
  final bool showDetails;
  final Future<List<LedgerLineItem>?> Function(String operationId)? loadItems;
  final VoidCallback? onOpen;

  /// Position within the displayed list, independent of the invoice reference.
  final int position;

  @override
  State<LedgerOperationTable> createState() => _LedgerOperationTableState();
}

class _LedgerOperationTableState extends State<LedgerOperationTable> {
  List<LedgerLineItem>? _items;
  bool _loading = false;
  bool _failed = false;
  bool _showAllItems = false;
  int _readGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant LedgerOperationTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.line.operationId != widget.line.operationId ||
        oldWidget.line.kind != widget.line.kind ||
        oldWidget.loadItems != widget.loadItems ||
        oldWidget.showDetails != widget.showDetails) {
      _items = null;
      _failed = false;
      _showAllItems = false;
      _load();
    }
  }

  Future<void> _load() async {
    final load = widget.loadItems;
    final generation = ++_readGeneration;
    if (!widget.showDetails ||
        load == null ||
        !const {
          'sale',
          'purchase',
          'sale_return',
          'purchase_return',
          'scrap_sale',
        }.contains(widget.line.kind)) {
      _loading = false;
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final items = await load(widget.line.operationId);
      if (!mounted || generation != _readGeneration) return;
      setState(() {
        _items = items;
        _failed = items == null;
      });
    } catch (_) {
      if (mounted && generation == _readGeneration) {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted && generation == _readGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final line = widget.line;
    final border = AppSemanticColors.of(context).tableBorder;
    final items = _items;
    final visible = items == null
        ? const <LedgerLineItem>[]
        : _showAllItems
        ? items
        : items.take(2).toList();
    final time = formatShopTwelveHourTime(line.displayTime);
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppSemanticColors.of(context).ledgerCardBorder,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                key: Key('ledger-open-${line.kind}-${line.operationId}'),
                onTap: widget.onOpen,
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        ...[
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Text(
                                '${widget.position}',
                                key: Key(
                                  'ledger-seq-${line.kind}-${line.operationId}',
                                ),
                                textDirection: TextDirection.ltr,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: Text(
                            line.labelAr,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        if (line.totalPounds != null)
                          Flexible(
                            child: Text(
                              displayPounds(line.totalPounds!),
                              textDirection: TextDirection.ltr,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        if (widget.onOpen != null)
                          IconButton(
                            key: Key(
                              'ledger-open-btn-${line.kind}-${line.operationId}',
                            ),
                            tooltip: 'تفاصيل العملية',
                            onPressed: widget.onOpen,
                            style: IconButton.styleFrom(
                              minimumSize: const Size(48, 48),
                              shape: const CircleBorder(),
                            ),
                            icon: const Icon(Icons.chevron_left),
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'اسم البائع: ${line.actorDisplayName}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        Text(
                          time,
                          key: Key(
                            'ledger-time-${line.kind}-${line.operationId}',
                          ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.showDetails) ...[
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  ),
                if (_failed)
                  TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('تعذر تحميل الأصناف. إعادة المحاولة'),
                  ),
                if (items != null && items.isEmpty)
                  const Text('لا تحتوي العملية على أصناف مفصلة.'),
                if (visible.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, bounds) {
                      final scale = MediaQuery.textScalerOf(context).scale(1);
                      final minimum = scale > 1.3
                          ? 360 * scale
                          : bounds.maxWidth;
                      final width = minimum > bounds.maxWidth
                          ? minimum
                          : bounds.maxWidth;
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: width,
                            child: Table(
                              border: TableBorder(
                                horizontalInside: BorderSide(
                                  color: border.withValues(alpha: 0.45),
                                ),
                              ),
                              columnWidths: {
                                0: const FlexColumnWidth(),
                                1: FixedColumnWidth(52 * scale),
                                2: FixedColumnWidth(72 * scale),
                                3: FixedColumnWidth(44 * scale),
                              },
                              defaultVerticalAlignment:
                                  TableCellVerticalAlignment.middle,
                              children: [
                                TableRow(
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withValues(
                                      alpha: 0.09,
                                    ),
                                  ),
                                  children: [
                                    _cell(context, 'الصنف', heading: true),
                                    _cell(
                                      context,
                                      'العيار',
                                      heading: true,
                                      numeric: true,
                                    ),
                                    _cell(
                                      context,
                                      'الوزن\n(جرام)',
                                      heading: true,
                                      numeric: true,
                                    ),
                                    _cell(
                                      context,
                                      'العدد',
                                      heading: true,
                                      numeric: true,
                                    ),
                                  ],
                                ),
                                for (final item in visible)
                                  TableRow(
                                    children: [
                                      _cell(context, item.name),
                                      _cell(
                                        context,
                                        item.karat == null
                                            ? '—'
                                            : '${item.karat}',
                                        numeric: true,
                                      ),
                                      _cell(
                                        context,
                                        displayGrams(item.grams),
                                        numeric: true,
                                      ),
                                      _cell(
                                        context,
                                        item.count ?? '—',
                                        numeric: true,
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
                if (items != null && items.length > 2)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      key: Key(
                        'ledger-items-more-${line.kind}-${line.operationId}',
                      ),
                      onPressed: () =>
                          setState(() => _showAllItems = !_showAllItems),
                      icon: Icon(
                        _showAllItems ? Icons.expand_less : Icons.expand_more,
                      ),
                      label: Text(_showAllItems ? 'عرض أقل' : 'عرض المزيد'),
                    ),
                  ),
                if (items == null && !_loading && line.itemSummary != null)
                  Text(
                    [
                      line.itemSummary!,
                      if (line.pieceCount != null)
                        'عدد القطع: ${line.pieceCount}',
                    ].join(' · '),
                    style: theme.textTheme.bodySmall,
                  )
                else if (line.pieceCount != null &&
                    (items == null || items.isEmpty))
                  Text(
                    'عدد القطع: ${line.pieceCount}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Widget _cell(
  BuildContext context,
  String text, {
  bool heading = false,
  bool numeric = false,
}) {
  final theme = Theme.of(context);
  return Padding(
    padding: EdgeInsets.symmetric(horizontal: numeric ? 4 : 8, vertical: 6),
    child: Text(
      text,
      textAlign: numeric ? TextAlign.center : TextAlign.start,
      textDirection: numeric && !heading ? TextDirection.ltr : null,
      style: heading ? theme.textTheme.labelLarge : theme.textTheme.bodyMedium,
    ),
  );
}
