import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/shop_profile_gateway.dart';

class SupabaseShopProfileGateway implements ShopProfileGateway {
  const SupabaseShopProfileGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<ShopProfile> getProfile({required String userId}) async {
    _require(userId);
    try {
      final response = await _client
          .rpc('get_shop_profile_v1')
          .timeout(const Duration(seconds: 15));
      _require(userId);
      return _parse(response);
    } on ShopProfileException {
      rethrow;
    } on PostgrestException catch (error) {
      throw ShopProfileException(_map(error));
    } catch (_) {
      throw const ShopProfileException(ShopProfileFailure.unavailable);
    }
  }

  @override
  Future<ShopProfile> updateProfile({
    required String userId,
    required String key,
    required String name,
    required String ownerDisplayName,
    required String phone,
  }) async {
    _require(userId);
    try {
      final response = await _client
          .rpc(
            'update_shop_profile_v1',
            params: {
              'p_key': key,
              'p_name': name,
              'p_owner_display_name': ownerDisplayName,
              'p_phone': phone,
            },
          )
          .timeout(const Duration(seconds: 20));
      _require(userId);
      return _parse(response);
    } on ShopProfileException {
      rethrow;
    } on PostgrestException catch (error) {
      throw ShopProfileException(_map(error));
    } catch (_) {
      throw const ShopProfileException(ShopProfileFailure.unavailable);
    }
  }

  void _require(String userId) {
    final session = _client.auth.currentSession;
    if (session == null || session.user.id != userId) {
      throw const ShopProfileException(ShopProfileFailure.unauthorized);
    }
  }

  static ShopProfile _parse(Object? value) {
    if (value is! Map) {
      throw const ShopProfileException(ShopProfileFailure.invalidResponse);
    }
    final map = Map<String, dynamic>.from(value);
    final shopId = map['shop_id'];
    final name = map['name'];
    final owner = map['owner_display_name'];
    final phone = map['phone'];
    if (shopId is! String ||
        name is! String ||
        owner is! String ||
        phone is! String) {
      throw const ShopProfileException(ShopProfileFailure.invalidResponse);
    }
    return ShopProfile(
      shopId: shopId,
      name: name,
      ownerDisplayName: owner,
      phone: phone,
      governorateCode: map['governorate_code'] as String?,
    );
  }

  static ShopProfileFailure _map(PostgrestException error) {
    final message = error.message.toLowerCase();
    if (error.code == '42501' || message.contains('forbidden')) {
      return ShopProfileFailure.unauthorized;
    }
    if (message.contains('identifier_taken')) {
      return ShopProfileFailure.identifierTaken;
    }
    if (message.contains('invalid_input') ||
        message.contains('payload_mismatch')) {
      return ShopProfileFailure.invalidInput;
    }
    if (message.contains('shop_not_active')) {
      return ShopProfileFailure.rejected;
    }
    return ShopProfileFailure.unavailable;
  }
}
