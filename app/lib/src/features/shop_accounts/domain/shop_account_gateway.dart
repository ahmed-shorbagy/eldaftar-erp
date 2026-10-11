import 'shop_account.dart';

abstract class ShopAccountGateway {
  Future<List<ShopAccount>> listMyShopAccounts();

  Future<SubscriptionActivationResult> activateSubscription({
    required String requestKey,
    required String code,
    required String shopId,
  });
}

class ShopAccountException implements Exception {
  const ShopAccountException(this.failure);

  final ShopAccountFailure failure;
}
