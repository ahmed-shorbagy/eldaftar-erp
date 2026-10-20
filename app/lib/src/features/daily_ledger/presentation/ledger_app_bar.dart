import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../shell/shell_copy.dart';
import '../../../theme/brand_mark.dart';
import '../../../theme/app_tokens.dart';

/// Soft, jewelry-ledger header used above the daily workspace.
class LedgerAppBar extends StatelessWidget implements PreferredSizeWidget {
  const LedgerAppBar({
    super.key,
    required this.shopName,
    required this.onToggleTheme,
    required this.topInset,
    this.subtitle,
    this.shopImageBytes,
    this.onChangeShop,
    this.compact = false,
    this.textScaler = TextScaler.noScaling,
  });

  final String shopName;
  final String? subtitle;
  final Uint8List? shopImageBytes;
  final Future<void> Function(Brightness) onToggleTheme;
  final VoidCallback? onChangeShop;
  final double topInset;
  final bool compact;
  final TextScaler textScaler;

  static const double bodyHeight = 108;

  @override
  Size get preferredSize {
    final textHeight =
        textScaler.scale(compact ? AppTokens.bodySize : AppTokens.titleSize) *
            2.3 +
        2 +
        textScaler.scale(AppTokens.detailSize) * 1.5 +
        (subtitle == null || subtitle!.isEmpty
            ? 0
            : 2 + textScaler.scale(AppTokens.labelSize) * 1.2);
    return Size.fromHeight(
      topInset + (textHeight + 24).clamp(bodyHeight, double.infinity),
    );
  }

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
              _ShopMark(bytes: shopImageBytes, dark: dark, scheme: scheme),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'أهلاً $shopName',
                      key: const Key('ledger-title'),
                      maxLines: 2,
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
                      'الدفتر اليومي',
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

class _ShopMark extends StatelessWidget {
  const _ShopMark({
    required this.bytes,
    required this.dark,
    required this.scheme,
  });

  final Uint8List? bytes;
  final bool dark;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'صورة المتجر',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: dark ? 0.4 : 0.75),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: scheme.primary.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 48,
            height: 48,
            child: bytes == null
                ? const Padding(
                    padding: EdgeInsets.all(10),
                    child: BrandMark(size: 28),
                  )
                : Image.memory(
                    bytes!,
                    key: const Key('ledger-shop-image'),
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
          ),
        ),
      ),
    );
  }
}

class _PillIconButton extends StatelessWidget {
  const _PillIconButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 6),
      child: DecoratedBox(
        decoration: _pillDecoration(scheme),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          visualDensity: VisualDensity.compact,
          style: IconButton.styleFrom(
            shape: const StadiumBorder(),
            minimumSize: const Size(48, 48),
            tapTargetSize: MaterialTapTargetSize.padded,
          ),
          icon: Icon(icon, size: 20),
        ),
      ),
    );
  }
}
