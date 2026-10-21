import 'package:flutter/material.dart';

import '../../../theme/amount_format.dart';
import '../../../theme/app_theme.dart';
import '../application/daily_ledger_view.dart';

/// Confirmed cash methods. Honest when the shop has no method balances.
class LedgerCashBreakdown extends StatelessWidget {
  const LedgerCashBreakdown({super.key, required this.view});

  final DailyLedgerView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('وسائل الدفع', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'توزيع الأرصدة حسب نقدي وانستا وفيزا والمحفظة',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        if (view.cash.isEmpty)
          const Text('لا توجد أرصدة نقدية.', key: Key('ledger-cash-empty'))
        else
          LayoutBuilder(
            builder: (context, size) {
              final columns = size.maxWidth >= 360 ? 2 : 1;
              const gap = 10.0;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final line in view.cash)
                    SizedBox(
                      width: columns == 1
                          ? size.maxWidth
                          : (size.maxWidth - gap) / 2,
                      child: _FlagTile(
                        accent: Theme.of(context).colorScheme.primary,
                        icon: _paymentIcon(line.method),
                        title: line.labelAr,
                        value: displayPounds(line.pounds),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

/// Actual sold weights by category and karat. Karats stay separate.
class LedgerSoldGoldBreakdown extends StatelessWidget {
  const LedgerSoldGoldBreakdown({super.key, required this.view});

  final DailyLedgerView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = <String, List<LedgerGoldMovement>>{};
    for (final row
        in view.daySummary?.goldByBucket ?? const <LedgerGoldMovement>[]) {
      if (row.kind != 'sale') continue;
      groups.putIfAbsent(row.category, () => []).add(row);
    }
    for (final rows in groups.values) {
      rows.sort((a, b) => b.karat.compareTo(a.karat));
    }
    const preferred = ['worked_jewelry', 'jewelry', 'bullion', 'coin', 'scrap'];
    final categories = [
      for (final category in preferred)
        if (groups.containsKey(category)) category,
      for (final category in groups.keys)
        if (!preferred.contains(category)) category,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ذهب مباع', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'الوزن الفعلي لكل صنف وعيار.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        if (categories.isEmpty)
          const Text('لا يوجد ذهب مباع.', key: Key('ledger-sale-gold-empty'))
        else
          for (final category in categories)
            _InventoryCategoryBlock(
              category: category,
              label: goldCategoryLabel(category),
              items: [
                for (final row in groups[category]!)
                  (
                    karat: row.karat,
                    grams: row.milligrams,
                    count: category == 'scrap' ? null : row.count,
                  ),
              ],
            ),
      ],
    );
  }
}

/// Confirmed stock and scrap. Honest when both are empty.
class LedgerGoldBreakdown extends StatelessWidget {
  const LedgerGoldBreakdown({super.key, required this.view});

  final DailyLedgerView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byKarat = <int, BigInt>{};
    for (final line in view.stock) {
      byKarat.update(
        line.karat,
        (v) => v + BigInt.parse(line.milligrams),
        ifAbsent: () => BigInt.parse(line.milligrams),
      );
    }
    for (final line in view.scrap) {
      byKarat.update(
        line.karat,
        (v) => v + BigInt.parse(line.milligrams),
        ifAbsent: () => BigInt.parse(line.milligrams),
      );
    }
    final karats = byKarat.keys.toList()..sort((a, b) => b.compareTo(a));
    final groups = <String, List<({int karat, String grams, String? count})>>{};
    final labels = <String, String>{};
    for (final line in view.stock) {
      labels.putIfAbsent(
        line.category,
        () => line.labelAr.isNotEmpty
            ? line.labelAr
            : goldCategoryLabel(line.category),
      );
      groups.putIfAbsent(line.category, () => []).add((
        karat: line.karat,
        grams: line.grams,
        count: line.count,
      ));
    }
    if (view.scrap.isNotEmpty) {
      labels['scrap'] = goldCategoryLabel('scrap');
      groups['scrap'] = [
        for (final line in view.scrap)
          (karat: line.karat, grams: line.grams, count: null),
      ];
    }
    final categoryOrder = [
      'worked_jewelry',
      'jewelry',
      'bullion',
      'coin',
      'scrap',
      ...groups.keys.where(
        (key) => !const {
          'worked_jewelry',
          'jewelry',
          'bullion',
          'coin',
          'scrap',
        }.contains(key),
      ),
    ].where(groups.containsKey).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('المخزون والكسر', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'أرصدة الذهب المؤكدة حسب العيار والصنف',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 12),
        if (karats.isEmpty)
          const Text('لا توجد أرصدة ذهب.', key: Key('ledger-gold-empty'))
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final karat in karats)
                _KaratFlag(
                  karat: karat,
                  weight: '${displayGrams(byKarat[karat]!.toString())} جرام',
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final category in categoryOrder)
            _InventoryCategoryBlock(
              category: category,
              label: labels[category] ?? goldCategoryLabel(category),
              items: groups[category]!,
            ),
        ],
      ],
    );
  }
}

String goldCategoryLabel(String category) => switch (category) {
  'worked_jewelry' || 'jewelry' => 'مشغولات',
  'bullion' => 'سبائك',
  'coin' => 'جنيهات',
  'scrap' => 'كسر',
  _ => 'ذهب',
};

class _FlagTile extends StatelessWidget {
  const _FlagTile({
    required this.accent,
    required this.icon,
    required this.title,
    required this.value,
  });

  final Color accent;
  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadiusDirectional.only(
                  topStart: Radius.circular(20),
                  bottomStart: Radius.circular(20),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, size: 18, color: accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      value,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KaratFlag extends StatelessWidget {
  const _KaratFlag({required this.karat, required this.weight});

  final int karat;
  final String weight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: 'عيار $karat $weight',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _KaratBadge(karat: karat, fill: scheme.primary),
              const SizedBox(height: 8),
              Text(
                weight,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KaratBadge extends StatelessWidget {
  const _KaratBadge({required this.karat, required this.fill});

  final int karat;
  final Color fill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onFill = fill == scheme.error
        ? scheme.onError
        : fill == scheme.tertiary
        ? scheme.onTertiary
        : fill == scheme.secondary
        ? scheme.onSecondary
        : scheme.onPrimary;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          'عيار $karat',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: onFill,
            fontWeight: FontWeight.w800,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _InventoryCategoryBlock extends StatelessWidget {
  const _InventoryCategoryBlock({
    required this.category,
    required this.label,
    required this.items,
  });

  final String category;
  final String label;
  final List<({int karat, String grams, String? count})> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = _categoryAccent(scheme, category);
    final icon = _categoryIcon(category);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(icon, size: 18, color: accent),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in items)
                _InventoryPiece(
                  accent: accent,
                  karat: item.karat,
                  grams: item.grams,
                  count: item.count,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InventoryPiece extends StatelessWidget {
  const _InventoryPiece({
    required this.accent,
    required this.karat,
    required this.grams,
    this.count,
  });

  final Color accent;
  final int karat;
  final String grams;
  final String? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      label: [
        'عيار $karat',
        if (count != null) '$count قطعة',
        '${displayGrams(grams)} جرام',
      ].join(' '),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _KaratBadge(karat: karat, fill: accent),
              const SizedBox(height: 8),
              Text(
                '${displayGrams(grams)} جرام',
                textDirection: TextDirection.ltr,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (count != null)
                Text(
                  '$count قطعة',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _categoryAccent(ColorScheme scheme, String category) =>
    switch (category) {
      'worked_jewelry' || 'jewelry' => scheme.primary,
      'bullion' => scheme.tertiary,
      'coin' => scheme.secondary,
      'scrap' => scheme.error,
      _ => scheme.onSurfaceVariant,
    };

IconData _categoryIcon(String category) => switch (category) {
  'worked_jewelry' || 'jewelry' => Icons.diamond_outlined,
  'bullion' => Icons.view_in_ar_outlined,
  'coin' => Icons.monetization_on_outlined,
  'scrap' => Icons.content_cut_outlined,
  _ => Icons.category_outlined,
};

IconData _paymentIcon(String method) => switch (method) {
  'cash' => Icons.payments_outlined,
  'card' => Icons.credit_card_outlined,
  'wallet' => Icons.account_balance_wallet_outlined,
  'instant_transfer' => Icons.bolt_outlined,
  _ => Icons.savings_outlined,
};

/// Shared metric tile used on home and More.
class LedgerMetricTile extends StatelessWidget {
  const LedgerMetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.tone,
    this.compact = false,
    this.onOpen,
    this.openTooltip,
    this.openKey,
  });

  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final LedgerMetricTone tone;
  final bool compact;
  final VoidCallback? onOpen;
  final String? openTooltip;
  final Key? openKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final interactive = onOpen != null;
    final (Color accent, Color wash) = switch (tone) {
      LedgerMetricTone.primary => (
        scheme.primary,
        scheme.primary.withValues(alpha: 0.14),
      ),
      LedgerMetricTone.positive => (
        scheme.tertiary,
        scheme.tertiary.withValues(alpha: 0.16),
      ),
      LedgerMetricTone.negative => (
        scheme.error,
        scheme.error.withValues(alpha: 0.12),
      ),
      LedgerMetricTone.neutral => (
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest.withValues(alpha: 0.7),
      ),
    };
    final frame = AppSemanticColors.of(context).goldFrame;
    final side = interactive
        ? BorderSide(color: accent.withValues(alpha: 0.55), width: 1.4)
        : BorderSide(color: frame);
    final body = Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 10 : 14,
        compact ? 10 : 14,
        compact ? 10 : 14,
        compact ? 10 : 14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: wash,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(icon, size: 18, color: accent),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.25,
                  ),
                ),
              ),
              if (interactive)
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      Icons.keyboard_arrow_left_rounded,
                      size: 18,
                      color: accent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: MediaQuery.textScalerOf(context).scale(30),
            child: FittedBox(
              alignment: AlignmentDirectional.centerStart,
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                ),
              ),
            ),
          ),
          Text(
            unit.isEmpty ? ' ' : unit,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    final card = Material(
      key: openKey,
      color: scheme.surfaceContainerLow,
      elevation: interactive ? 1.5 : 0,
      shadowColor: scheme.shadow.withValues(alpha: 0.18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: side,
      ),
      clipBehavior: Clip.antiAlias,
      child: interactive ? InkWell(onTap: onOpen, child: body) : body,
    );
    return Semantics(
      button: interactive,
      label: [label, value, if (unit.isNotEmpty) unit, ?openTooltip].join(' '),
      child: openTooltip == null
          ? card
          : Tooltip(message: openTooltip!, child: card),
    );
  }
}

enum LedgerMetricTone { primary, positive, negative, neutral }
