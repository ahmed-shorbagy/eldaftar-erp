import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/shop_account.dart';
import '../domain/shop_account_gateway.dart';

class SupabaseShopAccountGateway implements ShopAccountGateway {
  const SupabaseShopAccountGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<List<ShopAccount>> listMyShopAccounts() async {
    _requireSession();
    try {
      final response = await _client.rpc('list_my_shop_accounts');
      _requireSession();
      if (response is! List) {
        throw const ShopAccountException(ShopAccountFailure.invalidResponse);
      }
      return response.map(_parseAccount).toList(growable: false);
    } on ShopAccountException {
      rethrow;
    } on PostgrestException catch (error) {
      throw ShopAccountException(_mapPostgrestError(error));
    } catch (_) {
      throw const ShopAccountException(ShopAccountFailure.unavailable);
    }
  }

  void _requireSession() {
    final session = _client.auth.currentSession;
    if (session == null || session.isExpired) {
      throw const ShopAccountException(ShopAccountFailure.unauthorized);
    }
  }

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static ShopAccount _parseAccount(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const ShopAccountException(ShopAccountFailure.invalidResponse);
    }
    final id = value['shop_id'];
    final name = value['shop_name'];
    final role = value['member_role'];
    final status = value['entitlement_status'];
    final expires = value['subscription_expires_at'];
    if (id is! String ||
        !_uuid.hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        role is! String ||
        !const ['owner', 'partner', 'employee'].contains(role) ||
        status is! String ||
        !const ['pending', 'active', 'expired'].contains(status) ||
        (expires != null && expires is! String)) {
      throw const ShopAccountException(ShopAccountFailure.invalidResponse);
    }
    final expiresAt = expires == null ? null : DateTime.tryParse(expires);
    if (expires != null && expiresAt == null) {
      throw const ShopAccountException(ShopAccountFailure.invalidResponse);
    }
    return ShopAccount(
      id: id,
      name: name,
      role: role,
      entitlement: ShopEntitlement.values.byName(status),
      expiresAt: expiresAt,
    );
  }

  static ShopAccountFailure _mapPostgrestError(PostgrestException error) {
    if (error.code == '42501' || error.code == 'PGRST301') {
      return ShopAccountFailure.unauthorized;
    }
    if (error.code == '22023' || error.code == '23505') {
      return ShopAccountFailure.rejected;
    }
    return ShopAccountFailure.unavailable;
  }
}
