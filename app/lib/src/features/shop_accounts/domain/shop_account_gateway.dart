import 'shop_account.dart';

abstract class ShopAccountGateway {
  Future<List<ShopAccount>> listMyShopAccounts();
}

class ShopAccountException implements Exception {
  const ShopAccountException(this.failure);

  final ShopAccountFailure failure;
}
