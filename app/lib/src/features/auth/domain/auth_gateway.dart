import 'account_identifiers.dart';
import 'egyptian_governorates.dart';
import 'owner_registration.dart';

export 'account_identifiers.dart';
export 'egyptian_governorates.dart';
export 'owner_registration.dart';

enum AuthStatus { signedOut, signedIn }

enum SignInFailure { invalidInput, invalidCredentials, unavailable }

class SignInException implements Exception {
  const SignInException(this.failure);

  final SignInFailure failure;

  @override
  String toString() => 'SignInException($failure)';
}

abstract class AuthGateway {
  AuthStatus get status;
  Stream<AuthStatus> get changes;
  Future<void> signIn(SignInRequest request);
  Future<OwnerRegistrationResult> registerOwner(OwnerRegistration registration);
  Future<List<Governorate>> loadGovernorates();
  Future<void> signOut();
}
