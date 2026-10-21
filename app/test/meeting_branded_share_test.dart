import 'package:eldafttar/src/features/daily_ledger/presentation/invoice_pdf_share_dialog.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/invoice_appearance_contract.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/invoice_appearance_gateway.dart';
import 'package:eldafttar/src/features/invoice_appearance/domain/appearance_rules.dart';
import 'package:eldafttar/src/features/invoice_appearance/domain/branded_invoice_document.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:eldafttar/src/theme/pdf_arabic.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'financial_trade_screen_test.dart' show FakeFinancialGateway;
import 'invoice_appearance_test.dart' show meetingInvoiceSource;
import 'meeting_ui_completion_test.dart' show completionUser, completionShop;

const brandOperation = 'a1333333-3333-4333-8333-333333333333';

class BrandShareGateway extends FakeFinancialGateway
    implements InvoiceAppearanceGateway {
  final identity = Object();
  var editions = 0, creates = 0, copyReads = 0;
  bool staleCopy = false;
  ValueNotifier<int>? syncTick;
  Map<String, Object?> liveFields = const {};
  @override
  Object? appearanceSession(String userId) => identity;
  @override
  Future<Map<String, Object?>> operation({
    required String callerUserId,
    required String operationId,
  }) async => {
    ...meetingInvoiceSource(),
    'operation_id': operationId,
    'shop_id': completionShop,
    ...liveFields,
  };
  @override
  Future<InvoiceBrandSource> readBrandSource({
    required String userId,
    required String shopId,
    required String operationId,
  }) async {
    final data = meetingInvoiceSource();
    return InvoiceBrandSource(
      shopId: shopId,
      operationId: operationId,
      kind: 'sale',
      shopName: data['shop_name'] as String,
      shopSequence: data['shop_sequence'] as String,
      timeZone: 'Africa/Cairo',
      occurredAtUtc: data['occurred_at'] as String,
      occurredAtShop: data['occurred_at_shop'] as String,
      payload: Map<String, Object?>.from(data['payload'] as Map),
      contentSha256: 'ab' * 32,
      appearance: InvoiceAppearanceValue.defaults,
      latestEdition: editions,
      canWrite: true,
    );
  }

  @override
  Future<AppearanceTransport> presentationStatus({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  }) async => const AppearanceTransport(absent: true);
  @override
  Future<AppearanceTransport> sendPresentation({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  }) async {
    creates++;
    editions = 1;
    syncTick?.value++;
    return AppearanceTransport(
      receipt: AppearanceReceipt(
        shopId: shopId,
        key: key,
        kind: invoicePresentationKind,
        payload: Map<String, Object?>.from(body['p_payload'] as Map),
        actorId: userId,
        atUtc: '2026-10-20T10:00:00Z',
        replayed: false,
        edition: 1,
        operationId: brandOperation,
        contentSha256: 'ab' * 32,
        appearanceRevision: 0,
      ),
    );
  }

  @override
  Future<InvoicePresentationCopy> readPresentation({
    required String userId,
    required String shopId,
    required String operationId,
    required int edition,
  }) async {
    copyReads++;
    final source = await readBrandSource(
      userId: userId,
      shopId: shopId,
      operationId: operationId,
    );
    return InvoicePresentationCopy(
      shopId: shopId,
      operationId: operationId,
      edition: edition,
      contentSha256: source.contentSha256,
      contentMatches: !staleCopy,
      appearance: source.appearance,
      logoState: 'absent',
      renderVersion: 2,
      actorId: userId,
      createdAtUtc: '2026-10-20T10:00:00Z',
      createdAtShop: '2026-10-20T13:00:00',
      shopName: source.shopName,
      shopSequence: source.shopSequence,
      kind: source.kind,
      timeZone: source.timeZone,
      occurredAtUtc: source.occurredAtUtc,
      occurredAtShop: source.occurredAtShop,
      payload: source.payload,
      canWrite: true,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  for (final stale in [false, true]) {
    testWidgets(
      'direct PDF share uses a confirmed branded edition; stale=$stale',
      (t) async {
        final gateway = BrandShareGateway()..staleCopy = stale;
        var shares = 0;
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: InvoicePdfShareDialog(
                gateway: gateway,
                userId: completionUser,
                shopId: completionShop,
                operationId: brandOperation,
                canRead: () => true,
                canWrite: () => true,
                share: (bytes, name) async {
                  shares++;
                  expect(String.fromCharCodes(bytes.take(4)), '%PDF');
                  return true;
                },
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('invoice-pdf-share')));
        await t.pumpAndSettle();
        expect(gateway.creates, 1);
        expect(gateway.copyReads, 1);
        expect(shares, stale ? 0 : 1);
        if (!stale) {
          await t.tap(find.byKey(const Key('invoice-pdf-share')));
          await t.pumpAndSettle();
          expect(gateway.creates, 1);
          expect(shares, 2);
        } else {
          expect(
            find.byKey(const Key('invoice-pdf-legacy-share')),
            findsOneWidget,
          );
        }
      },
    );
  }

  testWidgets(
    'sync ticks and live fields after the sale never block sharing the image',
    (t) async {
      final tick = ValueNotifier<int>(0);
      final gateway = BrandShareGateway()..syncTick = tick;
      final names = <String>[];
      Uint8List? rasterInput;
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: InvoicePdfShareDialog(
              gateway: gateway,
              userId: completionUser,
              shopId: completionShop,
              operationId: brandOperation,
              canRead: () => true,
              canWrite: () => true,
              invalidations: tick,
              rasterize: (pdf) async {
                rasterInput = pdf;
                gateway.liveFields = {
                  'return_remainder': {'fully_returned': false},
                };
                return Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
              },
              share: (bytes, name) async {
                names.add(name);
                return true;
              },
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      tick.value++;
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('invoice-image-share')));
      await t.pumpAndSettle();
      expect(gateway.creates, 1);
      expect(String.fromCharCodes(rasterInput!.take(4)), '%PDF');
      expect(names.single, endsWith('.png'));
      expect(find.textContaining('تغيّرت'), findsNothing);
      expect(find.text('إرسال صورة عبر واتساب'), findsOneWidget);
      expect(find.byKey(const Key('invoice-pdf-share')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      tick.dispose();
    },
  );

  test('invoice fingerprint ignores live fields but not printed facts', () {
    final base = {...meetingInvoiceSource(), 'operation_id': brandOperation};
    final live = {
      ...base,
      'return_remainder': {'fully_returned': false},
      'returned_by_operation_id': null,
    };
    expect(invoiceFactsFingerprint(live), invoiceFactsFingerprint(base));
    final payload = Map<String, Object?>.from(base['payload'] as Map)
      ..['customer_name'] = 'اسم آخر';
    expect(
      invoiceFactsFingerprint({...base, 'payload': payload}),
      isNot(invoiceFactsFingerprint(base)),
    );
  });

  test('isolated yeh is printable while joined yeh is kept', () {
    expect(pdfArabic('نقدي'), 'نقدى');
    expect(pdfArabic('مهدي'), 'مهدى');
    expect(pdfArabic('علي'), 'علي');
    expect(pdfArabic('بيع'), 'بيع');
    expect(pdfArabic('يوم'), 'يوم');
    expect(pdfArabic('ي'), 'ى');
    expect(pdfArabic('ريال'), 'ريال');
  });

  test('karat weight totals are exact milligram sums', () {
    final document = BrandedInvoiceDocument.fromConfirmed(
      source: {
        'operation_id': brandOperation,
        'kind': 'sale',
        'shop_name': 'متجر',
        'shop_sequence': '1',
        'time_zone': 'Africa/Cairo',
        'occurred_at': '2026-10-17T08:00:00Z',
        'occurred_at_shop': '2026-10-17T10:00:00',
        'payload': {
          'total_piastres': '100',
          'items': [
            for (final (karat, mg) in [(21, '1830'), (18, '2560'), (21, '1')])
              {
                'item_name': 'صنف',
                'category': 'worked_jewelry',
                'karat': karat,
                'milligrams': mg,
                'count': '1',
              },
          ],
          'tenders': [
            {'method': 'cash', 'piastres': '100'},
          ],
        },
      },
      edition: 1,
      contentSha256: 'ab' * 32,
      appearanceRevision: 0,
      template: InvoiceTemplate.header,
      accent: InvoiceAccent.brown,
      renderVersion: 2,
      copyCreatedAtUtc: '2026-10-17T09:00:00Z',
      copyCreatedAtShop: '2026-10-17T11:00:00',
    );
    expect(
      [
        for (final row in document.weightByKarat)
          '${row.karat}:${row.gramsText}',
      ],
      ['21:1.831', '18:2.560'],
    );
    expect(document.totalGramsText, '4.391');
    expect(document.titleLabel, 'فاتورة بيع');
  });
}
