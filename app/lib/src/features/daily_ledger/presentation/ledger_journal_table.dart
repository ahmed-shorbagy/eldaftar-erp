import 'package:flutter/material.dart';

import '../../../theme/amount_format.dart';
import '../../../theme/app_theme.dart';
import '../application/daily_ledger_view.dart';
import '../application/ledger_line_items.dart';
import 'opening_copy.dart';

const _previewItemCount = 3;

/// Horizontal item table for one confirmed operation.
///
/// Structured items come from [loadItems]. A missing or failed read does not
/// turn the lossy item summary into rows.
class LedgerOperationTable extends StatefulWidget {
  const LedgerOperationTable({
    super.key,
    required this.line,
    this.loadItems,
    this.onOpen,
    this.position = 1,
  });

  final LedgerFeedLine line;
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
        oldWidget.line.kind != widget.line.kind) {
      _items = null;
      _failed = false;
      _showAllItems = false;
      _load();
    } else if (oldWidget.loadItems != widget.loadItems) {
      // A ledger refresh: re-read quietly and keep the shown rows meanwhile.
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
          'customer_return',
          'scrap_sale',
        }.contains(widget.line.kind)) {
      _loading = false;
      return;
    }
    final hadItems = _items != null;
    setState(() {
      _loading = !hadItems;
      _failed = false;
    });
    try {
      final items = await load(widget.line.operationId);
      if (!mounted || generation != _readGeneration) return;
      setState(() {
        if (items != null || !hadItems) _items = items;
        _failed = items == null && !hadItems;
      });
    } catch (_) {
      if (mounted && generation == _readGeneration && !hadItems) {
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
        : items.take(_previewItemCount).toList();
    final time = formatShopTwelveHourTime(line.displayTime);
    final cardBorder = AppSemanticColors.of(context).ledgerCardBorder;
    final partyName = line.partyName?.trim();
    final partyPhone = line.partyPhone?.trim();
    final hasPartyName = partyName != null && partyName.isNotEmpty;
    final hasPartyPhone = partyPhone != null && partyPhone.isNotEmpty;
    final metaStyle = theme.textTheme.labelSmall?.copyWith(
      color: scheme.onSurfaceVariant,
      height: 1.3,
    );
    final showNote = line.hasNote && !line.isDailyNote;
    final summary = line.itemSummary?.trim();
    final expenseDescription =
        line.kind == 'expense' && summary != null && summary.isNotEmpty
        ? summary
        : null;
    // Prices are all-or-none per invoice; without them the card total stands.
    final priced = items?.any((item) => item.linePricePounds != null) ?? false;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: Material(
        color: scheme.surfaceContainerLow,
        elevation: widget.onOpen == null ? 0 : 0.5,
        shadowColor: scheme.shadow.withValues(alpha: 0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: cardBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: Key('ledger-open-${line.kind}-${line.operationId}'),
          onTap: widget.onOpen,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: scheme.primary.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  child: Text(
                                    '${widget.position}',
                                    key: Key(
                                      'ledger-seq-${line.kind}-${line.operationId}',
                                    ),
                                    textDirection: TextDirection.ltr,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              if (showNote)
                                PositionedDirectional(
                                  top: -3,
                                  end: -3,
                                  child: Semantics(
                                    label: 'فيها ملاحظة',
                                    child: Tooltip(
                                      message: 'فيها ملاحظة',
                                      child: Container(
                                        key: Key(
                                          'ledger-note-dot-${line.kind}-${line.operationId}',
                                        ),
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: scheme.error,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: scheme.surfaceContainerLow,
                                            width: 2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  line.labelAr,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${actorLabel(line.kind)}: ${line.actorDisplayName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: metaStyle,
                                ),
                                // U5: what the expense was for.
                                if (expenseDescription != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'الوصف: ${isolateText(expenseDescription)}',
                                    key: Key(
                                      'ledger-expense-description-${line.operationId}',
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: metaStyle,
                                  ),
                                ],
                                if (hasPartyName) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'العميل: $partyName',
                                    key: Key(
                                      'ledger-party-name-${line.kind}-${line.operationId}',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: metaStyle,
                                  ),
                                ],
                                if (hasPartyPhone) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'الجوال: \u2066$partyPhone\u2069',
                                    key: Key(
                                      'ledger-party-phone-${line.kind}-${line.operationId}',
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: metaStyle,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (line.totalPounds != null)
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 128,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: Text(
                                    displayPounds(line.totalPounds!),
                                    maxLines: 1,
                                    textDirection: TextDirection.ltr,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                  ),
                                ),
                              ),
                            if (widget.onOpen != null) ...[
                              const SizedBox(width: 8),
                              Material(
                                key: Key(
                                  'ledger-open-btn-${line.kind}-${line.operationId}',
                                ),
                                color: scheme.primaryContainer,
                                elevation: 1,
                                shadowColor: scheme.shadow.withValues(
                                  alpha: 0.18,
                                ),
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: widget.onOpen,
                                  child: SizedBox(
                                    width: 36,
                                    height: 36,
                                    child: Icon(
                                      Icons.keyboard_arrow_left_rounded,
                                      size: 22,
                                      color: scheme.onPrimaryContainer,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          time,
                          key: Key(
                            'ledger-time-${line.kind}-${line.operationId}',
                          ),
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ],
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
                                0: FlexColumnWidth(),
                                1: FixedColumnWidth(52 * scale),
                                2: FixedColumnWidth(72 * scale),
                                if (priced) 3: FixedColumnWidth(88 * scale),
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
                                    if (priced)
                                      _cell(
                                        context,
                                        'السعر',
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
                                      if (priced)
                                        _cell(
                                          context,
                                          item.linePricePounds == null
                                              ? '—'
                                              : displayPounds(
                                                  item.linePricePounds!,
                                                ),
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
                if (items != null && items.length > _previewItemCount)
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
                      label: Text(_showAllItems ? 'إظهار أقل' : 'إظهار المزيد'),
                    ),
                  ),
                if (items == null &&
                    !_loading &&
                    expenseDescription == null &&
                    line.itemSummary != null)
                  Text(line.itemSummary!, style: theme.textTheme.bodySmall),
              ],
            ),
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

/// U8 (ADR 0047 D8): on a sale the staff member is the seller; on a purchase
/// or any other entry the seller is the customer, so name the recorder.
String actorLabel(String kind) =>
    kind == 'sale' || kind == 'scrap_sale' ? 'اسم البائع' : 'المسجِّل';
