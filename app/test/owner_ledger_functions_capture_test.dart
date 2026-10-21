import 'dart:io';
import 'package:eldafttar/src/features/auth/presentation/auth_screen.dart';
import 'package:eldafttar/src/features/auth/presentation/auth_copy.dart';
import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/data/ledger_date_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/data/ledger_trade_change_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/daily_ledger_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_trade_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_date_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_more_balances.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_trade_change_screen.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'daily_ledger_capture_test.dart' show confirmedLedger;
import 'daily_ledger_widget_test.dart' show MemoryStore;
import 'ledger_more_balances_test.dart' show LiveMoreGateway;
import 'ledger_revision_test_support.dart';
import 'auth_capture_test.dart' show CaptureAuth;

class CaptureRevisionGateway extends RevisionGateway {
  CaptureRevisionGateway(this.view);
  final DailyLedgerView view;
  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async => view;
}

/// Actual synthetic widget captures. Historical review artifacts stay untouched.
void main() {
  if (!const bool.fromEnvironment('LEDGER_FUNCTIONS_CAPTURE')) return;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('Cairo')..addFont(
          Future.value(
            ByteData.sublistView(
              await File('assets/fonts/Cairo.ttf').readAsBytes(),
            ),
          ),
        ))
        .load();
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(
            ByteData.sublistView(
              await File(
                r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
              ).readAsBytes(),
            ),
          ),
        ))
        .load();
  });
  for (final width in [320.0, 390.0, 1440.0]) {
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.7]) {
        final suffix = '${width.toInt()}-${dark ? 'dark' : 'light'}-$scale';
        testWidgets('ledger function captures $suffix', (t) async {
          SharedPreferences.setMockInitialValues({});
          FlutterSecureStorage.setMockInitialValues({});
          t.view.physicalSize = Size(width, width == 1440 ? 900 : 800);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.resetPhysicalSize);
          addTearDown(t.view.resetDevicePixelRatio);
          final key = GlobalKey();
          Widget host(Widget child) => MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('ar'),
            supportedLocales: const [Locale('ar')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: RepaintBoundary(key: key, child: child!),
            ),
            home: child,
          );
          Future<void> shot(String state) async {
            await t.pumpAndSettle();
            expect(t.takeException(), isNull, reason: '$state-$suffix');
            await expectLater(
              find.byKey(key),
              matchesGoldenFile(
                '../../docs/reviews/owner-feedback-ledger-functions-2026-10-19/captures/$state-$suffix.png',
              ),
            );
          }

          Future<void> tap(Finder finder) async {
            if (finder.evaluate().isEmpty) {
              await t.scrollUntilVisible(
                finder,
                200,
                scrollable: find.byType(Scrollable).first,
              );
            }
            await t.ensureVisible(finder);
            await t.pumpAndSettle();
            await t.tap(finder);
            await t.pumpAndSettle();
          }

          await t.pumpWidget(
            host(
              AuthScreen(
                gateway: CaptureAuth(),
                onToggleTheme: (_) async {},
                onHold: (_) {},
                onSessionSettled: () {},
              ),
            ),
          );
          await t.pumpAndSettle();
          await t.runAsync(
            () => precacheImage(
              const AssetImage('assets/brand/auth-jewelry.png'),
              t.element(find.byType(AuthScreen)),
            ),
          );
          await t.enterText(
            find.byKey(const Key('sign-in-identifier')),
            'owner@example.test',
          );
          await t.enterText(find.byKey(const Key('sign-in-password')), 'a');
          await tap(find.byKey(const Key('sign-in-submit')));
          expect(find.text(AuthCopy.passwordInvalid), findsWidgets);
          await shot('login-password-hint');
          await tap(find.byKey(const Key('show-signup')));
          for (final field in {
            'signup-owner-name': 'مالك تجريبي',
            'signup-email': 'owner@example.test',
            'signup-phone': '01012345678',
            'signup-password': 'a',
            'signup-password-confirm': 'a',
          }.entries) {
            await t.ensureVisible(find.byKey(Key(field.key)));
            await t.pumpAndSettle();
            await t.enterText(find.byKey(Key(field.key)), field.value);
          }
          await tap(find.byKey(const Key('signup-submit')));
          await t.ensureVisible(find.byKey(const Key('signup-password')));
          expect(find.text(AuthCopy.passwordInvalid), findsWidgets);
          await shot('signup-password-hint');

          final base = confirmedLedger();
          final view = DailyLedgerView(
            state: base.state,
            entitlementStatus: base.entitlementStatus,
            canConfirm: base.canConfirm,
            businessDay: base.businessDay,
            cash: base.cash,
            stock: base.stock,
            scrap: base.scrap,
            feed: base.feed,
            daySummary: const LedgerDaySummary(
              salePiastres: '700025',
              purchasePiastres: '400000',
              expensePiastres: '500',
              saleCount: 3,
              purchaseCount: 4,
              expenseCount: 1,
              goldByBucket: [
                LedgerGoldMovement(
                  kind: 'sale',
                  category: 'worked_jewelry',
                  karat: 18,
                  milligrams: '2000',
                  count: '1',
                ),
                LedgerGoldMovement(
                  kind: 'sale',
                  category: 'bullion',
                  karat: 24,
                  milligrams: '3000',
                  count: '1',
                ),
                LedgerGoldMovement(
                  kind: 'purchase',
                  category: 'scrap',
                  karat: 22,
                  milligrams: '1255',
                  count: '0',
                ),
              ],
            ),
          );
          await t.pumpWidget(
            host(
              DailyLedgerScreen(
                shop: const ShopAccount(
                  id: revisionShop,
                  name: 'مجوهرات كذا',
                  role: 'owner',
                  entitlement: ShopEntitlement.active,
                ),
                gateway: CaptureRevisionGateway(view),
                store: MemoryStore(),
                userId: revisionUser,
                onToggleTheme: (_) async {},
              ),
            ),
          );
          await shot('summary21');
          await tap(find.byKey(const Key('ledger-customize')));
          await tap(find.byKey(const ValueKey('ledger-normalize-21')));
          await t.tap(find.text('عيار 24').last);
          await t.pumpAndSettle();
          await tap(find.byKey(const Key('detail-close')));
          await shot('summary24');
          await tap(find.byKey(const Key('ledger-customize')));
          await shot('six-slots');
          await t.ensureVisible(find.byKey(const Key('ledger-scrap-karat-22')));
          await shot('scrap-settings');
          await tap(find.byKey(const Key('detail-close')));
          await t.pumpWidget(
            host(
              Scaffold(
                body: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: LedgerMoreBalances(
                        shop: const ShopAccount(
                          id: revisionShop,
                          name: 'مجوهرات كذا',
                          role: 'owner',
                          entitlement: ShopEntitlement.active,
                        ),
                        gateway: LiveMoreGateway(view),
                        userId: revisionUser,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await shot('karat-more');
          final g = RevisionGateway();
          await t.pumpWidget(
            host(
              LedgerDateScreen(
                gateway: g,
                userId: revisionUser,
                shopId: revisionShop,
                canRead: () => true,
                onOperation: (_) async {},
              ),
            ),
          );
          await shot('dated-ledger');
          await tap(find.byKey(const Key('ledger-select-date')));
          await shot('date-picker');
          await tap(find.text('إلغاء'));
          await t.pumpWidget(const SizedBox.shrink());
          g.dateValue = parseLedgerDate(dateJson(rows: []), revisionShop);
          await t.pumpWidget(
            host(
              LedgerDateScreen(
                gateway: g,
                userId: revisionUser,
                shopId: revisionShop,
                canRead: () => true,
                onOperation: (_) async {},
              ),
            ),
          );
          await t.pumpAndSettle();
          await t.scrollUntilVisible(
            find.byKey(const Key('ledger-date-empty')),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await shot('empty-date');
          await t.pumpWidget(
            host(
              FinancialTradeScreen(
                kind: FinancialKind.sale,
                gateway: g,
                statusGateway: g,
                userId: revisionUser,
                shopId: revisionShop,
                initialPayload: sourceTrade(),
                onDraftReviewed: (_) async => false,
              ),
            ),
          );
          await shot('edit-form');
          await t.pumpWidget(
            host(
              LedgerTradeChangeScreen(
                review: changeReview(),
                gateway: g,
                statusGateway: g,
                userId: revisionUser,
                canRead: () => true,
                canWrite: () => true,
              ),
            ),
          );
          await shot('delete-review');
          g.result = const FinancialUnknown();
          await t.scrollUntilVisible(
            find.byKey(const Key('trade-change-confirm')),
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tap(find.byKey(const Key('trade-change-confirm')));
          await shot('unknown-change');
          g.result = const FinancialCommitted(
            revisionOperation,
            replayed: true,
          );
          await tap(find.byKey(const Key('trade-change-retry')));
          await shot('confirmed-change');
          await t.pumpWidget(const SizedBox.shrink());
          final edited = sourceTrade()..['note'] = 'ملاحظة معدّلة';
          final json = reviewJson(action: 'edit');
          json['effects'] = {
            'cash': <Object?>[],
            'stock': <Object?>[],
            'scrap': <Object?>[],
            'payable_delta_piastres': '0',
          };
          final review = parseTradeChangeReview(
            json,
            shopId: revisionShop,
            operationId: revisionOperation,
            action: 'edit',
          );
          await t.pumpWidget(
            host(
              LedgerTradeChangeScreen(
                review: review,
                gateway: g,
                statusGateway: g,
                userId: revisionUser,
                canRead: () => true,
                canWrite: () => true,
                replacement: edited,
              ),
            ),
          );
          await shot('edit-review');
          await t.pumpWidget(const SizedBox.shrink());
        });
      }
    }
  }
}
