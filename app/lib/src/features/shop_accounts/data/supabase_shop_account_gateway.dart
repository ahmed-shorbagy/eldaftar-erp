import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/shop_account.dart';
import '../domain/shop_account_gateway.dart';

class SupabaseShopAccountGateway implements ShopAccountGateway {
  const SupabaseShopAccountGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<List<ShopAccount>> listMyShopAccounts() async {
    final owner = _requireSession();
    try {
      final response = await _client
          .rpc('list_my_shop_accounts')
          .timeout(const Duration(seconds: 15));
      if (_requireSession() != owner) {
        throw const ShopAccountException(ShopAccountFailure.unauthorized);
      }
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

  @override
  Future<SubscriptionActivationResult> activateSubscription({
    required String requestKey,
    required String code,
    required String shopId,
  }) async {
    final userId = _requireIdentity();
    try {
      final response = await _client
          .rpc(
            'redeem_subscription_code',
            params: {'p_request_key': requestKey, 'p_code': code},
          )
          .timeout(const Duration(seconds: 15));
      if (_client.auth.currentUser?.id != userId) {
        throw const SubscriptionActivationException(
          SubscriptionActivationFailure.unauthorized,
        );
      }
      _requireIdentity();
      return _parseActivation(response, expectedShopId: shopId);
    } on SubscriptionActivationException {
      rethrow;
    } on ShopAccountException catch (error) {
      throw SubscriptionActivationException(
        error.failure == ShopAccountFailure.unauthorized
            ? SubscriptionActivationFailure.unauthorized
            : SubscriptionActivationFailure.unavailable,
      );
    } on PostgrestException catch (error) {
      throw SubscriptionActivationException(_mapActivationError(error));
    } catch (_) {
      throw const SubscriptionActivationException(
        SubscriptionActivationFailure.unknownOutcome,
      );
    }
  }

  String _requireIdentity() {
    final session = _client.auth.currentSession;
    final userId = _client.auth.currentUser?.id;
    if (session == null ||
        session.isExpired ||
        userId == null ||
        userId.isEmpty) {
      throw const ShopAccountException(ShopAccountFailure.unauthorized);
    }
    return userId;
  }

  String _requireSession() => _requireIdentity();

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
    final imageSha = value['shop_image_sha256'];
    if (id is! String ||
        !_uuid.hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        role is! String ||
        role != 'owner' ||
        status is! String ||
        !const ['pending', 'active', 'expired'].contains(status) ||
        (expires != null && expires is! String) ||
        (imageSha != null &&
            (imageSha is! String ||
                !RegExp(r'^[0-9a-f]{64}$').hasMatch(imageSha)))) {
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
      imageSha256: imageSha as String?,
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

  static SubscriptionActivationResult _parseActivation(
    Object? value, {
    required String expectedShopId,
  }) {
    Object? row = value;
    if (row is List) {
      if (row.length != 1) {
        throw const SubscriptionActivationException(
          SubscriptionActivationFailure.unknownOutcome,
        );
      }
      row = row.first;
    }
    if (row is! Map) {
      throw const SubscriptionActivationException(
        SubscriptionActivationFailure.unknownOutcome,
      );
    }
    final map = Map<String, dynamic>.from(row);
    final status = map['status'];
    if (status is String && status != 'activated' && status != 'replayed') {
      throw SubscriptionActivationException(_statusFailure(status));
    }
    final shopId = map['shop_id'];
    final starts = map['starts_at'];
    final expires = map['expires_at'];
    final startsAt = starts is String ? DateTime.tryParse(starts) : null;
    final expiresAt = expires is String ? DateTime.tryParse(expires) : null;
    if (shopId is! String ||
        !_uuid.hasMatch(shopId) ||
        shopId != expectedShopId ||
        startsAt == null ||
        expiresAt == null ||
        status is! String ||
        (status != 'activated' && status != 'replayed')) {
      throw const SubscriptionActivationException(
        SubscriptionActivationFailure.unknownOutcome,
      );
    }
    return SubscriptionActivationResult(
      shopId: shopId,
      startsAt: startsAt.toUtc(),
      expiresAt: expiresAt.toUtc(),
      replayed: status == 'replayed',
    );
  }

  static SubscriptionActivationFailure _statusFailure(String status) {
    return switch (status) {
      'invalid_code' => SubscriptionActivationFailure.invalidCode,
      'invalid_input' => SubscriptionActivationFailure.invalidInput,
      'expired_code' => SubscriptionActivationFailure.expiredCode,
      'reused_code' => SubscriptionActivationFailure.reusedCode,
      'foreign_owner' => SubscriptionActivationFailure.foreignOwner,
      'rate_limited' => SubscriptionActivationFailure.rateLimited,
      'request_key_reused' => SubscriptionActivationFailure.requestKeyReused,
      'unauthorized' => SubscriptionActivationFailure.unauthorized,
      _ => SubscriptionActivationFailure.unknownOutcome,
    };
  }

  static SubscriptionActivationFailure _mapActivationError(
    PostgrestException error,
  ) {
    final message = error.message.toLowerCase();
    if (message.contains('rate_limited') || error.code == 'P0003') {
      return SubscriptionActivationFailure.rateLimited;
    }
    if (message.contains('foreign_owner')) {
      return SubscriptionActivationFailure.foreignOwner;
    }
    if (message.contains('request_key_reused')) {
      return SubscriptionActivationFailure.requestKeyReused;
    }
    if (message.contains('reused_code')) {
      return SubscriptionActivationFailure.reusedCode;
    }
    if (message.contains('expired_code')) {
      return SubscriptionActivationFailure.expiredCode;
    }
    if (message.contains('invalid_code') || message.contains('invalid_input')) {
      return message.contains('invalid_input')
          ? SubscriptionActivationFailure.invalidInput
          : SubscriptionActivationFailure.invalidCode;
    }
    if (error.code == '42501' || error.code == 'PGRST301') {
      return SubscriptionActivationFailure.unauthorized;
    }
    if (error.code == '22023') {
      return SubscriptionActivationFailure.invalidCode;
    }
    return SubscriptionActivationFailure.unavailable;
  }
}
