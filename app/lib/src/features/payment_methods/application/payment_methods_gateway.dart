class ShopPaymentMethod {
  const ShopPaymentMethod({
    required this.accountId,
    required this.method,
    required this.labelAr,
    required this.archived,
  });

  final String accountId;
  final String method;
  final String labelAr;
  final bool archived;
}

class ShopPaymentMethodsDirectory {
  const ShopPaymentMethodsDirectory({
    required this.shopId,
    required this.methods,
  });

  final String shopId;
  final List<ShopPaymentMethod> methods;
}

enum PaymentMethodsFailure {
  unauthorized,
  unavailable,
  invalidInput,
  rejected,
  invalidResponse,
}

class PaymentMethodsException implements Exception {
  const PaymentMethodsException(this.failure);
  final PaymentMethodsFailure failure;
}

abstract class PaymentMethodsGateway {
  Future<ShopPaymentMethodsDirectory> listMethods({required String userId});

  Future<ShopPaymentMethodsDirectory> saveMethods({
    required String userId,
    required String key,
    required List<({String method, String labelAr, bool archived})> methods,
  });
}
