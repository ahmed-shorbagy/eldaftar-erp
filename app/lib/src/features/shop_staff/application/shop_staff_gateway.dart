import '../../shop_accounts/domain/shop_account.dart';

class ShopStaffMember {
  const ShopStaffMember({
    required this.userId,
    required this.role,
    required this.displayName,
    required this.grants,
    this.phone,
  });

  final String userId;
  final String role;
  final String displayName;
  final String? phone;
  final Set<ShopPermission> grants;
}

class ShopStaffDirectory {
  const ShopStaffDirectory({required this.shopId, required this.members});
  final String shopId;
  final List<ShopStaffMember> members;
}

enum ShopStaffFailure {
  unauthorized,
  unavailable,
  invalidInput,
  identifierTaken,
  staffLimit,
  rejected,
  invalidResponse,
}

class ShopStaffException implements Exception {
  const ShopStaffException(this.failure);
  final ShopStaffFailure failure;
}

abstract class ShopStaffGateway {
  Future<ShopStaffDirectory> listStaff({
    required String userId,
    required String shopId,
  });

  Future<String> createStaff({
    required String userId,
    required String key,
    required String name,
    required String phone,
    required String password,
    required String role,
    required Set<ShopPermission> grants,
  });

  Future<void> setGrants({
    required String userId,
    required String key,
    required String memberUserId,
    required Set<ShopPermission> grants,
  });

  Future<void> revokeStaff({
    required String userId,
    required String key,
    required String memberUserId,
  });
}
