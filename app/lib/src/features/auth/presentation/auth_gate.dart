import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/supabase_startup.dart';
import '../../../shell/home_shell.dart';
import '../../auth/domain/auth_gateway.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.supabaseStatus,
    required this.authGateway,
    required this.onToggleTheme,
  });

  final SupabaseStartupStatus supabaseStatus;
  final AuthGateway? authGateway;
  final Future<void> Function(Brightness) onToggleTheme;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  StreamSubscription<AuthStatus>? _subscription;
  AuthStatus _status = AuthStatus.signedOut;

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
      _listen();
    }
  }

  void _listen() {
    _status = widget.authGateway?.status ?? AuthStatus.signedOut;
    _subscription = widget.authGateway?.changes.listen((status) {
      if (mounted) setState(() => _status = status);
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
    if (_status == AuthStatus.signedIn && widget.authGateway != null) {
      return HomeShell(
        supabaseStatus: widget.supabaseStatus,
        onToggleTheme: widget.onToggleTheme,
        onSignOut: () async {
          await widget.authGateway!.signOut();
          if (mounted) setState(() => _status = AuthStatus.signedOut);
        },
      );
    }
    return SignInScreen(
      unavailable: widget.authGateway == null,
      unverified: _status == AuthStatus.unverifiedEmail,
      onSubmit: (email, password) async {
        await widget.authGateway!.signIn(email, password);
        if (mounted) setState(() => _status = widget.authGateway!.status);
      },
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.unavailable,
    required this.unverified,
    required this.onSubmit,
  });

  final bool unavailable;
  final bool unverified;
  final Future<void> Function(String, String) onSubmit;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_email.text, _password.text);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'تعذر تسجيل الدخول. تحقق من البيانات وتأكيد البريد الإلكتروني ثم حاول مجددًا.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('الدفتر')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(24),
                children: [
                  Text('تسجيل الدخول', style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  const Text(
                    'ادخل بريدك الإلكتروني المؤكد للوصول إلى حساب المتجر.',
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: const Key('sign-in-email'),
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                    ),
                    validator: (value) => value == null || !value.contains('@')
                        ? 'أدخل بريدًا إلكترونيًا صحيحًا'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('sign-in-password'),
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'كلمة المرور'),
                    validator: (value) => value == null || value.isEmpty
                        ? 'أدخل كلمة المرور'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  if (widget.unverified)
                    Text(
                      'أكد بريدك الإلكتروني قبل المتابعة.',
                      style: TextStyle(color: scheme.error),
                    ),
                  if (widget.unavailable)
                    Text(
                      'خدمة تسجيل الدخول غير متاحة الآن.',
                      style: TextStyle(color: scheme.error),
                    ),
                  if (_error != null)
                    Text(
                      _error!,
                      key: const Key('sign-in-error'),
                      style: TextStyle(color: scheme.error),
                    ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('sign-in-submit'),
                    onPressed: _busy || widget.unavailable ? null : _submit,
                    child: Text(_busy ? 'جارٍ تسجيل الدخول…' : 'دخول'),
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
