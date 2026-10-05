import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_trade_screen.dart';
import 'package:eldafttar/src/features/onboarding/application/onboarding_store.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'financial_trade_screen_test.dart'
    show FakeFinancialGateway, beginTrade, nextTrade;

class _GuideStore implements OnboardingStore {
  int step = 0;
  bool complete = false;
  @override
  Future<bool> isComplete(String path) async => complete;
  @override
  Future<int> readStep(String path) async => step;
  @override
  Future<void> saveStep(String path, int step) async => this.step = step;
  @override
  Future<void> markComplete(String path) async => complete = true;
}

Widget _host(Widget child, Brightness brightness, {GlobalKey? capture}) =>
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark(),
      home: child,
      builder: (context, page) => RepaintBoundary(key: capture, child: page!),
    );

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final picture = await boundary.toImage();
    final png = await picture.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/m03-workspace-review/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = await File('assets/fonts/NotoSansArabic.ttf').readAsBytes();
    await (FontLoader(
      'NotoSansArabic',
    )..addFont(Future.value(ByteData.sublistView(font)))).load();
    final sdkRoot = Platform.resolvedExecutable
        .split(RegExp(r'[/\\]bin[/\\]cache[/\\]'))
        .first;
    final icons = await File(
      '$sdkRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('practice review cannot post or persist a financial command', (
    tester,
  ) async {
    final gateway = FakeFinancialGateway();
    final guide = _GuideStore();
    await tester.pumpWidget(
      _host(
        FinancialTradeScreen(
          kind: FinancialKind.sale,
          gateway: gateway,
          statusGateway: gateway,
          userId: 'owner-1',
          shopId: 'shop-1',
          practice: true,
          onboardingStore: guide,
        ),
        Brightness.light,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onboarding-guide')), findsNothing);
    await beginTrade(tester);
    expect(guide.step, 0);
    await tester.enterText(find.byKey(const Key('trade-name-0')), 'خاتم تدريب');
    await tester.ensureVisible(find.byKey(const Key('trade-grams-0')));
    await tester.enterText(find.byKey(const Key('trade-grams-0')), '1.830');
    await nextTrade(tester);
    await tester.ensureVisible(find.byKey(const Key('trade-tender-amount-0')));
    await tester.enterText(
      find.byKey(const Key('trade-tender-amount-0')),
      '1200.01',
    );
    await nextTrade(tester);
    await tester.ensureVisible(find.byKey(const Key('trade-review')));
    await tester.tap(find.byKey(const Key('trade-review')));
    await tester.pumpAndSettle();
    expect(find.text('إنهاء التدريب دون حفظ'), findsOneWidget);
    expect(find.text('1,200.01 جنيه'), findsWidgets);
    await tester.tap(find.byKey(const Key('trade-confirm')));
    await tester.pumpAndSettle();
    expect(gateway.keys, isEmpty);
    expect(gateway.closeCounts, isEmpty);
    expect(
      await const PendingFinancialCommands().read('owner-1', 'shop-1'),
      isNull,
    );
    expect(guide.complete, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'Arabic workspace without guides ${width.toInt()} ${brightness.name}',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final capture = GlobalKey();
          await tester.pumpWidget(
            _host(
              ShopWorkspace(
                shop: const ShopAccount(
                  id: 'shop-1',
                  name: 'متجر تجريبي',
                  role: 'owner',
                  entitlement: ShopEntitlement.active,
                ),
                gateway: FakeFinancialGateway(),
                userId: 'owner-1',
                onSignOut: () async {},
                onToggleTheme: (_) async {},
                onChangeShop: () {},
                onboardingStore: _GuideStore(),
              ),
              brightness,
              capture: capture,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text('الرئيسية').last);
          await tester.pumpAndSettle();
          expect(
            Directionality.of(
              tester.element(
                find.text(
                  'ابدأ يومك من الدفتر وتابع الأرصدة المؤكدة قبل تسجيل حركة جديدة.',
                ),
              ),
            ),
            TextDirection.rtl,
          );
          await _capture(
            tester,
            capture,
            'home-${width.toInt()}-${brightness.name}',
          );
          await tester.tap(find.text('المزيد').last);
          await tester.pumpAndSettle();
          await _capture(
            tester,
            capture,
            'more-${width.toInt()}-${brightness.name}',
          );
          expect(find.byKey(const Key('workspace-help')), findsNothing);
          expect(find.byKey(const Key('help-practice-sale')), findsNothing);
          expect(find.byKey(const Key('onboarding-guide')), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
