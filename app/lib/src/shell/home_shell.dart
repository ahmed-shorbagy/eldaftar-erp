import 'package:flutter/material.dart';

import '../config/supabase_startup.dart';
import '../theme/app_tokens.dart';
import 'shell_copy.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({
    super.key,
    required this.supabaseStatus,
    required this.onToggleTheme,
    this.onSignOut,
    this.shopName,
    this.onChangeShop,
  });

  final SupabaseStartupStatus supabaseStatus;
  final Future<void> Function(Brightness resolvedBrightness) onToggleTheme;
  final Future<void> Function()? onSignOut;
  final String? shopName;
  final VoidCallback? onChangeShop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= AppTokens.wideBreakpoint;

    return Scaffold(
      appBar: AppBar(
        title: const Text(ShellCopy.appTitle),
        actions: [
          if (onChangeShop != null)
            IconButton(
              tooltip: 'اختيار متجر آخر',
              onPressed: onChangeShop,
              icon: const Icon(Icons.storefront_outlined),
            ),
          if (onSignOut != null)
            IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: onSignOut,
              icon: const Icon(Icons.logout),
            ),
          IconButton(
            key: const Key('theme-toggle'),
            tooltip: isDark ? ShellCopy.toggleToLight : ShellCopy.toggleToDark,
            color: scheme.onSurface,
            onPressed: () => onToggleTheme(theme.brightness),
            icon: Icon(
              isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTokens.contentMaxWidth,
            ),
            child: ListView(
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 32 : 20,
                vertical: wide ? 32 : 20,
              ),
              children: [
                if (shopName != null) ...[
                  Text(shopName!, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                ],
                const _PrototypeBanner(),
                const SizedBox(height: 16),
                _StatusCard(status: supabaseStatus),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrototypeBanner extends StatelessWidget {
  const _PrototypeBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ShellCopy.prototypeLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              ShellCopy.prototypeBody,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onPrimaryContainer,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});

  final SupabaseStartupStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (title, body) = switch (status) {
      SupabaseStartupStatus.missingConfiguration => (
        ShellCopy.missingTitle,
        ShellCopy.missingBody,
      ),
      SupabaseStartupStatus.ready => (
        ShellCopy.readyTitle,
        ShellCopy.readyBody,
      ),
      SupabaseStartupStatus.failed => (
        ShellCopy.failedTitle,
        ShellCopy.failedBody,
      ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              key: const Key('supabase-status-title'),
              style: theme.textTheme.titleLarge?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              body,
              key: const Key('supabase-status-body'),
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurface,
                height: 1.6,
              ),
            ),
            if (status == SupabaseStartupStatus.missingConfiguration) ...[
              const SizedBox(height: 12),
              Text(
                ShellCopy.missingHint,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: scheme.onSurface,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 12),
              const _DefineExample(),
            ],
          ],
        ),
      ),
    );
  }
}

class _DefineExample extends StatelessWidget {
  const _DefineExample();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SelectableText(
            ShellCopy.defineExample,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              height: 1.6,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}
