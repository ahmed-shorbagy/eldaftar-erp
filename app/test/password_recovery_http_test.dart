import 'dart:async';
import 'dart:convert';

import 'package:eldafttar/src/features/auth/data/recovery_session_storage.dart';
import 'package:eldafttar/src/features/auth/data/supabase_auth_gateway.dart';
import 'package:eldafttar/src/features/auth/domain/auth_gateway.dart';
import 'package:eldafttar/src/features/auth/domain/password_recovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const publishableKey = 'sb_publishable_auth_review_key';
const userId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';

class RecordedRequest {
  RecordedRequest(this.method, this.url, this.headers, this.body);
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String body;
}

class RecordingClient extends http.BaseClient {
  RecordingClient(this.onRequest);
  final Future<http.Response> Function(RecordedRequest request) onRequest;
  final recorded = <RecordedRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    final recordedRequest = RecordedRequest(
      request.method,
      request.url,
      Map<String, String>.from(request.headers),
      utf8.decode(bytes),
    );
    recorded.add(recordedRequest);
    final response = await onRequest(recordedRequest);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      request: request,
      headers: {
        'content-type': 'application/json; charset=utf-8',
        ...response.headers,
      },
      reasonPhrase: response.reasonPhrase,
    );
  }
}

class MemoryAuthStorage implements GotrueAsyncStorage {
  final values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => values[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    values.remove(key);
  }
}

class MemoryLocalStorage implements LocalStorage {
  String? raw;
  int removals = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() async => raw != null;

  @override
  Future<String?> accessToken() async => raw;

  @override
  Future<void> removePersistedSession() async {
    raw = null;
    removals++;
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    raw = persistSessionString;
  }
}

class RecoveryFake {
  RecoveryFake() {
    storage = MemoryAuthStorage();
    httpClient = RecordingClient(_handle);
    client = SupabaseClient(
      'http://127.0.0.1:9',
      publishableKey,
      httpClient: httpClient,
      authOptions: AuthClientOptions(
        autoRefreshToken: false,
        pkceAsyncStorage: storage,
      ),
    );
    gateway = SupabaseAuthGateway(client);
  }

  late final MemoryAuthStorage storage;
  late final RecordingClient httpClient;
  late final SupabaseClient client;
  late final SupabaseAuthGateway gateway;
  int recoverStatus = 200;
  Object recoverBody = '';
  int userStatus = 200;
  int logoutStatus = 204;
  bool throwOffline = false;
  Completer<void>? releaseRecover;

  Future<void> dispose() async {
    await client.dispose();
    httpClient.close();
  }

  Future<http.Response> _handle(RecordedRequest request) async {
    if (throwOffline) throw http.ClientException('offline');
    final path = request.url.path;
    if (path.endsWith('/recover')) {
      final release = releaseRecover;
      if (release != null) await release.future;
      return _json(recoverStatus, recoverBody);
    }
    if (path.endsWith('/token')) {
      expect(request.url.queryParameters['grant_type'], 'pkce');
      return _json(200, _session(recovery: true));
    }
    if (path.endsWith('/user')) {
      if (userStatus != 200) {
        return _json(userStatus, {
          'error_code': 'session_expired',
          'code': 'session_expired',
          'msg': 'expired',
        });
      }
      return _json(200, _session(recovery: true)['user']!);
    }
    if (path.endsWith('/logout')) {
      return http.Response('', logoutStatus);
    }
    return _json(500, {'error_code': 'unexpected', 'path': path});
  }

  http.Response _json(int status, Object body) {
    return http.Response(
      body is String ? body : jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
  }
}

Map<String, Object?> _session({required bool recovery}) {
  return {
    'access_token': _jwt(recovery: recovery),
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'refresh-test',
    'user': {
      'id': userId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'owner@example.test',
      'created_at': '2026-09-26T00:00:00.000Z',
    },
  };
}

String _jwt({required bool recovery}) {
  String part(String raw) =>
      base64Url.encode(utf8.encode(raw)).replaceAll('=', '');
  final exp =
      DateTime.now()
          .toUtc()
          .add(const Duration(hours: 2))
          .millisecondsSinceEpoch ~/
      1000;
  final method = recovery ? 'recovery' : 'password';
  return '${part('{"alg":"none","typ":"JWT"}')}.'
      '${part('{"exp":$exp,"sub":"$userId","role":"authenticated","amr":[{"method":"$method","timestamp":1}]}')}.'
      '${part('sig')}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recovery callback allow-list rejects every other redirect', () {
    expect(
      RecoveryCallback.allows(Uri.parse(RecoveryCallback.redirectUrl)),
      isTrue,
    );
    expect(
      RecoveryCallback.allows(
        Uri.parse('${RecoveryCallback.redirectUrl}?code=abc'),
      ),
      isTrue,
    );
    expect(
      RecoveryCallback.allows(
        Uri.parse('${RecoveryCallback.redirectUrl}#access_token=abc'),
      ),
      isTrue,
    );
    for (final rejected in [
      'https://evil.test/auth/recovery?code=abc',
      'eldafttar://evil/recovery?code=abc',
      'eldafttar://auth/other?code=abc',
      'eldafttar://auth:9/recovery?code=abc',
      'eldafttar://user@auth/recovery?code=abc',
      'eldafttar://auth/recovery/extra?code=abc',
    ]) {
      expect(
        RecoveryCallback.allows(Uri.parse(rejected)),
        isFalse,
        reason: rejected,
      );
    }
    expect(
      RecoverySessionClaims.accessTokenIsRecovery(_jwt(recovery: true)),
      isTrue,
    );
    expect(
      RecoverySessionClaims.accessTokenIsRecovery(_jwt(recovery: false)),
      isFalse,
    );
  });

  test('recovery sessions are not written to application storage', () async {
    final inner = MemoryLocalStorage()..raw = '{"access_token":"keep-me"}';
    final storage = RecoverySessionStorage(inner);
    final recovery = jsonEncode(_session(recovery: true));
    await storage.persistSession(recovery);
    expect(inner.raw, '{"access_token":"keep-me"}');
    inner.raw = recovery;
    expect(await storage.accessToken(), isNull);
    expect(inner.raw, isNull);
    expect(await storage.hasAccessToken(), isFalse);
    final normal = jsonEncode(_session(recovery: false));
    await storage.persistSession(normal);
    expect(await storage.accessToken(), normal);
  });

  group('Supabase recovery adapter', () {
    late RecoveryFake fake;

    setUp(() => fake = RecoveryFake());
    tearDown(() async => fake.dispose());

    test('known and unknown emails share one acknowledgement', () async {
      await fake.gateway.requestEmailReset('Owner@Example.TEST');
      fake.recoverStatus = 400;
      fake.recoverBody = {
        'error_code': 'user_not_found',
        'code': 'user_not_found',
        'msg': 'User not found',
      };
      await fake.gateway.requestEmailReset('missing@example.test');
      final recovers = fake.httpClient.recorded
          .where((request) => request.url.path.endsWith('/recover'))
          .toList();
      expect(recovers, hasLength(2));
      for (final request in recovers) {
        expect(
          request.url.queryParameters['redirect_to'],
          RecoveryCallback.redirectUrl,
        );
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.containsKey('password'), isFalse);
        expect(body.containsKey('phone'), isFalse);
        expect(request.body.toLowerCase(), isNot(contains('service_role')));
        final apiKey = request.headers.entries
            .where((entry) => entry.key.toLowerCase() == 'apikey')
            .map((entry) => entry.value)
            .single;
        expect(apiKey, publishableKey);
      }
      expect(
        (jsonDecode(recovers.first.body) as Map)['email'],
        'owner@example.test',
      );
      expect(
        (jsonDecode(recovers.last.body) as Map)['email'],
        'missing@example.test',
      );
      expect(fake.gateway.recoveryPending, isFalse);
      expect(fake.gateway.status, AuthStatus.signedOut);
    });

    test(
      'invalid email and transport failure do not invent an account',
      () async {
        await expectLater(
          () => fake.gateway.requestEmailReset('not-an-email'),
          throwsA(
            isA<RecoveryException>().having(
              (error) => error.failure,
              'failure',
              RecoveryFailure.invalidEmail,
            ),
          ),
        );
        expect(fake.httpClient.recorded, isEmpty);
        fake.recoverStatus = 429;
        fake.recoverBody = {
          'error_code': 'over_email_send_rate_limit',
          'msg': 'slow down',
        };
        await expectLater(
          () => fake.gateway.requestEmailReset('owner@example.test'),
          throwsA(
            isA<RecoveryException>().having(
              (error) => error.failure,
              'failure',
              RecoveryFailure.unavailable,
            ),
          ),
        );
        fake.throwOffline = true;
        await expectLater(
          () => fake.gateway.requestEmailReset('owner@example.test'),
          throwsA(
            isA<RecoveryException>().having(
              (error) => error.failure,
              'failure',
              RecoveryFailure.unavailable,
            ),
          ),
        );
      },
    );

    test('a second request waits on the in-flight mail', () async {
      fake.releaseRecover = Completer<void>();
      final first = fake.gateway.requestEmailReset('owner@example.test');
      await Future<void>.delayed(Duration.zero);
      final second = fake.gateway.requestEmailReset('owner@example.test');
      expect(
        fake.httpClient.recorded.where(
          (request) => request.url.path.endsWith('/recover'),
        ),
        hasLength(1),
      );
      fake.releaseRecover!.complete();
      await first;
      await second;
      expect(
        fake.httpClient.recorded.where(
          (request) => request.url.path.endsWith('/recover'),
        ),
        hasLength(1),
      );
    });

    test('untrusted and expired links do not create a shop session', () async {
      await expectLater(
        () => fake.gateway.acceptCallback(
          Uri.parse('https://evil.test/recovery?code=abc'),
        ),
        throwsA(
          isA<RecoveryException>().having(
            (error) => error.failure,
            'failure',
            RecoveryFailure.untrustedCallback,
          ),
        ),
      );
      expect(fake.httpClient.recorded, isEmpty);
      await expectLater(
        fake.gateway.acceptCallback(
          Uri.parse(
            '${RecoveryCallback.redirectUrl}?error=access_denied&error_code=otp_expired&error_description=expired',
          ),
        ),
        throwsA(
          isA<RecoveryException>().having(
            (error) => error.failure,
            'failure',
            RecoveryFailure.expiredOrInvalidLink,
          ),
        ),
      );
      expect(fake.client.auth.currentSession, isNull);
      expect(fake.gateway.recoveryPending, isFalse);
      expect(fake.gateway.status, AuthStatus.signedOut);
      expect(fake.gateway.linkFailure, RecoveryFailure.expiredOrInvalidLink);
    });

    test(
      'recovery link stays closed until the password is saved once',
      () async {
        await fake.gateway.requestEmailReset('owner@example.test');
        await fake.gateway.acceptCallback(
          Uri.parse('${RecoveryCallback.redirectUrl}?code=abc'),
        );
        expect(fake.gateway.recoveryPending, isTrue);
        expect(fake.gateway.status, AuthStatus.signedOut);
        await expectLater(
          () => fake.gateway.completeReset('short'),
          throwsA(
            isA<RecoveryException>().having(
              (error) => error.failure,
              'failure',
              RecoveryFailure.rejectedPassword,
            ),
          ),
        );
        await fake.gateway.completeReset('example-password');
        final updates = fake.httpClient.recorded
            .where(
              (request) =>
                  request.method == 'PUT' && request.url.path.endsWith('/user'),
            )
            .toList();
        expect(updates, hasLength(1));
        expect(
          (jsonDecode(updates.single.body) as Map)['password'],
          'example-password',
        );
        expect(fake.client.auth.currentSession, isNull);
        expect(fake.gateway.recoveryPending, isFalse);
        expect(fake.gateway.status, AuthStatus.signedOut);
        await expectLater(
          () => fake.gateway.completeReset('example-password'),
          throwsA(
            isA<RecoveryException>().having(
              (error) => error.failure,
              'failure',
              RecoveryFailure.missingRecoverySession,
            ),
          ),
        );
        expect(
          fake.httpClient.recorded.where(
            (request) =>
                request.method == 'PUT' && request.url.path.endsWith('/user'),
          ),
          hasLength(1),
        );
      },
    );

    test('expired and failed saves keep the shop closed', () async {
      await fake.gateway.requestEmailReset('owner@example.test');
      await fake.gateway.acceptCallback(
        Uri.parse('${RecoveryCallback.redirectUrl}?code=abc'),
      );
      fake.userStatus = 401;
      await expectLater(
        () => fake.gateway.completeReset('example-password'),
        throwsA(
          isA<RecoveryException>().having(
            (error) => error.failure,
            'failure',
            RecoveryFailure.expiredOrInvalidLink,
          ),
        ),
      );
      expect(fake.gateway.recoveryPending, isFalse);
      expect(fake.gateway.status, AuthStatus.signedOut);

      await fake.gateway.requestEmailReset('owner@example.test');
      await fake.gateway.acceptCallback(
        Uri.parse('${RecoveryCallback.redirectUrl}?code=again'),
      );
      fake.userStatus = 500;
      await expectLater(
        () => fake.gateway.completeReset('example-password'),
        throwsA(
          isA<RecoveryException>().having(
            (error) => error.failure,
            'failure',
            RecoveryFailure.unavailable,
          ),
        ),
      );
      expect(fake.gateway.recoveryPending, isTrue);
      expect(fake.gateway.status, AuthStatus.signedOut);
      fake.userStatus = 200;
      await fake.gateway.completeReset('example-password');
      expect(fake.gateway.recoveryPending, isFalse);
    });

    test('a restored recovery token cannot open the shop', () async {
      await fake.client.auth.setInitialSession(
        jsonEncode(_session(recovery: true)),
      );
      expect(fake.gateway.recoveryPending, isTrue);
      expect(fake.gateway.status, AuthStatus.signedOut);
      await fake.client.auth.signOut();
      await fake.client.auth.setInitialSession(
        jsonEncode(_session(recovery: false)),
      );
      expect(fake.gateway.recoveryPending, isFalse);
      expect(fake.gateway.status, AuthStatus.signedIn);
    });
  });
}
