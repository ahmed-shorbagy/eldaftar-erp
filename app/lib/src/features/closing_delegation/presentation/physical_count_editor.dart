import 'package:flutter/material.dart';
import '../../../theme/gram_input.dart';
import '../../daily_ledger/domain/opening_issue.dart';
import '../../daily_ledger/domain/quantities.dart';
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

class _CountLine {
  _CountLine(this.bucket);
  final ClosingCountBucket bucket;
  final name = TextEditingController(),
      count = TextEditingController(),
      grams = TextEditingController();
  void dispose() {
    name.dispose();
    count.dispose();
    grams.dispose();
  }
}

class _PhysicalCountEditorState extends State<PhysicalCountEditor> {
  late final _rows = [
    for (final bucket in widget.assignment.stock) _CountLine(bucket),
  ];
  late final _scrap = {
    for (final karat in widget.assignment.scrapKarats)
      karat: TextEditingController(),
  };
  String? _error;
  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    for (final controller in _scrap.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _review() {
    if (!widget.enabled) return;
    final stock = <Map<String, Object?>>[],
        scrap = <Map<String, Object?>>[],
        names = <String>{};
    for (final row in _rows) {
      final name = row.name.text.trim();
      final countText = canonicalNumericEntry(row.count.text, decimalPlaces: 0);
      final count = countText == null || countText.isEmpty
          ? null
          : PieceCount.parseWire(countText);
      final weight = row.grams.text.trim();
      final weightText = canonicalNumericEntry(weight, decimalPlaces: 3);
      final grams = weight.isEmpty
          ? null
          : weightText == null || weightText.isEmpty
          ? const Rejected<Milligrams>(OpeningIssueCode.invalidInput)
          : Milligrams.parseGrams(weightText);
      final identity = '${row.bucket.category}:${row.bucket.karat}:$name';
      if (name.isEmpty ||
          name.runes.length > 120 ||
          count is! Accepted<PieceCount> ||
          !names.add(identity) ||
          (grams != null && grams is! Accepted<Milligrams>) ||
          (grams is Accepted<Milligrams> &&
              (count.value.value == BigInt.zero) !=
                  (grams.value.value == BigInt.zero))) {
        setState(
          () => _error =
              'أدخل نوعاً مختلفاً وعدداً صحيحاً لكل صف. وزن المخزون اختياري.',
        );
        return;
      }
      stock.add({
        'item_name': name,
        'category': row.bucket.category,
        'karat': row.bucket.karat,
        'count': count.value.wire,
        'milligrams': grams is Accepted<Milligrams> ? grams.value.wire : null,
      });
    }
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
    widget.onReview({'stock': stock, 'scrap': scrap});
  }

  String _bucketTitle(ClosingCountBucket bucket) => switch (bucket.category) {
    'coin' => 'جنيهات · عيار ${bucket.karat}',
    'bullion' => 'سبائك · عيار ${bucket.karat}',
    _ => 'عيار ${bucket.karat}',
  };

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'أدخل ما عُدّ فعلياً. العدد مطلوب ووزن المخزون اختياري. لا تظهر أرصدة الدفتر في هذه المهمة.',
      ),
      for (final bucket in widget.assignment.stock) ...[
        const SizedBox(height: 12),
        Text(
          _bucketTitle(bucket),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final row in _rows.where((row) => identical(row.bucket, bucket)))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LedgerCountFields(
                  type: TextField(
                    key: Key('staff-item-name-${_rows.indexOf(row)}'),
                    controller: row.name,
                    enabled: widget.enabled,
                    maxLength: 120,
                    decoration: ledgerFieldDecoration(
                      context,
                      label: 'النوع',
                    ).copyWith(counterText: ''),
                  ),
                  count: TextField(
                    key: Key('staff-item-count-${_rows.indexOf(row)}'),
                    controller: row.count,
                    enabled: widget.enabled,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: const [
                      GramInputFormatter(decimalPlaces: 0),
                    ],
                    decoration: ledgerFieldDecoration(context, label: 'العدد'),
                  ),
                  weight: TextField(
                    key: Key('staff-item-weight-${_rows.indexOf(row)}'),
                    controller: row.grams,
                    enabled: widget.enabled,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    textDirection: TextDirection.ltr,
                    autocorrect: false,
                    enableSuggestions: false,
                    inputFormatters: const [
                      GramInputFormatter(decimalPlaces: 3),
                    ],
                    decoration: ledgerFieldDecoration(
                      context,
                      label: 'الوزن (اختياري)',
                    ),
                  ),
                ),
                if (_rows
                        .where((other) => identical(other.bucket, bucket))
                        .length >
                    1)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      onPressed: widget.enabled
                          ? () => setState(() {
                              _rows.remove(row);
                              row.dispose();
                            })
                          : null,
                      child: const Text('حذف الصف'),
                    ),
                  ),
              ],
            ),
          ),
        OutlinedButton.icon(
          onPressed: widget.enabled && _rows.length < 200
              ? () => setState(() => _rows.add(_CountLine(bucket)))
              : null,
          icon: const Icon(Icons.add),
          label: const Text('إضافة نوع من هذا العيار'),
        ),
      ],
      if (_scrap.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('الكسر', style: Theme.of(context).textTheme.titleMedium),
      ],
      for (final entry in _scrap.entries)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
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
