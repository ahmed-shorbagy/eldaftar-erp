import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/payment_methods_gateway.dart';

class SupabasePaymentMethodsGateway implements PaymentMethodsGateway {
  const SupabasePaymentMethodsGateway(this._client);
  final SupabaseClient _client;

  @override
  Future<ShopPaymentMethodsDirectory> listMethods({
    required String userId,
  }) async {
    _require(userId);
    try {
      final response = await _client
          .rpc('list_shop_payment_methods_v1')
          .timeout(const Duration(seconds: 15));
      _require(userId);
      return _parse(response);
    } on PaymentMethodsException {
      rethrow;
    } on PostgrestException catch (error) {
      throw PaymentMethodsException(_map(error));
    } catch (_) {
      throw const PaymentMethodsException(PaymentMethodsFailure.unavailable);
    }
  }

  @override
  Future<ShopPaymentMethodsDirectory> saveMethods({
    required String userId,
    required String key,
    required List<({String method, String labelAr, bool archived})> methods,
  }) async {
    _require(userId);
    try {
      final response = await _client
          .rpc(
            'save_shop_payment_methods_v1',
            params: {
              'p_key': key,
              'p_methods': [
                for (final method in methods)
                  {
                    'method': method.method,
                    'label_ar': method.labelAr,
                    'archived': method.archived,
                  },
              ],
            },
          )
          .timeout(const Duration(seconds: 20));
      _require(userId);
      return _parse(response);
    } on PaymentMethodsException {
      rethrow;
    } on PostgrestException catch (error) {
      throw PaymentMethodsException(_map(error));
    } catch (_) {
      throw const PaymentMethodsException(PaymentMethodsFailure.unavailable);
    }
  }

  void _require(String userId) {
    final session = _client.auth.currentSession;
    if (session == null || session.user.id != userId) {
      throw const PaymentMethodsException(PaymentMethodsFailure.unauthorized);
    }
  }

  static ShopPaymentMethodsDirectory _parse(Object? value) {
    if (value is! Map) {
      throw const PaymentMethodsException(PaymentMethodsFailure.invalidResponse);
    }
    final map = Map<String, dynamic>.from(value);
    final shopId = map['shop_id'];
    final methods = map['methods'];
    if (shopId is! String || methods is! List) {
      throw const PaymentMethodsException(PaymentMethodsFailure.invalidResponse);
    }
    final parsed = <ShopPaymentMethod>[];
    for (final raw in methods) {
      if (raw is! Map) {
        throw const PaymentMethodsException(
          PaymentMethodsFailure.invalidResponse,
        );
      }
      final row = Map<String, dynamic>.from(raw);
      final accountId = row['account_id'];
      final method = row['method'];
      final label = row['label_ar'];
      final archived = row['archived'];
      if (accountId is! String ||
          method is! String ||
          label is! String ||
          archived is! bool) {
        throw const PaymentMethodsException(
          PaymentMethodsFailure.invalidResponse,
        );
      }
      parsed.add(
        ShopPaymentMethod(
          accountId: accountId,
          method: method,
          labelAr: label,
          archived: archived,
        ),
      );
    }
    return ShopPaymentMethodsDirectory(shopId: shopId, methods: parsed);
  }

  static PaymentMethodsFailure _map(PostgrestException error) {
    final message = error.message.toLowerCase();
    if (error.code == '42501' ||
        message.contains('forbidden') ||
        message.contains('unauthenticated')) {
      return PaymentMethodsFailure.unauthorized;
    }
    if (message.contains('invalid_input') ||
        message.contains('payload_mismatch')) {
      return PaymentMethodsFailure.invalidInput;
    }
    if (message.contains('shop_not_active')) {
      return PaymentMethodsFailure.rejected;
    }
    return PaymentMethodsFailure.unavailable;
  }
}
