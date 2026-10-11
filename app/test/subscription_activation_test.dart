import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account_gateway.dart';
import 'package:eldafttar/src/features/shop_accounts/presentation/subscription_activation.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class ScriptActivation implements ShopAccountGateway {
  ScriptActivation({this.onActivate, this.accounts = const []});

  Future<SubscriptionActivationResult> Function(
    String requestKey,
    String code,
    String shopId,
  )?
  onActivate;
  final List<ShopAccount> accounts;
  final keys = <String>[];
  final codes = <String>[];

  @override
  Future<List<ShopAccount>> listMyShopAccounts() async => accounts;

  @override
  Future<SubscriptionActivationResult> activateSubscription({
    required String requestKey,
    required String code,
    required String shopId,
  }) async {
    keys.add(requestKey);
    codes.add(code);
    return onActivate!(requestKey, code, shopId);
  }
}

const shop = ShopAccount(
  id: '11111111-1111-4111-8111-111111111111',
  name: 'متجر تجريبي',
  role: 'owner',
  entitlement: ShopEntitlement.pending,
);

Future<void> pumpPanel(
  WidgetTester tester,
  ScriptActivation gateway, {
  Future<void> Function()? onActivated,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      home: Scaffold(
        body: SubscriptionActivationPanel(
          account: shop,
          gateway: gateway,
          onActivated: onActivated ?? () async {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('unknown outcome freezes the code and retries the same key', (
    tester,
  ) async {
    final gateway = ScriptActivation(
      onActivate: (key, code, shopId) async {
        throw const SubscriptionActivationException(
          SubscriptionActivationFailure.unknownOutcome,
        );
      },
    );
    await pumpPanel(tester, gateway);
    await tester.enterText(
      find.byKey(const Key('subscription-code')),
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );
    await tester.tap(find.byKey(const Key('subscription-activate')));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(
      find.byKey(const Key('subscription-code')),
    );
    expect(field.enabled, isFalse);
    expect(field.controller!.text, 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
    expect(find.text(SubscriptionCopy.retry), findsOneWidget);
    gateway.onActivate = (key, code, shopId) async {
      return SubscriptionActivationResult(
        shopId: shop.id,
        startsAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2026, 2, 1),
        replayed: true,
      );
    };
    await tester.tap(find.byKey(const Key('subscription-activate')));
    await tester.pumpAndSettle();
    expect(gateway.keys, hasLength(2));
    expect(gateway.keys[0], gateway.keys[1]);
    expect(gateway.codes, everyElement('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA'));
  });

  testWidgets('confirmed redemption stays success if refetch fails', (
    tester,
  ) async {
    final gateway = ScriptActivation(
      onActivate: (key, code, shopId) async {
        expect(shopId, shop.id);
        return SubscriptionActivationResult(
          shopId: shop.id,
          startsAt: DateTime.utc(2026, 1, 1),
          expiresAt: DateTime.utc(2026, 2, 1),
          replayed: false,
        );
      },
    );
    await pumpPanel(
      tester,
      gateway,
      onActivated: () async {
        throw StateError('refetch');
      },
    );
    await tester.enterText(
      find.byKey(const Key('subscription-code')),
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    );
    await tester.tap(find.byKey(const Key('subscription-activate')));
    await tester.pumpAndSettle();
    expect(find.text(SubscriptionCopy.refetchFailed), findsOneWidget);
    expect(find.text(SubscriptionCopy.unknown), findsNothing);
    final field = tester.widget<TextField>(
      find.byKey(const Key('subscription-code')),
    );
    expect(field.enabled, isFalse);
  });
}
