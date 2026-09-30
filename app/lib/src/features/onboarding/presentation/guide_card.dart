import 'package:flutter/material.dart';

/// A compact, skippable guide that acts on the live control behind each step.
class GuideCard extends StatelessWidget {
  const GuideCard({
    super.key,
    required this.title,
    required this.description,
    required this.progress,
    required this.actionLabel,
    required this.onAction,
    required this.onSkip,
  });

  final String title;
  final String description;
  final String progress;
  final String actionLabel;
  final VoidCallback onAction;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      key: const Key('onboarding-guide'),
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: scheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  progress,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onPrimaryContainer,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  key: const Key('onboarding-skip'),
                  onPressed: onSkip,
                  child: const Text('تخطي الإرشاد'),
                ),
                OutlinedButton(
                  key: const Key('onboarding-action'),
                  onPressed: onAction,
                  child: Text(actionLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
