import 'dart:convert';
import 'dart:typed_data';

import 'package:eldafttar/src/features/daily_ledger/application/confirmed_operation_pdf.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/branded_invoice_pdf.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/invoice_appearance_contract.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/invoice_appearance_flow.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/invoice_appearance_gateway.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/logo_codec.dart';
import 'package:eldafttar/src/features/invoice_appearance/domain/appearance_rules.dart';
import 'package:eldafttar/src/features/invoice_appearance/domain/branded_invoice_document.dart';
import 'package:eldafttar/src/features/invoice_appearance/domain/logo_bytes.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_sync.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

const _user = 'a1111111-1111-4111-8111-111111111111';
const _shop = 'a1222222-2222-4222-8222-222222222222';
const _key = 'a1555555-5555-4555-8555-555555555555';
const _operation = 'a1333333-3333-4333-8333-333333333333';
const _png =
    '89504e470d0a1a0a0000000d494844520000000200000002080600000072b60d240000001a49444154789c63e1129163909393fbcf626363d3b07bd3ca930020e105b1e1ef98ad0000000049454e44ae426082';
const _jpeg = 'ffd8ffc0000b080001000101011100ffda0008010100003f0000ffd9';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test('defaults and optional text stay exact', () {
    expect(InvoiceAppearanceValue.defaults.revision, 0);
    expect(InvoiceAppearanceValue.defaults.template, InvoiceTemplate.header);
    expect(InvoiceAppearanceValue.defaults.accent, InvoiceAccent.brown);
    expect(InvoiceAppearanceValue.defaults.slogan, isNull);
    expect(normalizeSlogan('  ذهب أمين  '), 'ذهب أمين');
    expect(normalizeSlogan('   '), isNull);
    expect(normalizeAddress('سطر\nثان'), 'سطر\nثان');
    expect(normalizeSlogan('سطر\nممنوع'), 'سطر\nممنوع');
    expect(() => normalizeSlogan('تحكم\u0001'), throwsFormatException);
    expect(() => normalizeSlogan('ا' * 121), throwsFormatException);
    expect(() => normalizeAddress('ا\nب\nج\nد\nه'), throwsFormatException);
    expect(normalizeAddress('ا' * 200), 'ا' * 200);
    for (final template in InvoiceTemplate.values) {
      expect(InvoiceTemplate.parse(template.wire), template);
    }
    for (final accent in InvoiceAccent.values) {
      expect(InvoiceAccent.parse(accent.wire), accent);
      expect(InvoiceDocumentPalette.accent(accent), isNonZero);
    }
    expect(InvoiceDocumentPalette.paper, 0xFFFFFBF5);
    final cleared = InvoiceAppearanceValue.defaults
        .copyWith(
          slogan: 'نص',
          address: 'عنوان',
          logoAssetId: _operation,
          logoSha256: 'ab' * 32,
        )
        .copyWith(clearSlogan: true, clearAddress: true, clearLogo: true);
    expect(cleared.slogan, isNull);
    expect(cleared.address, isNull);
    expect(cleared.logoAssetId, isNull);
  });

  test(
    'logo inspection rejects hostile bytes and keeps a real image',
    () async {
      final png = _hex(_png);
      final jpeg = _hex(_jpeg);
      expect(inspectLogoBytes(png).width, 2);
      expect(inspectLogoBytes(jpeg).mime, 'image/jpeg');
      expect(
        () => inspectLogoBytes(Uint8List(0)),
        throwsA(
          isA<LogoByteRejection>().having(
            (error) => error.code,
            'code',
            'image_too_large',
          ),
        ),
      );
      expect(
        () => inspectLogoBytes(Uint8List(logoMaxBytes + 1)),
        throwsA(
          isA<LogoByteRejection>().having(
            (error) => error.code,
            'code',
            'image_too_large',
          ),
        ),
      );
      expect(
        () => inspectLogoBytes(Uint8List.fromList([0x47, 0x49, 0x46, 0x38])),
        throwsA(
          isA<LogoByteRejection>().having(
            (error) => error.code,
            'code',
            'logo_rejected',
          ),
        ),
      );
      expect(
        () => inspectLogoSource(Uint8List.fromList('<html>'.codeUnits)),
        throwsA(isA<LogoByteRejection>()),
      );
      final wide = Uint8List.fromList(png);
      wide[16] = 0;
      wide[17] = 0;
      wide[18] = 0x08;
      wide[19] = 0x01;
      expect(() => inspectLogoSource(wide), throwsA(isA<LogoByteRejection>()));
      final textChunk = _pngWithChunk(png, 'tEXt', [0x41, 0, 0x62]);
      expect(inspectLogoSource(textChunk).mime, 'image/png');
      expect(
        () => inspectLogoBytes(textChunk),
        throwsA(isA<LogoByteRejection>()),
      );
      final animation = _pngWithChunk(png, 'acTL', [0, 0, 0, 2, 0, 0, 0, 0]);
      expect(
        () => inspectLogoSource(animation),
        throwsA(isA<LogoByteRejection>()),
      );
      final picture = img.Image(width: 2, height: 2);
      img.fill(picture, color: img.ColorRgba8(1, 2, 3, 255));
      final encodedJpeg = Uint8List.fromList(
        img.encodeJpg(picture, quality: 90),
      );
      final exif = Uint8List.fromList([
        0xFF,
        0xD8,
        0xFF,
        0xE1,
        0x00,
        0x08,
        0x45,
        0x78,
        0x69,
        0x66,
        0x00,
        0x00,
        ...encodedJpeg.sublist(2),
      ]);
      expect(inspectLogoSource(exif).mime, 'image/jpeg');
      expect(() => inspectLogoBytes(exif), throwsA(isA<LogoByteRejection>()));

      final prepared = await prepareLogo(textChunk);
      expect(inspectLogoBytes(prepared.bytes).mime, 'image/png');
      expect(prepared.sha256, hasLength(64));
      expect(() => inspectLogoBytes(prepared.bytes), returnsNormally);
      final preparedJpeg = await prepareLogo(exif);
      expect(inspectLogoBytes(preparedJpeg.bytes).mime, 'image/jpeg');
    },
  );

  test(
    'branded document keeps source fields and rejects a broken line',
    () async {
      final document = BrandedInvoiceDocument.fromConfirmed(
        source: _source(kind: 'purchase'),
        edition: 1,
        contentSha256: 'ab' * 32,
        appearanceRevision: 3,
        template: InvoiceTemplate.compact,
        accent: InvoiceAccent.gold,
        renderVersion: 1,
        copyCreatedAtUtc: '2026-10-17T10:00:00.000000Z',
        copyCreatedAtShop: '2026-10-17T12:00:00',
        slogan: 'ذهب أمين',
      );
      expect(document.lines.single.categoryLabel, 'مشغولات');
      expect(document.lines.single.gramsText, '1.830');
      expect(document.lines.single.karat, 18);
      expect(document.purchasePaidPiastres, '104002');
      expect(document.obligationPiastres, '8000');
      expect(document.pricing, isNull);
      expect(document.tenders.map((item) => item.piastres), ['50000', '54002']);
      final broken = _source();
      (broken['payload'] as Map)['items'] = [
        {'item_name': 'ناقص'},
      ];
      expect(
        () => BrandedInvoiceDocument.fromConfirmed(
          source: broken,
          edition: 1,
          contentSha256: 'ab' * 32,
          appearanceRevision: 0,
          template: InvoiceTemplate.header,
          accent: InvoiceAccent.brown,
          renderVersion: 1,
          copyCreatedAtUtc: '2026-10-17T10:00:00.000000Z',
          copyCreatedAtShop: '2026-10-17T12:00:00',
        ),
        throwsFormatException,
      );
      final legacy = Map<String, Object?>.from(_source());
      (legacy['payload'] as Map)['items'] = ['ليس سطراً'];
      expect(
        String.fromCharCodes(
          (await buildConfirmedOperationPdf(legacy)).take(4),
        ),
        '%PDF',
      );
      for (final template in InvoiceTemplate.values) {
        for (final accent in InvoiceAccent.values) {
          final bytes = await buildBrandedInvoicePdf(
            BrandedInvoiceDocument.fromConfirmed(
              source: _source(),
              edition: 1,
              contentSha256: 'cd' * 32,
              appearanceRevision: 1,
              template: template,
              accent: accent,
              renderVersion: 1,
              copyCreatedAtUtc: '2026-10-17T10:00:00.000000Z',
              copyCreatedAtShop: '2026-10-17T12:00:00',
            ),
          );
          expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        }
      }
      expect(
        () => buildBrandedInvoicePdf(
          BrandedInvoiceDocument.fromConfirmed(
            source: _source(),
            edition: 1,
            contentSha256: 'cd' * 32,
            appearanceRevision: 1,
            template: InvoiceTemplate.header,
            accent: InvoiceAccent.neutral,
            renderVersion: 1,
            copyCreatedAtUtc: '2026-10-17T10:00:00.000000Z',
            copyCreatedAtShop: '2026-10-17T12:00:00',
            logoAssetId: _operation,
            logoSha256: 'ab' * 32,
            logoRequired: true,
          ),
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'logo_unverified',
          ),
        ),
      );
    },
  );

  test(
    'appearance and presentation commands use the original envelope',
    () async {
      final appearance = appearanceCommandPayload(
        expectedRevision: 2,
        template: InvoiceTemplate.compact,
        accent: InvoiceAccent.gold,
        slogan: ' ذهب ',
        address: '',
      );
      expect(appearance['slogan'], 'ذهب');
      expect(appearance['address'], isNull);
      expect(appearance.length, 8);
      final body = {'p_idempotency_key': _key, 'p_payload': appearance};
      expect(
        matchesInvoiceAppearanceEnvelope(_key, invoiceAppearanceKind, body),
        isTrue,
      );
      final presentation = presentationCommandPayload(
        operationId: _operation,
        contentSha256: 'ab' * 32,
        expectedAppearanceRevision: 3,
        expectedLatestEdition: 0,
      );
      expect(presentation.length, 6);
      final store = _MemoryLocker();
      final gateway = _Gateway();
      final flow = InvoiceAppearanceFlow(gateway, store);
      final blocked = await flow.submitAppearance(
        _user,
        _shop,
        _key,
        appearance,
        canWrite: false,
      );
      expect(blocked.error, 'shop_not_active');
      expect(store.command, isNull);
      gateway.send = const AppearanceTransport();
      gateway.statusResult = const AppearanceTransport(absent: true);
      final unknown = await flow.submitAppearance(
        _user,
        _shop,
        _key,
        appearance,
        canWrite: true,
      );
      expect(unknown.pending?.key, _key);
      expect(unknown.receipt, isNull);
      expect(
        canonicalInvoiceJson(unknown.pending!.body['p_payload']),
        canonicalInvoiceJson(appearance),
      );
      gateway.replacement = Object();
      final late = await flow.reconcile(
        _user,
        _shop,
        unknown.pending!,
        retry: true,
        canWrite: true,
      );
      expect(late.error, 'discarded');
      expect(store.command?.key, _key);
      store.command = const PendingFinancialCommand(
        key: _operation,
        kind: 'sale',
        body: {'p_idempotency_key': _operation},
      );
      final foreign = await flow.submitAppearance(
        _user,
        _shop,
        _key,
        appearance,
        canWrite: true,
      );
      expect(foreign.error, 'other_pending');
      expect(store.command?.kind, 'sale');
      expect(
        ShopSyncSnapshot(
          shopId: _shop,
          revision: 1,
          ledgerRevision: 1,
          inventoryRevision: 0,
          traderRevision: 0,
          invoiceRevision: 0,
          dayRevision: 0,
          locationRevision: 0,
          subscriptionRevision: 0,
          repairRevision: 0,
          debtRevision: 0,
          customerRevision: 0,
        ).appearanceRevision,
        0,
      );
    },
  );

  test(
    'the locker keeps invoice commands and refuses to replace another kind',
    () async {
      const store = PendingFinancialCommands();
      final appearance = PendingFinancialCommand(
        key: _key,
        kind: invoiceAppearanceKind,
        body: {
          'p_idempotency_key': _key,
          'p_payload': appearanceCommandPayload(
            expectedRevision: 0,
            template: InvoiceTemplate.header,
            accent: InvoiceAccent.brown,
          ),
        },
      );
      await store.save(_user, _shop, appearance);
      final restored = await store.read(_user, _shop);
      expect(restored?.kind, invoiceAppearanceKind);
      expect(restored?.body, appearance.body);
      expect(
        store.save(
          _user,
          _shop,
          PendingFinancialCommand(
            key: _operation,
            kind: invoicePresentationKind,
            body: {
              'p_idempotency_key': _operation,
              'p_payload': presentationCommandPayload(
                operationId: _operation,
                contentSha256: 'ab' * 32,
                expectedAppearanceRevision: 0,
                expectedLatestEdition: 0,
              ),
            },
          ),
        ),
        throwsStateError,
      );
      expect((await store.read(_user, _shop))?.kind, invoiceAppearanceKind);
      final storage = const FlutterSecureStorage();
      await storage.write(
        key: 'pending_financial_${_user}_$_shop',
        value: jsonEncode({
          'key': _key,
          'kind': 'not_a_command',
          'body': {'p_idempotency_key': _key},
        }),
      );
      expect(
        PendingFinancialCommands(storage: storage).read(_user, _shop),
        throwsFormatException,
      );
      expect(
        PendingFinancialCommands(
          storage: storage,
        ).save(_user, _shop, appearance),
        throwsFormatException,
      );
      final raw = await storage.read(key: 'pending_financial_${_user}_$_shop');
      expect(raw, contains('not_a_command'));
    },
  );
}

Map<String, Object?> _source({String kind = 'sale'}) => {
  'operation_id': _operation,
  'kind': kind,
  'shop_name': 'متجر المعاينة',
  'shop_sequence': '44',
  'time_zone': 'Africa/Cairo',
  'occurred_at': '2026-10-17T08:00:00.000000Z',
  'occurred_at_shop': '2026-10-17T10:00:00',
  'payload': {
    'total_piastres': '104002',
    'customer_name': 'طرف معاينة',
    'items': [
      {
        'item_name': 'خاتم',
        'category': 'worked_jewelry',
        'karat': 18,
        'milligrams': '1830',
        'count': '1',
        'line_price_piastres': null,
      },
    ],
    'tenders': [
      {'method': 'cash', 'piastres': '50000'},
      {'method': 'card', 'piastres': '54002'},
    ],
    if (kind == 'purchase') 'purchase_obligation_piastres': '8000',
    if (kind == 'purchase') 'purchase_payable_remaining_piastres': '1',
  },
};

Uint8List _hex(String value) {
  final out = Uint8List(value.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(value.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

Uint8List _pngWithChunk(Uint8List png, String type, List<int> data) {
  final chunk = BytesBuilder();
  final length = ByteData(4)..setUint32(0, data.length);
  chunk.add(length.buffer.asUint8List());
  chunk.add(type.codeUnits);
  chunk.add(data);
  chunk.add([0, 0, 0, 0]);
  final end = png.length - 12;
  return Uint8List.fromList([
    ...png.sublist(0, end),
    ...chunk.toBytes(),
    ...png.sublist(end),
  ]);
}

final class _MemoryLocker implements FinancialCommandLocker {
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
    final current = this.command;
    if (current != null && current.key != command.key) {
      throw StateError('pending_financial_exists');
    }
    this.command = command;
  }
}

final class _Gateway implements InvoiceAppearanceGateway {
  Object? session = Object();
  Object? replacement;
  AppearanceTransport send = const AppearanceTransport();
  AppearanceTransport statusResult = const AppearanceTransport(absent: true);
  var sends = 0;

  @override
  Object? appearanceSession(String userId) => session;

  @override
  Future<AppearanceTransport> sendAppearance({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  }) async {
    sends++;
    return send;
  }

  @override
  Future<AppearanceTransport> appearanceStatus({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  }) async {
    if (replacement != null) session = replacement;
    return statusResult;
  }

  @override
  Future<InvoiceAppearanceSnapshot> readAppearance({
    required String userId,
    required String shopId,
  }) => throw UnimplementedError();

  @override
  Future<InvoiceAppearanceReview> reviewAppearance({
    required String userId,
    required String shopId,
    required Map<String, Object?> payload,
  }) => throw UnimplementedError();

  @override
  Future<LogoUploadResult> uploadInvoiceLogo({
    required String userId,
    required String shopId,
    required String objectName,
    required String mimeType,
    required List<int> bytes,
  }) => throw UnimplementedError();

  @override
  Future<LogoConfirmation> confirmInvoiceLogo({
    required String userId,
    required String shopId,
    required String base64Bytes,
    required String sha256,
  }) => throw UnimplementedError();

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
  }) async => send;

  @override
  Future<AppearanceTransport> presentationStatus({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  }) async => statusResult;

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
