import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'message_tone.dart';

/// Decision dialog (messaging tier 5). Use only when the owner must choose
/// before anything happens: delete, discard, open/close a day, revoke.
///
/// The title is a question, the message states the consequence, the action
/// button names the verb («مسح الملاحظة», «تجاهل العدّ») and the safe choice
/// is the default. Back, a tap outside, or the safe button all return false.
Future<bool> showAppConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'إلغاء',
  bool destructive = false,
  Key? confirmKey,
  Key? cancelKey,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialog) => AppConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      destructive: destructive,
      confirmKey: confirmKey,
      cancelKey: cancelKey,
    ),
  );
  return result == true;
}

class AppConfirmDialog extends StatelessWidget {
  const AppConfirmDialog({
    super.key,
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.cancelLabel = 'إلغاء',
    this.destructive = false,
    this.confirmKey,
    this.cancelKey,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final String cancelLabel;
  final bool destructive;
  final Key? confirmKey;
  final Key? cancelKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tone = destructive ? MessageTone.error : MessageTone.warning;
    final colors = MessageColors.of(scheme, tone);
    return AlertDialog(
      key: const Key('app-confirm'),
      icon: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.container,
            shape: BoxShape.circle,
            border: Border.all(color: colors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              destructive
                  ? Icons.delete_outline_rounded
                  : Icons.help_outline_rounded,
              color: colors.accent,
              size: 28,
            ),
          ),
        ),
      ),
      title: Text(title, textAlign: TextAlign.center),
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          height: 1.5,
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actionsOverflowButtonSpacing: AppTokens.spaceSm,
      actions: [
        OutlinedButton(
          key: cancelKey,
          autofocus: true,
          onPressed: () => Navigator.pop(context, false),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(96, AppTokens.minControlSize),
          ),
          child: Text(cancelLabel),
        ),
        FilledButton(
          key: confirmKey,
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            minimumSize: const Size(96, AppTokens.minControlSize),
            backgroundColor: destructive ? scheme.error : null,
            foregroundColor: destructive ? scheme.onError : null,
          ),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
