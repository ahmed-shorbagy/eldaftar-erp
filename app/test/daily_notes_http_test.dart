import 'dart:async';
import 'dart:convert';

import 'package:eldafttar/src/features/daily_ledger/application/ledger_activity.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/data/daily_ledger_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/daily_notes/application/notes_gateway.dart';
import 'package:eldafttar/src/features/daily_notes/data/note_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const shop = '22222222-2222-4222-8222-222222222222';
const day = '33333333-3333-4333-8333-333333333333';
const note = '66666666-6666-4666-8666-666666666666';
const objectId = '44444444-4444-4444-8444-444444444444';

HttpOpeningGateway gateway(http.Client client) => HttpOpeningGateway(
  client: client,
  supabaseUrl: 'https://example.test/',
  publishableKey: 'publishable-key',
  accessToken: () => 'access-token',
  currentUserId: () => 'owner-a',
);

Map<String, Object?> noteBody() => {
  'note_id': note,
  'operation_id': note,
  'shop_sequence': '4',
  'business_day_id': day,
  'text': 'ملاحظة',
  'actor_display_name': 'منى',
  'created_at': '2026-01-01T22:30:00+00:00',
  'occurred_at_shop': '2026-01-02T00:30:00',
  'attachment': null,
};

void main() {
  test('note command and page keep sequences as canonical strings', () {
    final command = parseNoteCommand({
      'ok': true,
      'note_id': note,
      'operation_id': note,
      'business_day_id': day,
      'shop_sequence': '4',
      'replayed': false,
    });
    expect((command as NoteCommitted).shopSequence, '4');
    expect(
      () => parseNoteCommand({
        'ok': true,
        'note_id': note,
        'operation_id': note,
        'business_day_id': day,
        'shop_sequence': '04',
        'replayed': false,
      }),
      throwsFormatException,
    );
    final page = parseDailyNotePage({
      'shop_id': shop,
      'day_id': day,
      'limit': 1,
      'has_more': false,
      'server_sequence': '4',
      'snapshot_sequence': '4',
      'next_before_sequence': null,
      'items': [noteBody()],
    }, expectedShopId: shop);
    expect(page.items.single.shopSequence, '4');
    expect(page.items.single.occurredAtShop, '2026-01-02T00:30:00');
    final wrongShop = noteBody();
    wrongShop['attachment'] = {
      'bucket': 'eldafttar-private-notes',
      'object_name': '99999999-9999-4999-8999-999999999999/$day/$objectId.jpg',
      'mime_type': 'image/jpeg',
      'byte_size': '4',
    };
    expect(
      () => parseDailyNote(wrongShop, expectedShopId: shop),
      throwsFormatException,
    );
  });

  test(
    'upload does not upsert and a signed URL is requested for five minutes',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.contains('/object/sign/')) {
          return http.Response(
            jsonEncode({
              'signedURL':
                  '/object/sign/eldafttar-private-notes/$shop/$day/$objectId.jpg?token=short',
            }),
            200,
          );
        }
        if (request.method == 'POST' &&
            request.url.path.contains('/storage/')) {
          return http.Response(
            '{}',
            request.headers['x-upsert'] == 'false' ? 200 : 500,
          );
        }
        return http.Response(jsonEncode({'status': 'absent'}), 200);
      });
      final api = gateway(client);
      final objectName = '$shop/$day/$objectId.jpg';
      final uploaded = await api.uploadNoteImage(
        callerUserId: 'owner-a',
        objectName: objectName,
        mimeType: 'image/jpeg',
        bytes: const [1, 2, 3, 4],
      );
      expect(uploaded.disposition, NoteUploadDisposition.stored);
      expect(requests.single.headers['x-upsert'], 'false');
      expect(requests.single.url.path, contains(objectName));
      final url = await api.noteReadUrl(
        callerUserId: 'owner-a',
        objectName: objectName,
      );
      final sign = requests.last;
      expect(jsonDecode(sign.body), {'expiresIn': 300});
      expect(url, contains('token=short'));
      expect(url, isNot(contains('service_role')));
    },
  );

  test('ledger page HTTP rejects both cursors before the request', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      return http.Response('{}', 200);
    });
    expect(
      () => gateway(client).operationPage(
        callerUserId: 'owner-a',
        shopId: shop,
        dayId: day,
        beforeSequence: '2',
        afterSequence: '4',
        limit: 100,
      ),
      throwsFormatException,
    );
    expect(calls, 0);
    expect(gateway(client), isA<LedgerFeedGateway>());
    expect(gateway(client), isA<NotesGateway>());
  });

  test(
    'a bounded summary feed still parses legacy rows and optional page metadata',
    () {
      final legacy = {
        'read_model_version': 2,
        'state': 'confirmed',
        'entitlement_status': 'active',
        'can_confirm': false,
        'business_day': {
          'id': day,
          'business_date': '2026-01-02',
          'opened_at': '2026-01-01T22:30:00Z',
        },
        'cash': [
          for (final method in const [
            ['cash', 'نقدي'],
            ['instant_transfer', 'انستا'],
            ['wallet', 'محفظة'],
            ['card', 'فيزا'],
          ])
            {
              'method': method[0],
              'label_ar': method[1],
              'piastres': '0',
              'pounds': '0.00',
            },
        ],
        'stock': <Object?>[],
        'scrap': <Object?>[],
        'feed': [
          {
            'kind': 'opening_balances',
            'label_ar': 'رصيد افتتاحي',
            'operation_id': note,
            'actor_display_name': 'منى',
            'occurred_at': '2026-01-01T22:30:00Z',
            'occurred_at_cairo': '2026-01-02T00:30:00',
          },
        ],
        'day_summary': {
          'sale_piastres': '5000',
          'purchase_piastres': '0',
          'expense_piastres': '0',
          'sale_count': 1,
          'purchase_count': 0,
          'expense_count': 0,
        },
        'feed_page': {
          'limit': 100,
          'has_more': true,
          'direction': 'desc',
          'next_before_sequence': '1',
          'server_sequence': '250',
          'snapshot_sequence': '250',
        },
      };
      final view = parseDailyLedger(legacy);
      expect(view.daySummary?.salePiastres, '5000');
      expect(view.feedCursor?.hasMore, isTrue);
      expect(view.feedCursor?.limit, 100);
      expect(view.feed.single.shopSequence, isNull);
    },
  );

  test(
    'a note mutation that finishes after the owner changes stays unknown',
    () async {
      var owner = 'owner-a';
      final started = Completer<void>();
      final release = Completer<void>();
      final client = MockClient((request) async {
        if (!started.isCompleted) started.complete();
        await release.future;
        if (request.url.path.contains('/storage/')) {
          return http.Response('{}', 200);
        }
        return http.Response(
          jsonEncode({
            'ok': true,
            'note_id': note,
            'operation_id': note,
            'business_day_id': day,
            'shop_sequence': '4',
            'replayed': false,
          }),
          200,
        );
      });
      final api = HttpOpeningGateway(
        client: client,
        supabaseUrl: 'https://example.test/',
        publishableKey: 'publishable-key',
        accessToken: () => 'access-token',
        currentUserId: () => owner,
      );
      final posted = api.postNote(
        callerUserId: 'owner-a',
        idempotencyKey: '11111111-1111-4111-8111-111111111111',
        payload: const {'version': 1, 'kind': 'daily_note'},
      );
      await started.future;
      owner = 'owner-b';
      release.complete();
      expect(await posted, isA<NoteUnknown>());
      final uploadStarted = Completer<void>();
      final uploadRelease = Completer<void>();
      final uploadClient = MockClient((request) async {
        uploadStarted.complete();
        await uploadRelease.future;
        return http.Response('{}', 200);
      });
      owner = 'owner-a';
      final uploads = HttpOpeningGateway(
        client: uploadClient,
        supabaseUrl: 'https://example.test/',
        publishableKey: 'publishable-key',
        accessToken: () => 'access-token',
        currentUserId: () => owner,
      );
      final uploaded = uploads.uploadNoteImage(
        callerUserId: 'owner-a',
        objectName: '$shop/$day/$objectId.jpg',
        mimeType: 'image/jpeg',
        bytes: const [1, 2, 3, 4],
      );
      await uploadStarted.future;
      owner = 'owner-b';
      uploadRelease.complete();
      final upload = await uploaded;
      expect(upload.disposition, NoteUploadDisposition.unknown);
      var calls = 0;
      final early = HttpOpeningGateway(
        client: MockClient((request) async {
          calls += 1;
          return http.Response('{}', 200);
        }),
        supabaseUrl: 'https://example.test/',
        publishableKey: 'publishable-key',
        accessToken: () => 'access-token',
        currentUserId: () => 'owner-b',
      );
      final rejected = await early.postNote(
        callerUserId: 'owner-a',
        idempotencyKey: '11111111-1111-4111-8111-111111111111',
        payload: const {'version': 1},
      );
      expect(rejected, isA<NoteRejected>());
      expect((rejected as NoteRejected).code, 'session_expired');
      expect(calls, 0);
    },
  );

  test(
    'a delayed note or feed read is not applied after the owner changes',
    () async {
      final started = Completer<void>();
      final release = Completer<void>();
      var owner = 'owner-a';
      final client = MockClient((request) async {
        if (!started.isCompleted) started.complete();
        await release.future;
        return http.Response(
          jsonEncode({
            'shop_id': shop,
            'day_id': day,
            'limit': 1,
            'has_more': false,
            'server_sequence': '4',
            'snapshot_sequence': '4',
            'items': [noteBody()],
            'status': 'completed',
            'note_id': note,
            'direction': 'desc',
            'next_before_sequence': null,
            'next_after_sequence': null,
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final api = HttpOpeningGateway(
        client: client,
        supabaseUrl: 'https://example.test/',
        publishableKey: 'publishable-key',
        accessToken: () => 'access-token',
        currentUserId: () => owner,
      );
      final listed = api.listNotes(
        callerUserId: 'owner-a',
        shopId: shop,
        dayId: day,
      );
      await started.future;
      owner = 'owner-b';
      release.complete();
      await expectLater(
        listed,
        throwsA(
          isA<NoteReadException>().having(
            (error) => error.code,
            'code',
            'session_expired',
          ),
        ),
      );
      owner = 'owner-a';
      final statusStarted = Completer<void>();
      final statusRelease = Completer<void>();
      final statusApi = HttpOpeningGateway(
        client: MockClient((request) async {
          statusStarted.complete();
          await statusRelease.future;
          return http.Response(
            jsonEncode({'status': 'completed', 'note_id': note}),
            200,
          );
        }),
        supabaseUrl: 'https://example.test/',
        publishableKey: 'publishable-key',
        accessToken: () => 'access-token',
        currentUserId: () => owner,
      );
      final status = statusApi.noteStatus(
        callerUserId: 'owner-a',
        idempotencyKey: '11111111-1111-4111-8111-111111111111',
      );
      await statusStarted.future;
      owner = 'owner-b';
      statusRelease.complete();
      expect(await status, isA<NoteStatusUnknown>());
      owner = 'owner-a';
      final pageStarted = Completer<void>();
      final pageRelease = Completer<void>();
      final pageApi = HttpOpeningGateway(
        client: MockClient((request) async {
          pageStarted.complete();
          await pageRelease.future;
          return http.Response(
            jsonEncode({
              'shop_id': shop,
              'day_id': day,
              'direction': 'asc',
              'limit': 1,
              'has_more': false,
              'server_sequence': '4',
              'snapshot_sequence': '4',
              'items': <Object?>[],
            }),
            200,
          );
        }),
        supabaseUrl: 'https://example.test/',
        publishableKey: 'publishable-key',
        accessToken: () => 'access-token',
        currentUserId: () => owner,
      );
      final page = pageApi.operationPage(
        callerUserId: 'owner-a',
        shopId: shop,
        dayId: day,
        beforeSequence: null,
        afterSequence: '1',
        limit: 1,
      );
      await pageStarted.future;
      owner = 'owner-b';
      pageRelease.complete();
      await expectLater(
        page,
        throwsA(
          isA<LedgerReadException>().having(
            (error) => error.code,
            'code',
            'session_expired',
          ),
        ),
      );
    },
  );

  test('a signed URL must match the configured origin and object path', () async {
    final objectName = '$shop/$day/$objectId.jpg';
    Future<HttpOpeningGateway> api(String signed) async {
      return HttpOpeningGateway(
        client: MockClient(
          (request) async =>
              http.Response(jsonEncode({'signedURL': signed}), 200),
        ),
        supabaseUrl: 'https://example.test/',
        publishableKey: 'publishable-key',
        accessToken: () => 'access-token',
        currentUserId: () => 'owner-a',
      );
    }

    await expectLater(
      api(
        'https://evil.example/storage/v1/object/sign/eldafttar-private-notes/$objectName?token=short',
      ).then(
        (gateway) => gateway.noteReadUrl(
          callerUserId: 'owner-a',
          objectName: objectName,
        ),
      ),
      throwsA(isA<NoteReadException>()),
    );
    await expectLater(
      api(
        'https://example.test/storage/v1/object/sign/other-bucket/$objectName?token=short',
      ).then(
        (gateway) => gateway.noteReadUrl(
          callerUserId: 'owner-a',
          objectName: objectName,
        ),
      ),
      throwsA(isA<NoteReadException>()),
    );
    final accepted = await api(
      'https://example.test/storage/v1/object/sign/eldafttar-private-notes/$objectName?token=short',
    );
    final url = await accepted.noteReadUrl(
      callerUserId: 'owner-a',
      objectName: objectName,
    );
    expect(url, startsWith('https://example.test/'));
    expect(url, contains('/eldafttar-private-notes/$objectName'));
    expect(url, contains('token=short'));
    expect(url, isNot(contains('evil')));
  });
}
