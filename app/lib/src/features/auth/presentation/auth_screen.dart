import 'dart:math';

import 'package:flutter/material.dart';

import '../../../shell/shell_copy.dart';
import '../../../theme/app_tokens.dart';
import '../domain/auth_gateway.dart';
import 'auth_copy.dart';

enum AuthFormMode { signIn, signUp }

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.gateway,
    required this.onToggleTheme,
    required this.onHold,
    required this.onSessionSettled,
  });

  final AuthGateway gateway;
  final Future<void> Function(Brightness brightness) onToggleTheme;
  final ValueChanged<bool> onHold;
  final VoidCallback onSessionSettled;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final _scroll = ScrollController();
  final _owner = TextEditingController();
  final _business = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _ownerFocus = FocusNode();
  final _businessFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _phoneFocus = FocusNode();
  final _governorateFocus = FocusNode();
  final _passwordFocus = FocusNode();

  AuthFormMode _mode = AuthFormMode.signIn;
  SignInIdentifier _kind = SignInIdentifier.email;
  List<Governorate> _governorates = const [];
  String? _governorateCode;
  OwnerRegistration? _attempt;
  bool _unknown = false;
  bool _busy = false;
  bool _loadingGovernorates = false;
  bool _governorateLoadFailed = false;
  String? _serverMessage;
  int _governorateLoadGeneration = 0;

  @override
  void dispose() {
    _scroll.dispose();
    _owner.dispose();
    _business.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    _ownerFocus.dispose();
    _businessFocus.dispose();
    _emailFocus.dispose();
    _phoneFocus.dispose();
    _governorateFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool get _locked => _busy || _unknown;

  Future<void> _loadGovernorates() async {
    final generation = ++_governorateLoadGeneration;
    setState(() {
      _loadingGovernorates = true;
      _governorateLoadFailed = false;
    });
    try {
      final list = await widget.gateway.loadGovernorates();
      if (!mounted || generation != _governorateLoadGeneration) return;
      setState(() {
        _governorates = list;
        _loadingGovernorates = false;
        if (_governorateCode != null &&
            list.every((item) => item.code != _governorateCode)) {
          _governorateCode = null;
        }
      });
    } catch (_) {
      if (!mounted || generation != _governorateLoadGeneration) return;
      setState(() {
        _loadingGovernorates = false;
        _governorateLoadFailed = true;
      });
    }
  }

  void _showMode(AuthFormMode mode) {
    if (_busy) return;
    setState(() {
      _mode = mode;
      _serverMessage = null;
    });
    if (mode == AuthFormMode.signUp &&
        _governorates.isEmpty &&
        !_loadingGovernorates) {
      _loadGovernorates();
    }
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _submitSignIn() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final request = SignInRequest.tryCreate(
      kind: _kind,
      identifier: _kind == SignInIdentifier.email ? _email.text : _phone.text,
      password: _password.text,
    );
    if (request == null) return;
    setState(() {
      _busy = true;
      _serverMessage = null;
    });
    try {
      await widget.gateway.signIn(request);
    } on SignInException catch (error) {
      if (mounted) {
        setState(() {
          _serverMessage = error.failure == SignInFailure.unavailable
              ? AuthCopy.signInUnavailable
              : AuthCopy.signInFailed;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _serverMessage = AuthCopy.signInFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
      widget.onSessionSettled();
    }
  }

  Future<void> _submitSignUp() async {
    if (_busy) return;
    if (_unknown && _attempt != null) {
      await _sendRegistration(_attempt!);
      return;
    }
    if (_governorates.isEmpty) {
      setState(() => _serverMessage = AuthCopy.governorateFailed);
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final registration = _registrationFromFields();
    if (registration == null) return;
    await _sendRegistration(registration);
  }

  OwnerRegistration? _registrationFromFields() {
    final previous = _attempt;
    final owner = AccountName.tryCanonical(_owner.text);
    final business = AccountName.tryCanonical(_business.text);
    final email = AccountEmail.tryCanonical(_email.text);
    final phone = EgyptianPhone.tryCanonical(_phone.text);
    final governorate = _governorateCode;
    if (owner == null ||
        business == null ||
        email == null ||
        phone == null ||
        governorate == null) {
      return null;
    }
    final draft = OwnerRegistration.tryCreate(
      idempotencyKey: IdempotencyKey.generate(Random.secure()),
      ownerName: owner,
      businessName: business,
      email: email,
      phone: phone,
      governorateCode: governorate,
      password: _password.text,
    );
    if (draft == null) return null;
    if (previous != null && previous.samePayloadAs(draft)) return previous;
    return draft;
  }

  Future<void> _sendRegistration(OwnerRegistration registration) async {
    setState(() {
      _busy = true;
      _attempt = registration;
      _serverMessage = null;
    });
    widget.onHold(true);
    try {
      await widget.gateway.registerOwner(registration);
      _unknown = false;
    } on RegistrationException catch (error) {
      if (mounted) {
        setState(() {
          _unknown =
              error.failure == RegistrationFailure.unknownOutcome ||
              error.failure == RegistrationFailure.unavailable;
          _serverMessage = _unknown
              ? AuthCopy.signupUnknown
              : AuthCopy.registrationFailure(error.failure);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _unknown = true;
          _serverMessage = AuthCopy.signupUnknown;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      widget.onHold(false);
      widget.onSessionSettled();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= AppTokens.wideBreakpoint;
    final signingUp = _mode == AuthFormMode.signUp;
    return RepaintBoundary(
      key: const Key('auth-capture-boundary'),
      child: Scaffold(
        appBar: AppBar(
          title: const Text(ShellCopy.appTitle),
          actions: [
            IconButton(
              key: const Key('auth-theme-toggle'),
              tooltip: theme.brightness == Brightness.dark
                  ? ShellCopy.toggleToLight
                  : ShellCopy.toggleToDark,
              onPressed: () => widget.onToggleTheme(theme.brightness),
              icon: Icon(
                theme.brightness == Brightness.dark
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTokens.contentMaxWidth,
              ),
              child: Form(
                key: _formKey,
                child: FocusTraversalGroup(
                  policy: OrderedTraversalPolicy(),
                  child: ListView(
                    key: const Key('auth-scroll'),
                    controller: _scroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 32 : 20,
                      vertical: wide ? 32 : 20,
                    ),
                    children: [
                      Text(
                        signingUp ? AuthCopy.signUpTitle : AuthCopy.signInTitle,
                        style: theme.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        signingUp ? AuthCopy.signUpBody : AuthCopy.signInBody,
                      ),
                      const SizedBox(height: 20),
                      if (!signingUp) ..._signInFields(),
                      if (signingUp) ..._signUpFields(scheme),
                      if (_serverMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _serverMessage!,
                          key: Key(
                            signingUp
                                ? (_unknown ? 'signup-unknown' : 'signup-error')
                                : 'sign-in-error',
                          ),
                          style: TextStyle(
                            color: _unknown ? scheme.onSurface : scheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton(
                        key: Key(
                          signingUp ? 'signup-submit' : 'sign-in-submit',
                        ),
                        onPressed: _busy
                            ? null
                            : signingUp
                            ? _submitSignUp
                            : _submitSignIn,
                        child: Text(
                          _busy
                              ? (signingUp
                                    ? AuthCopy.signUpBusy
                                    : AuthCopy.signInBusy)
                              : signingUp
                              ? (_attempt == null
                                    ? AuthCopy.signUpAction
                                    : AuthCopy.retryAction)
                              : AuthCopy.signInAction,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        key: Key(signingUp ? 'show-sign-in' : 'show-signup'),
                        onPressed: _busy
                            ? null
                            : () => _showMode(
                                signingUp
                                    ? AuthFormMode.signIn
                                    : AuthFormMode.signUp,
                              ),
                        child: Text(
                          signingUp ? AuthCopy.showSignIn : AuthCopy.showSignUp,
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
    );
  }

  List<Widget> _signInFields() {
    final email = _kind == SignInIdentifier.email;
    return [
      RadioGroup<SignInIdentifier>(
        groupValue: _kind,
        onChanged: (value) {
          if (_busy || value == null) return;
          setState(() {
            _kind = value;
            _serverMessage = null;
          });
        },
        child: const Column(
          children: [
            RadioListTile<SignInIdentifier>(
              key: Key('sign-in-kind-email'),
              value: SignInIdentifier.email,
              contentPadding: EdgeInsets.zero,
              title: Text(AuthCopy.emailKind),
            ),
            RadioListTile<SignInIdentifier>(
              key: Key('sign-in-kind-phone'),
              value: SignInIdentifier.phone,
              contentPadding: EdgeInsets.zero,
              title: Text(AuthCopy.phoneKind),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      if (email)
        _contactField(
          key: const Key('sign-in-email'),
          controller: _email,
          focusNode: _emailFocus,
          next: _passwordFocus,
          label: AuthCopy.emailLabel,
          keyboardType: TextInputType.emailAddress,
          validator: (value) => AccountEmail.tryCanonical(value ?? '') == null
              ? AuthCopy.emailInvalid
              : null,
        )
      else
        _contactField(
          key: const Key('sign-in-phone'),
          controller: _phone,
          focusNode: _phoneFocus,
          next: _passwordFocus,
          label: AuthCopy.phoneLabel,
          keyboardType: TextInputType.phone,
          validator: (value) => EgyptianPhone.tryCanonical(value ?? '') == null
              ? AuthCopy.phoneInvalid
              : null,
        ),
      const SizedBox(height: 12),
      _passwordField(key: const Key('sign-in-password'), onDone: _submitSignIn),
    ];
  }

  List<Widget> _signUpFields(ColorScheme scheme) {
    return [
      _nameField(
        key: const Key('signup-owner-name'),
        controller: _owner,
        focusNode: _ownerFocus,
        next: _businessFocus,
        label: AuthCopy.ownerLabel,
        invalid: AuthCopy.ownerInvalid,
      ),
      const SizedBox(height: 12),
      _nameField(
        key: const Key('signup-business-name'),
        controller: _business,
        focusNode: _businessFocus,
        next: _emailFocus,
        label: AuthCopy.businessLabel,
        invalid: AuthCopy.businessInvalid,
      ),
      const SizedBox(height: 12),
      _contactField(
        key: const Key('signup-email'),
        controller: _email,
        focusNode: _emailFocus,
        next: _phoneFocus,
        label: AuthCopy.emailLabel,
        keyboardType: TextInputType.emailAddress,
        validator: (value) => AccountEmail.tryCanonical(value ?? '') == null
            ? AuthCopy.emailInvalid
            : null,
      ),
      const SizedBox(height: 12),
      _contactField(
        key: const Key('signup-phone'),
        controller: _phone,
        focusNode: _phoneFocus,
        next: _governorateFocus,
        label: AuthCopy.phoneLabel,
        keyboardType: TextInputType.phone,
        validator: (value) => EgyptianPhone.tryCanonical(value ?? '') == null
            ? AuthCopy.phoneInvalid
            : null,
      ),
      const SizedBox(height: 12),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const Key('governorate-refresh'),
          onPressed: _loadingGovernorates ? null : _loadGovernorates,
          icon: const Icon(Icons.refresh),
          label: const Text(AuthCopy.governorateRetry),
        ),
      ),
      if (_loadingGovernorates) ...[
        const LinearProgressIndicator(),
        const SizedBox(height: 8),
        const Text(AuthCopy.governorateLoading),
      ],
      if (_governorateLoadFailed) ...[
        const SizedBox(height: 8),
        Text(
          AuthCopy.governorateFailed,
          key: const Key('governorate-error'),
          style: TextStyle(color: scheme.error),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('governorate-retry'),
          onPressed: _loadingGovernorates ? null : _loadGovernorates,
          child: const Text(AuthCopy.governorateRetry),
        ),
      ],
      if (_governorates.isNotEmpty) ...[
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: const Key('signup-governorate'),
          initialValue: _governorateCode,
          isExpanded: true,
          focusNode: _governorateFocus,
          decoration: const InputDecoration(
            labelText: AuthCopy.governorateLabel,
          ),
          hint: const Text(AuthCopy.governorateHint),
          items: [
            for (final item in _governorates)
              DropdownMenuItem(
                value: item.code,
                child: Text(item.nameAr, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: _locked
              ? null
              : (value) => setState(() => _governorateCode = value),
          validator: (value) =>
              value == null || !EgyptianGovernorates.isValid(value)
              ? AuthCopy.governorateInvalid
              : null,
        ),
      ],
      const SizedBox(height: 12),
      _passwordField(key: const Key('signup-password'), onDone: _submitSignUp),
    ];
  }

  Widget _nameField({
    required Key key,
    required TextEditingController controller,
    required FocusNode focusNode,
    required FocusNode next,
    required String label,
    required String invalid,
  }) {
    return TextFormField(
      key: key,
      controller: controller,
      focusNode: focusNode,
      enabled: !_locked,
      textInputAction: TextInputAction.next,
      onFieldSubmitted: (_) => next.requestFocus(),
      decoration: InputDecoration(labelText: label),
      validator: (value) =>
          AccountName.tryCanonical(value ?? '') == null ? invalid : null,
    );
  }

  Widget _contactField({
    required Key key,
    required TextEditingController controller,
    required FocusNode focusNode,
    required FocusNode next,
    required String label,
    required TextInputType keyboardType,
    required FormFieldValidator<String> validator,
  }) {
    return TextFormField(
      key: key,
      controller: controller,
      focusNode: focusNode,
      enabled: !_locked,
      keyboardType: keyboardType,
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.start,
      textInputAction: TextInputAction.next,
      autofillHints: const [],
      onFieldSubmitted: (_) => next.requestFocus(),
      decoration: InputDecoration(labelText: label),
      validator: validator,
    );
  }

  Widget _passwordField({required Key key, required VoidCallback onDone}) {
    return TextFormField(
      key: key,
      controller: _password,
      focusNode: _passwordFocus,
      enabled: !_locked,
      obscureText: true,
      enableSuggestions: false,
      autocorrect: false,
      autofillHints: const [],
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: (_) {
        if (!_busy) onDone();
      },
      decoration: const InputDecoration(labelText: AuthCopy.passwordLabel),
      validator: (value) => AccountPassword.isAcceptable(value ?? '')
          ? null
          : AuthCopy.passwordInvalid,
    );
  }
}
