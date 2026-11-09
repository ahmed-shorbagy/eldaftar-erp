import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../application/customer_gateway.dart';
import '../domain/customer_display.dart';

/// Four figure tiles in one row, as in the owner's design (ADR 0043).
class CustomerOverviewHeader extends StatelessWidget {
  const CustomerOverviewHeader({super.key, required this.overview});

  final CustomerOverview overview;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tiles = [
      _OverviewTile(
        tileKey: const Key('customer-overview-total'),
        label: 'إجمالي العملاء',
        value: customerCount(overview.activeCount),
        unit: 'عميل',
        icon: Icons.groups_outlined,
        color: scheme.tertiary,
      ),
      _OverviewTile(
        tileKey: const Key('customer-overview-vip'),
        label: 'عملاء مميزون',
        value: customerCount(overview.vipCount),
        unit: 'عميل',
        icon: Icons.star_outline,
        color: scheme.primary,
      ),
      _OverviewTile(
        tileKey: const Key('customer-overview-active'),
        label: 'عملاء نشطون',
        value: customerCount(overview.active30Days),
        unit: 'آخر 30 يوم',
        icon: Icons.person_search_outlined,
        color: scheme.secondary,
      ),
      _OverviewTile(
        tileKey: const Key('customer-overview-open'),
        label: 'طلبات مفتوحة',
        value: customerCount(overview.openRequestCount),
        unit: 'عميل',
        icon: Icons.schedule_outlined,
        color: scheme.primary,
      ),
    ];
    return Row(
      key: const Key('customer-overview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}

class _OverviewTile extends StatelessWidget {
  const _OverviewTile({
    required this.tileKey,
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
    required this.color,
  });

  final Key tileKey;
  final String label, value, unit;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      container: true,
      label: '$label $value $unit',
      child: ExcludeSemantics(
        child: DecoratedBox(
          key: tileKey,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppSemanticColors.of(context).goldFrame),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              children: [
                Icon(icon, size: 22, color: color),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    value,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  unit,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
