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
  });

  final LedgerFeedLine line;
  final bool showDetails;
  final Future<List<LedgerLineItem>?> Function(String operationId)? loadItems;
  final VoidCallback? onOpen;

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
        oldWidget.loadItems != widget.loadItems) {
      _items = null;
      _failed = false;
      _showAllItems = false;
      _load();
    }
  }

  Future<void> _load() async {
    final load = widget.loadItems;
    final generation = ++_readGeneration;
    if (load == null ||
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
    final line = widget.line;
    final border = AppSemanticColors.of(context).tableBorder;
    final items = _items;
    final visible = items == null
        ? const <LedgerLineItem>[]
        : _showAllItems
        ? items
        : items.take(2).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: widget.onOpen,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    widget.showDetails &&
                            line.partyName != null &&
                            line.partyName!.isNotEmpty
                        ? '${line.labelAr} · ${line.partyName}'
                        : line.labelAr,
                    style: theme.textTheme.titleSmall,
                  ),
                  if (line.totalPounds != null)
                    Text(
                      displayPounds(line.totalPounds!),
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.titleMedium,
                    ),
                  if (widget.onOpen != null)
                    const Icon(Icons.chevron_left, size: 20),
                ],
              ),
            ),
          ),
          if (line.weightGrams != null)
            Text(
              '${displayGrams(line.weightGrams!)} جرام${line.karat == null ? '' : ' · عيار ${line.karat}'}',
              style: theme.textTheme.bodyMedium,
            ),
          if (widget.showDetails)
            Text(
              formatServerCairoTimestamp(line.displayTime),
              style: theme.textTheme.bodySmall,
            ),
          if (line.paymentLabel != null)
            Text(line.paymentLabel!, style: theme.textTheme.bodySmall),
          Text(
            'المسجل: ${line.actorDisplayName}',
            style: theme.textTheme.labelSmall,
          ),
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
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, bounds) {
                final scale = MediaQuery.textScalerOf(context).scale(1);
                final minimum = scale > 1.3 ? 360 * scale : bounds.maxWidth;
                final width = minimum > bounds.maxWidth
                    ? minimum
                    : bounds.maxWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: Table(
                      border: TableBorder.all(color: border, width: 1),
                      columnWidths: const {
                        0: FlexColumnWidth(3),
                        1: FlexColumnWidth(1.6),
                        2: FlexColumnWidth(2.6),
                        3: FlexColumnWidth(1.7),
                      },
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          children: [
                            for (final label in const [
                              'الصنف',
                              'العيار',
                              'الوزن',
                              'العدد',
                            ])
                              _cell(context, label, heading: true),
                          ],
                        ),
                        for (final item in visible)
                          TableRow(
                            children: [
                              _cell(context, item.name),
                              _cell(
                                context,
                                item.karat == null ? '—' : '${item.karat}',
                              ),
                              _cell(
                                context,
                                '${displayGrams(item.grams)} جرام',
                              ),
                              _cell(context, item.count ?? '—'),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
          if (items != null && items.length > 2)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: Key('ledger-items-more-${line.kind}-${line.operationId}'),
                onPressed: () => setState(() => _showAllItems = !_showAllItems),
                child: Text(_showAllItems ? 'عرض أقل' : 'عرض المزيد'),
              ),
            ),
          if (items == null && !_loading && line.itemSummary != null)
            Text(
              [
                line.itemSummary!,
                if (line.pieceCount != null) 'عدد القطع: ${line.pieceCount}',
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            )
          else if (line.pieceCount != null && (items == null || items.isEmpty))
            Text(
              'عدد القطع: ${line.pieceCount}',
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

Widget _cell(BuildContext context, String text, {bool heading = false}) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
    child: Text(
      text,
      style: heading ? theme.textTheme.labelLarge : theme.textTheme.bodyMedium,
    ),
  );
}
