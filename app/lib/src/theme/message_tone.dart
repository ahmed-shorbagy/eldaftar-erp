import 'package:flutter/material.dart';

/// The meaning of a user-facing message. Every toast and inline banner picks
/// exactly one tone; the tone decides its icon and semantic colour roles.
enum MessageTone { success, info, warning, error, pending }

/// Colour roles for a [MessageTone], derived from the active [ColorScheme]
/// so light and dark themes stay on the shared tokens (no component hex).
@immutable
class MessageColors {
  const MessageColors({
    required this.container,
    required this.border,
    required this.accent,
    required this.onContainer,
    required this.onContainerMuted,
  });

  factory MessageColors.of(ColorScheme scheme, MessageTone tone) {
    final dark = scheme.brightness == Brightness.dark;
    final accent = switch (tone) {
      MessageTone.success => scheme.tertiary,
      MessageTone.error => scheme.error,
      MessageTone.warning => scheme.secondary,
      MessageTone.pending => scheme.primary,
      MessageTone.info => scheme.onSurfaceVariant,
    };
    final base = scheme.surfaceContainerHigh;
    final tint = tone == MessageTone.info ? 0.0 : (dark ? 0.18 : 0.11);
    return MessageColors(
      container: Color.alphaBlend(accent.withValues(alpha: tint), base),
      border: accent.withValues(alpha: tone == MessageTone.info ? 0.28 : 0.55),
      accent: accent,
      onContainer: scheme.onSurface,
      onContainerMuted: scheme.onSurfaceVariant,
    );
  }

  final Color container;
  final Color border;
  final Color accent;
  final Color onContainer;
  final Color onContainerMuted;
}

IconData messageIcon(MessageTone tone) => switch (tone) {
  MessageTone.success => Icons.check_circle_rounded,
  MessageTone.info => Icons.info_outline_rounded,
  MessageTone.warning => Icons.warning_amber_rounded,
  MessageTone.error => Icons.error_outline_rounded,
  MessageTone.pending => Icons.schedule_rounded,
};

/// Arabic label read by screen readers before the message text.
String messageToneLabel(MessageTone tone) => switch (tone) {
  MessageTone.success => 'تم',
  MessageTone.info => 'تنبيه',
  MessageTone.warning => 'تحذير',
  MessageTone.error => 'خطأ',
  MessageTone.pending => 'قيد الانتظار',
};
