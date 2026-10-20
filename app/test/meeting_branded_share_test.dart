import 'package:eldafttar/src/features/daily_ledger/presentation/invoice_pdf_share_dialog.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/invoice_appearance_contract.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/invoice_appearance_gateway.dart';
import 'package:eldafttar/src/features/invoice_appearance/domain/appearance_rules.dart';
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
}
