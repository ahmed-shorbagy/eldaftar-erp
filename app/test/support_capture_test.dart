import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/help/domain/help_models.dart';
import 'package:eldafttar/src/features/help/presentation/help_screen.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/features/support/domain/support_models.dart';
import 'package:eldafttar/src/features/support/presentation/support_screen.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support_screen_test.dart' show FakeSupportGateway, inquiryOf;

/// Synthetic widget captures for the HELP-02 support screens. These are not
/// device proof; Arabic RTL review evidence in both themes and text scales.
final String captureDir =
    Platform.environment['ELDAFTTAR_CAPTURE_DIR'] ?? 'build/support-review';

const reviewSizes = <(Size, String)>[
  (Size(320, 640), '320'),
  (Size(390, 844), '390'),
  (Size(1440, 900), '1440'),
];

class CaptureHelpGateway implements HelpGateway {
  @override
  Future<PlatformAnnouncement?> getAnnouncement() async => null;

  @override
  Future<List<HelpTopic>> listCatalog() async => const [
    HelpTopic(
      id: 't1',
      titleAr: 'المبيعات',
      sortOrder: 1,
      articles: [
        HelpArticle(
          id: 'a1',
          titleAr: 'كيف أسجّل بيعًا',
          bodyAr: 'افتح الدفتر ثم اختر بيع.',
          sortOrder: 1,
        ),
      ],
    ),
  ];
}

Future<void> frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> capture(WidgetTester tester, String name) async {
  await frames(tester);
  expect(tester.takeException(), isNull, reason: name);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('support-capture-boundary')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('$captureDir/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
    image.dispose();
  });
}

Widget harness({
  required Brightness brightness,
  required Widget child,
  double textScale = 1.0,
}) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
  home: RepaintBoundary(
    key: const Key('support-capture-boundary'),
    child: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: child,
    ),
  ),
);

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

  testWidgets('captures the support screen filled with rows', (tester) async {
    final gateway = FakeSupportGateway(
      initial: [
        inquiryOf('inq-new', category: SupportCategory.subscription),
        inquiryOf(
          'inq-progress',
          category: SupportCategory.technical,
          status: SupportInquiryStatus.inProgress,
        ),
        inquiryOf(
          'inq-answered',
          category: SupportCategory.financialQuestion,
          status: SupportInquiryStatus.answered,
          replyAr: 'راجعنا الاستفسار وأعدنا ضبط الاشتراك؛ سيصل التأكيد قريبًا.',
        ),
      ],
    );
    await tester.pumpWidget(
      harness(
        brightness: Brightness.light,
        child: SupportScreen(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'support-filled-390-light-1x');

    await tester.pumpWidget(
      harness(
        brightness: Brightness.dark,
        child: SupportScreen(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();
    await capture(tester, 'support-filled-390-dark-1x');
  });

  for (final (size, label) in reviewSizes) {
    for (final brightness in Brightness.values) {
      for (final scale in const [1.0, 1.7]) {
        testWidgets('captures support $label ${brightness.name} ${scale}x', (
          tester,
        ) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final gateway = FakeSupportGateway(
            initial: [
              inquiryOf('inq-new', category: SupportCategory.subscription),
              inquiryOf(
                'inq-answered',
                status: SupportInquiryStatus.answered,
                replyAr:
                    'راجعنا الاستفسار وأعدنا ضبط الاشتراك؛ سيصل التأكيد قريبًا.',
              ),
            ],
          );
          await tester.pumpWidget(
            harness(
              brightness: brightness,
              textScale: scale,
              child: SupportScreen(gateway: gateway),
            ),
          );
          await tester.pumpAndSettle();
          await capture(tester, 'support-$label-${brightness.name}-$scale');
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('captures the help screen support entry and workspace link', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Emphasized entry when the help search finds no match (light + dark).
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        harness(
          brightness: brightness,
          child: HelpScreen(
            gateway: CaptureHelpGateway(),
            supportBuilder: (_) => SupportScreen(gateway: FakeSupportGateway()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('help-search')),
        'كلمة غير موجودة في المساعدة',
      );
      await tester.pumpAndSettle();
      await capture(tester, 'help-support-entry-${brightness.name}');
    }

    // Workspace more menu with the owner-only support link.
    await tester.pumpWidget(
      harness(
        brightness: Brightness.light,
        child: ShopWorkspace(
          shop: const ShopAccount(
            id: 's1',
            name: 'متجر المعاينة',
            role: 'owner',
            entitlement: ShopEntitlement.active,
          ),
          onSignOut: () async {},
          onToggleTheme: (_) async {},
          supportGateway: FakeSupportGateway(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('المزيد').last);
    await tester.pumpAndSettle();
    final supportLink = find.byKey(const Key('workspace-support'));
    for (
      var attempt = 0;
      attempt < 12 && supportLink.evaluate().isEmpty;
      attempt++
    ) {
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -300));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(supportLink);
    await tester.pumpAndSettle();
    await capture(tester, 'workspace-support-link-390-light');
  });
}
