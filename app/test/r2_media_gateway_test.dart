import 'dart:convert';

import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/daily_notes/application/notes_gateway.dart';
import 'package:eldafttar/src/features/daily_notes/data/note_codec.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/invoice_appearance_gateway.dart';
import 'package:eldafttar/src/features/media/data/r2_media_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const shop = '22222222-2222-4222-8222-222222222222';
const day = '33333333-3333-4333-8333-333333333333';
const operation = '55555555-5555-4555-8555-555555555555';
const asset = '77777777-7777-4777-8777-777777777777';
const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 1, 2, 3, 4];

HttpOpeningGateway gateway(http.Client client) => HttpOpeningGateway(
  client: client,
  supabaseUrl: 'https://example.test/',
  publishableKey: 'publishable-key',
  accessToken: () => 'access-token',
  currentUserId: () => 'owner-a',
);

Map<String, Object?> presentation({
  required String logoSha,
  String? objectKey,
}) => {
  'version': 1,
  'shop_id': shop,
  'operation_id': operation,
  'edition': '2',
  'content_sha256': 'c' * 64,
  'content_matches': true,
  'appearance_revision': '2',
  'template': 'header',
  'accent': 'brown',
  'slogan': null,
  'address': null,
  'logo_asset_id': asset,
  'logo_sha256': logoSha,
  'logo_state': 'verified',
  'logo_bytes': null,
  'logo_object_key': objectKey,
  'render_version': 2,
  'actor_user_id': 'owner-a',
  'created_at': '2026-10-20T10:00:00.000000Z',
  'created_at_shop': '2026-10-20T13:00:00',
  'shop_name': 'متجر',
  'shop_sequence': '9',
  'kind': 'sale',
  'time_zone': 'Africa/Cairo',
  'occurred_at': '2026-10-20T10:00:00Z',
  'occurred_at_shop': '2026-10-20T13:00:00',
  'payload': <String, Object?>{},
  'can_write': true,
};

void main() {
  test('invoice logos upload to R2 and confirm by object key', () async {
    final sha = await R2MediaClient.sha256Hex(png);
    final key = 'invoice-logo/$shop/$sha.png';
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.host == 'r2.example') return http.Response('', 200);
      if (request.url.path == '/rest/v1/rpc/confirm_invoice_logo_v2') {
        return http.Response(
          jsonEncode({
            'version': 1,
            'shop_id': shop,
            'asset_id': asset,
            'sha256': sha,
            'mime': 'image/png',
            'width': 2,
            'height': 2,
            'byte_size': png.length,
            'confirmed': true,
            'replayed': false,
            'cash_piastres': '0',
            'gold_milligrams': '0',
            'stock_milligrams': '0',
            'invoice_effect': false,
            'dispatch_effect': false,
          }),
          200,
        );
      }
      final body = jsonDecode(request.body) as Map<String, Object?>;
      expect(body['kind'], 'invoice_logo');
      return switch (body['op']) {
        'upload' => http.Response(
          jsonEncode({
            'object_key': 'invoice-logo/$shop/${body['sha256']}.png',
            'url': 'https://r2.example/bucket/$key?X-Amz-Signature=s',
            'headers': {'content-type': 'image/png'},
          }),
          200,
        ),
        _ => http.Response(
          jsonEncode({
            'object_key': body['object_key'],
            'sha256': sha,
            'byte_size': png.length,
            'replayed': false,
          }),
          200,
        ),
      };
    });
    final api = gateway(client);
    final uploaded = await api.uploadInvoiceLogo(
      userId: 'owner-a',
      shopId: shop,
      objectName: '$shop/$sha.png',
      mimeType: 'image/png',
      bytes: png,
    );
    expect(uploaded.disposition, LogoUploadDisposition.stored);
    expect(requests[1].method, 'PUT');
    expect(jsonDecode(requests[2].body)['op'], 'confirm');
    final confirmed = await api.confirmInvoiceLogo(
      userId: 'owner-a',
      shopId: shop,
      base64Bytes: base64Encode(png),
      sha256: sha,
    );
    expect(confirmed.assetId, asset);
    expect(jsonDecode(requests.last.body), {'p_object_key': key});
    expect(
      requests.any(
        (r) =>
            r.url.path.contains('/storage/') ||
            r.url.path.endsWith('confirm_invoice_logo_v1'),
      ),
      isFalse,
      reason: 'new logos must not use Supabase Storage or inline bytes',
    );
  });

  test('a branded copy downloads its R2 logo and checks the hash', () async {
    final sha = await R2MediaClient.sha256Hex(png);
    final key = 'invoice-logo/$shop/$sha.png';
    var served = png;
    final client = MockClient((request) async {
      if (request.url.host == 'r2.example') {
        return http.Response.bytes(served, 200);
      }
      if (request.url.path == '/rest/v1/rpc/get_invoice_presentation_v1') {
        return http.Response(
          jsonEncode(presentation(logoSha: sha, objectKey: key)),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(
        jsonEncode({'url': 'https://r2.example/bucket/$key?sig=r'}),
        200,
      );
    });
    final api = gateway(client);
    final copy = await api.readPresentation(
      userId: 'owner-a',
      shopId: shop,
      operationId: operation,
      edition: 2,
    );
    expect(copy.logoState, 'verified');
    expect(copy.logoBytes, png);

    served = [...png, 9];
    final tampered = await api.readPresentation(
      userId: 'owner-a',
      shopId: shop,
      operationId: operation,
      edition: 2,
    );
    expect(tampered.logoState, 'unverified');
    expect(tampered.logoBytes, isNull);
  });

  test('note attachments in R2 and in the legacy bucket both parse', () {
    for (final bucket in [noteR2Bucket, noteLegacyBucket]) {
      final note = parseDailyNote({
        'note_id': operation,
        'operation_id': operation,
        'shop_sequence': '4',
        'business_day_id': day,
        'text': '',
        'actor_display_name': 'منى',
        'created_at': '2026-01-01T22:30:00+00:00',
        'occurred_at_shop': '2026-01-02T00:30:00',
        'attachment': {
          'bucket': bucket,
          'object_name': '$shop/$day/$asset.jpg',
          'mime_type': 'image/jpeg',
          'byte_size': '4',
        },
      }, expectedShopId: shop);
      expect(note.attachment?.bucket, bucket);
    }
  });
}
