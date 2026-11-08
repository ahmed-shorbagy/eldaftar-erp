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
                      width: 64,
                      child: Text(
                        '$karat',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                  ],
                ],
              ),
            for (var index = 0; index < grid.rows.length; index++) ...[
              const SizedBox(height: AppTokens.spaceSm),
              _GridRow(
                row: grid.rows[index],
                index: index,
                nameWidth: nameWidth,
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
    required this.showWeights,
    required this.readOnly,
    required this.fields,
    required this.counts,
    required this.weights,
  });

  final ClosingGridRow row;
  final int index;
  final double nameWidth;
  final bool showWeights;
  final bool readOnly;
  final List<({String name, int karat, bool weight, int rowIndex})> fields;
  final Map<String, TextEditingController> counts;
  final Map<String, TextEditingController> weights;

  @override
  Widget build(BuildContext context) {
    Widget cell(int karat, {required bool weight}) {
      final last =
          fields.isNotEmpty &&
          fields.last.name == row.name &&
          fields.last.karat == karat &&
          fields.last.weight == weight &&
          fields.last.rowIndex == index;
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
        textInputAction: last ? TextInputAction.done : TextInputAction.next,
        onSubmitted: (_) {
          if (last) {
            FocusScope.of(context).unfocus();
          } else {
            FocusScope.of(context).nextFocus();
          }
        },
      );
    }

    final countsRow = Row(
      children: [
        SizedBox(
          width: nameWidth,
          child: Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        for (final karat in row.karats) ...[
          const SizedBox(width: AppTokens.spaceSm),
          cell(karat, weight: false),
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
            for (final karat in row.karats) ...[
              const SizedBox(width: AppTokens.spaceSm),
              cell(karat, weight: true),
            ],
          ],
        ),
      ],
    );
  }
}
