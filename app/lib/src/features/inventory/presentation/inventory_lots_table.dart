import 'package:flutter/material.dart';

import '../domain/inventory_models.dart';
import 'inventory_copy.dart';

/// Exact lot quantities, with horizontal scrolling on narrow viewports.
class InventoryLotsTable extends StatelessWidget {
  const InventoryLotsTable({
    super.key,
    required this.lots,
    required this.onOpen,
  });

  final List<LotSnapshot> lots;
  final ValueChanged<LotSnapshot> onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          columnSpacing: 24,
          dataRowMinHeight: 64,
          dataRowMaxHeight: double.infinity,
          headingRowColor: WidgetStatePropertyAll(
            scheme.surfaceContainerHighest,
          ),
          columns: const [
            DataColumn(label: Text('الصنف')),
            DataColumn(label: Text('العيار')),
            DataColumn(label: Text('العدد')),
            DataColumn(label: Text('الوزن بالجرام')),
            DataColumn(label: Text('حالة الملكية')),
          ],
          rows: [
            for (final lot in lots)
              DataRow(
                onSelectChanged: (_) => onOpen(lot),
                cells: [
                  DataCell(
                    SizedBox(
                      width: 180,
                      child: TextButton(
                        key: Key('lot-row-${lot.id}'),
                        onPressed: () => onOpen(lot),
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            '${lot.legacyAggregate ? 'رصيد سابق مجمّع — ' : ''}${lot.displayName}\n'
                            '${inventoryCategoryLabel(lot.category)}'
                            '${lotIdentityCopy(lot).isEmpty ? '' : '\n${lotIdentityCopy(lot)}'}',
                          ),
                        ),
                      ),
                    ),
                  ),
                  DataCell(Text('${lot.karat}')),
                  DataCell(Text(lot.remainingCount?.toString() ?? 'غير مسجّل')),
                  DataCell(Text(gramsOf(lot.remainingMilligrams))),
                  DataCell(Text(stockClassLabel(lot.stockClass))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
