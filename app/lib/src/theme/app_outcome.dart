import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'message_tone.dart';

/// One confirmed figure on an outcome screen, such as the total or the gold
/// weight per karat, as already formatted by `amount_format.dart`.
class OutcomeFigure {
  const OutcomeFigure(this.label, this.value);

  final String label;
  final String value;
}

/// Outcome screen body (messaging tier 1): shown in place of the review once
/// the server confirms an operation that changes cash, stock or balances.
/// It names the operation, quotes the confirmed figures and leaves the next
/// actions to the caller.
class AppOutcome extends StatelessWidget {
  const AppOutcome({
    super.key,
    required this.title,
    this.titleKey,
    this.subtitle,
    this.figures = const [],
    this.figuresKey,
    this.tone = MessageTone.success,
    this.children = const [],
  });

  final String title;
  final Key? titleKey;
  final String? subtitle;
  final List<OutcomeFigure> figures;
  final Key? figuresKey;
  final MessageTone tone;

  /// Next actions or notes under the figures.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = MessageColors.of(theme.colorScheme, tone);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppTokens.spaceLg),
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.container,
                shape: BoxShape.circle,
                border: Border.all(color: colors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: ExcludeSemantics(
                  child: Icon(
                    messageIcon(tone),
                    size: 52,
                    color: colors.accent,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Text(
            title,
            key: titleKey,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (figures.isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceMd),
            DecoratedBox(
              key: figuresKey,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppTokens.fieldRadius),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTokens.spaceMd,
                  vertical: AppTokens.spaceSm,
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < figures.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          color: theme.colorScheme.outlineVariant,
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                figures[i].label,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppTokens.spaceSm),
                            Flexible(
                              child: Text(
                                figures[i].value,
                                textAlign: TextAlign.end,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          ...children,
        ],
      ),
    );
  }
}
