class ShopProfile {
  const ShopProfile({
    required this.shopId,
    required this.name,
    required this.ownerDisplayName,
    required this.phone,
    this.governorateCode,
  });

  final String shopId;
  final String name;
  final String ownerDisplayName;
  final String phone;
  final String? governorateCode;
}

enum ShopProfileFailure {
  unauthorized,
  unavailable,
  invalidInput,
  identifierTaken,
  rejected,
  invalidResponse,
}

class ShopProfileException implements Exception {
  const ShopProfileException(this.failure);
  final ShopProfileFailure failure;
}

abstract class ShopProfileGateway {
  Future<ShopProfile> getProfile({required String userId});
  Future<ShopProfile> updateProfile({
    required String userId,
    required String key,
    required String name,
    required String ownerDisplayName,
    required String phone,
  });
}
