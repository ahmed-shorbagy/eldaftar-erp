import 'package:flutter/material.dart';
import '../../../theme/amount_format.dart';
import '../domain/financial_draft.dart';
import '../domain/ledger_compensation.dart';

class ExchangeEffectReview extends StatelessWidget {
  const ExchangeEffectReview({
    super.key,
    required this.returnSide,
    required this.replacement,
  });
  final PartialReturnReview returnSide;
  final FinancialDraft replacement;

  @override
  Widget build(BuildContext context) {
    final result = reviewExchange(
      returnSide: returnSide,
      replacementKind: replacement.kind.name,
      replacementTotal: replacement.total.value,
      replacementTenders: {
        for (final row in replacement.tenders)
          row['method']! as String: BigInt.parse(row['piastres']! as String),
      },
      replacementLines: [
        for (final row in replacement.items)
          ReplacementLine(
            category: row['category']! as String,
            karat: row['karat']! as int,
            milligrams: BigInt.parse(row['milligrams']! as String),
            count: row['count'] == null
                ? BigInt.zero
                : BigInt.parse(row['count']! as String),
            itemName: row['item_name']! as String,
          ),
      ],
    );
    if (result is! CompensationAccepted<ExchangeReview>) {
      return const Text('تعذر حساب أثر الاستبدال. راجع البيانات.');
    }
    final review = result.value;
    final methodEffects = <String, BigInt>{};
    for (final entry in returnSide.tenders.entries) {
      methodEffects[entry.key] = returnSide.kind == 'sale_return'
          ? -entry.value
          : entry.value;
    }
    for (final row in replacement.tenders) {
      final method = row['method']! as String;
      final amount = BigInt.parse(row['piastres']! as String);
      methodEffects[method] =
          (methodEffects[method] ?? BigInt.zero) +
          (replacement.kind == FinancialKind.sale ? amount : -amount);
    }
    String money(BigInt value) =>
        '\u2066${displayPounds(signedPoundsText(value))}\u2069';
    String metal(MetalEffect row) =>
        '${_category(row.category)} · عيار ${row.karat}: ${_weightLabel(row.milligrams)} جرام${row.count == null ? '' : ' · ${_pieceLabel(row.count!)} قطعة'}';
    return Card(
      key: const Key('exchange-effects'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'مراجعة الاستبدال',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              'المرتجع: مقابل ${money(returnSide.consideration)} · أثر النقد ${money(returnSide.signedCash)}',
            ),
            if (returnSide.cancelledPayable > BigInt.zero)
              Text('إلغاء مستحق: ${money(returnSide.cancelledPayable)}'),
            for (final line in returnSide.lines)
              Text(
                metal(
                  MetalEffect(
                    category: line.category,
                    karat: line.karat,
                    milligrams: returnSide.kind == 'sale_return'
                        ? line.milligrams
                        : -line.milligrams,
                    count: line.scrap
                        ? null
                        : returnSide.kind == 'sale_return'
                        ? line.count
                        : -line.count,
                  ),
                ),
              ),
            const Divider(),
            Text(
              'البديل: مقابل ${money(replacement.total.value)} · أثر النقد ${money(review.replacementCash)}',
            ),
            for (final line in review.replacementLines) Text(metal(line)),
            if (replacement.purchasePayable != null)
              Text(
                'مستحق البديل: ${money(replacement.purchasePayable!.value)}',
              ),
            const Divider(),
            Text(
              'صافي النقد: ${money(review.netCash)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            for (final entry in methodEffects.entries)
              Text('${_method(entry.key)}: ${money(entry.value)}'),
            for (final line in review.netLines) Text(metal(line)),
            const Text('يُحفظ المرتجع والبديل معًا بعد تأكيد الخادم.'),
          ],
        ),
      ),
    );
  }
}

String _category(String code) => switch (code) {
  'worked_jewelry' => 'مشغولات',
  'bullion' => 'سبائك',
  'coin' => 'جنيهات',
  'scrap' => 'كسر',
  _ => 'ذهب',
};
String _method(String code) => switch (code) {
  'cash' => 'نقدي',
  'card' => 'بطاقة',
  'wallet' => 'محفظة',
  _ => 'تحويل فوري',
};

class ConfirmedCompensationEffects extends StatelessWidget {
  const ConfirmedCompensationEffects({
    super.key,
    required this.effects,
    required this.exchange,
  });
  final Map<String, Object?> effects;
  final bool exchange;
  @override
  Widget build(BuildContext context) {
    final rows = exchange
        ? [
            ('المرتجع', effects['return_effects']),
            ('البديل', effects['replacement_effects']),
            ('الصافي', effects['net_effects']),
          ]
        : [('أثر التسوية', effects)];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (label, raw) in rows)
              if (raw is Map) ...[
                Text(label, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  'النقد: ${_cashLabel(BigInt.parse(raw['cash_piastres'] as String))}',
                ),
                for (final line in raw['buckets'] as List)
                  if (line is Map)
                    Text(
                      '${_category(line['category'] as String)} عيار ${line['karat']}: ${_weightLabel(BigInt.parse(line['milligrams'] as String))} جرام${line['count'] == null ? '' : ' · ${_pieceLabel(BigInt.parse(line['count'] as String))} قطعة'}',
                    ),
              ],
          ],
        ),
      ),
    );
  }
}

String _weightLabel(BigInt value) => '\u2066${signedGramsText(value)}\u2069';
String _pieceLabel(BigInt value) => '\u2066$value\u2069';
String _cashLabel(BigInt value) =>
    '\u2066${displayPounds(signedPoundsText(value))}\u2069';
