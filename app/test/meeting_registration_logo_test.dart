import 'dart:async';
import 'dart:typed_data';
import 'package:eldafttar/src/features/auth/domain/auth_gateway.dart';
import 'package:eldafttar/src/features/auth/presentation/auth_screen.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_image.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'auth_screen_test.dart'
    show ScriptedAuth, openSignup, fillSignup, nextSignup;

Uint8List registrationLogoBytes() {
  final image = img.Image(width: 32, height: 32);
  img.fill(image, color: img.ColorRgba8(148, 104, 31, 255));
  return Uint8List.fromList(img.encodePng(image));
}

class RegistrationImageGateway implements ShopImageGateway {
  var saves = 0;
  @override
  Future<ShopImage?> readCurrent() async => null;
  @override
  Future<void> clearImage() async {}
  @override
  Future<ShopImage> setImage(Uint8List preparedBytes) async {
    saves++;
    return ShopImage(
      shopId: 'shop-1',
      sha256: 'ab' * 32,
      mime: 'image/png',
      width: 32,
      height: 32,
      bytes: preparedBytes,
    );
  }
}

void main() {
  for (final useLogo in [false, true]) {
    testWidgets(
      'registration invoice logo requires explicit selection $useLogo',
      (t) async {
        t.view.physicalSize = const Size(390, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        final auth = ScriptedAuth()
          ..registration = Completer<OwnerRegistrationResult>();
        addTearDown(auth.close);
        final images = RegistrationImageGateway();
        var logoDrafts = 0, settled = 0;
        await t.pumpWidget(
          MaterialApp(
            theme: AppTheme.light(),
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: AuthScreen(
              gateway: auth,
              onToggleTheme: (_) async {},
              onHold: (_) {},
              onSessionSettled: () => settled++,
              shopImageGateway: images,
              pickShopImage: () async => registrationLogoBytes(),
              saveRegistrationInvoiceLogo: (bytes) async {
                logoDrafts++;
              },
            ),
          ),
        );
        await t.pumpAndSettle();
        await openSignup(t);
        await fillSignup(t);
        await t.ensureVisible(find.byKey(const Key('signup-back')));
        await t.tap(find.byKey(const Key('signup-back')));
        await t.pumpAndSettle();
        await t.ensureVisible(find.byKey(const Key('signup-shop-image')));
        await t.tap(find.byKey(const Key('signup-shop-image')));
        await t.pumpAndSettle();
        final choice = find.byKey(const Key('signup-invoice-logo'));
        await t.ensureVisible(choice);
        expect(t.widget<CheckboxListTile>(choice).value, isFalse);
        if (useLogo) {
          await t.tap(choice);
          await t.pumpAndSettle();
        }
        await nextSignup(t);
        await nextSignup(t);
        auth.registration!.complete(
          const OwnerRegistrationResult(userId: 'owner-1', shopId: 'shop-1'),
        );
        await t.pumpAndSettle();
        expect(auth.registrations.length, 1);
        expect(images.saves, 1);
        expect(logoDrafts, useLogo ? 1 : 0);
        expect(settled, 1);
      },
    );
  }
}
