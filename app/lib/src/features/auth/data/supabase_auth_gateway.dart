import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_gateway.dart';

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._client);

  final SupabaseClient _client;

  @override
  AuthStatus get status {
    final session = _client.auth.currentSession;
    if (session == null || session.isExpired) return AuthStatus.signedOut;
    if (session.user.emailConfirmedAt == null) {
      return AuthStatus.unverifiedEmail;
    }
    return AuthStatus.signedIn;
  }

  @override
  Stream<AuthStatus> get changes =>
      _client.auth.onAuthStateChange.map((_) => status);

  @override
  Future<void> signIn(String email, String password) async {
    await _client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
    if (status == AuthStatus.unverifiedEmail) {
      await _client.auth.signOut();
      throw const AuthException('email_not_verified');
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}
