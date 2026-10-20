import 'dart:typed_data';
import 'package:eldafttar/src/features/inventory/domain/inventory_models.dart';
import 'package:eldafttar/src/features/inventory/presentation/inventory_lots_table.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/invoice_appearance_gateway.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/logo_codec.dart';
import 'package:eldafttar/src/features/invoice_appearance/data/logo_upload_store.dart';
import 'package:eldafttar/src/features/invoice_appearance/presentation/invoice_appearance_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'invoice_appearance_screen_test.dart'
    show AppearanceTestGateway, AppearanceTestLocker;

const completionUser = 'a1111111-1111-4111-8111-111111111111';
const completionShop = 'a1222222-2222-4222-8222-222222222222';
List<LotSnapshot> completionLots() => [
  for (final measured in [true, false])
    LotSnapshot(
      id: measured ? 'measured' : 'legacy',
      productId: 'product',
      productName: 'خاتم',
      displayName: measured ? 'خاتم تجريبي' : 'رصيد تاريخي',
      category: 'worked_jewelry',
      karat: 21,
      stockClass: measured
          ? StockClass.ownedAvailable
          : StockClass.traderCustody,
      remainingMilligrams: BigInt.from(1831),
      remainingCount: measured ? BigInt.one : null,
      originalMilligrams: BigInt.from(1831),
      originalCount: measured ? BigInt.one : null,
      legacyAggregate: !measured,
    ),
];

class RegistrationLogoGateway extends AppearanceTestGateway {
  var uploads = 0;
  String? sha;
  @override
  Future<LogoUploadResult> uploadInvoiceLogo({
    required String userId,
    required String shopId,
    required String objectName,
    required String mimeType,
    required List<int> bytes,
  }) async {
    uploads++;
    sha = (await prepareLogo(Uint8List.fromList(bytes))).sha256;
    return const LogoUploadResult(LogoUploadDisposition.stored);
  }

  @override
  Future<LogoConfirmation> confirmInvoiceLogo({
    required String userId,
    required String shopId,
    required String base64Bytes,
    required String sha256,
  }) async => LogoConfirmation(
    shopId: shopId,
    assetId: 'a1333333-3333-4333-8333-333333333333',
    sha256: sha256,
    mime: 'image/png',
    width: 2,
    height: 2,
  );
}

void main() {
  Widget host(Widget child, bool dark) => MaterialApp(
    theme: dark ? AppTheme.dark() : AppTheme.light(),
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: Scaffold(body: child),
  );
  for (final dark in [false, true]) {
    testWidgets(
      'inventory exact columns and missing count ${dark ? 'dark' : 'light'}',
      (t) async {
        t.view.physicalSize = const Size(320, 850);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        LotSnapshot? opened;
        await t.pumpWidget(
          host(
            InventoryLotsTable(
              lots: completionLots(),
              onOpen: (lot) => opened = lot,
            ),
            dark,
          ),
        );
        await t.pumpAndSettle();
        expect(find.text('1.831'), findsNWidgets(2));
        expect(find.text('غير مسجّل'), findsOneWidget);
        expect(
          Directionality.of(t.element(find.byType(DataTable))),
          TextDirection.rtl,
        );
        await t.tap(find.byKey(const Key('lot-row-measured')));
        expect(opened?.id, 'measured');
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'registration logo resumes saved bytes and remains a draft until appearance save',
    (t) async {
      t.view.physicalSize = const Size(700, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final image = img.Image(width: 2, height: 2);
      final prepared = await prepareLogo(
        Uint8List.fromList(img.encodePng(image)),
      );
      final logos = MemoryLogoUploadStore();
      await logos.save(
        completionUser,
        completionShop,
        LogoUploadRecord(
          phase: LogoUploadPhase.uploadPending,
          sha256: prepared.sha256,
          mime: prepared.facts.mime,
          objectName: prepared.objectName(completionShop),
          fromRegistration: true,
        ),
        prepared.bytes,
      );
      final gateway = RegistrationLogoGateway(),
          locker = AppearanceTestLocker();
      Widget screen() => InvoiceAppearanceScreen(
        gateway: gateway,
        store: locker,
        logoStore: logos,
        userId: completionUser,
        shopId: completionShop,
        canRead: () => true,
        canWrite: () => true,
        pickLogo: () async => throw StateError('must resume the stored bytes'),
      );
      await t.pumpWidget(host(screen(), false));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('appearance-retry')));
      await t.tap(find.byKey(const Key('appearance-retry')));
      await t.pumpAndSettle();
      expect(gateway.uploads, 1);
      expect(logos.record?.phase, LogoUploadPhase.confirmed);
      expect(logos.record?.fromRegistration, isTrue);
      expect(locker.command, isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(host(screen(), true));
      await t.pumpAndSettle();
      expect(find.textContaining('شعار التسجيل مؤكد'), findsOneWidget);
      expect(gateway.uploads, 1);
    },
  );
}
