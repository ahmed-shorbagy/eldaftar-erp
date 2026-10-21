import 'package:flutter/material.dart';

import '../../../theme/amount_format.dart';
import '../application/daily_ledger_view.dart';
import '../application/ledger_home_metrics.dart';
import '../domain/gold_metrics.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';
import 'ledger_balance_sections.dart';

class LedgerNormalizationControl extends StatelessWidget {
  const LedgerNormalizationControl({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<int>(
    key: ValueKey('ledger-normalize-$value'),
    initialValue: value,
    decoration: const InputDecoration(labelText: 'عرض الذهب بمحيف عيار'),
    items: [
      for (final karat in normalizationKarats)
        DropdownMenuItem(value: karat, child: Text('عيار $karat')),
    ],
    onChanged: (next) {
      if (next != null) onChanged(next);
    },
  );
}

class LedgerMetricSpec {
  const LedgerMetricSpec(
    this.label,
    this.value,
    this.unit,
    this.icon,
    this.tone,
  );
  final String label, value, unit;
  final IconData icon;
  final LedgerMetricTone tone;
}

Map<String, LedgerMetricSpec> ledgerMetricValues(
  DailyLedgerView view,
  int targetKarat,
) {
  final summary = view.daySummary;
  String money(String? wire) {
    final amount = wire == null ? null : Piastres.parseWire(wire);
    return amount is Accepted<Piastres>
        ? displayPounds(amount.value.poundsText)
        : '—';
  }

  String normalized(String kind) {
    if (summary == null) return '—';
    final centigrams = normalizedGoldCentigrams([
      for (final row in summary.goldByBucket.where((r) => r.kind == kind))
        (karat: row.karat, milligrams: BigInt.parse(row.milligrams)),
    ], targetKarat);
    return displayGrams((centigrams * BigInt.from(10)).toString());
  }

  String byKarat(String kind, int karat, {bool scrap = false}) {
    if (summary == null) return '—';
    final milligrams = summary.goldByBucket
        .where(
          (row) =>
              row.kind == kind &&
              row.karat == karat &&
              (!scrap || row.category == 'scrap'),
        )
        .fold(BigInt.zero, (sum, row) => sum + BigInt.parse(row.milligrams));
    return displayGrams(milligrams.toString());
  }

  final equivalent = 'جرام محيف عيار $targetKarat';
  return {
    'total_cash': LedgerMetricSpec(
      ledgerMetricLabel('total_cash'),
      displayPounds(view.totalCashPounds ?? '—'),
      '',
      Icons.account_balance_wallet_outlined,
      LedgerMetricTone.primary,
    ),
    'sale': LedgerMetricSpec(
      ledgerMetricLabel('sale'),
      money(summary?.salePiastres),
      '${normalized('sale')} $equivalent',
      Icons.trending_up,
      LedgerMetricTone.positive,
    ),
    'purchase': LedgerMetricSpec(
      ledgerMetricLabel('purchase'),
      money(summary?.purchasePiastres),
      '${normalized('purchase')} $equivalent',
      Icons.trending_down,
      LedgerMetricTone.negative,
    ),
    'sale_gold': LedgerMetricSpec(
      ledgerMetricLabel('sale_gold'),
      normalized('sale'),
      equivalent,
      Icons.south_west,
      LedgerMetricTone.positive,
    ),
    'purchase_gold': LedgerMetricSpec(
      ledgerMetricLabel('purchase_gold'),
      normalized('purchase'),
      equivalent,
      Icons.south_east,
      LedgerMetricTone.negative,
    ),
    'expense': LedgerMetricSpec(
      ledgerMetricLabel('expense'),
      money(summary?.expensePiastres),
      '',
      Icons.receipt_long_outlined,
      LedgerMetricTone.neutral,
    ),
    for (final karat in [18, 21, 24])
      'sale_karat_$karat': LedgerMetricSpec(
        ledgerMetricLabel('sale_karat_$karat'),
        byKarat('sale', karat),
        'جرام فعلي عيار $karat',
        Icons.sell_outlined,
        LedgerMetricTone.positive,
      ),
    for (final karat in [18, 21, 24, 22, 14])
      'scrap_purchase_$karat': LedgerMetricSpec(
        ledgerMetricLabel('scrap_purchase_$karat'),
        byKarat('purchase', karat, scrap: true),
        'جرام فعلي عيار $karat',
        Icons.content_cut_outlined,
        LedgerMetricTone.negative,
      ),
  };
}
