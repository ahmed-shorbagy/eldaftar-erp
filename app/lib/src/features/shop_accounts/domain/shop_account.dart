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

enum ShopAccountFailure { unauthorized, unavailable, invalidResponse, rejected }
