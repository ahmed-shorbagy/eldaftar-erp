import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phone_form_field/phone_form_field.dart';

import '../../../shell/shell_copy.dart';
import '../../../theme/brand_mark.dart';
import '../../onboarding/application/onboarding_store.dart';
import '../domain/registration_country.dart';
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
  final _phone = PhoneController(
    initialValue: const PhoneNumber(isoCode: IsoCode.EG, nsn: ''),
  );
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
  int _signupStep = 0;
  RegistrationCountry _country = RegistrationCountry.all.first;
  final _region = TextEditingController();
  final _confirmPassword = TextEditingController();
  final _confirmFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _email.addListener(_refreshContacts);
    _phone.addListener(_refreshPhone);
  }

  @override
  void dispose() {
    _email.removeListener(_refreshContacts);
    _phone.removeListener(_refreshPhone);
    _region.dispose();
    _confirmPassword.dispose();
    _confirmFocus.dispose();
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

  void _refreshPhone() {
    final country = RegistrationCountry.byCode(_phone.value.isoCode.name);
    if (country != null && country.code != _country.code) {
      _country = country;
      _governorateCode = null;
      _region.clear();
    }
    _refreshContacts();
  }

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
      _signupStep = 0;
    });
    if (mode == AuthFormMode.signUp &&
        _governorates.isEmpty &&
        !_loadingGovernorates) {
      _loadGovernorates();
    }
    if (_scroll.hasClients) _scroll.jumpTo(0);
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
    return RegistrationCountry.internationalPhone(value) == null
        ? AuthCopy.phoneInvalid
        : null;
  }

  String? _signupContactError(
    String own,
    String other, {
    required bool secondary,
  }) {
    return secondary
        ? (_country.canonicalPhone(own) == null ? AuthCopy.phoneInvalid : null)
        : (AccountEmail.tryCanonical(own) == null
              ? AuthCopy.emailInvalid
              : null);
  }

  ({String email, String phone})? _resolvedContacts() {
    final email = AccountEmail.tryCanonical(_email.text);
    final phone = _country.canonicalPhone(_phone.value.international);
    return email == null || phone == null ? null : (email: email, phone: phone);
  }

  List<_FieldCheck> _signUpChecks() => _signupStep == 1
      ? [
          _FieldCheck(
            _businessFocus,
            AccountName.tryCanonical(_business.text) == null
                ? AuthCopy.businessInvalid
                : null,
          ),
          _FieldCheck(
            _governorateFocus,
            (_country.code == 'EG' && _governorates.isNotEmpty
                    ? _governorateCode == null
                    : _country.regionCode(_region.text) == null)
                ? AuthCopy.governorateInvalid
                : null,
          ),
        ]
      : [
          _FieldCheck(
            _ownerFocus,
            AccountName.tryCanonical(_owner.text) == null
                ? AuthCopy.ownerInvalid
                : null,
          ),
          _FieldCheck(
            _emailFocus,
            _signupContactError(
              _email.text,
              _phone.value.international,
              secondary: false,
            ),
          ),
          _FieldCheck(
            _phoneFocus,
            _signupContactError(
              _phone.value.international,
              _email.text,
              secondary: true,
            ),
          ),
          _passwordCheck(),
          _FieldCheck(
            _confirmFocus,
            _confirmPassword.text == _password.text
                ? null
                : 'كلمتا المرور غير متطابقتين',
          ),
        ];

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
    final governorate = _country.code == 'EG' && _governorates.isNotEmpty
        ? _governorateCode
        : _country.regionCode(_region.text);
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
    final scheme = theme.colorScheme;
    return PopScope(
      canPop: !_signingUp && !_busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_busy) _back();
      },
      child: Theme(
        data: theme,
        child: RepaintBoundary(
          key: const Key('auth-capture-boundary'),
          child: Scaffold(
            backgroundColor: scheme.surface,
            body: Stack(
              fit: StackFit.expand,
              children: [
                const _AuthAtmosphere(),
                SafeArea(
                  child: Center(
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
                            child: SingleChildScrollView(
                              key: const Key('auth-scroll'),
                              controller: _scroll,
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _header(theme),
                                  const SizedBox(height: 8),
                                  const BrandHero(markSize: 56),
                                  SizedBox(height: _signingUp ? 28 : 120),
                                  _panel(theme, [
                                    _headline(theme),
                                    const SizedBox(height: 20),
                                    if (widget.recoveryNotice != null) ...[
                                      _recoveryNotice(theme),
                                      const SizedBox(height: 12),
                                    ],
                                    if (_signingUp) ...[
                                      _signupProgress(theme),
                                      const SizedBox(height: 20),
                                      ..._signUpFields(theme),
                                    ] else
                                      ..._signInFields(theme),
                                    if (!_signingUp &&
                                        widget.onForgotPassword != null)
                                      _forgotPassword(),
                                    if (_fieldAlert != null)
                                      Semantics(
                                        key: const Key('auth-field-alert'),
                                        liveRegion: true,
                                        label: _fieldAlert,
                                        child: const SizedBox.shrink(),
                                      ),
                                    _status(theme.colorScheme),
                                    const SizedBox(height: 8),
                                    _submit(),
                                    if (!_signingUp) ...[
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          const Expanded(child: Divider()),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                            ),
                                            child: Text(
                                              'أو',
                                              style: theme.textTheme.bodyMedium,
                                            ),
                                          ),
                                          const Expanded(child: Divider()),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      OutlinedButton.icon(
                                        key: const Key('show-signup'),
                                        onPressed: _busy
                                            ? null
                                            : () => _showMode(
                                                AuthFormMode.signUp,
                                              ),
                                        icon: const Icon(
                                          Icons.person_add_outlined,
                                        ),
                                        label: const Text('إنشاء حساب جديد'),
                                      ),
                                    ],
                                  ]),
                                ],
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

  void _back() {
    if (_signingUp && _signupStep > 0 && !_unknown) {
      setState(() {
        _signupStep--;
        _validated = false;
        _formKey = GlobalKey<FormState>();
      });
    } else {
      _showMode(AuthFormMode.signIn);
    }
  }

  void _nextSignup() {
    if (_busy) return;
    if (_signupStep == 2 || _unknown) {
      _submitSignUp();
      return;
    }
    if (_rejected(_signUpChecks())) return;
    setState(() {
      _signupStep++;
      _validated = false;
      _formKey = GlobalKey<FormState>();
    });
    _scroll.jumpTo(0);
  }

  Widget _signupProgress(ThemeData theme) => Row(
    children: [
      for (var i = 0; i < 3; i++)
        Expanded(
          child: Semantics(
            selected: _signupStep == i,
            child: Column(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: _signupStep == i
                      ? theme.colorScheme.primary
                      : theme.colorScheme.surfaceContainerHighest,
                  foregroundColor: _signupStep == i
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                  child: Text('${i + 1}'),
                ),
                const SizedBox(height: 8),
                Text(
                  const ['بيانات الحساب', 'بيانات المحل', 'مراجعة'][i],
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _header(ThemeData theme) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      if (_signingUp)
        IconButton(
          key: const Key('signup-back'),
          tooltip: AuthCopy.backToSignIn,
          onPressed: _busy ? null : _back,
          icon: const Icon(Icons.arrow_back),
        )
      else
        const SizedBox(width: 48),
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
  );

  Widget _panel(ThemeData theme, List<Widget> children) {
    final scheme = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.18),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
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
        helper: null,
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
    if (_signupStep == 2) {
      return [
        _registrationLine('الاسم', _owner.text),
        _registrationLine('البريد الإلكتروني', _email.text),
        _registrationLine(
          'رقم الهاتف',
          _country.canonicalPhone(_phone.value.international) ??
              _phone.value.international,
        ),
        _registrationLine('اسم المحل', _business.text),
        _registrationLine('الدولة', _country.nameAr),
        _registrationLine(
          'المحافظة / المنطقة',
          _country.code == 'EG' && _governorates.isNotEmpty
              ? _governorates
                        .where((g) => g.code == _governorateCode)
                        .firstOrNull
                        ?.nameAr ??
                    ''
              : _region.text,
        ),
        const SizedBox(height: 16),
      ];
    }
    if (_signupStep == 1) {
      return [
        _nameField(
          order: 1,
          key: const Key('signup-business-name'),
          controller: _business,
          focusNode: _businessFocus,
          next: _governorateFocus,
          label: AuthCopy.businessLabel,
          invalid: AuthCopy.businessInvalid,
          icon: Icons.storefront_outlined,
          autofillHints: const [AutofillHints.organizationName],
        ),
        if (_country.code == 'EG' &&
            (_loadingGovernorates || _governorates.isNotEmpty))
          _governorateBlock(theme, theme.colorScheme)
        else
          _labeled(
            order: 2,
            label: 'المحافظة / المنطقة',
            theme: theme,
            field: TextFormField(
              key: const Key('signup-region'),
              controller: _region,
              focusNode: _governorateFocus,
              enabled: !_locked,
              decoration: const InputDecoration(hintText: 'اكتب المنطقة'),
              validator: (value) => _country.regionCode(value ?? '') == null
                  ? 'أدخل المنطقة'
                  : null,
            ),
          ),
      ];
    }
    return [
      _nameField(
        order: 1,
        key: const Key('signup-owner-name'),
        controller: _owner,
        focusNode: _ownerFocus,
        next: _emailFocus,
        label: AuthCopy.ownerLabel,
        invalid: AuthCopy.ownerInvalid,
        icon: Icons.person_outline,
        autofillHints: const [AutofillHints.name],
      ),
      _contactField(
        order: 2,
        key: const Key('signup-email'),
        controller: _email,
        focusNode: _emailFocus,
        next: _phoneFocus,
        label: AuthCopy.emailLabel,
        hint: AuthCopy.emailHint,
        helper: null,
        icon: Icons.mail_outline,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        validator: (value) => AccountEmail.tryCanonical(value ?? '') == null
            ? AuthCopy.emailInvalid
            : null,
      ),
      _labeled(
        order: 3,
        label: AuthCopy.phoneLabel,
        theme: theme,
        field: Localizations.override(
          context: context,
          locale: const Locale('ar'),
          delegates: PhoneFieldLocalization.delegates.toList(),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: PhoneFormField(
              key: const Key('signup-phone'),
              controller: _phone,
              focusNode: _phoneFocus,
              enabled: !_locked,
              isCountrySelectionEnabled: !_locked,
              shouldLimitLengthByCountry: false,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => _passwordFocus.requestFocus(),
              scrollPadding: _fieldScrollPadding,
              autofillHints: const [AutofillHints.telephoneNumber],
              autovalidateMode: _validated
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,
              countryButtonStyle: CountryButtonStyle(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                flagSize: 24,
                textStyle: theme.textTheme.bodyMedium,
                borderRadius: BorderRadius.circular(12),
              ),
              countrySelectorNavigator: CountrySelectorNavigator.dialog(
                countries: [
                  for (final country in RegistrationCountry.all)
                    IsoCode.values.firstWhere(
                      (iso) => iso.name == country.code,
                    ),
                ],
                favorites: const [IsoCode.EG, IsoCode.SA, IsoCode.AE],
                searchAutofocus: false,
                backgroundColor: theme.colorScheme.surface,
                titleStyle: theme.textTheme.bodyLarge,
                subtitleStyle: theme.textTheme.bodyMedium,
                searchBoxDecoration: const InputDecoration(
                  labelText: 'ابحث عن الدولة أو كودها',
                  prefixIcon: Icon(Icons.search),
                ),
                noResultMessage: 'لا توجد دولة مطابقة',
              ),
              decoration: const InputDecoration(
                hintText: 'رقم الهاتف',
                hintTextDirection: TextDirection.rtl,
              ),
              validator: (value) =>
                  value == null ||
                      value.nsn.isEmpty ||
                      RegistrationCountry.byCode(value.isoCode.name) == null ||
                      _country.canonicalPhone(value.international) == null
                  ? AuthCopy.phoneInvalid
                  : null,
            ),
          ),
        ),
      ),
      _passwordField(
        order: 5,
        key: const Key('signup-password'),
        autofillHints: const [AutofillHints.newPassword],
        onDone: _nextSignup,
      ),
      _labeled(
        order: 6,
        label: 'تأكيد كلمة المرور',
        theme: theme,
        field: TextFormField(
          key: const Key('signup-password-confirm'),
          controller: _confirmPassword,
          focusNode: _confirmFocus,
          enabled: !_locked,
          obscureText: !_passwordVisible,
          textDirection: TextDirection.ltr,
          autofillHints: const [AutofillHints.newPassword],
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.lock_outline),
          ),
          validator: (value) =>
              value == _password.text && (value ?? '').isNotEmpty
              ? null
              : 'كلمتا المرور غير متطابقتين',
        ),
      ),
    ];
  }

  Widget _registrationLine(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    ),
  );

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
        ? (_signupStep < 2 && !_unknown
              ? 'التالي'
              : _attempt == null
              ? AuthCopy.signUpAction
              : AuthCopy.retryAction)
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
              ? _nextSignup
              : _submitSignIn,
          child: Text(label, textAlign: TextAlign.center),
        ),
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
          helperText: null,
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
        padding: const EdgeInsets.only(bottom: 16),
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

/// Full-bleed jewelry photo that fades into the page surface.
class _AuthAtmosphere extends StatelessWidget {
  const _AuthAtmosphere();

  static const _asset = 'assets/brand/auth-jewelry.png';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final height = MediaQuery.sizeOf(context).height;
    return ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: height * 0.58,
              width: double.infinity,
              child: Image.asset(
                _asset,
                fit: BoxFit.cover,
                alignment: const Alignment(0, 0.55),
                color: dark
                    ? scheme.surface.withValues(alpha: 0.42)
                    : scheme.surface.withValues(alpha: 0.12),
                colorBlendMode: BlendMode.darken,
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              height: height * 0.28,
              width: double.infinity,
              child: Opacity(
                opacity: dark ? 0.34 : 0.22,
                child: Image.asset(
                  _asset,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.35),
                  color: scheme.surface.withValues(alpha: dark ? 0.55 : 0.35),
                  colorBlendMode: BlendMode.darken,
                ),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  scheme.surface.withValues(alpha: dark ? 0.55 : 0.28),
                  scheme.surface.withValues(alpha: dark ? 0.18 : 0.08),
                  scheme.surface.withValues(alpha: 0.82),
                  scheme.surface,
                ],
                stops: const [0, 0.28, 0.52, 0.72],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
