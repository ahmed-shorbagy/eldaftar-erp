import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shop_accounts/domain/shop_account.dart';
import '../application/shop_staff_gateway.dart';

class SupabaseShopStaffGateway implements ShopStaffGateway {
  const SupabaseShopStaffGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<ShopStaffDirectory> listStaff({
    required String userId,
    required String shopId,
  }) async {
    _require(userId);
    try {
      final response = await _client
          .rpc('list_shop_staff_v1')
          .timeout(const Duration(seconds: 15));
      _require(userId);
      if (response is! Map) {
        throw const ShopStaffException(ShopStaffFailure.invalidResponse);
      }
      final map = Map<String, dynamic>.from(response);
      if (map['shop_id'] != shopId || map['members'] is! List) {
        throw const ShopStaffException(ShopStaffFailure.invalidResponse);
      }
      final members = <ShopStaffMember>[];
      for (final row in map['members'] as List) {
        if (row is! Map) {
          throw const ShopStaffException(ShopStaffFailure.invalidResponse);
        }
        final item = Map<String, dynamic>.from(row);
        final grants = <ShopPermission>{};
        final raw = item['grants'];
        if (raw is List) {
          for (final g in raw) {
            if (g is! String) {
              throw const ShopStaffException(ShopStaffFailure.invalidResponse);
            }
            final p = shopPermissionFromApi(g);
            if (p == null) {
              throw const ShopStaffException(ShopStaffFailure.invalidResponse);
            }
            grants.add(p);
          }
        }
        final id = item['user_id'];
        final role = item['role'];
        final name = item['display_name'];
        if (id is! String ||
            role is! String ||
            name is! String ||
            !const ['partner', 'employee'].contains(role)) {
          throw const ShopStaffException(ShopStaffFailure.invalidResponse);
        }
        members.add(
          ShopStaffMember(
            userId: id,
            role: role,
            displayName: name,
            phone: item['phone'] as String?,
            grants: grants,
          ),
        );
      }
      return ShopStaffDirectory(shopId: shopId, members: members);
    } on ShopStaffException {
      rethrow;
    } on PostgrestException catch (error) {
      throw ShopStaffException(_map(error));
    } catch (_) {
      throw const ShopStaffException(ShopStaffFailure.unavailable);
    }
  }

  @override
  Future<String> createStaff({
    required String userId,
    required String key,
    required String name,
    required String phone,
    required String password,
    required String role,
    required Set<ShopPermission> grants,
  }) async {
    _require(userId);
    try {
      final digits = phone.replaceFirst(RegExp(r'^\+'), '');
      final response = await _client.functions
          .invoke(
            'shop-staff-create',
            body: {
              'idempotency_key': key,
              'name': name,
              'phone': digits,
              'password': password,
              'role': role,
              'grants': grants.map(shopPermissionToApi).toList()..sort(),
            },
          )
          .timeout(const Duration(seconds: 30));
      _require(userId);
      final data = response.data;
      if (response.status != 200 || data is! Map) {
        final code = data is Map ? data['code']?.toString() : null;
        throw ShopStaffException(_code(code));
      }
      final id = data['user_id'];
      if (id is! String) {
        throw const ShopStaffException(ShopStaffFailure.invalidResponse);
      }
      return id;
    } on ShopStaffException {
      rethrow;
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map ? details['code']?.toString() : null;
      throw ShopStaffException(_code(code));
    } catch (_) {
      throw const ShopStaffException(ShopStaffFailure.unavailable);
    }
  }

  @override
  Future<void> setGrants({
    required String userId,
    required String key,
    required String memberUserId,
    required Set<ShopPermission> grants,
  }) async {
    _require(userId);
    try {
      await _client
          .rpc(
            'set_shop_staff_grants_v1',
            params: {
              'p_key': key,
              'p_user_id': memberUserId,
              'p_grants': grants.map(shopPermissionToApi).toList()..sort(),
            },
          )
          .timeout(const Duration(seconds: 15));
      _require(userId);
    } on ShopStaffException {
      rethrow;
    } on PostgrestException catch (error) {
      throw ShopStaffException(_map(error));
    } catch (_) {
      throw const ShopStaffException(ShopStaffFailure.unavailable);
    }
  }

  @override
  Future<void> revokeStaff({
    required String userId,
    required String key,
    required String memberUserId,
  }) async {
    _require(userId);
    try {
      await _client
          .rpc(
            'revoke_shop_staff_v1',
            params: {'p_key': key, 'p_user_id': memberUserId},
          )
          .timeout(const Duration(seconds: 15));
      _require(userId);
    } on ShopStaffException {
      rethrow;
    } on PostgrestException catch (error) {
      throw ShopStaffException(_map(error));
    } catch (_) {
      throw const ShopStaffException(ShopStaffFailure.unavailable);
    }
  }

  void _require(String userId) {
    final session = _client.auth.currentSession;
    if (session == null || session.user.id != userId) {
      throw const ShopStaffException(ShopStaffFailure.unauthorized);
    }
  }

  static ShopStaffFailure _map(PostgrestException error) {
    final message = error.message.toLowerCase();
    if (error.code == '42501' || message.contains('forbidden')) {
      return ShopStaffFailure.unauthorized;
    }
    return _code(
      message.contains('identifier_taken')
          ? 'identifier_taken'
          : message.contains('staff_limit')
          ? 'staff_limit'
          : message.contains('invalid_input') ||
                message.contains('payload_mismatch')
          ? 'invalid_input'
          : message.contains('shop_not_active') ||
                message.contains('target_staff')
          ? 'rejected'
          : null,
    );
  }

  static ShopStaffFailure _code(String? code) => switch (code) {
    'identifier_taken' => ShopStaffFailure.identifierTaken,
    'staff_limit' => ShopStaffFailure.staffLimit,
    'invalid_input' || 'payload_mismatch' => ShopStaffFailure.invalidInput,
    'forbidden' || 'unauthenticated' => ShopStaffFailure.unauthorized,
    'shop_not_active' ||
    'target_staff_unavailable' ||
    'rejected' => ShopStaffFailure.rejected,
    _ => ShopStaffFailure.unavailable,
  };
}
