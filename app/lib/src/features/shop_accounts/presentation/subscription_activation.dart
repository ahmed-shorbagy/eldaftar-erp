import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_tokens.dart';
import '../../auth/domain/owner_registration.dart';
import '../domain/shop_account.dart';
import '../domain/shop_account_gateway.dart';

abstract final class SubscriptionCopy {
  static const pendingTitle = 'تفعيل الاشتراك';
  static const expiredTitle = 'تجديد الاشتراك';
  static const pendingBody =
      'الحساب ينتظر التفعيل. أدخل رمز الاشتراك الذي استلمته لتفعيل المتجر.';
  static const expiredBody =
      'انتهى الاشتراك. العرض الحالي للقراءة فقط. أدخل رمز التجديد لاستعادة الكتابة.';
  static const codeLabel = 'رمز الاشتراك';
  static const codeHint = 'رمز من ٣٢ خانة';
  static const activate = 'تفعيل';
  static const retry = 'إعادة المحاولة';
  static const busy = 'جارٍ تفعيل الاشتراك…';
  static const close = 'إغلاق';
  static const later = 'لاحقًا';
  static const success = 'تم تفعيل الاشتراك بنجاح.';
  static const replayed = 'تم تأكيد التفعيل السابق بنفس الطلب.';
  static const openAction = 'تفعيل الاشتراك';
  static const invalid = 'أدخل رمز اشتراك صالحًا.';
  static const failed = 'تعذر تفعيل الاشتراك. تحقق من الرمز وحاول مجددًا.';
  static const expired = 'انتهت صلاحية هذا الرمز.';
  static const reused = 'هذا الرمز مستخدم مسبقًا.';
  static const foreign = 'هذا الرمز غير مرتبط بهذا الحساب.';
  static const rateLimited = 'محاولات كثيرة غير صحيحة. انتظر ثم حاول مجددًا.';
  static const keyReused = 'هذا الطلب استُخدم برمز مختلف. أعد المحاولة.';
  static const unauthorized = 'انتهت الجلسة. سجّل الدخول مجددًا.';
  static const unknown =
      'لم نتأكد من التفعيل. لا تعتبر الطلب مكتملًا. أعد المحاولة بنفس الرمز.';
  static const refetchFailed =
      'تم التفعيل. تعذر تحديث بيانات المتجر. ستُعاد المحاولة تلقائيًا.';

  static String failure(SubscriptionActivationFailure failure) {
    return switch (failure) {
      SubscriptionActivationFailure.invalidInput ||
      SubscriptionActivationFailure.invalidCode => invalid,
      SubscriptionActivationFailure.expiredCode => expired,
      SubscriptionActivationFailure.reusedCode => reused,
      SubscriptionActivationFailure.foreignOwner => foreign,
      SubscriptionActivationFailure.rateLimited => rateLimited,
      SubscriptionActivationFailure.requestKeyReused => keyReused,
      SubscriptionActivationFailure.unauthorized => unauthorized,
      SubscriptionActivationFailure.unavailable => failed,
      SubscriptionActivationFailure.unknownOutcome => unknown,
    };
  }
}

class SubscriptionActivationPanel extends StatefulWidget {
  const SubscriptionActivationPanel({
    super.key,
    required this.account,
    required this.gateway,
    required this.onActivated,
    this.compact = false,
    this.onDismiss,
  });

  final ShopAccount account;
  final ShopAccountGateway gateway;
  final Future<void> Function() onActivated;
  final bool compact;
  final VoidCallback? onDismiss;

  @override
  State<SubscriptionActivationPanel> createState() =>
      _SubscriptionActivationPanelState();
}

class _SubscriptionActivationPanelState
    extends State<SubscriptionActivationPanel> {
  final _code = TextEditingController();
  final _codeFocus = FocusNode();
  String _requestKey = IdempotencyKey.generate(Random.secure());
  String? _lockedCode;
  bool _busy = false;
  bool _unknown = false;
  bool _success = false;
  String? _message;
  bool _messageError = false;

  @override
  void didUpdateWidget(covariant SubscriptionActivationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account.id != widget.account.id) {
      _requestKey = IdempotencyKey.generate(Random.secure());
      _lockedCode = null;
      _busy = false;
      _unknown = false;
      _success = false;
      _message = null;
      _messageError = false;
      _code.clear();
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  String get _title => widget.account.entitlement == ShopEntitlement.expired
      ? SubscriptionCopy.expiredTitle
      : SubscriptionCopy.pendingTitle;

  String get _body => widget.account.entitlement == ShopEntitlement.expired
      ? SubscriptionCopy.expiredBody
      : SubscriptionCopy.pendingBody;

  Future<void> _submit() async {
    if (_busy) return;
    if (_unknown && _lockedCode != null) {
      _code.value = TextEditingValue(
        text: _lockedCode!,
        selection: TextSelection.collapsed(offset: _lockedCode!.length),
      );
      await _send(_lockedCode!);
      return;
    }
    final code = (_lockedCode ?? _code.text).trim().toUpperCase();
    if (!RegExp(r'^[A-F0-9]{32}$').hasMatch(code)) {
      setState(() {
        _message = SubscriptionCopy.invalid;
        _messageError = true;
        _success = false;
      });
      _codeFocus.requestFocus();
      return;
    }
    await _send(code);
  }

  Future<void> _send(String code) async {
    setState(() {
      _busy = true;
      _lockedCode = code;
      _code.value = TextEditingValue(
        text: code,
        selection: TextSelection.collapsed(offset: code.length),
      );
      _message = null;
      _success = false;
      _messageError = false;
    });
    SubscriptionActivationResult? result;
    try {
      result = await widget.gateway.activateSubscription(
        requestKey: _requestKey,
        code: code,
        shopId: widget.account.id,
      );
    } on SubscriptionActivationException catch (error) {
      if (!mounted) return;
      final unknown =
          error.failure == SubscriptionActivationFailure.unknownOutcome ||
          error.failure == SubscriptionActivationFailure.unavailable;
      setState(() {
        _busy = false;
        _unknown = unknown;
        _success = false;
        _messageError = true;
        _message = SubscriptionCopy.failure(error.failure);
        if (!unknown) {
          _requestKey = IdempotencyKey.generate(Random.secure());
          _lockedCode = null;
        }
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _unknown = true;
        _success = false;
        _messageError = true;
        _message = SubscriptionCopy.unknown;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _unknown = false;
      _success = true;
      _messageError = false;
      _message = result!.replayed
          ? SubscriptionCopy.replayed
          : SubscriptionCopy.success;
    });
    try {
      await widget.onActivated();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messageError = true;
        _message = SubscriptionCopy.refetchFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      key: const Key('subscription-activation'),
      container: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Text(_body, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
          const SizedBox(height: AppTokens.spaceMd),
          Text(
            SubscriptionCopy.codeLabel,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            key: const Key('subscription-code'),
            controller: _code,
            focusNode: _codeFocus,
            enabled: !_busy && !_success && !_unknown,
            textDirection: TextDirection.ltr,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9a-fA-F]')),
              LengthLimitingTextInputFormatter(32),
            ],
            decoration: const InputDecoration(
              hintText: SubscriptionCopy.codeHint,
              prefixIcon: Icon(Icons.vpn_key_outlined),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_busy) ...[
            const SizedBox(height: AppTokens.spaceMd),
            Semantics(
              key: const Key('subscription-progress'),
              liveRegion: true,
              label: SubscriptionCopy.busy,
              child: const LinearProgressIndicator(minHeight: 4),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            const Text(SubscriptionCopy.busy),
          ],
          if (_message != null) ...[
            const SizedBox(height: AppTokens.spaceMd),
            Semantics(
              key: const Key('subscription-status'),
              liveRegion: true,
              child: Text(
                _message!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: _messageError ? scheme.error : scheme.tertiary,
                  height: 1.5,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppTokens.spaceMd),
          FilledButton(
            key: const Key('subscription-activate'),
            onPressed: _busy || _success ? null : _submit,
            child: Text(
              _unknown ? SubscriptionCopy.retry : SubscriptionCopy.activate,
            ),
          ),
          if (widget.onDismiss != null) ...[
            const SizedBox(height: AppTokens.spaceSm),
            OutlinedButton(
              key: const Key('subscription-dismiss'),
              onPressed: _busy ? null : widget.onDismiss,
              child: Text(
                _success ? SubscriptionCopy.close : SubscriptionCopy.later,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> showSubscriptionActivationDialog({
  required BuildContext context,
  required ShopAccount account,
  required ShopAccountGateway gateway,
  required Future<void> Function() onActivated,
  void Function(Route<void> route)? onRouteCreated,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final route = DialogRoute<void>(
    context: context,
    themes: InheritedTheme.capture(from: context, to: navigator.context),
    settings: const RouteSettings(name: 'subscription-activation'),
    barrierDismissible: true,
    barrierLabel: 'إغلاق نافذة الاشتراك',
    builder: (dialogContext) => AlertDialog(
      scrollable: true,
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      content: SizedBox(
        width: 420,
        child: SubscriptionActivationPanel(
          account: account,
          gateway: gateway,
          onActivated: () async {
            await onActivated();
            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
          },
          onDismiss: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    ),
  );
  onRouteCreated?.call(route);
  return navigator.push<void>(route);
}
