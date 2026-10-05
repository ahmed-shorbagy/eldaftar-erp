import 'package:flutter/material.dart';

import '../../../shell/shell_copy.dart';
import '../../../theme/brand_mark.dart';

/// Soft, jewelry-ledger header used above the daily workspace.
class LedgerAppBar extends StatelessWidget implements PreferredSizeWidget {
  const LedgerAppBar({
    super.key,
    required this.shopName,
    required this.onRefresh,
    required this.onToggleTheme,
    required this.onSignOut,
    required this.refreshFocus,
    required this.topInset,
    this.subtitle,
    this.onChangeShop,
    this.compact = false,
  });

  final String shopName;
  final String? subtitle;
  final VoidCallback onRefresh;
  final Future<void> Function(Brightness) onToggleTheme;
  final Future<void> Function() onSignOut;
  final VoidCallback? onChangeShop;
  final FocusNode refreshFocus;
  final double topInset;
  final bool compact;

  static const double bodyHeight = 108;

  @override
  Size get preferredSize => Size.fromHeight(topInset + bodyHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: Container(
        height: preferredSize.height,
        padding: EdgeInsets.only(top: topInset),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scheme.primaryContainer.withValues(alpha: dark ? 0.58 : 0.78),
              scheme.surface.withValues(alpha: 0.98),
            ],
          ),
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(28),
          ),
          border: Border(
            bottom: BorderSide(color: scheme.primary.withValues(alpha: 0.2)),
          ),
          boxShadow: [
            BoxShadow(
              color: scheme.shadow.withValues(alpha: dark ? 0.35 : 0.08),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compact ? 14 : 20,
            8,
            compact ? 10 : 16,
            14,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: dark ? 0.4 : 0.75),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.35),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withValues(alpha: 0.12),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: BrandMark(size: 28),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'الدفتر اليومي',
                      key: const Key('ledger-title'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          (compact
                                  ? theme.textTheme.titleMedium
                                  : theme.textTheme.titleLarge)
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                height: 1.15,
                              ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      shopName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              _PillIconButton(
                tooltip: 'تحديث الدفتر',
                focusNode: refreshFocus,
                onPressed: onRefresh,
                icon: Icons.refresh_rounded,
              ),
              if (compact)
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 6),
                  child: DecoratedBox(
                    decoration: _pillDecoration(scheme),
                    child: PopupMenuButton<String>(
                      tooltip: 'المزيد',
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      onSelected: (value) {
                        switch (value) {
                          case 'shop':
                            onChangeShop?.call();
                          case 'theme':
                            onToggleTheme(theme.brightness);
                          case 'signout':
                            onSignOut();
                        }
                      },
                      itemBuilder: (context) => [
                        if (onChangeShop != null)
                          const PopupMenuItem(
                            value: 'shop',
                            child: Text('اختيار متجر آخر'),
                          ),
                        PopupMenuItem(
                          value: 'theme',
                          child: Text(
                            theme.brightness == Brightness.dark
                                ? ShellCopy.toggleToLight
                                : ShellCopy.toggleToDark,
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'signout',
                          child: Text('تسجيل الخروج'),
                        ),
                      ],
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.more_horiz_rounded, size: 20),
                      ),
                    ),
                  ),
                )
              else ...[
                if (onChangeShop != null)
                  _PillIconButton(
                    tooltip: 'اختيار متجر آخر',
                    onPressed: onChangeShop,
                    icon: Icons.storefront_outlined,
                  ),
                _PillIconButton(
                  key: const Key('theme-toggle'),
                  tooltip: theme.brightness == Brightness.dark
                      ? ShellCopy.toggleToLight
                      : ShellCopy.toggleToDark,
                  onPressed: () => onToggleTheme(theme.brightness),
                  icon: theme.brightness == Brightness.dark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                ),
                _PillIconButton(
                  tooltip: 'تسجيل الخروج',
                  onPressed: onSignOut,
                  icon: Icons.logout_rounded,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

BoxDecoration _pillDecoration(ColorScheme scheme) => BoxDecoration(
  color: scheme.surface.withValues(alpha: 0.55),
  borderRadius: BorderRadius.circular(999),
  border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.65)),
);

class _PillIconButton extends StatelessWidget {
  const _PillIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
    this.focusNode,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 6),
      child: DecoratedBox(
        decoration: _pillDecoration(scheme),
        child: IconButton(
          tooltip: tooltip,
          focusNode: focusNode,
          onPressed: onPressed,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            shape: const StadiumBorder(),
            minimumSize: const Size(44, 44),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          icon: Icon(icon, size: 20),
        ),
      ),
    );
  }
}
