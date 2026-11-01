enum ShopEntitlement { pending, active, expired }

enum ShopMemberRole { owner, partner, employee }

enum ShopPermission { sale, purchase, inventory, expense, reports, invoiceSend }

const kAllShopPermissions = {
  ShopPermission.sale,
  ShopPermission.purchase,
  ShopPermission.inventory,
  ShopPermission.expense,
  ShopPermission.reports,
  ShopPermission.invoiceSend,
};

ShopPermission? shopPermissionFromApi(String value) => switch (value) {
  'sale' => ShopPermission.sale,
  'purchase' => ShopPermission.purchase,
  'inventory' => ShopPermission.inventory,
  'expense' => ShopPermission.expense,
  'reports' => ShopPermission.reports,
  'invoice_send' => ShopPermission.invoiceSend,
  _ => null,
};

String shopPermissionToApi(ShopPermission value) => switch (value) {
  ShopPermission.sale => 'sale',
  ShopPermission.purchase => 'purchase',
  ShopPermission.inventory => 'inventory',
  ShopPermission.expense => 'expense',
  ShopPermission.reports => 'reports',
  ShopPermission.invoiceSend => 'invoice_send',
};

enum SubscriptionNoticeKind { renewalDue, expired, retentionEnding }

String subscriptionNoticeKindToApi(SubscriptionNoticeKind kind) =>
    switch (kind) {
      SubscriptionNoticeKind.renewalDue => 'renewal_due',
      SubscriptionNoticeKind.expired => 'expired',
      SubscriptionNoticeKind.retentionEnding => 'retention_ending',
    };

class SubscriptionNotice {
  const SubscriptionNotice({
    required this.shopId,
    required this.kind,
    required this.expiresAt,
    this.retentionEndsOn,
  });

  final String shopId;
  final SubscriptionNoticeKind kind;

  /// Entitlement expiry that keys the dismissal. This is not the retention end.
  final DateTime expiresAt;

  /// Shop-local calendar date `YYYY-MM-DD` when [kind] is [SubscriptionNoticeKind.retentionEnding].
  final String? retentionEndsOn;
}

final _subscriptionNoticeShopId = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final _retentionEndsOn = RegExp(r'^\d{4}-\d{2}-\d{2}$');

SubscriptionNotice subscriptionNoticeFromApi(Map<String, dynamic> value) {
  final id = value['shop_id'];
  final kind = value['kind'];
  final expires = value['entitlement_expires_at'];
  final expiresAt = expires is String ? DateTime.tryParse(expires) : null;
  if (id is! String ||
      !_subscriptionNoticeShopId.hasMatch(id) ||
      expiresAt == null) {
    throw const SubscriptionNoticeException(
      SubscriptionNoticeFailure.invalidResponse,
    );
  }
  final parsedKind = switch (kind) {
    'renewal_due' => SubscriptionNoticeKind.renewalDue,
    'expired' => SubscriptionNoticeKind.expired,
    'retention_ending' => SubscriptionNoticeKind.retentionEnding,
    _ => null,
  };
  if (parsedKind == null) {
    throw const SubscriptionNoticeException(
      SubscriptionNoticeFailure.invalidResponse,
    );
  }
  String? retentionEndsOn;
  if (parsedKind == SubscriptionNoticeKind.retentionEnding) {
    final endsOn = value['retention_ends_on'];
    if (endsOn is! String || !_retentionEndsOn.hasMatch(endsOn)) {
      throw const SubscriptionNoticeException(
        SubscriptionNoticeFailure.invalidResponse,
      );
    }
    retentionEndsOn = endsOn;
  }
  return SubscriptionNotice(
    shopId: id,
    kind: parsedKind,
    expiresAt: expiresAt.toUtc(),
    retentionEndsOn: retentionEndsOn,
  );
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
    this.grants = const {},
  });

  final String id;
  final String name;
  final String role;
  final ShopEntitlement entitlement;
  final DateTime? expiresAt;

  /// Present when the owner saved a shop image for the ledger header.
  final String? imageSha256;

  /// Server grants. Owners receive every grant implicitly from the API.
  final Set<ShopPermission> grants;

  ShopMemberRole? get memberRole => switch (role) {
    'owner' => ShopMemberRole.owner,
    'partner' => ShopMemberRole.partner,
    'employee' => ShopMemberRole.employee,
    _ => null,
  };

  bool get isOwner => memberRole == ShopMemberRole.owner;
  bool get isEmployee => memberRole == ShopMemberRole.employee;

  bool hasPermission(ShopPermission permission) =>
      isOwner || grants.contains(permission);

  ShopAccount copyWith({
    String? name,
    ShopEntitlement? entitlement,
    DateTime? expiresAt,
    String? imageSha256,
    Set<ShopPermission>? grants,
    bool clearImage = false,
  }) => ShopAccount(
    id: id,
    name: name ?? this.name,
    role: role,
    entitlement: entitlement ?? this.entitlement,
    expiresAt: expiresAt ?? this.expiresAt,
    imageSha256: clearImage ? null : (imageSha256 ?? this.imageSha256),
    grants: grants ?? this.grants,
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
