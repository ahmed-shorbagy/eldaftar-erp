import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../../../theme/gram_input.dart';
import '../../daily_ledger/domain/closing_item_grid.dart';
import '../../daily_ledger/domain/opening_issue.dart';
import '../../daily_ledger/domain/quantities.dart';
import '../../daily_ledger/presentation/closing_item_grid_view.dart';
import '../../daily_ledger/presentation/ledger_form_fields.dart';
import '../application/closing_delegation_gateway.dart';

class PhysicalCountEditor extends StatefulWidget {
  const PhysicalCountEditor({
    super.key,
    required this.assignment,
    required this.enabled,
    required this.onReview,
  });
  final StaffCountAssignment assignment;
  final bool enabled;
  final ValueChanged<Map<String, Object?>> onReview;
  @override
  State<PhysicalCountEditor> createState() => _PhysicalCountEditorState();
}

class _PhysicalCountEditorState extends State<PhysicalCountEditor> {
  late final ClosingItemGrid _grid = ClosingItemGrid.build(
    // The task lists every book bucket, including zeros, and never the
    // quantities. An untouched bucket is submitted as a zero count.
    bookStock: [
      for (final bucket in widget.assignment.stock)
        {'category': bucket.category, 'karat': bucket.karat, 'count': '0'},
    ],
    shopNames: [
      for (final item in widget.assignment.itemNames)
        (name: item.name, category: item.category, karat: item.karat),
    ],
  );
  late final _counts = {
    for (final row in _grid.rows)
      for (final karat in row.karats)
        ClosingItemGridView.cellKey(row.name, karat): TextEditingController(),
  };
  late final _grams = {
    for (final row in _grid.rows)
      for (final karat in row.karats)
        ClosingItemGridView.cellKey(row.name, karat): TextEditingController(),
  };
  late final _scrap = {
    for (final karat in widget.assignment.scrapKarats)
      karat: TextEditingController(),
  };
  var _showWeights = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in _counts.values) {
      controller.dispose();
    }
    for (final controller in _grams.values) {
      controller.dispose();
    }
    for (final controller in _scrap.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _review() {
    if (!widget.enabled) return;
    final cells = <(String, int), (String, String)>{};
    for (final row in _grid.rows) {
      for (final karat in row.karats) {
        final key = ClosingItemGridView.cellKey(row.name, karat);
        String normalized(String text, int places) =>
            canonicalNumericEntry(text, decimalPlaces: places) ?? text;
        cells[(row.name, karat)] = (
          normalized(_counts[key]?.text ?? '', 0),
          _showWeights ? normalized(_grams[key]?.text ?? '', 3) : '',
        );
      }
    }
    final draft = _grid.toObservations(cells);
    if (draft is ClosingGridRejected) {
      setState(
        () => _error = draft.issue == ClosingGridIssue.weightWithoutCount
            ? 'اكتب العدد قبل الوزن.'
            : 'أدخل عدداً صحيحاً لكل خانة.',
      );
      return;
    }
    final scrap = <Map<String, Object?>>[];
    for (final entry in _scrap.entries) {
      final scrapText = canonicalNumericEntry(
        entry.value.text,
        decimalPlaces: 3,
      );
      final grams = scrapText == null || scrapText.isEmpty
          ? const Rejected<Milligrams>(OpeningIssueCode.invalidInput)
          : Milligrams.parseGrams(scrapText);
      if (grams is! Accepted<Milligrams>) {
        setState(() => _error = 'أدخل وزن الكسر لكل عيار؛ هذا الوزن مطلوب.');
        return;
      }
      scrap.add({'karat': entry.key, 'milligrams': grams.value.wire});
    }
    widget.onReview({
      'stock': (draft as ClosingGridReady).stock,
      'scrap': scrap,
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('لا تظهر أرصدة الدفتر في هذه المهمة.'),
      const SizedBox(height: AppTokens.spaceSm),
      ClosingItemGridView(
        grid: _grid,
        counts: _counts,
        weights: _grams,
        showWeights: _showWeights,
        readOnly: !widget.enabled,
        onShowWeights: (value) => setState(() => _showWeights = value),
      ),
      if (_scrap.isNotEmpty) ...[
        const SizedBox(height: AppTokens.spaceMd),
        Text('الكسر', style: Theme.of(context).textTheme.titleMedium),
      ],
      for (final entry in _scrap.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('عيار ${entry.key}'),
              const SizedBox(height: 4),
              TextField(
                key: Key('staff-scrap-${entry.key}'),
                controller: entry.value,
                enabled: widget.enabled,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textDirection: TextDirection.ltr,
                autocorrect: false,
                enableSuggestions: false,
                inputFormatters: const [GramInputFormatter(decimalPlaces: 3)],
                decoration: ledgerFieldDecoration(
                  context,
                  label: 'الوزن بالجرام',
                  helper: 'مطلوب',
                ),
              ),
            ],
          ),
        ),
      if (_error != null)
        Text(
          _error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      FilledButton(
        key: const Key('staff-count-review'),
        onPressed: widget.enabled ? _review : null,
        child: const Text('مراجعة العد'),
      ),
    ],
  );
}
