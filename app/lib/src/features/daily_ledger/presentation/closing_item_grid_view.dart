import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../domain/closing_item_grid.dart';
import 'ledger_form_fields.dart';

/// Item-first closing grid shared by the owner and the assigned counter.
class ClosingItemGridView extends StatelessWidget {
  const ClosingItemGridView({
    super.key,
    required this.grid,
    required this.counts,
    required this.weights,
    required this.showWeights,
    required this.onShowWeights,
    this.onAddItem,
    this.readOnly = false,
  });

  final ClosingItemGrid grid;
  final Map<String, TextEditingController> counts;
  final Map<String, TextEditingController> weights;
  final bool showWeights;
  final ValueChanged<bool> onShowWeights;
  final VoidCallback? onAddItem;
  final bool readOnly;

  static String cellKey(String name, int karat) => '$name:$karat';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fields = <({String name, int karat, bool weight, int rowIndex})>[];
    for (var index = 0; index < grid.rows.length; index++) {
      final row = grid.rows[index];
      for (final karat in row.karats) {
        fields.add((
          name: row.name,
          karat: karat,
          weight: false,
          rowIndex: index,
        ));
      }
      if (showWeights) {
        for (final karat in row.karats) {
          fields.add((
            name: row.name,
            karat: karat,
            weight: true,
            rowIndex: index,
          ));
        }
      }
    }
    final columnCount = grid.rows.fold<int>(
      grid.jewelryKarats.length,
      (widest, row) => row.karats.length > widest ? row.karats.length : widest,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // One width for headers, counts and weights so every cell sits under
        // its karat heading.
        final cellWidth = showWeights ? 80.0 : 64.0;
        final cellsWidth = columnCount == 0
            ? 0.0
            : columnCount * cellWidth + columnCount * AppTokens.spaceSm;
        final fits = constraints.maxWidth - cellsWidth >= 48;
        final nameWidth = fits
            ? (constraints.maxWidth - cellsWidth).clamp(48.0, 180.0)
            : 96.0;
        final table = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (grid.jewelryKarats.isNotEmpty)
              Row(
                children: [
                  SizedBox(width: nameWidth),
                  for (final karat in grid.jewelryKarats) ...[
                    const SizedBox(width: AppTokens.spaceSm),
                    SizedBox(
                      width: cellWidth,
                      child: Text(
                        'عيار $karat',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                  ],
                ],
              ),
            for (var index = 0; index < grid.rows.length; index++) ...[
              if (grid.rows[index].category != 'worked_jewelry' &&
                  (index == 0 ||
                      grid.rows[index - 1].category == 'worked_jewelry')) ...[
                const SizedBox(height: AppTokens.spaceSm),
                if (grid.jewelryKarats.isNotEmpty) const Divider(height: 1),
                const SizedBox(height: AppTokens.spaceSm / 2),
                Text(
                  'جنيهات وسبائك',
                  key: const Key('close-other-heading'),
                  style: theme.textTheme.labelLarge,
                ),
              ],
              const SizedBox(height: AppTokens.spaceSm),
              _GridRow(
                row: grid.rows[index],
                index: index,
                nameWidth: nameWidth,
                cellWidth: cellWidth,
                columns: grid.rows[index].category == 'worked_jewelry'
                    ? grid.jewelryKarats
                    : grid.rows[index].karats,
                showWeights: showWeights,
                readOnly: readOnly,
                fields: fields,
                counts: counts,
                weights: weights,
              ),
            ],
          ],
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'اكتب عدد القطع لكل صنف وعيار. الوزن اختياري.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppTokens.spaceSm),
            if (fits)
              table
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: table,
              ),
            if (onAddItem != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  key: const Key('close-add-item'),
                  onPressed: readOnly ? null : onAddItem,
                  child: const Text('إضافة صنف آخر'),
                ),
              ),
            SwitchListTile(
              key: const Key('close-weights-toggle'),
              contentPadding: EdgeInsets.zero,
              title: const Text('إدخال الأوزان (اختياري)'),
              value: showWeights,
              onChanged: readOnly ? null : onShowWeights,
            ),
          ],
        );
      },
    );
  }
}

class _GridRow extends StatelessWidget {
  const _GridRow({
    required this.row,
    required this.index,
    required this.nameWidth,
    required this.cellWidth,
    required this.columns,
    required this.showWeights,
    required this.readOnly,
    required this.fields,
    required this.counts,
    required this.weights,
  });

  final ClosingGridRow row;
  final int index;
  final double nameWidth;
  final double cellWidth;

  /// Karat columns in heading order. A jewelry row follows the table
  /// heading; a coin or bullion row names its own karat.
  final List<int> columns;
  final bool showWeights;
  final bool readOnly;
  final List<({String name, int karat, bool weight, int rowIndex})> fields;
  final Map<String, TextEditingController> counts;
  final Map<String, TextEditingController> weights;

  @override
  Widget build(BuildContext context) {
    Widget cell(int karat, {required bool weight}) {
      return ClosingCountCell(
        fieldKey: Key(
          weight ? 'close-weight-$index-$karat' : 'close-count-$index-$karat',
        ),
        controller: (weight
            ? weights
            : counts)[ClosingItemGridView.cellKey(row.name, karat)]!,
        semanticsLabel: weight
            ? 'وزن ${row.name} عيار $karat'
            : 'عدد ${row.name} عيار $karat',
        readOnly: readOnly,
        weight: weight,
        width: cellWidth,
        // U15: the number pad's ✓ closes the keyboard; it no longer jumps
        // into the next cell, where the owner could type without noticing.
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => FocusScope.of(context).unfocus(),
      );
    }

    final countsRow = Row(
      children: [
        SizedBox(
          width: nameWidth,
          child: Text(
            row.category == 'worked_jewelry'
                ? row.name
                : '${row.name} · عيار ${row.karats.join('، ')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        for (final karat in columns) ...[
          const SizedBox(width: AppTokens.spaceSm),
          row.karats.contains(karat)
              ? cell(karat, weight: false)
              : SizedBox(width: cellWidth),
        ],
      ],
    );
    if (!showWeights) return countsRow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        countsRow,
        const SizedBox(height: AppTokens.spaceSm),
        Row(
          children: [
            SizedBox(width: nameWidth),
            for (final karat in columns) ...[
              const SizedBox(width: AppTokens.spaceSm),
              row.karats.contains(karat)
                  ? cell(karat, weight: true)
                  : SizedBox(width: cellWidth),
            ],
          ],
        ),
      ],
    );
  }
}
