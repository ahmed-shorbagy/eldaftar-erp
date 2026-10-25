import 'package:flutter/material.dart';

import '../domain/shop_account.dart';

/// Arabic copy for the server-timed subscription notice banner.
abstract final class SubscriptionNoticeCopy {
  static const dismiss = 'إخفاء التنبيه';
  static const renew = 'تجديد الاشتراك';
  static const dismissFailed = 'تعذر إخفاء التنبيه. حاول مجددًا.';
  static const dismissPending = 'جارٍ إخفاء التنبيه…';

  static String renewalBody(String expiryText) =>
      'ينتهي الاشتراك قريبًا. الكتابة متاحة حتى \u2066$expiryText\u2069 حسب توقيت الخادم. جدّد الرمز قبل الانتهاء.';

  static const expiredBody =
      'انتهى الاشتراك. يمكنك إخفاء هذا التنبيه؛ العرض يبقى للقراءة فقط حتى التجديد.';
}

String subscriptionNoticeExpiryText(DateTime expiresAt) {
  final utc = expiresAt.toUtc();
  final y = utc.year.toString().padLeft(4, '0');
  final m = utc.month.toString().padLeft(2, '0');
  final d = utc.day.toString().padLeft(2, '0');
  final h = utc.hour.toString().padLeft(2, '0');
  final min = utc.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $h:$min UTC';
}

class SubscriptionNoticeBanner extends StatelessWidget {
  const SubscriptionNoticeBanner({
    super.key,
    required this.notice,
    required this.dismissing,
    required this.dismissFailed,
    required this.onDismiss,
    this.onRenew,
  });

  final SubscriptionNotice notice;
  final bool dismissing;
  final bool dismissFailed;
  final VoidCallback onDismiss;
  final VoidCallback? onRenew;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final renewal = notice.kind == SubscriptionNoticeKind.renewalDue;
    final title = renewal ? 'تذكير بتجديد الاشتراك' : 'انتهى الاشتراك';
    final body = renewal
        ? SubscriptionNoticeCopy.renewalBody(
            subscriptionNoticeExpiryText(notice.expiresAt),
          )
        : SubscriptionNoticeCopy.expiredBody;
    return Semantics(
      container: true,
      label: title,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: renewal
              ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.65)
              : theme.colorScheme.errorContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: renewal
                ? theme.colorScheme.secondary.withValues(alpha: 0.35)
                : theme.colorScheme.error.withValues(alpha: 0.35),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                key: const Key('subscription-notice-title'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: renewal
                      ? theme.colorScheme.onSecondaryContainer
                      : theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 6),
              Text(body, key: const Key('subscription-notice-body')),
              if (dismissFailed) ...[
                const SizedBox(height: 8),
                Text(
                  SubscriptionNoticeCopy.dismissFailed,
                  key: const Key('subscription-notice-dismiss-error'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
              if (dismissing) ...[
                const SizedBox(height: 8),
                const Text(
                  SubscriptionNoticeCopy.dismissPending,
                  key: Key('subscription-notice-dismiss-pending'),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: const Key('subscription-notice-dismiss'),
                    onPressed: dismissing ? null : onDismiss,
                    child: const Text(SubscriptionNoticeCopy.dismiss),
                  ),
                  if (onRenew != null)
                    FilledButton(
                      key: const Key('subscription-notice-renew'),
                      onPressed: dismissing ? null : onRenew,
                      child: const Text(SubscriptionNoticeCopy.renew),
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
