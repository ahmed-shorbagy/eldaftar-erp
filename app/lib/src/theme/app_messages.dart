import 'dart:async';

import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'message_tone.dart';

/// Toast messaging (tier 2): short confirmations and non-blocking notices
/// raised after the owner returns to their context.
///
/// This is the only place in `lib/` that may talk to [ScaffoldMessenger];
/// `test/app_messages_test.dart` fails if any other file builds a SnackBar.
/// The app-level messenger lives above the navigator, so a toast raised just
/// before a route pops is shown on the destination screen.
abstract final class AppMessages {
  static const _mergeWindow = Duration(seconds: 3);
  static const _maxQueued = 3;
  static final Expando<_MessengerLog> _logs = Expando('app-messages');

  /// Clock seam for tests.
  static DateTime Function() now = DateTime.now;

  static void success(
    BuildContext context,
    String title, {
    String? body,
    String? id,
  }) => show(
    context,
    tone: MessageTone.success,
    title: title,
    body: body,
    id: id,
  );

  static void info(
    BuildContext context,
    String title, {
    String? body,
    String? id,
  }) => show(context, tone: MessageTone.info, title: title, body: body, id: id);

  static void warning(
    BuildContext context,
    String title, {
    String? body,
    String? id,
    String? actionLabel,
    VoidCallback? onAction,
  }) => show(
    context,
    tone: MessageTone.warning,
    title: title,
    body: body,
    id: id,
    actionLabel: actionLabel,
    onAction: onAction,
  );

  static void error(
    BuildContext context,
    String title, {
    String? body,
    String? id,
    String? actionLabel,
    VoidCallback? onAction,
  }) => show(
    context,
    tone: MessageTone.error,
    title: title,
    body: body,
    id: id,
    actionLabel: actionLabel,
    onAction: onAction,
  );

  /// Shows a toast. [id] identifies the event: a newer toast with the same id
  /// replaces the visible one; an identical toast within three seconds merges
  /// into it. Without an id the title and body identify it.
  static void show(
    BuildContext context, {
    required MessageTone tone,
    required String title,
    String? body,
    String? id,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    assert(
      (actionLabel == null) == (onAction == null),
      'actionLabel and onAction go together.',
    );
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final log = _logs[messenger] ??= _MessengerLog();
    final key = id ?? '$tone|$title|${body ?? ''}';
    final signature = '$tone|$title|${body ?? ''}|${actionLabel ?? ''}';
    final at = now();
    final visible = log.visible;
    if (visible != null && visible.key == key) {
      if (visible.signature == signature &&
          at.difference(visible.shownAt) < _mergeWindow) {
        return;
      }
      messenger.removeCurrentSnackBar(reason: SnackBarClosedReason.remove);
    } else if (log.queued >= _maxQueued &&
        tone != MessageTone.error &&
        tone != MessageTone.warning) {
      return;
    }
    final media = MediaQuery.maybeOf(context);
    final direction = Directionality.maybeOf(context) ?? TextDirection.rtl;
    final width = media?.size.width ?? 0;
    final entry = _Shown(key, signature, at);
    log.queued += 1;
    final controller = messenger.showSnackBar(
      SnackBar(
        key: ValueKey('app-message:$key'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: _margin(width, direction),
        // The toast owns its timer so it can pause; this is only a backstop.
        duration: const Duration(minutes: 10),
        dismissDirection: DismissDirection.horizontal,
        content: AppToast(
          tone: tone,
          title: title,
          body: body,
          actionLabel: actionLabel,
          onAction: onAction,
          onShown: () {
            log.visible = entry;
            entry.shownAt = now();
          },
        ),
      ),
      snackBarAnimationStyle: (media?.disableAnimations ?? false)
          ? AnimationStyle.noAnimation
          : null,
    );
    controller.closed.whenComplete(() {
      log.queued -= 1;
      if (identical(log.visible, entry)) log.visible = null;
    });
  }

  /// Removes the visible toast and every queued one. Called on sign-out and
  /// account changes so no message carries into another session.
  static void clear(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.clearSnackBars();
    final log = _logs[messenger];
    log?.visible = null;
  }

  /// How long a toast stays: success 4 s, info 5 s, warning/error 6 s, plus
  /// 50 ms per character beyond 60, capped at 10 s; at least 8 s with an
  /// action.
  static Duration durationFor(
    MessageTone tone,
    String title,
    String? body, {
    bool hasAction = false,
  }) {
    final base = switch (tone) {
      MessageTone.success => 4000,
      MessageTone.info || MessageTone.pending => 5000,
      MessageTone.warning || MessageTone.error => 6000,
    };
    final length = title.length + (body?.length ?? 0);
    var millis = base + (length > 60 ? (length - 60) * 50 : 0);
    if (millis > 10000) millis = 10000;
    if (hasAction && millis < 8000) millis = 8000;
    return Duration(milliseconds: millis);
  }

  static EdgeInsets _margin(double width, TextDirection direction) {
    const gutter = AppTokens.ledgerPhoneGutter;
    if (width < AppTokens.wideBreakpoint) {
      return const EdgeInsets.fromLTRB(gutter, 0, gutter, gutter);
    }
    // Wide layouts: a 480-pixel card in the bottom-start corner.
    const side = AppTokens.spaceLg;
    final far = width - side - _wideWidth;
    return direction == TextDirection.rtl
        ? EdgeInsets.fromLTRB(far, 0, side, side)
        : EdgeInsets.fromLTRB(side, 0, far, side);
  }

  static const double _wideWidth = 480;
}

class _MessengerLog {
  _Shown? visible;
  int queued = 0;
}

class _Shown {
  _Shown(this.key, this.signature, this.shownAt);
  final String key;
  final String signature;
  DateTime shownAt;
}

/// The toast card. Public so tests and previews can pump it directly.
class AppToast extends StatefulWidget {
  const AppToast({
    super.key,
    required this.tone,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    this.onShown,
  });

  final MessageTone tone;
  final String title;
  final String? body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onShown;

  @override
  State<AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<AppToast> {
  Timer? _timer;
  late Duration _remaining;
  DateTime? _startedAt;
  bool _held = false;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _remaining = AppMessages.durationFor(
      widget.tone,
      widget.title,
      widget.body,
      hasAction: widget.actionLabel != null,
    );
    widget.onShown?.call();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _resume();
  }

  bool get _screenReader =>
      MediaQuery.maybeOf(context)?.accessibleNavigation ?? false;

  void _resume() {
    if (_held || _screenReader || _timer != null) return;
    _startedAt = DateTime.now();
    _timer = Timer(_remaining, _close);
  }

  void _pause() {
    final timer = _timer;
    if (timer == null) return;
    timer.cancel();
    _timer = null;
    final started = _startedAt;
    if (started != null) {
      final left = _remaining - DateTime.now().difference(started);
      _remaining = left.isNegative ? Duration.zero : left;
    }
  }

  void _hold(bool held) {
    _held = held;
    held ? _pause() : _resume();
  }

  void _close([SnackBarClosedReason reason = SnackBarClosedReason.timeout]) {
    _timer?.cancel();
    _timer = null;
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar(reason: reason);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = MessageColors.of(theme.colorScheme, widget.tone);
    final action = widget.actionLabel;
    // At large text sizes the action moves under the text so nothing
    // overflows or truncates.
    final stacked =
        action != null &&
        MediaQuery.textScalerOf(context).scale(AppTokens.detailSize) >
            AppTokens.detailSize * 1.3;
    final actionButton = action == null
        ? null
        : TextButton(
            key: const Key('app-toast-action'),
            onPressed: () {
              _close(SnackBarClosedReason.action);
              widget.onAction?.call();
            },
            style: TextButton.styleFrom(
              foregroundColor: widget.tone == MessageTone.info
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
            child: Text(action),
          );
    return MouseRegion(
      onEnter: (_) => _hold(true),
      onExit: (_) => _hold(false),
      child: Listener(
        onPointerDown: (_) => _hold(true),
        onPointerUp: (_) => _hold(false),
        onPointerCancel: (_) => _hold(false),
        child: Semantics(
          container: true,
          label: messageToneLabel(widget.tone),
          child: Material(
            key: const Key('app-toast'),
            color: colors.container,
            elevation: 3,
            shadowColor: theme.colorScheme.shadow.withValues(alpha: 0.35),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTokens.cardRadius - 6),
              side: BorderSide(color: colors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ColoredBox(
                    color: colors.accent,
                    child: const SizedBox(width: 4),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(
                      start: 12,
                      top: 12,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.topCenter,
                      child: ExcludeSemantics(
                        child: Icon(
                          messageIcon(widget.tone),
                          size: 24,
                          color: colors.accent,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.title,
                            key: const Key('app-toast-title'),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onContainer,
                              fontWeight: FontWeight.w600,
                              height: 1.5,
                            ),
                          ),
                          if (widget.body != null)
                            Text(
                              widget.body!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onContainerMuted,
                                height: 1.5,
                              ),
                            ),
                          if (actionButton != null && stacked)
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: actionButton,
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (actionButton != null && !stacked)
                    Center(child: actionButton),
                  Align(
                    alignment: stacked
                        ? AlignmentDirectional.topCenter
                        : AlignmentDirectional.center,
                    child: IconButton(
                      key: const Key('app-toast-close'),
                      tooltip: 'إغلاق الرسالة',
                      onPressed: () => _close(SnackBarClosedReason.dismiss),
                      color: colors.onContainerMuted,
                      constraints: const BoxConstraints.tightFor(
                        width: AppTokens.minControlSize,
                        height: AppTokens.minControlSize,
                      ),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
