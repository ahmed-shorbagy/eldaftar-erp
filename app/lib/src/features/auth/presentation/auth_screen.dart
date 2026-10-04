import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shell/shell_copy.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/brand_mark.dart';
import '../../onboarding/application/onboarding_store.dart';
import '../../onboarding/presentation/guide_card.dart';
import '../domain/auth_gateway.dart';
import 'auth_copy.dart';
import 'auth_form_theme.dart';
import 'recovery_copy.dart';

enum AuthFormMode { signIn, signUp }

const double _measure = 480;
const double _control = 48;
const double _radius = 12;
const EdgeInsets _fieldScrollPadding = EdgeInsets.fromLTRB(16, 48, 16, 96);

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.gateway,
    required this.onToggleTheme,
    required this.onHold,
    required this.onSessionSettled,
    this.onboardingStore,
    this.onForgotPassword,
    this.recoveryNotice,
    this.recoveryNoticeIsError = false,
  });

  final AuthGateway gateway;
  final Future<void> Function(Brightness brightness) onToggleTheme;
  final ValueChanged<bool> onHold;
  final VoidCallback onSessionSettled;
  final OnboardingStore? onboardingStore;
  final VoidCallback? onForgotPassword;
  final String? recoveryNotice;
  final bool recoveryNoticeIsError;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _scroll = ScrollController();
  final _statusKey = GlobalKey();
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
  final _submitFocus = FocusNode();

  GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  AuthFormMode _mode = AuthFormMode.signIn;
  List<Governorate> _governorates = const [];
  String? _governorateCode;
  OwnerRegistration? _attempt;
  bool _unknown = false;
  bool _busy = false;
  bool _loadingGovernorates = false;
  bool _governorateLoadFailed = false;
  bool _passwordVisible = false;
  bool _validated = false;
  String? _serverMessage;
  String? _fieldAlert;
  int _governorateLoadGeneration = 0;
  bool _guideVisible = false;
  int _guideStep = 0;

  @override
  void initState() {
    super.initState();
    _email.addListener(_refreshContacts);
    _phone.addListener(_refreshContacts);
    _emailFocus.addListener(_onGuideFocus);
    _ownerFocus.addListener(_onGuideFocus);
    _passwordFocus.addListener(_onGuideFocus);
    _loadGuide();
  }

  String get _guidePath => _signingUp ? 'auth_signup' : 'auth_signin';

  Future<void> _loadGuide() async {
    final store = widget.onboardingStore;
    if (store == null) return;
    final path = _guidePath;
    final complete = await store.isComplete(path);
    final step = await store.readStep(path);
    if (mounted && _guidePath == path && !complete) {
      setState(() {
        _guideVisible = true;
        _guideStep = step.clamp(0, 2);
      });
    }
  }

  void _onGuideFocus() {
    if (!_guideVisible) return;
    if (_guideStep == 0 &&
        (_signingUp ? _ownerFocus.hasFocus : _emailFocus.hasFocus)) {
      setState(() => _guideStep = 1);
      widget.onboardingStore?.saveStep(_guidePath, 1);
    } else if (_guideStep == 1 &&
        (_signingUp ? _emailFocus.hasFocus : _passwordFocus.hasFocus)) {
      setState(() => _guideStep = 2);
      widget.onboardingStore?.saveStep(_guidePath, 2);
    }
  }

  void _skipGuide() {
    setState(() => _guideVisible = false);
    widget.onboardingStore?.saveStep(_guidePath, _guideStep);
  }

  void _finishGuide() {
    setState(() => _guideVisible = false);
    widget.onboardingStore?.markComplete(_guidePath);
  }

  void _resumeGuide() {
    setState(() => _guideVisible = true);
  }

  Widget _guide() {
    final signup = _signingUp;
    final titles = signup
        ? const ['ابدأ باسم المالك', 'أضف وسيلة التواصل', 'أكمل بيانات المتجر']
        : const ['مرحبًا بك', 'أدخل كلمة المرور', 'راجع ثم ادخل'];
    final descriptions = signup
        ? const [
            'المس اسم المالك الحقيقي في النموذج.',
            'اكتب البريد الإلكتروني والهاتف المصري في الحقلين.',
            'اختر المحافظة وكلمة المرور، ثم راجع الطلب قبل إرساله.',
          ]
        : const [
            'استخدم البريد الإلكتروني أو رقم الهاتف المصري في الحقل نفسه.',
            'أدخل كلمة المرور الخاصة بالحساب. يمكنك إظهارها للتأكد.',
            'اضغط دخول بعد مراجعة البيانات. لن يفتح المتجر إلا بعد تأكيد الخادم.',
          ];
    return GuideCard(
      title: titles[_guideStep],
      description: descriptions[_guideStep],
      progress: const ['١/٣', '٢/٣', '٣/٣'][_guideStep],
      actionLabel: _guideStep == 2 ? 'الانتقال إلى الإجراء' : 'تجربة الحقل',
      onAction: () {
        if (_guideStep == 2) {
          _finishGuide();
          _submitFocus.requestFocus();
        } else if (_guideStep == 0) {
          (signup ? _ownerFocus : _emailFocus).requestFocus();
        } else {
          (signup ? _emailFocus : _passwordFocus).requestFocus();
        }
      },
      onSkip: _skipGuide,
    );
  }

  @override
  void dispose() {
    _email.removeListener(_refreshContacts);
    _phone.removeListener(_refreshContacts);
    _emailFocus.removeListener(_onGuideFocus);
    _ownerFocus.removeListener(_onGuideFocus);
    _passwordFocus.removeListener(_onGuideFocus);
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
    _submitFocus.dispose();
    super.dispose();
  }

  bool get _locked => _busy || _unknown;

  bool get _signingUp => _mode == AuthFormMode.signUp;

  void _refreshContacts() {
    if (!mounted) return;
    setState(() {});
    if (!_validated) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_validated) return;
      _formKey.currentState?.validate();
    });
  }

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
    if (_busy || _mode == mode) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _mode = mode;
      _serverMessage = null;
      _fieldAlert = null;
      _formKey = GlobalKey<FormState>();
      _validated = false;
      _guideVisible = false;
      _guideStep = 0;
    });
    if (mode == AuthFormMode.signUp &&
        _governorates.isEmpty &&
        !_loadingGovernorates) {
      _loadGovernorates();
    }
    if (_scroll.hasClients) _scroll.jumpTo(0);
    if (widget.onboardingStore != null) _loadGuide();
  }

  Future<void> _submitSignIn() async {
    if (_busy || _rejected(_signInChecks())) return;
    final request = SignInRequest.tryParse(
      identifier: _email.text,
      password: _password.text,
    );
    if (request == null) return;
    setState(() {
      _busy = true;
      _serverMessage = null;
      _fieldAlert = null;
    });
    try {
      await widget.gateway.signIn(request);
      TextInput.finishAutofillContext();
    } on SignInException catch (error) {
      if (mounted) {
        setState(() {
          _serverMessage = error.failure == SignInFailure.unavailable
              ? AuthCopy.signInUnavailable
              : AuthCopy.signInFailed;
        });
        _revealStatus();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _serverMessage = AuthCopy.signInFailed);
        _revealStatus();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      widget.onSessionSettled();
    }
  }

  Future<void> _submitSignUp() async {
    if (_busy) return;
    // Unknown outcomes retry the original payload and key. Later edits are ignored.
    if (_unknown && _attempt != null) {
      await _sendRegistration(_attempt!);
      return;
    }
    if (_governorates.isEmpty) {
      setState(() {
        _serverMessage = AuthCopy.governorateFailed;
        _fieldAlert = null;
      });
      _revealStatus();
      return;
    }
    if (_rejected(_signUpChecks())) return;
    final registration = _registrationFromFields();
    if (registration == null) return;
    await _sendRegistration(registration);
  }

  List<_FieldCheck> _signInChecks() {
    return [
      _FieldCheck(_emailFocus, _signInContactError(_email.text)),
      _passwordCheck(),
    ];
  }

  String? _signInContactError(String value) {
    final kind = AccountIdentifier.detect(value);
    if (kind == null) return AuthCopy.contactInvalid;
    if (kind == SignInIdentifier.email) {
      return AccountEmail.tryCanonical(value) == null
          ? AuthCopy.emailInvalid
          : null;
    }
    return EgyptianPhone.tryCanonical(value) == null
        ? AuthCopy.phoneInvalid
        : null;
  }

  String? _signupContactError(
    String own,
    String other, {
    required bool secondary,
  }) {
    final ownKind = AccountIdentifier.detect(own);
    final otherKind = AccountIdentifier.detect(other);
    if (own.trim().isEmpty) {
      if (otherKind == SignInIdentifier.email) return AuthCopy.phoneInvalid;
      if (otherKind == SignInIdentifier.phone) return AuthCopy.emailInvalid;
      return AuthCopy.contactInvalid;
    }
    if (ownKind == SignInIdentifier.email) {
      if (AccountEmail.tryCanonical(own) == null) return AuthCopy.emailInvalid;
      if (secondary &&
          otherKind == SignInIdentifier.email &&
          AccountEmail.tryCanonical(other) != null) {
        return AuthCopy.duplicateContact;
      }
      return null;
    }
    if (ownKind == SignInIdentifier.phone) {
      if (EgyptianPhone.tryCanonical(own) == null) return AuthCopy.phoneInvalid;
      if (secondary &&
          otherKind == SignInIdentifier.phone &&
          EgyptianPhone.tryCanonical(other) != null) {
        return AuthCopy.duplicateContact;
      }
      return null;
    }
    return AuthCopy.contactInvalid;
  }

  ({String email, String phone})? _resolvedContacts() {
    final found = <SignInIdentifier, String>{};
    for (final raw in [_email.text, _phone.text]) {
      final kind = AccountIdentifier.detect(raw);
      if (kind == null) return null;
      final canonical = switch (kind) {
        SignInIdentifier.email => AccountEmail.tryCanonical(raw),
        SignInIdentifier.phone => EgyptianPhone.tryCanonical(raw),
      };
      if (canonical == null || found.containsKey(kind)) return null;
      found[kind] = canonical;
    }
    final email = found[SignInIdentifier.email];
    final phone = found[SignInIdentifier.phone];
    if (email == null || phone == null) return null;
    return (email: email, phone: phone);
  }

  List<_FieldCheck> _signUpChecks() {
    return [
      _FieldCheck(
        _ownerFocus,
        AccountName.tryCanonical(_owner.text) == null
            ? AuthCopy.ownerInvalid
            : null,
      ),
      _FieldCheck(
        _businessFocus,
        AccountName.tryCanonical(_business.text) == null
            ? AuthCopy.businessInvalid
            : null,
      ),
      _FieldCheck(
        _emailFocus,
        _signupContactError(_email.text, _phone.text, secondary: false),
      ),
      _FieldCheck(
        _phoneFocus,
        _signupContactError(_phone.text, _email.text, secondary: true),
      ),
      _FieldCheck(
        _governorateFocus,
        _governorateCode == null ||
                !EgyptianGovernorates.isValid(_governorateCode!)
            ? AuthCopy.governorateInvalid
            : null,
      ),
      _passwordCheck(),
    ];
  }

  _FieldCheck _passwordCheck() {
    return _FieldCheck(
      _passwordFocus,
      AccountPassword.isAcceptable(_password.text)
          ? null
          : AuthCopy.passwordInvalid,
    );
  }

  bool _rejected(List<_FieldCheck> checks) {
    setState(() => _validated = true);
    final valid = _formKey.currentState?.validate() ?? false;
    if (valid) {
      if (_fieldAlert != null) setState(() => _fieldAlert = null);
      return false;
    }
    _FieldCheck? first;
    for (final check in checks) {
      if (check.invalid != null) {
        first = check;
        break;
      }
    }
    setState(() => _fieldAlert = first?.invalid);
    final focus = first?.focus;
    if (focus != null) {
      focus.requestFocus();
      _reveal(focus);
    }
    return true;
  }

  void _reveal(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = node.context;
      if (target == null || !target.mounted) return;
      _ensure(target);
    });
  }

  void _revealStatus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _statusKey.currentContext;
      if (target == null || !target.mounted) return;
      _ensure(target);
    });
  }

  void _ensure(BuildContext target) {
    final reduce = MediaQuery.disableAnimationsOf(target);
    Scrollable.ensureVisible(
      target,
      alignment: 0.2,
      duration: reduce ? Duration.zero : const Duration(milliseconds: 160),
      curve: Curves.easeOut,
    );
  }

  OwnerRegistration? _registrationFromFields() {
    final previous = _attempt;
    final owner = AccountName.tryCanonical(_owner.text);
    final business = AccountName.tryCanonical(_business.text);
    final contacts = _resolvedContacts();
    final governorate = _governorateCode;
    if (owner == null ||
        business == null ||
        contacts == null ||
        governorate == null) {
      return null;
    }
    final email = contacts.email;
    final phone = contacts.phone;
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
      _fieldAlert = null;
    });
    widget.onHold(true);
    try {
      await widget.gateway.registerOwner(registration);
      _unknown = false;
      TextInput.finishAutofillContext();
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
        _revealStatus();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _unknown = true;
          _serverMessage = AuthCopy.signupUnknown;
        });
        _revealStatus();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
      widget.onHold(false);
      widget.onSessionSettled();
    }
  }

  ThemeData _authTheme(ThemeData theme) => authFormTheme(theme);

  @override
  Widget build(BuildContext context) {
    final theme = _authTheme(Theme.of(context));
    return PopScope(
      canPop: !_signingUp && !_busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _signingUp && !_busy) {
          _showMode(AuthFormMode.signIn);
        }
      },
      child: Theme(
        data: theme,
        child: RepaintBoundary(
          key: const Key('auth-capture-boundary'),
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            body: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
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
                  ),
                ),
                SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      key: const Key('auth-measure'),
                      constraints: const BoxConstraints(maxWidth: _measure),
                      child: Form(
                        key: _formKey,
                        autovalidateMode: _validated
                            ? AutovalidateMode.onUserInteraction
                            : AutovalidateMode.disabled,
                        child: AutofillGroup(
                          child: FocusTraversalGroup(
                            policy: OrderedTraversalPolicy(),
                            child: ScrollConfiguration(
                              // Avoid an animated edge effect during form
                              // replacement; retain platform scrollbars/physics.
                              behavior: ScrollConfiguration.of(
                                context,
                              ).copyWith(overscroll: false),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final wide =
                                      MediaQuery.sizeOf(context).width >=
                                      AppTokens.wideBreakpoint;
                                  final keyboard =
                                      MediaQuery.viewInsetsOf(context).bottom >
                                      0;
                                  final bounded =
                                      constraints.maxHeight.isFinite;
                                  final roomy =
                                      bounded &&
                                      constraints.maxHeight >= 760 &&
                                      !keyboard;
                                  final topPad = wide ? 40.0 : 8.0;
                                  const bottomPad = 24.0;
                                  final minHeight = roomy
                                      ? (constraints.maxHeight -
                                                topPad -
                                                bottomPad)
                                            .clamp(0.0, double.infinity)
                                      : 0.0;
                                  return SingleChildScrollView(
                                    key: const Key('auth-scroll'),
                                    controller: _scroll,
                                    keyboardDismissBehavior:
                                        ScrollViewKeyboardDismissBehavior
                                            .onDrag,
                                    padding: EdgeInsets.fromLTRB(
                                      16,
                                      topPad,
                                      16,
                                      bottomPad,
                                    ),
                                    child: ConstrainedBox(
                                      constraints: BoxConstraints(
                                        minHeight: minHeight,
                                      ),
                                      child: Column(
                                        mainAxisAlignment: roomy
                                            ? MainAxisAlignment.center
                                            : MainAxisAlignment.start,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          _header(theme),
                                          if (_signingUp) ...[
                                            const SizedBox(height: 4),
                                            _backButton(),
                                          ],
                                          const SizedBox(height: 20),
                                          _headline(theme),
                                          if (_guideVisible) ...[
                                            const SizedBox(height: 12),
                                            _guide(),
                                          ],
                                          const SizedBox(height: 16),
                                          _panel(theme, [
                                            if (widget.recoveryNotice !=
                                                null) ...[
                                              _recoveryNotice(theme),
                                              const SizedBox(height: 12),
                                            ],
                                            _modeSwitch(theme),
                                            const SizedBox(height: 16),
                                            if (!_signingUp)
                                              ..._signInFields(theme),
                                            if (_signingUp)
                                              ..._signUpFields(theme),
                                            if (_fieldAlert != null)
                                              Semantics(
                                                key: const Key(
                                                  'auth-field-alert',
                                                ),
                                                liveRegion: true,
                                                label: _fieldAlert,
                                                child: const SizedBox(
                                                  width: double.infinity,
                                                ),
                                              ),
                                            _status(theme.colorScheme),
                                            const SizedBox(height: 8),
                                            _submit(),
                                            if (!_signingUp &&
                                                widget.onForgotPassword != null)
                                              _forgotPassword(),
                                          ]),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    return Row(
      children: [
        const Expanded(child: BrandHero(markSize: 40, compact: true)),
        const SizedBox(width: 8),
        _order(
          0.01,
          IconButton(
            key: const Key('auth-help'),
            tooltip: 'إعادة الإرشاد',
            onPressed: _resumeGuide,
            icon: const Icon(Icons.help_outline),
          ),
        ),
        const SizedBox(width: 8),
        _order(
          0.02,
          IconButton(
            key: const Key('auth-theme-toggle'),
            tooltip: dark ? ShellCopy.toggleToLight : ShellCopy.toggleToDark,
            onPressed: () => widget.onToggleTheme(theme.brightness),
            icon: Icon(
              dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
          ),
        ),
      ],
    );
  }

  Widget _panel(ThemeData theme, List<Widget> children) {
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _modeSwitch(ThemeData theme) {
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            Expanded(
              child: _modeButton(
                theme: theme,
                order: 0.1,
                buttonKey: const Key('show-sign-in'),
                label: AuthCopy.modeSignIn,
                selected: !_signingUp,
                onPressed: () => _showMode(AuthFormMode.signIn),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _modeButton(
                theme: theme,
                order: 0.2,
                buttonKey: const Key('show-signup'),
                label: AuthCopy.modeSignUp,
                selected: _signingUp,
                onPressed: () => _showMode(AuthFormMode.signUp),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeButton({
    required ThemeData theme,
    required double order,
    required Key buttonKey,
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    final scheme = theme.colorScheme;
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(_control)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      elevation: const WidgetStatePropertyAll(0),
      tapTargetSize: MaterialTapTargetSize.padded,
      backgroundColor: WidgetStatePropertyAll(
        selected ? scheme.primary : scheme.surface,
      ),
      foregroundColor: WidgetStatePropertyAll(
        selected ? scheme.onPrimary : scheme.onSurface,
      ),
      side: WidgetStatePropertyAll(
        BorderSide(color: selected ? scheme.primary : scheme.outlineVariant),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radius)),
      ),
      textStyle: WidgetStatePropertyAll(
        theme.textTheme.titleSmall?.copyWith(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
    final child = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
    );
    return _order(
      order,
      Semantics(
        selected: selected,
        child: selected
            ? FilledButton(
                key: buttonKey,
                style: style,
                onPressed: _busy ? null : onPressed,
                child: child,
              )
            : OutlinedButton(
                key: buttonKey,
                style: style,
                onPressed: _busy ? null : onPressed,
                child: child,
              ),
      ),
    );
  }

  Widget _headline(ThemeData theme) {
    final scheme = theme.colorScheme;
    final title = _signingUp ? AuthCopy.signUpTitle : AuthCopy.signInTitle;
    final body = _signingUp ? AuthCopy.signUpBody : AuthCopy.signInBody;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: Text(
            title,
            textAlign: TextAlign.start,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          body,
          textAlign: TextAlign.start,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  List<Widget> _signInFields(ThemeData theme) {
    final kind = AccountIdentifier.detect(_email.text);
    return [
      _contactField(
        order: 1,
        key: const Key('sign-in-identifier'),
        controller: _email,
        focusNode: _emailFocus,
        next: _passwordFocus,
        label: kind == null ? AuthCopy.contactLabel : _kindLabel(kind),
        hint: _kindHint(kind),
        helper: kind == null ? null : _detectedCopy(kind),
        icon: _kindIcon(kind),
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [
          AutofillHints.username,
          AutofillHints.email,
          AutofillHints.telephoneNumber,
        ],
        validator: (value) => _signInContactError(value ?? ''),
      ),
      _passwordField(
        order: 4,
        key: const Key('sign-in-password'),
        autofillHints: const [AutofillHints.password],
        onDone: _submitSignIn,
      ),
    ];
  }

  List<Widget> _signUpFields(ThemeData theme) {
    final scheme = theme.colorScheme;
    return [
      _caption(theme, AuthCopy.ownerSection),
      const SizedBox(height: 8),
      _nameField(
        order: 2,
        key: const Key('signup-owner-name'),
        controller: _owner,
        focusNode: _ownerFocus,
        next: _businessFocus,
        label: AuthCopy.ownerLabel,
        invalid: AuthCopy.ownerInvalid,
        icon: Icons.person_outline,
        autofillHints: const [AutofillHints.name],
      ),
      _nameField(
        order: 3,
        key: const Key('signup-business-name'),
        controller: _business,
        focusNode: _businessFocus,
        next: _emailFocus,
        label: AuthCopy.businessLabel,
        invalid: AuthCopy.businessInvalid,
        icon: Icons.storefront_outlined,
        autofillHints: const [AutofillHints.organizationName],
      ),
      _caption(theme, AuthCopy.contactSection),
      const SizedBox(height: 4),
      Text(
        AuthCopy.contactGuide,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          height: 1.5,
        ),
      ),
      const SizedBox(height: 8),
      _contactField(
        order: 4,
        key: const Key('signup-email'),
        controller: _email,
        focusNode: _emailFocus,
        next: _phoneFocus,
        label: _signupLabel(_email.text, _phone.text),
        hint: _kindHint(AccountIdentifier.detect(_email.text)),
        helper: _detectedHelper(_email.text),
        icon: _kindIcon(AccountIdentifier.detect(_email.text)),
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [
          AutofillHints.email,
          AutofillHints.telephoneNumber,
        ],
        validator: (value) =>
            _signupContactError(value ?? '', _phone.text, secondary: false),
      ),
      _contactField(
        order: 5,
        key: const Key('signup-phone'),
        controller: _phone,
        focusNode: _phoneFocus,
        next: _governorateFocus,
        label: _signupLabel(_phone.text, _email.text),
        hint: _kindHint(AccountIdentifier.detect(_phone.text)),
        helper: _detectedHelper(_phone.text),
        icon: _kindIcon(AccountIdentifier.detect(_phone.text)),
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [
          AutofillHints.email,
          AutofillHints.telephoneNumber,
        ],
        validator: (value) =>
            _signupContactError(value ?? '', _email.text, secondary: true),
      ),
      _governorateBlock(theme, scheme),
      _caption(theme, AuthCopy.credentialsSection),
      const SizedBox(height: 8),
      _passwordField(
        order: 8,
        key: const Key('signup-password'),
        autofillHints: const [AutofillHints.newPassword],
        onDone: _submitSignUp,
      ),
    ];
  }

  Widget _governorateBlock(ThemeData theme, ColorScheme scheme) {
    final showFailure =
        _governorateLoadFailed ||
        (!_loadingGovernorates && _governorates.isEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loadingGovernorates) ...[
          Semantics(
            key: const Key('governorate-loading'),
            liveRegion: true,
            label: AuthCopy.governorateLoading,
            child: _motionBar(AuthCopy.governorateLoading),
          ),
          const SizedBox(height: 8),
          Text(
            AuthCopy.governorateLoading,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (showFailure) ...[
          ExcludeSemantics(child: _label(theme, AuthCopy.governorateLabel)),
          const SizedBox(height: 8),
          Semantics(
            container: true,
            liveRegion: true,
            child: Text(
              AuthCopy.governorateFailed,
              key: const Key('governorate-error'),
              softWrap: true,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.error,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _order(
            6,
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                key: const Key('governorate-retry'),
                onPressed: _loadingGovernorates ? null : _loadGovernorates,
                child: const Text(
                  AuthCopy.governorateRetry,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_governorates.isNotEmpty) ...[
          ExcludeSemantics(child: _label(theme, AuthCopy.governorateLabel)),
          const SizedBox(height: 8),
          _order(
            6,
            Semantics(
              label: AuthCopy.governorateLabel,
              child: DropdownButtonFormField<String>(
                key: const Key('signup-governorate'),
                initialValue: _governorateCode,
                isExpanded: true,
                focusNode: _governorateFocus,
                decoration: const InputDecoration(
                  hintText: AuthCopy.governorateHint,
                ),
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
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _recoveryNotice(ThemeData theme) {
    final scheme = theme.colorScheme;
    final error = widget.recoveryNoticeIsError;
    final message = widget.recoveryNotice ?? '';
    return Semantics(
      key: const Key('auth-recovery-notice'),
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: error ? scheme.errorContainer : scheme.primaryContainer,
          borderRadius: BorderRadius.circular(_radius),
          border: Border.all(color: error ? scheme.error : scheme.primary),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            message,
            softWrap: true,
            style: theme.textTheme.bodyLarge?.copyWith(
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

  Widget _forgotPassword() {
    return _order(
      7,
      SizedBox(
        width: double.infinity,
        child: TextButton(
          key: const Key('forgot-password'),
          style: TextButton.styleFrom(
            minimumSize: const Size(48, _control),
            alignment: AlignmentDirectional.centerStart,
          ),
          onPressed: _busy ? null : widget.onForgotPassword,
          child: const Text(
            RecoveryCopy.forgotPassword,
            textAlign: TextAlign.start,
          ),
        ),
      ),
    );
  }

  Widget _status(ColorScheme scheme) {
    final message = _serverMessage;
    if (_busy) {
      final label = _signingUp ? AuthCopy.signUpBusy : AuthCopy.signInBusy;
      return Semantics(
        key: const Key('auth-progress'),
        liveRegion: true,
        label: label,
        child: _motionBar(label),
      );
    }
    if (message == null) return const SizedBox.shrink();
    final unknown = _unknown && _signingUp;
    return KeyedSubtree(
      key: _statusKey,
      child: Semantics(
        key: const Key('auth-server-status'),
        liveRegion: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: unknown ? scheme.surface : scheme.errorContainer,
            borderRadius: BorderRadius.circular(_radius),
            border: Border.all(color: unknown ? scheme.outline : scheme.error),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    unknown ? Icons.schedule : Icons.error_outline,
                    color: unknown ? scheme.onSurface : scheme.onErrorContainer,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    message,
                    key: Key(
                      _signingUp
                          ? (_unknown ? 'signup-unknown' : 'signup-error')
                          : 'sign-in-error',
                    ),
                    softWrap: true,
                    style: _authTheme(Theme.of(context)).textTheme.bodyLarge
                        ?.copyWith(
                          color: unknown
                              ? scheme.onSurface
                              : scheme.onErrorContainer,
                          height: 1.5,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _backButton() {
    return _order(
      0.05,
      SizedBox(
        width: double.infinity,
        child: TextButton(
          key: const Key('signup-back'),
          style: TextButton.styleFrom(
            minimumSize: const Size(48, _control),
            alignment: AlignmentDirectional.centerStart,
            padding: const EdgeInsetsDirectional.only(end: 8),
          ),
          onPressed: _busy ? null : () => _showMode(AuthFormMode.signIn),
          child: const Row(
            children: [
              Icon(Icons.arrow_back),
              SizedBox(width: 8),
              Expanded(
                child: Text(AuthCopy.backToSignIn, textAlign: TextAlign.start),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _motionBar(String label) {
    final scheme = Theme.of(context).colorScheme;
    if (MediaQuery.disableAnimationsOf(context)) {
      return Tooltip(
        message: label,
        child: SizedBox(
          height: 4,
          width: double.infinity,
          child: ColoredBox(color: scheme.primary),
        ),
      );
    }
    return const LinearProgressIndicator(minHeight: 4);
  }

  Widget _submit() {
    final label = _busy
        ? (_signingUp ? AuthCopy.signUpBusy : AuthCopy.signInBusy)
        : _signingUp
        ? (_attempt == null ? AuthCopy.signUpAction : AuthCopy.retryAction)
        : AuthCopy.signInAction;
    return _order(
      _signingUp ? 10 : 6,
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          key: Key(_signingUp ? 'signup-submit' : 'sign-in-submit'),
          focusNode: _submitFocus,
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, _control),
          ),
          onPressed: _busy
              ? null
              : _signingUp
              ? _submitSignUp
              : _submitSignIn,
          child: Text(label, textAlign: TextAlign.center),
        ),
      ),
    );
  }

  Widget _caption(ThemeData theme, String text) {
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        children: [
          ExcludeSemantics(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(2),
              ),
              child: const SizedBox(width: 3, height: 16),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleSmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(ThemeData theme, String text) {
    return Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurface,
        fontWeight: FontWeight.w600,
        height: 1.4,
      ),
    );
  }

  Widget _nameField({
    required double order,
    required Key key,
    required TextEditingController controller,
    required FocusNode focusNode,
    required FocusNode next,
    required String label,
    required String invalid,
    required IconData icon,
    required List<String> autofillHints,
  }) {
    final theme = _authTheme(Theme.of(context));
    return _labeled(
      order: order,
      label: label,
      theme: theme,
      field: TextFormField(
        key: key,
        controller: controller,
        focusNode: focusNode,
        enabled: !_locked,
        textInputAction: TextInputAction.next,
        keyboardType: TextInputType.name,
        autofillHints: autofillHints,
        enableInteractiveSelection: true,
        scrollPadding: _fieldScrollPadding,
        onFieldSubmitted: (_) => next.requestFocus(),
        decoration: InputDecoration(
          prefixIcon: ExcludeSemantics(
            child: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        validator: (value) =>
            AccountName.tryCanonical(value ?? '') == null ? invalid : null,
      ),
    );
  }

  Widget _contactField({
    required double order,
    required Key key,
    required TextEditingController controller,
    required FocusNode focusNode,
    required FocusNode next,
    required String label,
    required String? hint,
    required String? helper,
    required IconData icon,
    required TextInputType keyboardType,
    required List<String> autofillHints,
    required FormFieldValidator<String> validator,
  }) {
    final theme = _authTheme(Theme.of(context));
    return _labeled(
      order: order,
      label: label,
      theme: theme,
      field: TextFormField(
        key: key,
        controller: controller,
        focusNode: focusNode,
        enabled: !_locked,
        keyboardType: keyboardType,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.start,
        textInputAction: TextInputAction.next,
        autofillHints: autofillHints,
        autocorrect: false,
        enableSuggestions: false,
        enableInteractiveSelection: true,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        scrollPadding: _fieldScrollPadding,
        onFieldSubmitted: (_) => next.requestFocus(),
        decoration: InputDecoration(
          hintText: hint,
          helperText: helper,
          helperMaxLines: 3,
          prefixIcon: ExcludeSemantics(
            child: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        validator: validator,
      ),
    );
  }

  String _signupLabel(String own, String other) {
    final ownKind = AccountIdentifier.detect(own);
    if (ownKind != null) return _kindLabel(ownKind);
    final otherKind = AccountIdentifier.detect(other);
    if (otherKind == SignInIdentifier.email) return AuthCopy.phoneLabel;
    if (otherKind == SignInIdentifier.phone) return AuthCopy.emailLabel;
    return AuthCopy.contactLabel;
  }

  String? _detectedHelper(String value) {
    final kind = AccountIdentifier.detect(value);
    if (kind == null) return null;
    return _detectedCopy(kind);
  }

  String _kindLabel(SignInIdentifier kind) {
    return switch (kind) {
      SignInIdentifier.email => AuthCopy.emailLabel,
      SignInIdentifier.phone => AuthCopy.phoneLabel,
    };
  }

  String? _kindHint(SignInIdentifier? kind) {
    return switch (kind) {
      SignInIdentifier.email => AuthCopy.emailHint,
      SignInIdentifier.phone => AuthCopy.phoneHint,
      null => null,
    };
  }

  String _detectedCopy(SignInIdentifier kind) {
    return switch (kind) {
      SignInIdentifier.email => AuthCopy.detectedEmail,
      SignInIdentifier.phone => AuthCopy.detectedPhone,
    };
  }

  IconData _kindIcon(SignInIdentifier? kind) {
    return switch (kind) {
      SignInIdentifier.email => Icons.mail_outline,
      SignInIdentifier.phone => Icons.phone_outlined,
      null => Icons.alternate_email,
    };
  }

  Widget _passwordField({
    required double order,
    required Key key,
    required List<String> autofillHints,
    required VoidCallback onDone,
  }) {
    final theme = _authTheme(Theme.of(context));
    return _labeled(
      order: order,
      label: AuthCopy.passwordLabel,
      theme: theme,
      field: TextFormField(
        key: key,
        controller: _password,
        focusNode: _passwordFocus,
        enabled: !_locked,
        obscureText: !_passwordVisible,
        enableSuggestions: false,
        autocorrect: false,
        enableInteractiveSelection: true,
        smartDashesType: SmartDashesType.disabled,
        smartQuotesType: SmartQuotesType.disabled,
        autofillHints: autofillHints,
        keyboardType: TextInputType.visiblePassword,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.start,
        textInputAction: TextInputAction.done,
        scrollPadding: _fieldScrollPadding,
        onFieldSubmitted: (_) {
          if (!_busy) onDone();
        },
        decoration: InputDecoration(
          helperText: _signingUp ? AuthCopy.passwordHelper : null,
          helperMaxLines: 4,
          prefixIcon: ExcludeSemantics(
            child: Icon(
              Icons.lock_outline,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          suffixIcon: IconButton(
            key: const Key('password-visibility'),
            tooltip: _passwordVisible
                ? AuthCopy.hidePassword
                : AuthCopy.showPassword,
            onPressed: () =>
                setState(() => _passwordVisible = !_passwordVisible),
            icon: Icon(
              _passwordVisible
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
            ),
          ),
        ),
        validator: (value) => AccountPassword.isAcceptable(value ?? '')
            ? null
            : AuthCopy.passwordInvalid,
      ),
    );
  }

  Widget _labeled({
    required double order,
    required String label,
    required ThemeData theme,
    required Widget field,
  }) {
    return _order(
      order,
      Padding(
        padding: EdgeInsets.only(bottom: _guideVisible ? 8 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(child: _label(_authTheme(theme), label)),
            const SizedBox(height: 8),
            Semantics(label: label, child: field),
          ],
        ),
      ),
    );
  }

  Widget _order(double order, Widget child) {
    return FocusTraversalOrder(order: NumericFocusOrder(order), child: child);
  }
}

class _FieldCheck {
  const _FieldCheck(this.focus, this.invalid);

  final FocusNode focus;
  final String? invalid;
}
