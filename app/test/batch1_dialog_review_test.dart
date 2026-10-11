import 'package:eldafttar/src/app.dart';
import 'package:eldafttar/src/config/supabase_startup.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'batch1_capture_test.dart' as review;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'Cairo',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final size in review.sizes) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'activation remains usable with keyboard and large Arabic text ${brightness.name} ${size.width}',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
          final auth = review.CaptureAuth(signedIn: true);
          addTearDown(auth.controller.close);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('batch1-capture'),
              child: ElDafttarApp(
                supabaseStatus: SupabaseStartupStatus.ready,
                themeController: ThemeController(
                  store: review.MemoryThemeStore(),
                  initial: brightness == Brightness.dark
                      ? ThemeMode.dark
                      : ThemeMode.light,
                ),
                authGateway: auth,
                shopAccountGateway: review.CaptureShops(const [
                  ShopAccount(
                    id: '11111111-1111-4111-8111-111111111111',
                    name: 'متجر اختبار الاشتراك',
                    role: 'owner',
                    entitlement: ShopEntitlement.pending,
                  ),
                ]),
                currentUserId: () => 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
              ),
            ),
          );
          await tester.pumpAndSettle();
          tester.view.viewInsets = FakeViewPadding(
            bottom: size.width < 840 ? 300 : 0,
          );
          await tester.pumpAndSettle();
          final field = find.byKey(const Key('subscription-code'));
          await tester.ensureVisible(field);
          await tester.enterText(field, 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
          await tester.pumpAndSettle();
          expect(
            tester.widget<TextField>(field).textDirection,
            TextDirection.ltr,
          );
          expect(Directionality.of(tester.element(field)), TextDirection.rtl);
          final activate = find.byKey(const Key('subscription-activate'));
          await tester.ensureVisible(activate);
          await tester.pumpAndSettle();
          expect(
            tester.getRect(activate).bottom,
            lessThanOrEqualTo(size.height - (size.width < 840 ? 300 : 0)),
          );
          expect(tester.takeException(), isNull);
          await review.savePng(
            tester,
            'keyboard-${brightness.name}-${size.width.toInt()}.png',
          );
          await tester.tap(activate);
          await tester.pumpAndSettle();
          expect(tester.widget<TextField>(field).enabled, isFalse);
          await tester.ensureVisible(
            find.byKey(const Key('subscription-status')),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await review.savePng(
            tester,
            'activation-unknown-${brightness.name}-${size.width.toInt()}.png',
          );
        },
      );
    }
  }
}
