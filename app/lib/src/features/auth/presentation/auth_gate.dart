import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/supabase_startup.dart';
import '../../../shell/home_shell.dart';
import '../../../shell/shell_copy.dart';
import '../../shop_accounts/domain/shop_account_gateway.dart';
import '../../shop_accounts/presentation/shop_accounts_gate.dart';
import '../domain/auth_gateway.dart';
import 'auth_copy.dart';
import 'auth_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.supabaseStatus,
    required this.authGateway,
    required this.shopAccountGateway,
    required this.onToggleTheme,
  });

  final SupabaseStartupStatus supabaseStatus;
  final AuthGateway? authGateway;
  final ShopAccountGateway? shopAccountGateway;
  final Future<void> Function(Brightness) onToggleTheme;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthStatus>? _subscription;
  AuthStatus _status = AuthStatus.signedOut;
  bool _hold = false;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant AuthGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authGateway != widget.authGateway) {
      _subscription?.cancel();
      _hold = false;
      _listen();
    }
  }

  void _listen() {
    final gateway = widget.authGateway;
    _status = _hold
        ? AuthStatus.signedOut
        : gateway?.status ?? AuthStatus.signedOut;
    _subscription = gateway?.changes.listen((status) {
      if (!mounted || _hold) return;
      setState(() => _status = status);
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
    if (!_hold && _status == AuthStatus.signedIn) {
      return ShopAccountsGate(
        gateway: shops,
        onToggleTheme: widget.onToggleTheme,
        onSignOut: () async {
          await gateway.signOut();
          if (mounted) setState(() => _status = AuthStatus.signedOut);
        },
      );
    }
    return AuthScreen(
      gateway: gateway,
      onToggleTheme: widget.onToggleTheme,
      onHold: _setHold,
      onSessionSettled: _syncStatus,
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
        title: const Text(ShellCopy.appTitle),
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
