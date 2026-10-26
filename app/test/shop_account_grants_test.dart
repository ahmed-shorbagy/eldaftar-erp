import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('owner has every permission', () {
    const account = ShopAccount(
      id: 'a1000000-0000-4000-8000-000000000001',
      name: 'متجر',
      role: 'owner',
      entitlement: ShopEntitlement.active,
      grants: kAllShopPermissions,
    );
    expect(account.isOwner, isTrue);
    expect(account.hasPermission(ShopPermission.sale), isTrue);
    expect(account.hasPermission(ShopPermission.invoiceSend), isTrue);
  });

  test('employee respects grants and hides owner-only surfaces', () {
    const account = ShopAccount(
      id: 'a1000000-0000-4000-8000-000000000001',
      name: 'متجر',
      role: 'employee',
      entitlement: ShopEntitlement.active,
      grants: {ShopPermission.sale, ShopPermission.purchase},
    );
    expect(account.isEmployee, isTrue);
    expect(account.isOwner, isFalse);
    expect(account.hasPermission(ShopPermission.sale), isTrue);
    expect(account.hasPermission(ShopPermission.inventory), isFalse);
    expect(account.hasPermission(ShopPermission.reports), isFalse);
  });

  test('permission api round-trip', () {
    for (final permission in ShopPermission.values) {
      expect(
        shopPermissionFromApi(shopPermissionToApi(permission)),
        permission,
      );
    }
  });
}
