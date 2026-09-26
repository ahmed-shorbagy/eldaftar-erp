import 'dart:async';
import 'dart:convert';

import 'package:eldafttar/src/features/auth/data/supabase_auth_gateway.dart';
import 'package:eldafttar/src/features/auth/domain/auth_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
// The app does not call HTTP itself; this fake is the Supabase client's transport.
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const publishableKey = 'sb_publishable_auth_review_key';
const userId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const shopId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const otherUserId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

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

class FakeSupabase {
  FakeSupabase() {
    httpClient = RecordingClient(_handle);
    client = SupabaseClient(
      'http://127.0.0.1:9',
      publishableKey,
      httpClient: httpClient,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      postgrestOptions: const PostgrestClientOptions(retryEnabled: false),
    );
    gateway = SupabaseAuthGateway(client);
  }

  late final RecordingClient httpClient;
  late final SupabaseClient client;
  late final SupabaseAuthGateway gateway;
  int registerStatus = 200;
  Object registerBody = {
    'status': 'completed',
    'user_id': userId,
    'shop_id': shopId,
  };
  String tokenUserId = userId;
  int governorateStatus = 200;
  Object governorateBody = [
    {'code': 'EG-GZ', 'name_ar': 'الجيزة'},
    {'code': 'EG-C', 'name_ar': 'القاهرة'},
  ];
  Completer<void>? releaseToken;

  Future<void> dispose() async {
    await client.dispose();
    httpClient.close();
  }

  Future<http.Response> _handle(RecordedRequest request) async {
    final path = request.url.path;
    if (path.endsWith('/owner-register')) {
      return _json(registerStatus, registerBody);
    }
    if (path.endsWith('/token')) {
      final release = releaseToken;
      if (release != null) await release.future;
      expect(request.url.queryParameters['grant_type'], 'password');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (body['password'] != 'example-password') {
        return _json(400, {
          'error': 'invalid_grant',
          'error_description': 'Invalid login credentials',
        });
      }
      final email = body['email'];
      final phone = body['phone'];
      if (email != null) expect(email, 'owner@example.test');
      if (phone != null) expect(phone, '+201012345678');
      return _json(200, _session(tokenUserId));
    }
    if (path.endsWith('/logout')) return http.Response('', 204);
    if (path.contains('/egypt_governorates')) {
      return _json(governorateStatus, governorateBody);
    }
    return _json(500, {'error': 'unexpected', 'path': path});
  }

  http.Response _json(int status, Object body) {
    return http.Response(
      body is String ? body : jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );
  }
}

Map<String, Object?> _session(String id) {
  return {
    'access_token': _jwt(id),
    'token_type': 'bearer',
    'expires_in': 3600,
    'refresh_token': 'refresh-test',
    'user': {
      'id': id,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'owner@example.test',
      'phone': '201012345678',
      'app_metadata': {'provider': 'email'},
      'user_metadata': <String, Object?>{},
      'created_at': '2026-09-26T00:00:00.000Z',
    },
  };
}

String _jwt(String id) {
  String part(String raw) =>
      base64Url.encode(utf8.encode(raw)).replaceAll('=', '');
  final exp =
      DateTime.now()
          .toUtc()
          .add(const Duration(hours: 2))
          .millisecondsSinceEpoch ~/
      1000;
  return '${part('{"alg":"none","typ":"JWT"}')}.'
      '${part('{"exp":$exp,"sub":"$id","role":"authenticated"}')}.'
      '${part('sig')}';
}

void expectNoPrivilegedCalls(List<RecordedRequest> recorded) {
  const forbidden = [
    'otp',
    'verify',
    'signup',
    'magiclink',
    'recover',
    'invite',
    '/admin',
  ];
  expect(recorded, isNotEmpty);
  for (final request in recorded) {
    final path = request.url.path.toLowerCase();
    for (final piece in forbidden) {
      expect(path, isNot(contains(piece)), reason: request.url.toString());
    }
    final headerText = request.headers.entries
        .map((entry) => '${entry.key}:${entry.value}')
        .join('\n')
        .toLowerCase();
    expect(headerText, isNot(contains('sb_secret_')));
    expect(headerText, isNot(contains('service_role')));
    expect(request.body.toLowerCase(), isNot(contains('service_role')));
    final apiKey = request.headers.entries
        .where((entry) => entry.key.toLowerCase() == 'apikey')
        .map((entry) => entry.value)
        .single;
    expect(apiKey, publishableKey);
  }
}

OwnerRegistration sampleRegistration() {
  return OwnerRegistration.tryCreate(
    idempotencyKey: '11111111-1111-4111-8111-111111111111',
    ownerName: 'منى حسن',
    businessName: 'ذهب الجيزة',
    email: 'Owner@Example.TEST',
    phone: '(010) 1234-5678',
    governorateCode: 'EG-GZ',
    password: 'example-password',
  )!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSupabase fake;

  setUp(() => fake = FakeSupabase());
  tearDown(() async {
    if (fake.releaseToken != null && !fake.releaseToken!.isCompleted) {
      fake.releaseToken!.complete();
    }
    try {
      if (fake.httpClient.recorded.isNotEmpty) {
        expectNoPrivilegedCalls(fake.httpClient.recorded);
      }
    } finally {
      await fake.dispose();
    }
  });

  test('email and phone passwords resolve to the same user id', () async {
    await fake.gateway.signIn(
      SignInRequest.tryCreate(
        kind: SignInIdentifier.email,
        identifier: 'Owner@Example.TEST',
        password: 'example-password',
      )!,
    );
    expect(fake.client.auth.currentUser!.id, userId);
    expect(fake.gateway.status, AuthStatus.signedIn);
    await fake.gateway.signOut();
    expect(fake.gateway.status, AuthStatus.signedOut);
    await fake.gateway.signIn(
      SignInRequest.tryCreate(
        kind: SignInIdentifier.phone,
        identifier: '010 1234 5678',
        password: 'example-password',
      )!,
    );
    expect(fake.client.auth.currentUser!.id, userId);
    expect(fake.gateway.status, AuthStatus.signedIn);
  });

  test('wrong passwords fail the same way for both identifiers', () async {
    Future<SignInFailure> rejected(SignInRequest request) async {
      try {
        await fake.gateway.signIn(request);
      } on SignInException catch (error) {
        expect(fake.gateway.status, AuthStatus.signedOut);
        expect(fake.client.auth.currentSession, isNull);
        return error.failure;
      }
      throw StateError('sign-in succeeded');
    }

    final emailFailure = await rejected(
      SignInRequest.tryCreate(
        kind: SignInIdentifier.email,
        identifier: 'owner@example.test',
        password: 'wrong-password',
      )!,
    );
    final phoneFailure = await rejected(
      SignInRequest.tryCreate(
        kind: SignInIdentifier.phone,
        identifier: '01012345678',
        password: 'wrong-password',
      )!,
    );
    expect(emailFailure, SignInFailure.invalidCredentials);
    expect(phoneFailure, emailFailure);
  });

  test('completed registration binds the session to the server user', () async {
    final seen = <AuthStatus>[];
    final subscription = fake.gateway.changes.listen(seen.add);
    fake.releaseToken = Completer<void>();
    final pending = fake.gateway.registerOwner(sampleRegistration());
    var waits = 0;
    while (!fake.httpClient.recorded.any(
      (request) => request.url.path.endsWith('/token'),
    )) {
      expect(waits, lessThan(100));
      waits += 1;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(fake.gateway.status, AuthStatus.signedOut);
    expect(seen, isNot(contains(AuthStatus.signedIn)));
    fake.releaseToken!.complete();
    final result = await pending;
    await subscription.cancel();
    expect(result.userId, userId);
    expect(result.shopId, shopId);
    expect(fake.client.auth.currentUser!.id, userId);
    expect(fake.gateway.status, AuthStatus.signedIn);
    final register = fake.httpClient.recorded
        .where((request) => request.url.path.endsWith('/owner-register'))
        .single;
    final body = jsonDecode(register.body) as Map<String, dynamic>;
    expect(body.keys.toSet(), {
      'idempotency_key',
      'owner_name',
      'business_name',
      'email',
      'phone',
      'governorate_code',
      'password',
    });
    expect(body['email'], 'owner@example.test');
    expect(body['phone'], '+201012345678');
    expect(body['idempotency_key'], '11111111-1111-4111-8111-111111111111');
    expect(body['password'], 'example-password');
    expect(
      fake.httpClient.recorded.map((request) => request.url.path),
      containsAll(['/functions/v1/owner-register', '/auth/v1/token']),
    );
  });

  test('a mismatched session user does not open shop access', () async {
    fake.tokenUserId = otherUserId;
    final seen = <AuthStatus>[];
    final subscription = fake.gateway.changes.listen(seen.add);
    await expectLater(
      fake.gateway.registerOwner(sampleRegistration()),
      throwsA(
        isA<RegistrationException>().having(
          (error) => error.failure,
          'failure',
          RegistrationFailure.registrationIdentityMismatch,
        ),
      ),
    );
    await subscription.cancel();
    expect(fake.gateway.status, AuthStatus.signedOut);
    expect(fake.client.auth.currentSession, isNull);
    expect(seen, isNot(contains(AuthStatus.signedIn)));
    expect(
      fake.httpClient.recorded.map((request) => request.url.path),
      contains('/auth/v1/logout'),
    );
  });

  test('incomplete or rejected registration is not treated as saved', () async {
    fake.registerBody = {
      'status': 'pending',
      'user_id': userId,
      'shop_id': shopId,
    };
    await expectLater(
      fake.gateway.registerOwner(sampleRegistration()),
      throwsA(
        isA<RegistrationException>().having(
          (error) => error.failure,
          'failure',
          RegistrationFailure.unknownOutcome,
        ),
      ),
    );
    expect(
      fake.httpClient.recorded.map((request) => request.url.path),
      isNot(contains('/auth/v1/token')),
    );

    fake.registerStatus = 409;
    fake.registerBody = {'error': 'identifier_taken'};
    await expectLater(
      fake.gateway.registerOwner(sampleRegistration()),
      throwsA(
        isA<RegistrationException>().having(
          (error) => error.failure,
          'failure',
          RegistrationFailure.identifierTaken,
        ),
      ),
    );
    expect(fake.gateway.status, AuthStatus.signedOut);
  });

  test(
    'governorate catalog is the ordered server table or a failure',
    () async {
      final loaded = await fake.gateway.loadGovernorates();
      expect(loaded.map((item) => item.code), ['EG-C', 'EG-GZ']);
      final request = fake.httpClient.recorded.single;
      expect(request.url.path, contains('/egypt_governorates'));
      expect(request.url.query, contains('select=code'));
      expect(request.url.query, contains('name_ar'));
      expect(request.url.query, contains('code.asc'));
      expect(request.url.query, contains('name_ar.asc'));

      fake.httpClient.recorded.clear();
      fake.governorateStatus = 503;
      await expectLater(
        fake.gateway.loadGovernorates(),
        throwsA(isA<GovernorateLoadException>()),
      );
    },
  );
}
