enum AuthStatus { signedOut, unverifiedEmail, signedIn }

abstract class AuthGateway {
  AuthStatus get status;
  Stream<AuthStatus> get changes;
  Future<void> signIn(String email, String password);
  Future<void> signOut();
}
