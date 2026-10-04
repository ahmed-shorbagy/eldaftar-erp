import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../../daily_ledger/presentation/ledger_form_fields.dart';
import '../../onboarding/presentation/guide_card.dart';
import '../domain/inventory_models.dart';
import 'inventory_copy.dart';

class InventoryPage extends StatelessWidget {
  const InventoryPage({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.scrollController,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: actions),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTokens.contentMaxWidth,
            ),
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: children,
            ),
          ),
        ),
      ),
    );
  }
}

class InventoryNotice extends StatelessWidget {
  const InventoryNotice({
    super.key,
    required this.message,
    this.error = false,
    this.messageKey = const Key('inventory-status'),
  });

  final String message;
  final bool error;
  final Key messageKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      container: true,
      child: Text(
        message,
        key: messageKey,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: error ? scheme.error : scheme.onSurface,
          height: 1.5,
        ),
      ),
    );
  }
}

class EffectList extends StatelessWidget {
  const EffectList(this.command, {super.key});
  final ReviewedCommand command;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      key: const Key('command-effects'),
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'أثر الأمر قبل التأكيد',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            for (final effect in command.effects)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  effectCopy(effect),
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    height: 1.45,
                  ),
                ),
              ),
            if (command.effects.isEmpty)
              Text(
                'لا يغير هذا الأمر النقد أو الذهب.',
                style: TextStyle(color: scheme.onPrimaryContainer),
              ),
            for (final note in command.notes)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  inventoryNoteCopy(note),
                  style: TextStyle(
                    color: scheme.onPrimaryContainer,
                    height: 1.45,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'لن يُحتسب الأمر محفوظاً قبل رد الخادم.',
              style: TextStyle(color: scheme.onPrimaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}

class CommandActions extends StatelessWidget {
  const CommandActions({
    super.key,
    required this.busy,
    required this.readOnly,
    required this.canReview,
    required this.canSubmit,
    required this.unconfirmed,
    required this.onReview,
    required this.onSubmit,
    required this.onRetry,
  });

  final bool busy;
  final bool readOnly;
  final bool canReview;
  final bool canSubmit;
  final bool unconfirmed;
  final VoidCallback onReview;
  final VoidCallback onSubmit;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton(
          key: const Key('command-review'),
          onPressed: busy || readOnly || unconfirmed || !canReview
              ? null
              : onReview,
          child: const Text('مراجعة الأثر'),
        ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('command-submit'),
          onPressed: busy || readOnly || unconfirmed || !canSubmit
              ? null
              : onSubmit,
          child: Text(busy ? 'جارٍ الإرسال' : 'تأكيد الأمر'),
        ),
        if (unconfirmed) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            key: const Key('command-retry'),
            onPressed: busy ? null : onRetry,
            child: const Text('التحقق وإعادة المحاولة بالمفتاح نفسه'),
          ),
        ],
      ],
    );
  }
}

Widget inventoryField({
  required BuildContext context,
  required TextEditingController controller,
  required String label,
  required Key fieldKey,
  FocusNode? focusNode,
  TextInputType keyboard = TextInputType.text,
  TextInputAction action = TextInputAction.next,
  bool enabled = true,
  int maxLength = 200,
}) {
  return TextField(
    key: fieldKey,
    controller: controller,
    focusNode: focusNode,
    enabled: enabled,
    maxLength: maxLength,
    keyboardType: keyboard,
    textInputAction: action,
    decoration: ledgerFieldDecoration(context, label: label),
  );
}

class InventoryGuide extends StatelessWidget {
  const InventoryGuide({
    super.key,
    required this.steps,
    required this.step,
    required this.onAction,
    required this.onSkip,
  });

  final List<({String title, String description, String action})> steps;
  final int step;
  final VoidCallback onAction;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final current = steps[step.clamp(0, steps.length - 1)];
    return GuideCard(
      title: current.title,
      description: current.description,
      progress: '${step + 1} / ${steps.length}',
      actionLabel: current.action,
      onAction: onAction,
      onSkip: onSkip,
    );
  }
}
