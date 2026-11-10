import 'package:flutter/material.dart';

import '../../../theme/amount_format.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_tokens.dart';
import '../../daily_ledger/domain/opening_issue.dart';
import '../../daily_ledger/domain/quantities.dart';
import '../../daily_ledger/presentation/ledger_balance_sections.dart';
import '../domain/inventory_item_grid.dart';

/// Pooled opening stock has no item name; the table says so plainly.
String inventoryGridItemLabel(String name) =>
    name == 'رصيد افتتاحي مجمّع' ? 'رصيد افتتاحي (بدون صنف)' : name;

String _count(BigInt value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

/// Six figures at the top of «الجرد الفوري», like the ledger home figures.
class InventoryInsightsStrip extends StatelessWidget {
  const InventoryInsightsStrip({super.key, required this.insights});

  final InventoryInsights insights;

  @override
  Widget build(BuildContext context) {
    final cash = Piastres.parseWire(insights.cashPiastres.toString());
    final tiles = <Widget>[
      LedgerMetricTile(
        key: const Key('inventory-insight-worked'),
        compact: true,
        label: 'وزن المشغولات',
        value: displayGrams(insights.workedMilligrams.toString()),
        unit: 'جرام',
        icon: Icons.diamond_outlined,
        tone: LedgerMetricTone.primary,
      ),
      LedgerMetricTile(
        key: const Key('inventory-insight-pieces'),
        compact: true,
        label: 'عدد القطع',
        value: insights.workedCountKnown ? _count(insights.workedCount) : '—',
        unit: 'قطعة',
        icon: Icons.format_list_numbered,
        tone: LedgerMetricTone.primary,
      ),
      LedgerMetricTile(
        key: const Key('inventory-insight-scrap'),
        compact: true,
        label: 'الكسر',
        value: displayGrams(insights.scrapMilligrams.toString()),
        unit: 'جرام',
        icon: Icons.content_cut_outlined,
        tone: LedgerMetricTone.negative,
      ),
      LedgerMetricTile(
        key: const Key('inventory-insight-bullion'),
        compact: true,
        label: 'السبائك',
        value: displayGrams(insights.bullionMilligrams.toString()),
        unit: 'جرام',
        icon: Icons.view_in_ar_outlined,
        tone: LedgerMetricTone.neutral,
      ),
      LedgerMetricTile(
        key: const Key('inventory-insight-coins'),
        compact: true,
        label: 'الجنيهات',
        value: _count(insights.coinCount),
        unit: 'قطعة',
        icon: Icons.monetization_on_outlined,
        tone: LedgerMetricTone.neutral,
      ),
      LedgerMetricTile(
        key: const Key('inventory-insight-cash'),
        compact: true,
        label: 'النقدية',
        value: cash is Accepted<Piastres>
            ? displayPounds(cash.value.poundsText)
            : '—',
        unit: 'جنيه',
        icon: Icons.payments_outlined,
        tone: LedgerMetricTone.positive,
      ),
    ];
    return LayoutBuilder(
      key: const Key('inventory-insights'),
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 600 ? 3 : 2;
        return Column(
          children: [
            for (var start = 0; start < tiles.length; start += perRow) ...[
              if (start > 0) const SizedBox(height: AppTokens.spaceSm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = start; i < start + perRow; i++) ...[
                    if (i > start) const SizedBox(width: AppTokens.spaceSm),
                    Expanded(
                      child: i < tiles.length ? tiles[i] : const SizedBox(),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}

/// «الأصناف حسب العيار»: item rows, one column per visible karat.
class InventoryItemGridView extends StatelessWidget {
  const InventoryItemGridView({
    super.key,
    required this.grid,
    required this.order,
    required this.expanded,
    required this.onExpanded,
    required this.onOrder,
    required this.onCell,
    this.loading = false,
    this.failed = false,
    this.onRetry,
  });

  final InventoryItemGrid? grid;
  final List<int> order;
  final bool expanded;
  final ValueChanged<bool> onExpanded;
  final VoidCallback onOrder;
  final void Function(String itemName, int karat) onCell;
  final bool loading;
  final bool failed;
  final VoidCallback? onRetry;

  // Four karat columns fit a 375 px phone: 72 + 4 × (58 + 4) = 320.
  static const double cellWidth = 58;
  static const double cellGap = 4;
  static const double minNameWidth = 72;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible = visibleInventoryKarats(order, expanded: expanded);
    final hidden = [
      for (final karat in order)
        if (!visible.contains(karat)) karat,
    ];
    final grid = this.grid;
    return Column(
      key: const Key('inventory-grid'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('الأصناف حسب العيار', style: theme.textTheme.titleMedium),
        const SizedBox(height: AppTokens.spaceSm),
        Wrap(
          spacing: AppTokens.spaceSm,
          runSpacing: AppTokens.spaceSm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
              key: const Key('inventory-grid-more-karats'),
              selected: expanded,
              onSelected: onExpanded,
              label: Text(
                expanded
                    ? 'عيارات أخرى'
                    : 'عيارات أخرى (${order.skip(2).join('، ')})',
              ),
            ),
            TextButton.icon(
              key: const Key('inventory-grid-order'),
              onPressed: onOrder,
              icon: const Icon(Icons.reorder),
              label: const Text('ترتيب العيارات'),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceSm),
        if (loading && grid == null)
          const LinearProgressIndicator()
        else if (failed && grid == null)
          Row(
            children: [
              const Expanded(
                child: Text('تعذر تحميل جدول الأصناف. أعد المحاولة.'),
              ),
              TextButton(
                key: const Key('inventory-grid-retry'),
                onPressed: onRetry,
                child: const Text('إعادة المحاولة'),
              ),
            ],
          )
        else if (grid == null)
          Text(
            'لا توجد أصناف متاحة في المخزون.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final cellsWidth = visible.length * (cellWidth + cellGap);
              final fits = constraints.maxWidth - cellsWidth >= minNameWidth;
              final nameWidth = fits
                  ? constraints.maxWidth - cellsWidth
                  : minNameWidth;
              final table = _Table(
                grid: grid,
                karats: visible,
                nameWidth: nameWidth,
                onCell: onCell,
              );
              if (fits) return table;
              return SingleChildScrollView(
                key: const Key('inventory-grid-scroll'),
                scrollDirection: Axis.horizontal,
                child: table,
              );
            },
          ),
        if (hidden.isNotEmpty && grid != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'عيار ${hidden.join('، ')} مخفي. اضغط «عيارات أخرى» لإظهاره.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({
    required this.grid,
    required this.karats,
    required this.nameWidth,
    required this.onCell,
  });

  final InventoryItemGrid grid;
  final List<int> karats;
  final double nameWidth;
  final void Function(String itemName, int karat) onCell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final border = AppSemanticColors.of(context).tableBorder;
    const cellWidth = InventoryItemGridView.cellWidth;

    Widget row({
      required Key key,
      required Widget name,
      required List<Widget> cells,
      bool top = false,
    }) => Container(
      key: key,
      decoration: BoxDecoration(
        border: Border(
          top: top
              ? BorderSide(color: scheme.outlineVariant, width: 1.5)
              : BorderSide.none,
          bottom: BorderSide(color: border),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: nameWidth, child: name),
          for (final cell in cells) ...[
            const SizedBox(width: InventoryItemGridView.cellGap),
            SizedBox(width: cellWidth, child: cell),
          ],
        ],
      ),
    );

    Widget value({
      required String count,
      required String grams,
      bool bold = false,
    }) => Column(
      children: [
        Text(
          count,
          textDirection: TextDirection.ltr,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            grams,
            textDirection: TextDirection.ltr,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: bold ? FontWeight.w700 : null,
            ),
          ),
        ),
      ],
    );

    String countOf(InventoryGridCell cell) =>
        cell.countKnown ? _count(cell.count) : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(
          key: const Key('inventory-grid-header'),
          name: Text('الصنف', style: theme.textTheme.labelLarge),
          cells: [
            for (final karat in karats)
              Column(
                children: [
                  Text(
                    'عيار $karat',
                    // onSurface keeps AA contrast for small labels.
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'عدد · وزن',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
          ],
        ),
        for (final item in grid.rows)
          row(
            key: Key('inventory-grid-row-${item.itemName}'),
            name: Text(
              inventoryGridItemLabel(item.itemName),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
            cells: [
              for (final karat in karats)
                item.cells[karat] == null ||
                        item.cells[karat]!.milligrams == BigInt.zero
                    ? Center(
                        key: Key('inventory-grid-cell-${item.itemName}-$karat'),
                        child: value(count: '0', grams: '0.00'),
                      )
                    : InkWell(
                        key: Key('inventory-grid-cell-${item.itemName}-$karat'),
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => onCell(item.itemName, karat),
                        child: value(
                          count: countOf(item.cells[karat]!),
                          grams: displayGrams(
                            item.cells[karat]!.milligrams.toString(),
                          ),
                        ),
                      ),
            ],
          ),
        row(
          key: const Key('inventory-grid-scrap'),
          name: Text('كسر', style: theme.textTheme.bodyMedium),
          cells: [
            for (final karat in karats)
              grid.scrapByKarat[karat] == null
                  ? const SizedBox()
                  : value(
                      count: '—',
                      grams: displayGrams(grid.scrapByKarat[karat]!.toString()),
                    ),
          ],
        ),
        row(
          key: const Key('inventory-grid-total'),
          top: true,
          name: Text(
            'الإجمالي',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          cells: [
            for (final karat in karats)
              grid.totals[karat] == null
                  ? const SizedBox()
                  : value(
                      count: countOf(grid.totals[karat]!),
                      grams: displayGrams(
                        grid.totals[karat]!.milligrams.toString(),
                      ),
                      bold: true,
                    ),
          ],
        ),
      ],
    );
  }
}

/// Bottom sheet to reorder the four karats. Returns the new order or null.
Future<List<int>?> showInventoryKaratOrder(
  BuildContext context,
  List<int> current,
) {
  Widget body(BuildContext context) =>
      _KaratOrderSheet(initial: List<int>.from(current));
  if (MediaQuery.sizeOf(context).width >= 600) {
    return showDialog<List<int>>(
      context: context,
      builder: (context) =>
          Dialog(child: SizedBox(width: 420, child: body(context))),
    );
  }
  return showModalBottomSheet<List<int>>(
    context: context,
    isScrollControlled: true,
    builder: body,
  );
}

class _KaratOrderSheet extends StatefulWidget {
  const _KaratOrderSheet({required this.initial});

  final List<int> initial;

  @override
  State<_KaratOrderSheet> createState() => _KaratOrderSheetState();
}

class _KaratOrderSheetState extends State<_KaratOrderSheet> {
  late List<int> _order = widget.initial;

  void _move(int index, int by) {
    final to = index + by;
    if (to < 0 || to >= _order.length) return;
    setState(() {
      final next = [..._order];
      final value = next.removeAt(index);
      next.insert(to, value);
      _order = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Column(
          key: const Key('inventory-karat-order-sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ترتيب العيارات', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'أول عيارين يظهران دائمًا.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            for (var i = 0; i < _order.length; i++)
              ListTile(
                key: Key('inventory-karat-order-${_order[i]}'),
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 14,
                  child: Text('${i + 1}', style: theme.textTheme.labelMedium),
                ),
                title: Text('عيار ${_order[i]}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      key: Key('inventory-karat-up-${_order[i]}'),
                      tooltip: 'تقديم عيار ${_order[i]}',
                      onPressed: i == 0 ? null : () => _move(i, -1),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      key: Key('inventory-karat-down-${_order[i]}'),
                      tooltip: 'تأخير عيار ${_order[i]}',
                      onPressed: i == _order.length - 1
                          ? null
                          : () => _move(i, 1),
                      icon: const Icon(Icons.arrow_downward),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppTokens.spaceSm),
            Wrap(
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceSm,
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  key: const Key('inventory-karat-order-default'),
                  onPressed: () => setState(
                    () => _order = List<int>.from(inventoryDefaultKaratOrder),
                  ),
                  child: const Text('الترتيب الافتراضي'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  key: const Key('inventory-karat-order-save'),
                  onPressed: () => Navigator.of(context).pop(_order),
                  child: const Text('حفظ'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
