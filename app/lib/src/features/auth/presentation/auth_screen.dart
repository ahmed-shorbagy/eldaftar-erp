import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phone_form_field/phone_form_field.dart';

import '../../../shell/shell_copy.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/brand_mark.dart';
import '../../invoice_appearance/domain/logo_bytes.dart';
import '../../onboarding/application/onboarding_store.dart';
import '../../shop_accounts/domain/shop_image.dart';
import '../../shop_accounts/presentation/shop_image_copy.dart';
import '../../shop_accounts/presentation/shop_image_picker.dart';
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
    this.shopImageGateway,
    this.saveRegistrationInvoiceLogo,
    this.pickShopImage,
    this.onForgotPassword,
    this.recoveryNotice,
    this.recoveryNoticeIsError = false,
  });

  final AuthGateway gateway;
  final Future<void> Function(Brightness brightness) onToggleTheme;
  final ValueChanged<bool> onHold;
  final VoidCallback onSessionSettled;
  final OnboardingStore? onboardingStore;
  final ShopImageGateway? shopImageGateway;
  final Future<void> Function(Uint8List)? saveRegistrationInvoiceLogo;
  final Future<Uint8List?> Function()? pickShopImage;
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
  OwnerRegistration? _attempt;
  bool _unknown = false;
  bool _busy = false;
  bool _passwordVisible = false;
  bool _validated = false;
  String? _serverMessage;
  String? _fieldAlert;
  int _signupStep = 0;
  RegistrationCountry _country = RegistrationCountry.all.first;
  final _region = TextEditingController();
  String? _selectedGovernorate;
  List<Governorate>? _governorates;
  bool _governoratesLoading = false;
  String? _governoratesError;
  int _governorateLoad = 0;
  final _confirmPassword = TextEditingController();
  final _confirmFocus = FocusNode();
  Uint8List? _shopImageBytes;
  String? _shopImageAlert;
  bool _pickingShopImage = false;
  bool _useImageForInvoices = false;

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

  bool get _compactLogin {
    final media = MediaQuery.of(context);
    return !_signingUp &&
        (media.size.height - media.padding.vertical - media.viewInsets.bottom <
                720 ||
            media.textScaler.scale(1) >= 1.25);
  }

  void _refreshPhone() {
    final country = RegistrationCountry.byCode(_phone.value.isoCode.name);
    if (country != null && country.code != _country.code) {
      _country = country;
      _region.clear();
      _selectedGovernorate = null;
      if (country.code == 'EG') {
        _ensureGovernorates();
      }
    }
    _refreshContacts();
  }

  Future<void> _ensureGovernorates({bool retry = false}) async {
    if (_country.code != 'EG') return;
    if (!retry && (_governoratesLoading || _governorates != null)) return;
    final generation = ++_governorateLoad;
    setState(() {
      _governoratesLoading = true;
      _governoratesError = null;
      if (retry) _governorates = null;
    });
    try {
      final loaded = await widget.gateway.loadGovernorates();
      if (!mounted || generation != _governorateLoad) return;
      final catalog = [
        for (final item in loaded)
          if (EgyptianGovernorates.isValid(item.code)) item,
      ];
      if (catalog.isEmpty) {
        setState(() {
          _governoratesLoading = false;
          _governoratesError = AuthCopy.governorateLoadFailed;
        });
        return;
      }
      setState(() {
        _governorates = catalog;
        _governoratesLoading = false;
        if (_selectedGovernorate != null &&
            !catalog.any((item) => item.code == _selectedGovernorate)) {
          _selectedGovernorate = null;
        }
      });
    } catch (_) {
      if (!mounted || generation != _governorateLoad) return;
      setState(() {
        _governoratesLoading = false;
        _governoratesError = AuthCopy.governorateLoadFailed;
      });
    }
  }

  String? _locationCode() {
    if (_country.code == 'EG') {
      final selected = _selectedGovernorate;
      if (selected == null) return null;
      if (_governorates != null &&
          !_governorates!.any((item) => item.code == selected)) {
        return null;
      }
      return _country.regionCode(selected);
    }
    return _country.regionCode(_region.text);
  }

  String? _locationError() {
    if (_country.code == 'EG') {
      if (_governoratesLoading) return AuthCopy.governorateLoading;
      if (_governoratesError != null) return _governoratesError;
      return _locationCode() == null ? AuthCopy.governorateInvalid : null;
    }
    return _country.regionCode(_region.text) == null
        ? AuthCopy.cityRegionInvalid
        : null;
  }

  String _locationReviewValue() {
    if (_country.code == 'EG') {
      final selected = _selectedGovernorate;
      if (selected == null) return '';
      for (final item in _governorates ?? const <Governorate>[]) {
        if (item.code == selected) return item.nameAr;
      }
      return selected;
    }
    return _region.text.trim();
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
    if (mode == AuthFormMode.signUp) _ensureGovernorates();
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
          _FieldCheck(_governorateFocus, _locationError()),
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
    final governorate = _locationCode();
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

  Future<void> _pickShopImage() async {
    if (_locked || _pickingShopImage || widget.shopImageGateway == null) {
      return;
    }
    setState(() {
      _pickingShopImage = true;
      _shopImageAlert = null;
    });
    try {
      final picker = widget.pickShopImage;
      final selection = picker == null ? pickShopImageBytes(context) : picker();
      final bytes = await selection;
      if (!mounted) return;
      setState(() {
        _pickingShopImage = false;
        if (bytes != null) {
          _shopImageBytes = bytes;
          _shopImageAlert = null;
        }
      });
    } on LogoByteRejection catch (error) {
      if (!mounted) return;
      setState(() {
        _pickingShopImage = false;
        _shopImageAlert = error.code == 'image_too_large'
            ? ShopImageCopy.tooLarge
            : ShopImageCopy.rejected;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pickingShopImage = false;
        _shopImageAlert = ShopImageCopy.rejected;
      });
    }
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
      final image = _shopImageBytes;
      final imageGateway = widget.shopImageGateway;
      if (image != null && imageGateway != null) {
        try {
          await imageGateway.setImage(image);
        } on ShopImageException {
          // Account exists; image can be added later from More.
        }
      }
      if (image != null && _useImageForInvoices) {
        try {
          await widget.saveRegistrationInvoiceLogo?.call(image);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'تم إنشاء الحساب، وتعذر حفظ مسودة الشعار. أضفه من المزيد ← مظهر الفاتورة.',
                ),
              ),
            );
          }
        }
      }
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
            body: SafeArea(
              child: Form(
                key: _formKey,
                autovalidateMode: _validated
                    ? AutovalidateMode.onUserInteraction
                    : AutovalidateMode.disabled,
                child: AutofillGroup(
                  child: FocusTraversalGroup(
                    policy: OrderedTraversalPolicy(),
                    child: _signingUp
                        ? _signupShell(theme)
                        : _loginShell(theme),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _back() {
    if (_signingUp && _signupStep > 0 && !_unknown) {
      _goToSignupStep(_signupStep - 1);
    } else {
      _showMode(AuthFormMode.signIn);
    }
  }

  void _goToSignupStep(int step) {
    if (_busy || _unknown || step < 0 || step > 2 || step == _signupStep) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _signupStep = step;
      _validated = false;
      _formKey = GlobalKey<FormState>();
    });
    if (step == 1) _ensureGovernorates();
    if (_scroll.hasClients) _scroll.jumpTo(0);
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
    if (_signupStep == 1) _ensureGovernorates();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Widget _signupProgress(ThemeData theme) {
    const labels = [
      AuthCopy.stepAccount,
      AuthCopy.stepShop,
      AuthCopy.stepReview,
    ];
    return Row(
      children: [
        for (var i = 0; i < 3; i++)
          Expanded(
            child: Semantics(
              selected: _signupStep == i,
              button: i < _signupStep && !_locked && !_unknown,
              label: labels[i],
              child: InkWell(
                key: Key('signup-step-$i'),
                onTap: i < _signupStep && !_locked && !_unknown
                    ? () => _goToSignupStep(i)
                    : null,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 2,
                  ),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: i <= _signupStep
                            ? theme.colorScheme.primary
                            : theme.colorScheme.surfaceContainerHighest,
                        foregroundColor: i <= _signupStep
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                        child: i < _signupStep
                            ? const Icon(Icons.check, size: 16)
                            : Text('${i + 1}'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        labels[i],
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: i == _signupStep
                              ? theme.colorScheme.onSurface
                              : theme.colorScheme.onSurfaceVariant,
                          fontWeight: i == _signupStep
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _loginShell(ThemeData theme) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        key: const Key('auth-measure'),
        constraints: const BoxConstraints(maxWidth: _measure),
        child: SingleChildScrollView(
          key: const Key('auth-scroll'),
          controller: _scroll,
          clipBehavior: Clip.none,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(
            _compactLogin ? 16 : 20,
            _compactLogin ? 0 : 4,
            _compactLogin ? 16 : 20,
            (_compactLogin ? 12 : 28) + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _AuthPhotoBand(
                compact: _compactLogin,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(theme),
                    SizedBox(height: _compactLogin ? 0 : AppTokens.spaceSm),
                    BrandHero(
                      markSize: _compactLogin ? AppTokens.minControlSize : 56,
                      compact: _compactLogin,
                      onPhoto: !_compactLogin,
                    ),
                  ],
                ),
              ),
              _panel(theme, [
                _headline(theme),
                SizedBox(height: _compactLogin ? 8 : 14),
                if (widget.recoveryNotice != null) ...[
                  _recoveryNotice(theme),
                  const SizedBox(height: 12),
                ],
                ..._signInFields(theme),
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
                SizedBox(height: _compactLogin ? 6 : 10),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('أو', style: theme.textTheme.bodyMedium),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                SizedBox(height: _compactLogin ? 6 : 10),
                OutlinedButton.icon(
                  key: const Key('show-signup'),
                  onPressed: _busy
                      ? null
                      : () => _showMode(AuthFormMode.signUp),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('إنشاء حساب جديد'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _signupShell(ThemeData theme) {
    final media = MediaQuery.of(context);
    final roomForPhoto =
        media.size.height - media.viewInsets.bottom >= 700 &&
        media.textScaler.scale(1) < 1.25;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AuthPhotoBand(
          compact: true,
          enabled: roomForPhoto,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(theme),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: BrandHero(
                    markSize: AppTokens.minControlSize,
                    compact: true,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              key: const Key('auth-measure'),
              constraints: const BoxConstraints(maxWidth: _measure),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, roomForPhoto ? 0 : 8, 16, 12),
                child: DecoratedBox(
                  key: const Key('auth-signup-panel'),
                  decoration: _panelDecoration(theme.colorScheme),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: SingleChildScrollView(
                      key: const Key('auth-scroll'),
                      controller: _scroll,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _headline(theme),
                          const SizedBox(height: 12),
                          _signupProgress(theme),
                          if (widget.recoveryNotice != null) ...[
                            const SizedBox(height: 12),
                            _recoveryNotice(theme),
                          ],
                          const SizedBox(height: 12),
                          ..._signUpFields(theme),
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
    );
  }

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

  BoxDecoration _panelDecoration(ColorScheme scheme) {
    final dark = scheme.brightness == Brightness.dark;
    return BoxDecoration(
      color: (dark ? scheme.surfaceContainerLow : scheme.surface).withValues(
        alpha: dark ? 0.97 : 0.96,
      ),
      borderRadius: BorderRadius.circular(AppTokens.cardRadius),
      border: Border.all(
        color: scheme.outlineVariant.withValues(alpha: dark ? 1 : 0.8),
      ),
      boxShadow: [
        BoxShadow(
          color: scheme.shadow.withValues(alpha: dark ? 0.46 : 0.12),
          blurRadius: 32,
          offset: const Offset(0, 16),
        ),
      ],
    );
  }

  Widget _panel(ThemeData theme, List<Widget> children) {
    return DecoratedBox(
      decoration: _panelDecoration(theme.colorScheme),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, _compactLogin ? 12 : 16, 16, 14),
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
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          body,
          textAlign: TextAlign.start,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.4,
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
        trailing: widget.onForgotPassword == null ? null : _forgotPassword(),
      ),
    ];
  }

  List<Widget> _signUpFields(ThemeData theme) {
    if (_signupStep == 2) {
      final phone =
          _country.canonicalPhone(_phone.value.international) ??
          _phone.value.international;
      return [
        Text(
          AuthCopy.reviewHint,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 16),
        _reviewSection(
          theme: theme,
          sectionKey: const Key('review-account'),
          editKey: const Key('review-edit-account'),
          title: AuthCopy.reviewAccountSection,
          icon: Icons.person_outline,
          editStep: 0,
          rows: [
            (
              icon: Icons.badge_outlined,
              label: AuthCopy.ownerLabel,
              value: _owner.text,
              ltr: false,
            ),
            (
              icon: Icons.mail_outline,
              label: AuthCopy.emailLabel,
              value: _email.text,
              ltr: true,
            ),
            (
              icon: Icons.phone_outlined,
              label: AuthCopy.phoneLabel,
              value: phone,
              ltr: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _reviewSection(
          theme: theme,
          sectionKey: const Key('review-shop'),
          editKey: const Key('review-edit-shop'),
          title: AuthCopy.reviewShopSection,
          icon: Icons.storefront_outlined,
          editStep: 1,
          rows: [
            (
              icon: Icons.storefront_outlined,
              label: AuthCopy.businessLabel,
              value: _business.text,
              ltr: false,
            ),
            (
              icon: Icons.public_outlined,
              label: AuthCopy.countryLabel,
              value: _country.nameAr,
              ltr: false,
            ),
            (
              icon: Icons.location_on_outlined,
              label: _country.code == 'EG'
                  ? AuthCopy.egyptGovernorateLabel
                  : AuthCopy.cityRegionLabel,
              value: _locationReviewValue(),
              ltr: false,
            ),
          ],
        ),
        const SizedBox(height: 8),
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
        if (_country.code == 'EG')
          _egyptGovernorateField(theme)
        else
          _labeled(
            order: 2,
            label: AuthCopy.cityRegionLabel,
            theme: theme,
            field: TextFormField(
              key: const Key('signup-region'),
              controller: _region,
              focusNode: _governorateFocus,
              enabled: !_locked,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: AuthCopy.cityRegionHint,
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              validator: (_) => _locationError(),
            ),
          ),
        if (widget.shopImageGateway != null) _signupShopImage(theme),
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

  Widget _signupShopImage(ThemeData theme) {
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: _compactLogin ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ShopImageCopy.signupHint,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ShopImageCopy.signupHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: _shopImageBytes == null
                      ? Icon(
                          Icons.storefront_outlined,
                          color: scheme.onSurfaceVariant,
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.memory(
                            _shopImageBytes!,
                            fit: BoxFit.cover,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('signup-shop-image'),
                      onPressed: _locked || _pickingShopImage
                          ? null
                          : _pickShopImage,
                      icon: const Icon(Icons.image_outlined),
                      label: Text(
                        _pickingShopImage
                            ? ShopImageCopy.preparing
                            : _shopImageBytes == null
                            ? ShopImageCopy.pick
                            : ShopImageCopy.change,
                      ),
                    ),
                    if (_shopImageBytes != null)
                      TextButton(
                        key: const Key('signup-shop-image-clear'),
                        onPressed: _locked
                            ? null
                            : () => setState(() {
                                _shopImageBytes = null;
                                _shopImageAlert = null;
                                _useImageForInvoices = false;
                              }),
                        child: const Text(ShopImageCopy.clear),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (_shopImageBytes != null &&
              widget.saveRegistrationInvoiceLogo != null)
            CheckboxListTile(
              key: const Key('signup-invoice-logo'),
              contentPadding: EdgeInsets.zero,
              value: _useImageForInvoices,
              onChanged: _locked
                  ? null
                  : (value) =>
                        setState(() => _useImageForInvoices = value ?? false),
              title: const Text('اختيار الصورة أيضاً كشعار للفواتير'),
              subtitle: const Text(
                'تُحفظ كمسودة. أكمل رفعها وراجع مظهر الفاتورة من المزيد بعد تفعيل المتجر.',
              ),
            ),
          if (_shopImageAlert != null) ...[
            const SizedBox(height: 8),
            Text(
              _shopImageAlert!,
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _egyptGovernorateField(ThemeData theme) {
    final items = _governorates;
    return _labeled(
      order: 2,
      label: AuthCopy.egyptGovernorateLabel,
      theme: theme,
      field: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_governoratesLoading) ...[
            const LinearProgressIndicator(minHeight: 4),
            const SizedBox(height: AppTokens.spaceSm),
            const Text(AuthCopy.governorateLoading),
          ],
          if (_governoratesError != null) ...[
            Text(
              _governoratesError!,
              key: const Key('signup-governorate-error'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            OutlinedButton(
              key: const Key('signup-governorate-retry'),
              onPressed: _locked
                  ? null
                  : () => _ensureGovernorates(retry: true),
              child: const Text(AuthCopy.governorateRetry),
            ),
          ],
          if (items != null)
            KeyedSubtree(
              key: ValueKey(_selectedGovernorate),
              child: DropdownButtonFormField<String>(
                key: const Key('signup-region'),
                focusNode: _governorateFocus,
                initialValue: _selectedGovernorate,
                isExpanded: true,
                hint: const Text(AuthCopy.governorateHint),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                items: [
                  for (final item in items)
                    DropdownMenuItem(
                      value: item.code,
                      child: Text(item.nameAr, maxLines: 2),
                    ),
                ],
                onChanged: _locked
                    ? null
                    : (value) {
                        setState(() => _selectedGovernorate = value);
                      },
                validator: (_) => _locationError(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _reviewSection({
    required ThemeData theme,
    required Key sectionKey,
    required Key editKey,
    required String title,
    required IconData icon,
    required int editStep,
    required List<({IconData icon, String label, String value, bool ltr})> rows,
  }) {
    final scheme = theme.colorScheme;
    return DecoratedBox(
      key: sectionKey,
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppTokens.fieldRadius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: editKey,
                  onPressed: _locked || _unknown
                      ? null
                      : () => _goToSignupStep(editStep),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    foregroundColor: scheme.primary,
                  ),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text(AuthCopy.reviewEdit),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.7),
                ),
              _reviewRow(theme, rows[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _reviewRow(
    ThemeData theme,
    ({IconData icon, String label, String value, bool ltr}) row,
  ) {
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(row.icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  row.value,
                  textDirection: row.ltr ? TextDirection.ltr : null,
                  softWrap: true,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
      TextButton(
        key: const Key('forgot-password'),
        style: TextButton.styleFrom(
          minimumSize: const Size(48, _control),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: _busy ? null : widget.onForgotPassword,
        child: const Text(RecoveryCopy.forgotPassword),
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
    Widget? trailing,
  }) {
    final theme = _authTheme(Theme.of(context));
    return _labeled(
      order: order,
      label: AuthCopy.passwordLabel,
      theme: theme,
      trailing: trailing,
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
    Widget? trailing,
  }) {
    final caption = ExcludeSemantics(child: _label(_authTheme(theme), label));
    return _order(
      order,
      Padding(
        padding: EdgeInsets.only(bottom: _compactLogin ? 8 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (trailing == null) ...[
              caption,
              const SizedBox(height: 6),
            ] else
              Row(
                children: [
                  Expanded(child: caption),
                  trailing,
                ],
              ),
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

/// Brand header with the jewelry photo placed so the rings fill the space
/// between the tagline and the card that follows this widget.
///
/// The photo is decorative and spills past the band on every side; masks fade
/// each edge into [ColorScheme.surface] so no image border is visible.
class _AuthPhotoBand extends StatelessWidget {
  const _AuthPhotoBand({
    required this.child,
    this.compact = false,
    this.enabled = true,
  });

  final Widget child;
  final bool compact;
  final bool enabled;

  static const _asset = 'assets/brand/auth-jewelry.png';
  static const double _aspect = 1536 / 1024;

  /// Vertical span of the rings within the source photo.
  static const double _ringsTop = 0.49;
  static const double _ringsBottom = 0.8;

  /// How far the following card overlaps the bottom of the rings.
  static const double _overlap = 18;
  static const double _clearance = 6;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final screen = MediaQuery.sizeOf(context).width;
    final imageWidth = compact
        ? min(screen * 1.1, 720.0)
        : min(screen * 1.4, 1100.0);
    final imageHeight = imageWidth / _aspect;
    final gap =
        (_ringsBottom - _ringsTop) * imageHeight - _overlap + _clearance;
    final photoWidth = min(screen, imageWidth);
    final fadeSides = screen > imageWidth;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: (constraints.maxWidth - photoWidth) / 2,
              width: photoWidth,
              height: imageHeight,
              bottom: -(_overlap + (1 - _ringsBottom) * imageHeight),
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: _fade(
                    vertical: true,
                    child: _fade(
                      vertical: false,
                      enabled: fadeSides,
                      child: ClipRect(
                        child: OverflowBox(
                          maxWidth: imageWidth,
                          maxHeight: imageHeight,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.asset(
                                _asset,
                                width: imageWidth,
                                height: imageHeight,
                                fit: BoxFit.cover,
                                filterQuality: FilterQuality.medium,
                              ),
                              if (dark)
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        scheme.surface.withValues(alpha: 0.7),
                                        scheme.surface.withValues(alpha: 0.5),
                                        scheme.surface.withValues(alpha: 0.12),
                                        scheme.surface.withValues(alpha: 0.4),
                                      ],
                                      stops: const [0, 0.42, 0.62, 1],
                                    ),
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
            Padding(
              padding: EdgeInsets.only(bottom: gap),
              child: child,
            ),
          ],
        );
      },
    );
  }

  Widget _fade({
    required bool vertical,
    required Widget child,
    bool enabled = true,
  }) {
    if (!enabled) return child;
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => LinearGradient(
        begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
        end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
        // Alpha mask only: opaque keeps the photo, transparent shows the page.
        colors: const [
          Color(0x00FFFFFF),
          Color(0x40FFFFFF),
          Color(0xB3FFFFFF),
          Color(0xFFFFFFFF),
          Color(0xFFFFFFFF),
          Color(0xB3FFFFFF),
          Color(0x40FFFFFF),
          Color(0x00FFFFFF),
        ],
        stops: vertical
            ? const [0, 0.08, 0.16, 0.26, 0.68, 0.8, 0.9, 1]
            : const [0, 0.1, 0.22, 0.34, 0.66, 0.78, 0.9, 1],
      ).createShader(bounds),
      child: child,
    );
  }
}
