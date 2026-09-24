enum ShopEntitlement { pending, active, expired }

class ShopAccount {
  const ShopAccount({
    required this.id,
    required this.name,
    required this.role,
    required this.entitlement,
    this.expiresAt,
  });

  final String id;
  final String name;
  final String role;
  final ShopEntitlement entitlement;
  final DateTime? expiresAt;
}

class ShopSetupRequest {
  const ShopSetupRequest({
    required this.name,
    required this.ownerDisplayName,
    required this.timeZone,
    required this.requestKey,
    this.phone,
  });

  final String name;
  final String ownerDisplayName;
  final String? phone;
  final String timeZone;
  final String requestKey;
}

enum ShopAccountFailure { unauthorized, unavailable, invalidResponse, rejected }
