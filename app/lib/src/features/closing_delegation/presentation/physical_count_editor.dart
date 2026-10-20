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
      final name = row.name.text.trim(),
          count = PieceCount.parseWire(row.count.text.trim());
      final weight = row.grams.text.trim(),
          grams = weight.isEmpty ? null : Milligrams.parseGrams(weight);
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
      final grams = Milligrams.parseGrams(entry.value.text.trim());
      if (grams is! Accepted<Milligrams>) {
        setState(() => _error = 'أدخل وزن الكسر لكل عيار؛ هذا الوزن مطلوب.');
        return;
      }
      scrap.add({'karat': entry.key, 'milligrams': grams.value.wire});
    }
    widget.onReview({'stock': stock, 'scrap': scrap});
  }

  String _category(String value) => switch (value) {
    'coin' => 'جنيهات',
    'bullion' => 'سبائك',
    _ => 'مشغولات',
  };
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text(
        'أدخل ما عُدّ فعلياً. العدد مطلوب ووزن المخزون اختياري. لا تظهر أرصدة الدفتر في هذه المهمة.',
      ),
      for (final bucket in widget.assignment.stock) ...[
        const SizedBox(height: 16),
        Text(
          '${_category(bucket.category)} · عيار ${bucket.karat}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        for (final row in _rows.where((row) => identical(row.bucket, bucket)))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  TextField(
                    key: Key('staff-item-name-${_rows.indexOf(row)}'),
                    controller: row.name,
                    enabled: widget.enabled,
                    maxLength: 120,
                    decoration: ledgerFieldDecoration(
                      context,
                      label: 'النوع (مثل خاتم أو حلق)',
                    ),
                  ),
                  const SizedBox(height: 8),
                  LedgerFieldPair(
                    first: TextField(
                      key: Key('staff-item-count-${_rows.indexOf(row)}'),
                      controller: row.count,
                      enabled: widget.enabled,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      inputFormatters: const [
                        GramInputFormatter(decimalPlaces: 0),
                      ],
                      decoration: ledgerFieldDecoration(
                        context,
                        label: 'العدد',
                      ),
                    ),
                    second: TextField(
                      key: Key('staff-item-weight-${_rows.indexOf(row)}'),
                      controller: row.grams,
                      enabled: widget.enabled,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      textDirection: TextDirection.ltr,
                      decoration: ledgerFieldDecoration(
                        context,
                        label: 'الوزن بالجرام (اختياري)',
                      ),
                    ),
                  ),
                  if (_rows
                          .where((other) => identical(other.bucket, bucket))
                          .length >
                      1)
                    TextButton(
                      onPressed: widget.enabled
                          ? () => setState(() {
                              _rows.remove(row);
                              row.dispose();
                            })
                          : null,
                      child: const Text('حذف الصف'),
                    ),
                ],
              ),
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
          child: TextField(
            key: Key('staff-scrap-${entry.key}'),
            controller: entry.value,
            enabled: widget.enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            decoration: ledgerFieldDecoration(
              context,
              label: 'وزن كسر عيار ${entry.key} بالجرام (مطلوب)',
            ),
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
