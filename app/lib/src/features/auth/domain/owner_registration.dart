import 'dart:math';

import 'account_identifiers.dart';
import 'egyptian_governorates.dart';

enum RegistrationFailure {
  invalidInput,
  identifierTaken,
  requestKeyReused,
  registrationIdentityMismatch,
  unavailable,
  invalidCredentials,
  unknownOutcome,
}

class RegistrationException implements Exception {
  const RegistrationException(this.failure);

  final RegistrationFailure failure;

  @override
  String toString() => 'RegistrationException($failure)';
}

class OwnerRegistrationResult {
  const OwnerRegistrationResult({required this.userId, required this.shopId});

  final String userId;
  final String shopId;
}

abstract final class IdempotencyKey {
  static final _v4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );

  static bool isV4(String value) => _v4.hasMatch(value);

  static String generate(Random random) {
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((part) => part.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}

/// Validated owner signup. [password] is held only so the adapter can send it
/// to Auth; it is not a stored credential and is excluded from [toString].
class OwnerRegistration {
  const OwnerRegistration._({
    required this.idempotencyKey,
    required this.ownerName,
    required this.businessName,
    required this.email,
    required this.phone,
    required this.governorateCode,
    required this.password,
  });

  final String idempotencyKey;
  final String ownerName;
  final String businessName;
  final String email;
  final String phone;
  final String governorateCode;
  final String password;

  static OwnerRegistration? tryCreate({
    required String idempotencyKey,
    required String ownerName,
    required String businessName,
    required String email,
    required String phone,
    required String governorateCode,
    required String password,
  }) {
    final canonicalOwner = AccountName.tryCanonical(ownerName);
    final canonicalBusiness = AccountName.tryCanonical(businessName);
    final canonicalEmail = AccountEmail.tryCanonical(email);
    final canonicalPhone = EgyptianPhone.tryCanonical(phone);
    if (!IdempotencyKey.isV4(idempotencyKey) ||
        canonicalOwner == null ||
        canonicalBusiness == null ||
        canonicalEmail == null ||
        canonicalPhone == null ||
        !EgyptianGovernorates.isValid(governorateCode) ||
        !AccountPassword.isAcceptable(password)) {
      return null;
    }
    return OwnerRegistration._(
      idempotencyKey: idempotencyKey,
      ownerName: canonicalOwner,
      businessName: canonicalBusiness,
      email: canonicalEmail,
      phone: canonicalPhone,
      governorateCode: governorateCode,
      password: password,
    );
  }

  bool samePayloadAs(OwnerRegistration other) {
    return ownerName == other.ownerName &&
        businessName == other.businessName &&
        email == other.email &&
        phone == other.phone &&
        governorateCode == other.governorateCode &&
        password == other.password;
  }

  @override
  String toString() =>
      'OwnerRegistration(idempotencyKey: $idempotencyKey, '
      'governorateCode: $governorateCode)';
}
