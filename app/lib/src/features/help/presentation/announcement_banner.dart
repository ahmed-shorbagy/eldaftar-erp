import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../domain/help_models.dart';

abstract final class AnnouncementCopy {
  static const dismiss = 'إخفاء';
  static const openLink = 'فتح الرابط';
}

class AnnouncementBanner extends StatelessWidget {
  const AnnouncementBanner({
    super.key,
    required this.announcement,
    required this.onDismiss,
  });

  final PlatformAnnouncement announcement;
  final VoidCallback onDismiss;

  Future<void> _openLink() async {
    final raw = announcement.linkUrl;
    if (raw == null) return;
    final uri = Uri.tryParse(raw);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: announcement.titleAr,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.35),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                announcement.titleAr,
                key: const Key('platform-announcement-title'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                announcement.bodyAr,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (announcement.linkUrl != null)
                    FilledButton(
                      key: const Key('platform-announcement-link'),
                      onPressed: _openLink,
                      child: const Text(AnnouncementCopy.openLink),
                    ),
                  OutlinedButton(
                    key: const Key('platform-announcement-dismiss'),
                    onPressed: onDismiss,
                    child: const Text(AnnouncementCopy.dismiss),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
