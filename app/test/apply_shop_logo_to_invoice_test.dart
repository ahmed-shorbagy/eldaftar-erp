import 'dart:typed_data';

import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/apply_shop_logo_to_invoice.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/invoice_appearance_contract.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/invoice_appearance_gateway.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/logo_codec.dart';
import 'package:eldafttar/src/features/invoice_appearance/data/logo_upload_store.dart';
import 'package:eldafttar/src/features/invoice_appearance/domain/appearance_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _user = 'owner-1';
const _shop = 'shop-1';
const _asset = '11111111-1111-4111-8111-111111111111';

void main() {
  test('applies the logo and keeps the other appearance fields', () async {
    final gateway = _Gateway(
      _snapshot(
        const InvoiceAppearanceValue(
          revision: 4,
          template: InvoiceTemplate.compact,
          accent: InvoiceAccent.gold,
          slogan: 'عبارة المحل',
          address: 'شارع الذهب',
        ),
      ),
    );
    final logos = MemoryLogoUploadStore();
    final outcome = await ApplyShopLogoToInvoice(
      gateway: gateway,
      store: _Locker(),
      logoStore: logos,
    ).call(userId: _user, shopId: _shop, logoBytes: _png());
    expect(outcome, ApplyLogoOutcome.applied);
    expect(gateway.uploads, 1);
    expect(gateway.confirms, 1);
    expect(gateway.sends, 1);
    expect(logos.record, isNull);
    final payload = gateway.savedPayload!;
    expect(payload['slogan'], 'عبارة المحل');
    expect(payload['address'], 'شارع الذهب');
    expect(payload['template'], 'compact');
    expect(payload['accent'], 'gold');
    expect(payload['logo_asset_id'], _asset);
    expect(payload['expected_revision'], '4');
  });

  test('same logo sha is already applied and writes nothing', () async {
    final prepared = await prepareLogo(_png());
    final gateway = _Gateway(
      _snapshot(
        InvoiceAppearanceValue(
          revision: 2,
          template: InvoiceTemplate.header,
          accent: InvoiceAccent.brown,
          logoSha256: prepared.sha256,
          logoAssetId: _asset,
        ),
      ),
    );
    final outcome = await ApplyShopLogoToInvoice(
      gateway: gateway,
      store: _Locker(),
      logoStore: MemoryLogoUploadStore(),
    ).call(userId: _user, shopId: _shop, logoBytes: _png());
    expect(outcome, ApplyLogoOutcome.alreadyApplied);
    expect(gateway.uploads, 0);
    expect(gateway.confirms, 0);
    expect(gateway.reviews, 0);
    expect(gateway.sends, 0);
  });

  test('inactive entitlement is not allowed and writes nothing', () async {
    final gateway = _Gateway(
      _snapshot(InvoiceAppearanceValue.defaults, canWrite: false),
    );
    final outcome = await ApplyShopLogoToInvoice(
      gateway: gateway,
      store: _Locker(),
      logoStore: MemoryLogoUploadStore(),
    ).call(userId: _user, shopId: _shop, logoBytes: _png());
    expect(outcome, ApplyLogoOutcome.notAllowed);
    expect(gateway.uploads, 0);
    expect(gateway.sends, 0);
  });

  test('an unreachable server is reported as failed, never thrown', () async {
    final gateway = _Gateway(_snapshot(InvoiceAppearanceValue.defaults))
      ..throwReads = true;
    final outcome = await ApplyShopLogoToInvoice(
      gateway: gateway,
      store: _Locker(),
      logoStore: MemoryLogoUploadStore(),
    ).call(userId: _user, shopId: _shop, logoBytes: _png());
    expect(outcome, ApplyLogoOutcome.failed);
    expect(gateway.sends, 0);
  });

  test('a transport failure retries once with the same key', () async {
    final gateway = _Gateway(_snapshot(InvoiceAppearanceValue.defaults))
      ..throwSends = 1;
    final apply = ApplyShopLogoToInvoice(
      gateway: gateway,
      store: _Locker(),
      logoStore: MemoryLogoUploadStore(),
      newKey: () => '22222222-2222-4222-8222-222222222222',
    );
    final bytes = _png();
    expect(
      await apply.call(userId: _user, shopId: _shop, logoBytes: bytes),
      ApplyLogoOutcome.failed,
    );
    expect(
      await apply.call(userId: _user, shopId: _shop, logoBytes: bytes),
      ApplyLogoOutcome.applied,
    );
    expect(gateway.keys, [
      '22222222-2222-4222-8222-222222222222',
      '22222222-2222-4222-8222-222222222222',
    ]);
    expect(gateway.revisions, 1);
    expect(gateway.uploads, 1);
  });
}

InvoiceAppearanceSnapshot _snapshot(
  InvoiceAppearanceValue value, {
  bool canWrite = true,
}) => InvoiceAppearanceSnapshot(
  shopId: _shop,
  value: value,
  canWrite: canWrite,
  timeZone: 'Africa/Cairo',
);

Uint8List _png() {
  final image = img.Image(width: 8, height: 8);
  img.fill(image, color: img.ColorRgba8(148, 104, 31, 255));
  return Uint8List.fromList(img.encodePng(image));
}

final class _Locker implements FinancialCommandLocker {
  PendingFinancialCommand? command;

  @override
  Future<void> clear(String userId, String shopId, String key) async {
    if (command?.key == key) command = null;
  }

  @override
  Future<PendingFinancialCommand?> read(String userId, String shopId) async =>
      command;

  @override
  Future<void> save(
    String userId,
    String shopId,
    PendingFinancialCommand command,
  ) async {
    this.command = command;
  }
}

final class _Gateway implements InvoiceAppearanceGateway {
  _Gateway(this.snapshot);

  InvoiceAppearanceSnapshot snapshot;
  var uploads = 0;
  var confirms = 0;
  var reviews = 0;
  var sends = 0;
  var throwSends = 0;
  var throwReads = false;
  var revisions = 0;
  final keys = <String>[];
  Map<String, Object?>? savedPayload;
  final Object session = Object();

  @override
  Object? appearanceSession(String userId) => session;

  @override
  Future<InvoiceAppearanceSnapshot> readAppearance({
    required String userId,
    required String shopId,
  }) async {
    if (throwReads) throw StateError('offline');
    return snapshot;
  }

  @override
  Future<InvoiceAppearanceReview> reviewAppearance({
    required String userId,
    required String shopId,
    required Map<String, Object?> payload,
  }) async {
    reviews++;
    return InvoiceAppearanceReview(
      status: 'ready',
      currentRevision: snapshot.value.revision,
      canWrite: snapshot.canWrite,
    );
  }

  @override
  Future<AppearanceTransport> sendAppearance({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  }) async {
    sends++;
    keys.add(key);
    if (throwSends > 0) {
      throwSends--;
      throw StateError('transport');
    }
    revisions++;
    final payload = Map<String, Object?>.from(body['p_payload'] as Map);
    savedPayload = payload;
    return AppearanceTransport(
      receipt: AppearanceReceipt(
        shopId: shopId,
        key: key,
        kind: invoiceAppearanceKind,
        payload: payload,
        actorId: userId,
        atUtc: '2026-11-08T08:00:00.000000Z',
        replayed: false,
        revision: int.parse(payload['expected_revision'] as String) + 1,
      ),
    );
  }

  @override
  Future<AppearanceTransport> appearanceStatus({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  }) async => const AppearanceTransport(absent: true);

  @override
  Future<LogoUploadResult> uploadInvoiceLogo({
    required String userId,
    required String shopId,
    required String objectName,
    required String mimeType,
    required List<int> bytes,
  }) async {
    uploads++;
    return const LogoUploadResult(LogoUploadDisposition.stored);
  }

  @override
  Future<LogoConfirmation> confirmInvoiceLogo({
    required String userId,
    required String shopId,
    required String base64Bytes,
    required String sha256,
  }) async {
    confirms++;
    return LogoConfirmation(
      shopId: shopId,
      assetId: _asset,
      sha256: sha256,
      mime: 'image/png',
      width: 8,
      height: 8,
    );
  }

  @override
  Future<InvoiceBrandSource> readBrandSource({
    required String userId,
    required String shopId,
    required String operationId,
  }) => throw UnimplementedError();

  @override
  Future<AppearanceTransport> sendPresentation({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  }) => throw UnimplementedError();

  @override
  Future<AppearanceTransport> presentationStatus({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  }) => throw UnimplementedError();

  @override
  Future<InvoicePresentationList> listPresentations({
    required String userId,
    required String shopId,
    required String operationId,
  }) => throw UnimplementedError();

  @override
  Future<InvoicePresentationCopy> readPresentation({
    required String userId,
    required String shopId,
    required String operationId,
    required int edition,
  }) => throw UnimplementedError();
}
