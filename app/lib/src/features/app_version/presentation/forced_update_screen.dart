import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../theme/app_tokens.dart';
import '../../../theme/brand_mark.dart';
import '../application/app_version_evaluator.dart';

abstract final class ForcedUpdateCopy {
  static const title = 'يلزم تحديث التطبيق';
  static const openUpdate = 'فتح صفحة التحديث';
  static const retry = 'إعادة التحقق';
  static const retryHint =
      'بعد التحديث، اضغط إعادة التحقق. لا يمكن متابعة استخدام التطبيق قبل ذلك.';
  static const openFailed = 'تعذر فتح رابط التحديث. حاول من المتجر مباشرة.';

  static String versions(String current, String required) =>
      'الإصدار الحالي: \u2066$current\u2069\nالإصدار المطلوب: \u2066$required\u2069';
}

class ForcedUpdateScreen extends StatefulWidget {
  const ForcedUpdateScreen({
    super.key,
    required this.block,
    required this.onRetry,
    this.onToggleTheme,
  });

  final AppVersionBlock block;
  final Future<void> Function() onRetry;
  final Future<void> Function(Brightness)? onToggleTheme;

  @override
  State<ForcedUpdateScreen> createState() => _ForcedUpdateScreenState();
}

class _ForcedUpdateScreenState extends State<ForcedUpdateScreen> {
  bool _busy = false;
  String? _error;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onRetry();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = ForcedUpdateCopy.retryHint);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openUrl() async {
    final raw = widget.block.updateUrl;
    if (raw == null || raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    if (uri == null || uri.scheme != 'https') {
      setState(() => _error = ForcedUpdateCopy.openFailed);
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      setState(() => _error = ForcedUpdateCopy.openFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTokens.contentMaxWidth,
            ),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Row(
                  children: [
                    const BrandMark(),
                    const Spacer(),
                    if (widget.onToggleTheme != null)
                      IconButton(
                        tooltip: theme.brightness == Brightness.dark
                            ? 'المظهر الفاتح'
                            : 'المظهر الداكن',
                        onPressed: () =>
                            widget.onToggleTheme!(theme.brightness),
                        icon: const Icon(Icons.brightness_6_outlined),
                      ),
                  ],
                ),
                const SizedBox(height: 32),
                Text(
                  ForcedUpdateCopy.title,
                  key: const Key('forced-update-title'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.block.messageAr,
                  key: const Key('forced-update-message'),
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                Text(
                  ForcedUpdateCopy.versions(
                    widget.block.currentVersion,
                    widget.block.requiredVersion,
                  ),
                  key: const Key('forced-update-versions'),
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  ForcedUpdateCopy.retryHint,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    key: const Key('forced-update-error'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (widget.block.updateUrl != null &&
                    widget.block.updateUrl!.isNotEmpty)
                  FilledButton(
                    key: const Key('forced-update-open'),
                    onPressed: _busy ? null : _openUrl,
                    child: const Text(ForcedUpdateCopy.openUpdate),
                  ),
                if (widget.block.updateUrl != null &&
                    widget.block.updateUrl!.isNotEmpty)
                  const SizedBox(height: 12),
                OutlinedButton(
                  key: const Key('forced-update-retry'),
                  onPressed: _busy ? null : _retry,
                  child: Text(
                    _busy ? 'جارٍ التحقق…' : ForcedUpdateCopy.retry,
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
