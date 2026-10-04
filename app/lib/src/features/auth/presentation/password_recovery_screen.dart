import 'package:flutter/material.dart';

import '../../../shell/shell_copy.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/brand_mark.dart';
import '../domain/account_identifiers.dart';
import '../domain/password_recovery.dart';
import 'auth_copy.dart';
import 'auth_form_theme.dart';
import 'recovery_copy.dart';

const double _measure = 480;
const EdgeInsets _fieldScrollPadding = EdgeInsets.fromLTRB(16, 48, 16, 96);

class RecoveryRequestScreen extends StatefulWidget {
  const RecoveryRequestScreen({
    super.key,
    required this.gateway,
    required this.onToggleTheme,
    required this.onBack,
  });

  final PasswordRecoveryGateway gateway;
  final Future<void> Function(Brightness brightness) onToggleTheme;
  final VoidCallback onBack;

  @override
  State<RecoveryRequestScreen> createState() => _RecoveryRequestScreenState();
}

class _RecoveryRequestScreenState extends State<RecoveryRequestScreen> {
  final _email = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _validated = false;
  bool _sent = false;
  String? _message;
  bool _error = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _sent) return;
    setState(() => _validated = true);
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _busy = true;
      _message = null;
      _error = false;
    });
    try {
      await widget.gateway.requestEmailReset(_email.text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _sent = true;
        _message = RecoveryCopy.requestSuccess;
        _error = false;
      });
    } on RecoveryException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = true;
        _message = error.failure == RecoveryFailure.invalidEmail
            ? RecoveryCopy.emailInvalid
            : RecoveryCopy.requestUnavailable;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = authFormTheme(Theme.of(context));
    return _RecoveryScaffold(
      theme: theme,
      onToggleTheme: widget.onToggleTheme,
      child: Form(
        key: _formKey,
        autovalidateMode: _validated
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                RecoveryCopy.requestTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                RecoveryCopy.requestBody,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              if (_sent && _message != null)
                _RecoveryStatus(message: _message!, error: false)
              else ...[
                Text(
                  AuthCopy.emailLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Semantics(
                  label: AuthCopy.emailLabel,
                  child: TextFormField(
                    key: const Key('recovery-email'),
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.start,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.email],
                    autocorrect: false,
                    enableSuggestions: false,
                    enableInteractiveSelection: true,
                    scrollPadding: _fieldScrollPadding,
                    decoration: const InputDecoration(
                      hintText: AuthCopy.emailHint,
                    ),
                    validator: (value) =>
                        AccountEmail.tryCanonical(value ?? '') == null
                        ? RecoveryCopy.emailInvalid
                        : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(height: 8),
                if (_message != null)
                  _RecoveryStatus(message: _message!, error: _error),
                const SizedBox(height: 8),
                FilledButton(
                  key: const Key('recovery-request-submit'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, authControlHeight),
                  ),
                  onPressed: _busy ? null : _submit,
                  child: Text(
                    _busy
                        ? RecoveryCopy.requestBusy
                        : RecoveryCopy.requestAction,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              TextButton(
                key: const Key('recovery-back'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, authControlHeight),
                  alignment: AlignmentDirectional.centerStart,
                ),
                onPressed: _busy ? null : widget.onBack,
                child: const Text(RecoveryCopy.backToSignIn),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({
    super.key,
    required this.gateway,
    required this.onToggleTheme,
    required this.onFinished,
    required this.onAbandoned,
  });

  final PasswordRecoveryGateway gateway;
  final Future<void> Function(Brightness brightness) onToggleTheme;
  final VoidCallback onFinished;
  final VoidCallback onAbandoned;

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _busy = false;
  bool _validated = false;
  bool _visible = false;
  String? _message;
  bool _error = true;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _validated = true);
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.gateway.completeReset(_password.text);
      if (!mounted) return;
      widget.onFinished();
    } on RecoveryException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = true;
        _message = RecoveryCopy.resetMessageFor(error.failure);
      });
    }
  }

  Future<void> _abandon() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.gateway.abandonRecovery();
      if (!mounted) return;
      widget.onAbandoned();
    } on RecoveryException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = true;
        _message = RecoveryCopy.resetMessageFor(error.failure);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = authFormTheme(Theme.of(context));
    return _RecoveryScaffold(
      theme: theme,
      onToggleTheme: widget.onToggleTheme,
      child: Form(
        key: _formKey,
        autovalidateMode: _validated
            ? AutovalidateMode.onUserInteraction
            : AutovalidateMode.disabled,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                RecoveryCopy.resetTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                RecoveryCopy.resetBody,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                AuthCopy.passwordLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Semantics(
                label: AuthCopy.passwordLabel,
                child: TextFormField(
                  key: const Key('recovery-new-password'),
                  controller: _password,
                  enabled: !_busy,
                  obscureText: !_visible,
                  enableSuggestions: false,
                  autocorrect: false,
                  enableInteractiveSelection: true,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  autofillHints: const [AutofillHints.newPassword],
                  keyboardType: TextInputType.visiblePassword,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  textInputAction: TextInputAction.next,
                  scrollPadding: _fieldScrollPadding,
                  decoration: InputDecoration(
                    helperText: AuthCopy.passwordHelper,
                    helperMaxLines: 3,
                    suffixIcon: IconButton(
                      key: const Key('recovery-password-visibility'),
                      tooltip: _visible
                          ? AuthCopy.hidePassword
                          : AuthCopy.showPassword,
                      onPressed: () => setState(() => _visible = !_visible),
                      icon: Icon(
                        _visible
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                  validator: (value) =>
                      AccountPassword.isAcceptable(value ?? '')
                      ? null
                      : AuthCopy.passwordInvalid,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                RecoveryCopy.confirmLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Semantics(
                label: RecoveryCopy.confirmLabel,
                child: TextFormField(
                  key: const Key('recovery-confirm-password'),
                  controller: _confirm,
                  enabled: !_busy,
                  obscureText: !_visible,
                  enableSuggestions: false,
                  autocorrect: false,
                  enableInteractiveSelection: true,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  autofillHints: const [AutofillHints.newPassword],
                  keyboardType: TextInputType.visiblePassword,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  textInputAction: TextInputAction.done,
                  scrollPadding: _fieldScrollPadding,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (value) {
                    if (!AccountPassword.isAcceptable(value ?? '')) {
                      return AuthCopy.passwordInvalid;
                    }
                    if (value != _password.text) return RecoveryCopy.mismatch;
                    return null;
                  },
                ),
              ),
              const SizedBox(height: 8),
              if (_busy)
                Semantics(
                  key: const Key('recovery-reset-progress'),
                  liveRegion: true,
                  label: RecoveryCopy.resetBusy,
                  child: const LinearProgressIndicator(minHeight: 4),
                )
              else if (_message != null)
                _RecoveryStatus(message: _message!, error: _error),
              const SizedBox(height: 8),
              FilledButton(
                key: const Key('recovery-reset-submit'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, authControlHeight),
                ),
                onPressed: _busy ? null : _submit,
                child: Text(
                  _busy ? RecoveryCopy.resetBusy : RecoveryCopy.resetAction,
                  textAlign: TextAlign.center,
                ),
              ),
              TextButton(
                key: const Key('recovery-abandon'),
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, authControlHeight),
                  alignment: AlignmentDirectional.centerStart,
                ),
                onPressed: _busy ? null : _abandon,
                child: const Text(RecoveryCopy.abandon),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecoveryScaffold extends StatelessWidget {
  const _RecoveryScaffold({
    required this.theme,
    required this.onToggleTheme,
    required this.child,
  });

  final ThemeData theme;
  final Future<void> Function(Brightness brightness) onToggleTheme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = theme.brightness == Brightness.dark;
    final wide = MediaQuery.sizeOf(context).width >= AppTokens.wideBreakpoint;
    return Theme(
      data: theme,
      child: RepaintBoundary(
        key: const Key('recovery-capture-boundary'),
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          body: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.colorScheme.primaryContainer,
                  theme.colorScheme.surface,
                  theme.colorScheme.surface,
                ],
                stops: const [0, 0.42, 1],
              ),
            ),
            child: SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _measure),
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(overscroll: false),
                    child: SingleChildScrollView(
                      key: const Key('recovery-scroll'),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(16, wide ? 40 : 8, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: BrandHero(markSize: 40, compact: true),
                              ),
                              IconButton(
                                key: const Key('auth-theme-toggle'),
                                tooltip: dark
                                    ? ShellCopy.toggleToLight
                                    : ShellCopy.toggleToDark,
                                onPressed: () =>
                                    onToggleTheme(theme.brightness),
                                icon: Icon(
                                  dark
                                      ? Icons.light_mode_outlined
                                      : Icons.dark_mode_outlined,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: child,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecoveryStatus extends StatelessWidget {
  const _RecoveryStatus({required this.message, required this.error});

  final String message;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      key: const Key('recovery-status'),
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: error ? scheme.errorContainer : scheme.primaryContainer,
          borderRadius: BorderRadius.circular(authCornerRadius),
          border: Border.all(color: error ? scheme.error : scheme.primary),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            message,
            softWrap: true,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: error
                  ? scheme.onErrorContainer
                  : scheme.onPrimaryContainer,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
