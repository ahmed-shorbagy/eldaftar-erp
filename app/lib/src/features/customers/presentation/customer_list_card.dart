import 'package:flutter/material.dart';

import '../../../theme/amount_format.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_tokens.dart';
import '../application/customer_gateway.dart';
import '../domain/customer_display.dart';
import '../domain/customer_statistics.dart';
import 'customer_whatsapp_icon.dart';

/// One customer in «بيانات العملاء» (ADR 0043, owner design of 2026-11-09).
class CustomerListCard extends StatelessWidget {
  const CustomerListCard({
    super.key,
    required this.customer,
    required this.today,
    required this.onOpen,
    required this.onWhatsapp,
    required this.onCall,
  });

  final CustomerRecord customer;

  /// The viewer's date, for «منذ N يوم» only.
  final DateTime today;
  final VoidCallback? onOpen;
  final VoidCallback? onWhatsapp;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = customer;
    final primary = c.phones.where((p) => p.primary).firstOrNull;
    final largeText = MediaQuery.textScalerOf(context).scale(16) > 20;
    final statistics = c.statistics;
    return Card(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceSm + 4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: Key('customer-card-${c.id}'),
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(AppTokens.spaceMd - 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!largeText) ...[
                    CustomerAvatar(name: c.name, size: 44),
                    const SizedBox(width: AppTokens.spaceSm + 4),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          // The name is the card's detail target in tests
                          // and for screen readers; buttons sit beside it.
                          key: Key('customer-${c.id}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (primary == null)
                          Text(
                            'بدون رقم هاتف',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          )
                        else
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                primary.normalized,
                                textDirection: TextDirection.ltr,
                                style: theme.textTheme.bodyMedium,
                              ),
                              IconButton(
                                key: Key('customer-whatsapp-${c.id}'),
                                tooltip: 'محادثة واتساب مع ${c.name}',
                                visualDensity: VisualDensity.compact,
                                onPressed: onWhatsapp,
                                icon: const CustomerWhatsappIcon(),
                              ),
                              IconButton(
                                key: Key('customer-call-${c.id}'),
                                tooltip: 'اتصال بـ ${c.name}',
                                visualDensity: VisualDensity.compact,
                                onPressed: onCall,
                                icon: Icon(
                                  Icons.call_outlined,
                                  color: scheme.primary,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceSm),
                  CustomerLastOperation(customer: c, today: today),
                ],
              ),
              if (statistics != null) ...[
                const SizedBox(height: AppTokens.spaceSm),
                CustomerKaratStrip(statistics: statistics),
              ],
              const SizedBox(height: AppTokens.spaceSm),
              Row(
                children: [
                  Tooltip(
                    message: c.vip ? 'عميل مميز' : 'ليس مميزًا',
                    child: Icon(
                      c.vip ? Icons.star : Icons.star_border,
                      color: c.vip ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceSm),
                  Expanded(
                    child: Text(
                      c.latestNote ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  if (c.openRequest) ...[
                    const SizedBox(width: AppTokens.spaceSm),
                    _Tag(label: 'طلب مفتوح', color: scheme.primary),
                  ],
                  if (c.inWhatsappGroup) ...[
                    const SizedBox(width: AppTokens.spaceSm),
                    _Tag(label: 'في الجروب', color: scheme.tertiary),
                  ],
                  if (c.archived) ...[
                    const SizedBox(width: AppTokens.spaceSm),
                    _Tag(label: 'مؤرشف', color: scheme.onSurfaceVariant),
                  ],
                  if (primary != null) ...[
                    const SizedBox(width: AppTokens.spaceSm),
                    _SavedTag(state: primary.saved?.state),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// First letter in a gold-framed circle.
class CustomerAvatar extends StatelessWidget {
  const CustomerAvatar({super.key, required this.name, required this.size});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.primaryContainer,
        border: Border.all(
          color: AppSemanticColors.of(context).goldFrame,
          width: 1.5,
        ),
      ),
      child: Text(
        name.characters.isEmpty ? '' : name.characters.first,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// «آخر عملية» above «منذ N يوم» (or the date when that cannot be told).
class CustomerLastOperation extends StatelessWidget {
  const CustomerLastOperation({
    super.key,
    required this.customer,
    required this.today,
  });

  final CustomerRecord customer;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final at = customer.lastAtShop;
    final since = at == null ? null : customerSince(at, today);
    final value = at == null
        ? 'لا توجد عمليات'
        : since ?? at.substring(0, at.length < 10 ? at.length : 10);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'آخر عملية',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.schedule, size: 16, color: scheme.primary),
            const SizedBox(width: 4),
            Text(
              value,
              key: Key('customer-last-${customer.id}'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ],
    );
  }
}

/// Bought grams per karat in equal boxes: «18K» over «152.30 g».
class CustomerKaratStrip extends StatelessWidget {
  const CustomerKaratStrip({
    super.key,
    required this.statistics,
    this.large = false,
  });

  final CustomerStatistics statistics;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final frame = AppSemanticColors.of(context).tableBorder;
    final karats = customerCardKarats(statistics);
    Widget box(int karat) => Padding(
      padding: EdgeInsets.symmetric(vertical: large ? 12 : 8, horizontal: 4),
      child: Column(
        children: [
          Text(
            '${karat}K',
            textDirection: TextDirection.ltr,
            // Small labels keep onSurface for AA contrast (design guide).
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '${displayGrams(customerBoughtMilligrams(statistics, karat).toString())} g',
              key: Key('customer-karat-$karat'),
              textDirection: TextDirection.ltr,
              style:
                  (large
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (large) {
      return Row(
        children: [
          for (var i = 0; i < karats.length; i++) ...[
            if (i > 0) const SizedBox(width: AppTokens.spaceSm),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: frame),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: box(karats[i]),
              ),
            ),
          ],
        ],
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppSemanticColors.of(context).goldFrame),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < karats.length; i++) ...[
              if (i > 0) VerticalDivider(width: 1, color: frame),
              Expanded(child: box(karats[i])),
            ],
          ],
        ),
      ),
    );
  }
}

class _SavedTag extends StatelessWidget {
  const _SavedTag({required this.state});

  final String? state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final saved = state == 'saved';
    final color = saved
        ? scheme.tertiary
        : state == 'not_saved'
        ? scheme.error
        : scheme.onSurfaceVariant;
    return _Tag(
      label: saved
          ? 'محفوظ'
          : state == 'not_saved'
          ? 'غير محفوظ'
          : 'غير محدد',
      color: color,
      leading: const CustomerWhatsappIcon(size: 16),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color, this.leading});

  final String label;
  final Color color;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 4)],
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: color),
          ),
        ],
      ),
    ),
  );
}
