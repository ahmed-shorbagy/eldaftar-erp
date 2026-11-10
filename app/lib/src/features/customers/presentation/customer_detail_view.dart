import 'package:flutter/material.dart';

import '../../../theme/amount_format.dart';
import '../../../theme/app_theme.dart';
import '../../../theme/app_tokens.dart';
import '../application/customer_gateway.dart';
import '../domain/customer_display.dart';
import 'customer_list_card.dart';
import 'customer_whatsapp_icon.dart';

/// Detail header: avatar, name, phone, «مميز», then call / WhatsApp / edit.
class CustomerDetailHeader extends StatelessWidget {
  const CustomerDetailHeader({
    super.key,
    required this.customer,
    required this.onCall,
    required this.onWhatsapp,
    required this.onEdit,
  });

  final CustomerRecord customer;
  final VoidCallback? onCall, onWhatsapp, onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = customer;
    final primary = c.phones.where((p) => p.primary).firstOrNull;
    return Card(
      key: const Key('customer-detail-header'),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CustomerAvatar(name: c.name, size: 56),
                const SizedBox(width: AppTokens.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        primary?.normalized ?? 'بدون رقم هاتف',
                        textDirection: primary == null
                            ? null
                            : TextDirection.ltr,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (c.vip)
                  DecoratedBox(
                    key: const Key('customer-detail-vip'),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star, size: 18, color: scheme.primary),
                          const SizedBox(width: 4),
                          Text(
                            'مميز',
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (c.inWhatsappGroup)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Text(
                          'في الجروب',
                          key: const Key('customer-detail-whatsapp-group'),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (c.archived)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(start: 8),
                    child: Text(
                      'مؤرشف',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceMd),
            Row(
              children: [
                Expanded(
                  child: _ActionTile(
                    tileKey: const Key('customer-detail-call'),
                    label: 'اتصال',
                    icon: Icon(Icons.call_outlined, color: scheme.primary),
                    onTap: onCall,
                  ),
                ),
                const SizedBox(width: AppTokens.spaceSm),
                Expanded(
                  child: _ActionTile(
                    tileKey: const Key('customer-detail-whatsapp'),
                    label: 'واتساب',
                    icon: const CustomerWhatsappIcon(),
                    onTap: onWhatsapp,
                  ),
                ),
                if (onEdit != null) ...[
                  const SizedBox(width: AppTokens.spaceSm),
                  Expanded(
                    child: _ActionTile(
                      tileKey: const Key('customer-detail-edit'),
                      label: 'تعديل',
                      icon: Icon(Icons.edit_outlined, color: scheme.secondary),
                      onTap: onEdit,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// «ملخص المشتريات»: bought grams per karat, invoices and last operation.
class CustomerPurchaseSummary extends StatelessWidget {
  const CustomerPurchaseSummary({
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
    final s = customer.statistics;
    return Card(
      key: const Key('customer-detail-summary'),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ملخص المشتريات', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppTokens.spaceSm + 4),
            if (s == null)
              const Text('الإحصائيات غير متاحة؛ افتح الملف مجددًا لتحديثه.')
            else ...[
              CustomerKaratStrip(statistics: s, large: true),
              const SizedBox(height: AppTokens.spaceSm),
              Row(
                children: [
                  Expanded(
                    child: _InfoTile(
                      tileKey: const Key('customer-detail-invoices'),
                      icon: Icons.receipt_long_outlined,
                      label: 'إجمالي الفواتير',
                      value: '${customerCount(s.boughtCount)} فاتورة',
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceSm),
                  Expanded(
                    child: _InfoTile(
                      tileKey: const Key('customer-detail-last'),
                      icon: Icons.schedule,
                      label: 'آخر عملية',
                      value: _last(customer, today),
                    ),
                  ),
                ],
              ),
              if (!s.hasActivity) ...[
                const SizedBox(height: AppTokens.spaceSm),
                const Text(
                  'لا توجد عمليات مؤكدة مرتبطة؛ جميع الأوزان والأعداد صفر.',
                ),
              ],
              if (s.soldCount > BigInt.zero) ...[
                const SizedBox(height: AppTokens.spaceSm),
                Text(
                  'باع العميل للمحل: ${customerCount(s.soldCount)} عملية',
                  key: const Key('customer-detail-sold'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Wrap(
                  spacing: AppTokens.spaceSm,
                  children: [
                    for (final weight in s.weights)
                      if (weight.soldMilligrams > BigInt.zero)
                        Text(
                          '${weight.karat}K ${displayGrams(weight.soldMilligrams.toString())} g',
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.bodySmall,
                        ),
                  ],
                ),
              ],
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                s.lastOperation == null
                    ? 'لا توجد عملية مؤكدة مرتبطة لعرض تاريخها.'
                    : 'آخر عملية مؤكدة: ${_kinds[s.lastOperation!.kind] ?? s.lastOperation!.kind} · رقم \u2066${s.lastOperation!.sequence}\u2069 · \u2066${s.lastOperation!.createdAtShop.replaceFirst('T', ' ').split('.').first}\u2069',
                key: const Key('customer-detail-last-operation'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static const _kinds = {
    'sale': 'شراء العميل من المحل',
    'purchase': 'بيع العميل للمحل',
    'sale_return': 'مرتجع شراء العميل',
    'purchase_return': 'مرتجع بيع العميل للمحل',
  };

  static String _last(CustomerRecord c, DateTime today) {
    final at = c.lastAtShop;
    if (at == null) return 'لا توجد عمليات';
    return customerSince(at, today) ??
        at.substring(0, at.length < 10 ? at.length : 10);
  }
}

/// One entry of «إجراءات سريعة».
class CustomerQuickAction {
  const CustomerQuickAction({
    required this.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });

  final Key key;
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool destructive;
}

class CustomerQuickActions extends StatelessWidget {
  const CustomerQuickActions({super.key, required this.actions});

  final List<CustomerQuickAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: const Key('customer-detail-actions'),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 600 ? 3 : 2;
            final width =
                (constraints.maxWidth - AppTokens.spaceSm * (columns - 1)) /
                columns;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('إجراءات سريعة', style: theme.textTheme.titleMedium),
                const SizedBox(height: AppTokens.spaceSm + 4),
                Wrap(
                  spacing: AppTokens.spaceSm,
                  runSpacing: AppTokens.spaceSm,
                  children: [
                    for (final action in actions)
                      SizedBox(
                        width: width,
                        child: _ActionTile(
                          tileKey: action.key,
                          label: action.label,
                          icon: Icon(
                            action.icon,
                            color: action.destructive
                                ? scheme.error
                                : scheme.primary,
                          ),
                          onTap: action.onTap,
                          labelColor: action.destructive ? scheme.error : null,
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.tileKey,
    required this.label,
    required this.icon,
    required this.onTap,
    this.labelColor,
  });

  final Key tileKey;
  final String label;
  final Widget icon;
  final VoidCallback? onTap;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: AppSemanticColors.of(context).tableBorder),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: tileKey,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: labelColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.tileKey,
    required this.icon,
    required this.label,
    required this.value,
  });

  final Key tileKey;
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      key: tileKey,
      decoration: BoxDecoration(
        border: Border.all(color: AppSemanticColors.of(context).tableBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceSm + 2),
        child: Row(
          children: [
            Icon(icon, color: scheme.primary),
            const SizedBox(width: AppTokens.spaceSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(value, style: theme.textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
