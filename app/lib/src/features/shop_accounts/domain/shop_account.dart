enum ShopEntitlement { pending, active, expired }

enum SubscriptionNoticeKind { renewalDue, expired }

class SubscriptionNotice {
  const SubscriptionNotice({
    required this.shopId,
    required this.kind,
    required this.expiresAt,
  });

  final String shopId;
  final SubscriptionNoticeKind kind;
  final DateTime expiresAt;
}

enum SubscriptionNoticeFailure {
  unauthorized,
  unavailable,
  invalidResponse,
  stale,
  rejected,
}

class SubscriptionNoticeException implements Exception {
  const SubscriptionNoticeException(this.failure);

  final SubscriptionNoticeFailure failure;

  @override
  String toString() => 'SubscriptionNoticeException($failure)';
}

class ShopAccount {
  const ShopAccount({
    required this.id,
    required this.name,
    required this.role,
    required this.entitlement,
    this.expiresAt,
    this.imageSha256,
  });

  final String id;
  final String name;
  final String role;
  final ShopEntitlement entitlement;
  final DateTime? expiresAt;

  /// Present when the owner saved a shop image for the ledger header.
  final String? imageSha256;

  ShopAccount copyWith({
    String? name,
    ShopEntitlement? entitlement,
    DateTime? expiresAt,
    String? imageSha256,
    bool clearImage = false,
  }) => ShopAccount(
    id: id,
    name: name ?? this.name,
    role: role,
    entitlement: entitlement ?? this.entitlement,
    expiresAt: expiresAt ?? this.expiresAt,
    imageSha256: clearImage ? null : (imageSha256 ?? this.imageSha256),
  );

  bool get needsActivation =>
      entitlement == ShopEntitlement.pending ||
      entitlement == ShopEntitlement.expired;
}

enum ShopAccountFailure { unauthorized, unavailable, invalidResponse, rejected }

enum SubscriptionActivationFailure {
  invalidInput,
  invalidCode,
  expiredCode,
  reusedCode,
  foreignOwner,
  rateLimited,
  requestKeyReused,
  unauthorized,
  unavailable,
  unknownOutcome,
}

class SubscriptionActivationException implements Exception {
  const SubscriptionActivationException(this.failure);

  final SubscriptionActivationFailure failure;

  @override
  String toString() => 'SubscriptionActivationException($failure)';
}

class SubscriptionActivationResult {
  const SubscriptionActivationResult({
    required this.shopId,
    required this.startsAt,
    required this.expiresAt,
    required this.replayed,
  });

  final String shopId;
  final DateTime startsAt;
  final DateTime expiresAt;
  final bool replayed;
}
