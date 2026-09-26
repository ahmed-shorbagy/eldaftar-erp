import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_gateway.dart';

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._client);

  final SupabaseClient _client;

  /// Registration sign-in emits auth events before the server user id is
  /// confirmed. Shop access stays closed until that check finishes.
  bool _blockShopAccess = false;

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  AuthStatus get status {
    if (_blockShopAccess) return AuthStatus.signedOut;
    final session = _client.auth.currentSession;
    if (session == null || session.isExpired) return AuthStatus.signedOut;
    return AuthStatus.signedIn;
  }

  @override
  Stream<AuthStatus> get changes =>
      _client.auth.onAuthStateChange.map((_) => status);

  @override
  Future<void> signIn(SignInRequest request) async {
    if (_blockShopAccess) await _forceSignedOut();
    try {
      if (request.kind == SignInIdentifier.email) {
        await _client.auth.signInWithPassword(
          email: request.identifier,
          password: request.password,
        );
      } else {
        await _client.auth.signInWithPassword(
          phone: request.identifier,
          password: request.password,
        );
      }
    } on AuthRetryableFetchException {
      throw const SignInException(SignInFailure.unavailable);
    } on AuthException {
      throw const SignInException(SignInFailure.invalidCredentials);
    }
    if (status != AuthStatus.signedIn) {
      await _forceSignedOut();
      throw const SignInException(SignInFailure.invalidCredentials);
    }
  }

  @override
  Future<OwnerRegistrationResult> registerOwner(
    OwnerRegistration registration,
  ) async {
    _blockShopAccess = true;
    try {
      final issued = await _requestRegistration(registration);
      await _client.auth.signInWithPassword(
        email: registration.email,
        password: registration.password,
      );
      final session = _client.auth.currentSession;
      final signedInId = session?.user.id.toLowerCase();
      if (session == null ||
          session.isExpired ||
          signedInId != issued.userId.toLowerCase()) {
        await _forceSignedOut();
        throw const RegistrationException(
          RegistrationFailure.registrationIdentityMismatch,
        );
      }
      _blockShopAccess = false;
      return issued;
    } on RegistrationException {
      await _forceSignedOut();
      rethrow;
    } catch (_) {
      await _forceSignedOut();
      throw const RegistrationException(RegistrationFailure.unknownOutcome);
    }
  }

  Future<OwnerRegistrationResult> _requestRegistration(
    OwnerRegistration registration,
  ) async {
    if (!IdempotencyKey.isV4(registration.idempotencyKey) ||
        !AccountPassword.isAcceptable(registration.password)) {
      throw const RegistrationException(RegistrationFailure.invalidInput);
    }
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'owner-register',
        body: {
          'idempotency_key': registration.idempotencyKey,
          'owner_name': registration.ownerName,
          'business_name': registration.businessName,
          'email': registration.email,
          'phone': registration.phone,
          'governorate_code': registration.governorateCode,
          'password': registration.password,
        },
      );
    } on FunctionException catch (error) {
      throw RegistrationException(_failureFromDetails(error.details));
    }
    if (response.status != 200) {
      throw const RegistrationException(RegistrationFailure.unknownOutcome);
    }
    final body = _stringMap(response.data);
    final userId = body?['user_id'];
    final shopId = body?['shop_id'];
    if (body?['status'] != 'completed' ||
        userId is! String ||
        shopId is! String ||
        !_uuid.hasMatch(userId) ||
        !_uuid.hasMatch(shopId)) {
      throw const RegistrationException(RegistrationFailure.unknownOutcome);
    }
    return OwnerRegistrationResult(userId: userId, shopId: shopId);
  }

  @override
  Future<List<Governorate>> loadGovernorates() async {
    final Object response;
    try {
      response = await _client
          .from('egypt_governorates')
          .select('code, name_ar')
          .order('code', ascending: true)
          .order('name_ar', ascending: true);
    } on PostgrestException {
      throw const GovernorateLoadException(GovernorateLoadFailure.unavailable);
    } catch (_) {
      throw const GovernorateLoadException(GovernorateLoadFailure.unavailable);
    }
    if (response is! List) {
      throw const GovernorateLoadException(
        GovernorateLoadFailure.invalidResponse,
      );
    }
    final options = <Governorate>[];
    final seen = <String>{};
    for (final row in response) {
      final parsed = _parseGovernorate(row);
      if (!seen.add(parsed.code)) {
        throw const GovernorateLoadException(
          GovernorateLoadFailure.invalidResponse,
        );
      }
      options.add(parsed);
    }
    if (options.isEmpty) {
      throw const GovernorateLoadException(
        GovernorateLoadFailure.invalidResponse,
      );
    }
    options.sort((a, b) {
      final byCode = a.code.compareTo(b.code);
      if (byCode != 0) return byCode;
      return a.nameAr.compareTo(b.nameAr);
    });
    return List.unmodifiable(options);
  }

  Governorate _parseGovernorate(Object? row) {
    final fields = _stringMap(row);
    final code = fields?['code'];
    final name = fields?['name_ar'];
    if (code is! String ||
        name is! String ||
        name.trim().isEmpty ||
        !EgyptianGovernorates.isValid(code)) {
      throw const GovernorateLoadException(
        GovernorateLoadFailure.invalidResponse,
      );
    }
    return Governorate(code: code, nameAr: name.trim());
  }

  RegistrationFailure _failureFromDetails(Object? details) {
    final map = _stringMap(details);
    return switch (map?['error']) {
      'invalid_input' => RegistrationFailure.invalidInput,
      'identifier_taken' => RegistrationFailure.identifierTaken,
      'request_key_reused' => RegistrationFailure.requestKeyReused,
      'registration_identity_mismatch' =>
        RegistrationFailure.registrationIdentityMismatch,
      'unavailable' => RegistrationFailure.unavailable,
      'invalid_credentials' => RegistrationFailure.invalidCredentials,
      _ => RegistrationFailure.unknownOutcome,
    };
  }

  Map<String, Object?>? _stringMap(Object? value) {
    if (value is! Map) return null;
    return value.map((key, entry) => MapEntry(key.toString(), entry));
  }

  Future<void> _forceSignedOut() async {
    try {
      if (_client.auth.currentSession != null) {
        await _client.auth.signOut();
      }
    } catch (_) {}
    final session = _client.auth.currentSession;
    if (session == null || session.isExpired) {
      _blockShopAccess = false;
    }
  }

  @override
  Future<void> signOut() => _client.auth.signOut();
}
