import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'message_tone.dart';

/// Inline banner (messaging tier 3): a lasting condition of the screen it sits
/// in — pending confirmation, refresh failed, offline, read-only, a rejected
/// request. It stays until the condition clears and carries at most one action.
class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.tone,
    required this.title,
    this.message,
    this.titleKey,
    this.actionLabel,
    this.onAction,
    this.actionKey,
    this.action,
  }) : assert(
         action == null || actionLabel == null,
         'Pass either a custom action or actionLabel/onAction.',
       );

  final MessageTone tone;
  final String title;
  final String? message;

  /// Key placed on the title text, so callers keep their existing test keys.
  final Key? titleKey;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Key? actionKey;

  /// A custom trailing control, for callers that already own one.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = MessageColors.of(theme.colorScheme, tone);
    final trailing =
        action ??
        (actionLabel == null
            ? null
            : TextButton(
                key: actionKey,
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: tone == MessageTone.info
                      ? theme.colorScheme.primary
                      : colors.accent,
                  minimumSize: const Size(
                    AppTokens.minControlSize,
                    AppTokens.minControlSize,
                  ),
                  textStyle: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(actionLabel!),
              ));
    return Semantics(
      container: true,
      liveRegion: tone == MessageTone.error || tone == MessageTone.pending,
      label: messageToneLabel(tone),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.container,
          borderRadius: BorderRadius.circular(AppTokens.fieldRadius),
          border: Border.all(color: colors.border),
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            12,
            10,
            trailing == null ? 12 : 4,
            10,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ExcludeSemantics(
                child: tone == MessageTone.pending
                    ? SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: colors.accent,
                        ),
                      )
                    : Icon(messageIcon(tone), size: 22, color: colors.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      key: titleKey,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onContainer,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                    if (message != null)
                      Text(
                        message!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onContainerMuted,
                          height: 1.5,
                        ),
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}
