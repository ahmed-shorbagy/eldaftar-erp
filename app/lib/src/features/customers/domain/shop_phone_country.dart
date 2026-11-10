import 'phone_countries.dart';

/// Cached shop-owner phone country for empty customer phone fields (ADR 0044 C-D10).
final class ShopPhoneCountryCache {
  ShopPhoneCountryCache._();
  static final _byShop = <String, PhoneCountry>{};

  static PhoneCountry forShop(String shopId) => _byShop[shopId] ?? egypt;

  static void remember(String shopId, String? ownerPhone) {
    if (ownerPhone == null || ownerPhone.trim().isEmpty) {
      _byShop[shopId] = egypt;
      return;
    }
    _byShop[shopId] = splitCustomerPhone(ownerPhone).country;
  }

  static void clear() => _byShop.clear();
}
