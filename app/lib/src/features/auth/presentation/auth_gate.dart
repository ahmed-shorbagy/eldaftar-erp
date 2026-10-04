import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/supabase_startup.dart';
import '../../../shell/home_shell.dart';
import '../../../shell/shell_copy.dart';
import '../../../theme/brand_mark.dart';
import '../../daily_ledger/application/opening_gateway.dart';
import '../../daily_ledger/application/pending_opening_store.dart';
import '../../onboarding/application/onboarding_store.dart';
import '../../shop_accounts/domain/shop_account_gateway.dart';
import '../../shop_accounts/presentation/shop_accounts_gate.dart';
import '../domain/auth_gateway.dart';
import '../domain/password_recovery.dart';
import 'auth_copy.dart';
import 'auth_screen.dart';
import 'password_recovery_screen.dart';
import 'recovery_copy.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.supabaseStatus,
    required this.authGateway,
    required this.shopAccountGateway,
    required this.onToggleTheme,
    this.openingGateway,
    this.pendingOpeningStore,
    this.onboardingStore,
    this.currentUserId,
    this.recoveryGateway,
  });

  final SupabaseStartupStatus supabaseStatus;
  final AuthGateway? authGateway;
  final PasswordRecoveryGateway? recoveryGateway;
  final ShopAccountGateway? shopAccountGateway;
  final Future<void> Function(Brightness) onToggleTheme;
  final OpeningGateway? openingGateway;
  final PendingOpeningStore? pendingOpeningStore;
  final OnboardingStore? onboardingStore;
  final String? Function()? currentUserId;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthStatus>? _subscription;
  StreamSubscription<bool>? _recoverySub;
  AuthStatus _status = AuthStatus.signedOut;
  bool _hold = false;
  bool _requestingReset = false;
  bool _resetSuccess = false;

  /// Stays set until the reset screen reports success or abandon.
  ///
  /// The gateway clears [PasswordRecoveryGateway.recoveryPending] before that
  /// callback. Dropping the screen on the event would dispose it first and a
  /// cached signed-in status could open shop data.
  bool _awaitingRecoveryEnd = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant AuthGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authGateway != widget.authGateway ||
        oldWidget.recoveryGateway != widget.recoveryGateway) {
      _subscription?.cancel();
      _recoverySub?.cancel();
      _hold = false;
      _listen();
    }
  }

  void _listen() {
    final gateway = widget.authGateway;
    _status = _hold
        ? AuthStatus.signedOut
        : gateway?.status ?? AuthStatus.signedOut;
    _awaitingRecoveryEnd = widget.recoveryGateway?.recoveryPending ?? false;
    _subscription = gateway?.changes.listen((status) {
      if (!mounted || _hold) return;
      setState(() => _status = status);
    });
    _recoverySub = widget.recoveryGateway?.recoveryChanges.listen((pending) {
      if (!mounted || _hold) return;
      setState(() {
        if (pending) _awaitingRecoveryEnd = true;
      });
    });
  }

  void _setHold(bool hold) {
    if (!mounted) return;
    setState(() {
      _hold = hold;
      if (hold) _status = AuthStatus.signedOut;
    });
  }

  void _syncStatus() {
    if (!mounted || _hold) return;
    setState(() {
      _status = widget.authGateway?.status ?? AuthStatus.signedOut;
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _recoverySub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.supabaseStatus != SupabaseStartupStatus.ready) {
      return HomeShell(
        supabaseStatus: widget.supabaseStatus,
        onToggleTheme: widget.onToggleTheme,
      );
    }
    final gateway = widget.authGateway;
    final shops = widget.shopAccountGateway;
    if (gateway == null || shops == null) {
      return _AuthUnavailable(onToggleTheme: widget.onToggleTheme);
    }
    final recovery = widget.recoveryGateway;
    if (!_hold &&
        recovery != null &&
        (_awaitingRecoveryEnd || recovery.recoveryPending)) {
      return PasswordResetScreen(
        gateway: recovery,
        onToggleTheme: widget.onToggleTheme,
        onFinished: () {
          if (!mounted) return;
          setState(() {
            _awaitingRecoveryEnd = false;
            _resetSuccess = true;
            _requestingReset = false;
            _status = AuthStatus.signedOut;
          });
        },
        onAbandoned: () {
          if (!mounted) return;
          setState(() {
            _awaitingRecoveryEnd = false;
            _requestingReset = false;
            _status = AuthStatus.signedOut;
          });
        },
      );
    }
    if (!_hold && _requestingReset && recovery != null) {
      return RecoveryRequestScreen(
        gateway: recovery,
        onToggleTheme: widget.onToggleTheme,
        onBack: () {
          if (!mounted) return;
          setState(() => _requestingReset = false);
        },
      );
    }
    if (!_hold && _status == AuthStatus.signedIn) {
      final userId = widget.currentUserId?.call();
      return ShopAccountsGate(
        key: ValueKey(userId),
        gateway: shops,
        onToggleTheme: widget.onToggleTheme,
        openingGateway: widget.openingGateway,
        pendingOpeningStore: widget.pendingOpeningStore,
        onboardingStore: widget.onboardingStore,
        currentUserId: widget.currentUserId,
        onSignOut: () async {
          await gateway.signOut();
          if (mounted) setState(() => _status = AuthStatus.signedOut);
        },
      );
    }
    final failure = recovery?.linkFailure;
    final notice = _resetSuccess
        ? RecoveryCopy.resetSuccess
        : failure == null
        ? null
        : RecoveryCopy.messageFor(failure);
    return AuthScreen(
      gateway: gateway,
      onToggleTheme: widget.onToggleTheme,
      onHold: _setHold,
      onSessionSettled: _syncStatus,
      onboardingStore: widget.onboardingStore,
      onForgotPassword: recovery == null
          ? null
          : () {
              recovery.clearLinkFailure();
              setState(() {
                _requestingReset = true;
                _resetSuccess = false;
              });
            },
      recoveryNotice: notice,
      recoveryNoticeIsError: !_resetSuccess && failure != null,
    );
  }
}

class _AuthUnavailable extends StatelessWidget {
  const _AuthUnavailable({required this.onToggleTheme});

  final Future<void> Function(Brightness) onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const BrandLockup(title: ShellCopy.appTitle),
        actions: [
          IconButton(
            key: const Key('auth-theme-toggle'),
            tooltip: theme.brightness == Brightness.dark
                ? ShellCopy.toggleToLight
                : ShellCopy.toggleToDark,
            onPressed: () => onToggleTheme(theme.brightness),
            icon: Icon(
              theme.brightness == Brightness.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
        ],
      ),
      body: const SafeArea(child: Center(child: Text(AuthCopy.unavailable))),
    );
  }
}
