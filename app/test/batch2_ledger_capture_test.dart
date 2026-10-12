import 'dart:io';
import 'dart:ui' as ui;
import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';

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

import 'daily_ledger_widget_test.dart' show MemoryStore;
import 'owner_feedback_ledger_review_test.dart' show ReviewGateway;

class ItemReviewGateway extends ReviewGateway {
  static const weights = {
    'sale': ['500', '500', '830'],
    'purchase': ['4000', '3000', '3000'],
    'sale_return': ['200', '100', '200'],
  };
  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async {
    final base = await super.ledger(callerUserId: callerUserId);
    return DailyLedgerView(
      state: base.state,
      entitlementStatus: base.entitlementStatus,
      canConfirm: base.canConfirm,
      businessDay: base.businessDay,
      cash: base.cash,
      stock: base.stock,
      scrap: base.scrap,
      daySummary: base.daySummary,
      feed: [
        for (final row in base.feed)
          LedgerFeedLine(
            kind: row.kind,
            labelAr: row.labelAr,
            operationId: row.kind,
            actorDisplayName: row.actorDisplayName,
            occurredAt: row.occurredAt,
            occurredAtCairo: row.occurredAtCairo,
            partyName: row.partyName,
            totalPounds: row.totalPounds,
            weightGrams: row.weightGrams,
            karat: row.karat,
            paymentLabel: row.paymentLabel,
            pieceCount: '3',
            isReturn: row.isReturn,
          ),
      ],
    );
  }

  @override
  Future<Map<String, Object?>> operation({
    required String callerUserId,
    required String operationId,
  }) async => {
    'payload': {
      'items': [
        for (var index = 0; index < 3; index++)
          {
            'item_name': [
              'خاتم تجريبي',
              'سلسلة تجريبية',
              'تعليقة تجريبية',
            ][index],
            'milligrams': weights[operationId]![index],
            'category': 'worked_jewelry',
            'karat': 18,
            'count': '1',
          },
      ],
    },
  };
}

Future<void> capture(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: name);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('batch2-ledger-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('../tmp/batch2/captures/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

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
  for (final width in [320.0, 390.0, 1440.0]) {
    for (final dark in [false, true]) {
      testWidgets('Batch 2 ledger RTL ${dark ? 'dark' : 'light'} $width', (
        tester,
      ) async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          RepaintBoundary(
            key: const Key('batch2-ledger-capture'),
            child: MaterialApp(
              locale: const Locale('ar'),
              supportedLocales: const [Locale('ar')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              home: ShopWorkspace(
                shop: const ShopAccount(
                  id: 'shop-1',
                  name: 'متجر تجريبي',
                  role: 'owner',
                  entitlement: ShopEntitlement.active,
                ),
                gateway: ItemReviewGateway(),
                store: MemoryStore(),
                userId: 'owner-1',
                onSignOut: () async {},
                onToggleTheme: (_) async {},
              ),
            ),
          ),
        );
        final label = '${dark ? 'dark' : 'light'}-${width.toInt()}';
        await capture(tester, 'ledger-top-$label');
        expect(find.text('الرئيسية'), findsNothing);
        expect(find.byTooltip('تسجيل الخروج'), findsNothing);
        await tester.ensureVisible(find.byKey(const Key('ledger-new-sale')));
        await capture(tester, 'ledger-sale-$label');
        await tester.ensureVisible(
          find.byKey(const Key('ledger-new-purchase')),
        );
        await capture(tester, 'ledger-purchase-$label');
        await tester.ensureVisible(
          find.byKey(const Key('ledger-journal-details-purchase')),
        );
        await tester.tap(
          find.byKey(const Key('ledger-journal-details-purchase')),
        );
        await capture(tester, 'ledger-details-$label');
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
