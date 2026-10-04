import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_gateway.dart';
import '../domain/password_recovery.dart';

class SupabaseAuthGateway implements AuthGateway, PasswordRecoveryGateway {
  SupabaseAuthGateway(this._client) {
    _client.auth.onAuthStateChange.listen(_onAuth, onError: _onAuthError);
  }

  final SupabaseClient _client;
  final _recoveryEvents = StreamController<bool>.broadcast();
  bool _recoveryLock = false;
  Future<void>? _requestInFlight;
  Future<void>? _resetInFlight;
  RecoveryFailure? _linkFailure;

  /// Registration sign-in emits auth events before the server user id is
  /// confirmed. Shop access stays closed until that check finishes.
  bool _blockShopAccess = false;

  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  AuthStatus get status {
    if (_blockShopAccess || recoveryPending) return AuthStatus.signedOut;
    final session = _client.auth.currentSession;
    if (session == null || session.isExpired) return AuthStatus.signedOut;
    return AuthStatus.signedIn;
  }

  @override
  bool get recoveryPending {
    final session = _client.auth.currentSession;
    if (session == null || session.isExpired) return false;
    return _recoveryLock || _sessionIsRecovery;
  }

  @override
  Stream<bool> get recoveryChanges => _recoveryEvents.stream;

  @override
  RecoveryFailure? get linkFailure => _linkFailure;

  bool get _sessionIsRecovery {
    final session = _client.auth.currentSession;
    if (session == null) return false;
    return RecoverySessionClaims.accessTokenIsRecovery(session.accessToken);
  }

  @override
  Stream<AuthStatus> get changes =>
      _client.auth.onAuthStateChange.map((_) => status);

  @override
  Future<void> signIn(SignInRequest request) async {
    if (_blockShopAccess || _recoveryLock || _sessionIsRecovery) {
      await _forceSignedOut();
      if (_client.auth.currentSession == null) {
        _recoveryLock = false;
      } else if (_recoveryLock || _sessionIsRecovery) {
        throw const SignInException(SignInFailure.unavailable);
      }
    }
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
      if (_recoveryLock || _sessionIsRecovery) {
        await _forceSignedOut();
        if (_client.auth.currentSession == null) {
          _recoveryLock = false;
        } else {
          throw const RegistrationException(RegistrationFailure.unavailable);
        }
      }
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
  Future<void> signOut() async {
    await _client.auth.signOut();
    if (_client.auth.currentSession == null) _recoveryLock = false;
    _notifyRecovery();
  }

  @override
  Future<void> requestEmailReset(String email) {
    final canonical = AccountEmail.tryCanonical(email);
    if (canonical == null) {
      throw const RecoveryException(RecoveryFailure.invalidEmail);
    }
    final existing = _requestInFlight;
    if (existing != null) return existing;
    final run = _sendRecoveryEmail(canonical);
    _requestInFlight = run;
    return run.whenComplete(() {
      if (identical(_requestInFlight, run)) _requestInFlight = null;
    });
  }

  Future<void> _sendRecoveryEmail(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email,
        redirectTo: RecoveryCallback.redirectUrl,
      );
    } on AuthRetryableFetchException {
      throw const RecoveryException(RecoveryFailure.unavailable);
    } on AuthException catch (error) {
      if (error.code != 'user_not_found') {
        throw const RecoveryException(RecoveryFailure.unavailable);
      }
    }
    _linkFailure = null;
    _notifyRecovery();
  }

  @override
  Future<void> completeReset(String password) {
    if (!AccountPassword.isAcceptable(password)) {
      throw const RecoveryException(RecoveryFailure.rejectedPassword);
    }
    if (!recoveryPending) {
      throw const RecoveryException(RecoveryFailure.missingRecoverySession);
    }
    final existing = _resetInFlight;
    if (existing != null) return existing;
    final run = _saveRecoveryPassword(password);
    _resetInFlight = run;
    return run.whenComplete(() {
      if (identical(_resetInFlight, run)) _resetInFlight = null;
    });
  }

  Future<void> _saveRecoveryPassword(String password) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: password));
    } on AuthRetryableFetchException {
      throw const RecoveryException(RecoveryFailure.unavailable);
    } on AuthException catch (error) {
      if (_recoverySessionRejected(error)) {
        await _dropRecoverySession();
        _linkFailure = RecoveryFailure.expiredOrInvalidLink;
        _notifyRecovery();
        throw const RecoveryException(RecoveryFailure.expiredOrInvalidLink);
      }
      if (error is AuthWeakPasswordException ||
          error.code == 'weak_password' ||
          error.code == 'same_password') {
        throw const RecoveryException(RecoveryFailure.rejectedPassword);
      }
      throw const RecoveryException(RecoveryFailure.unavailable);
    }
    try {
      await _client.auth.signOut();
    } catch (_) {
      if (_client.auth.currentSession != null) {
        _recoveryLock = true;
        _notifyRecovery();
        throw const RecoveryException(RecoveryFailure.resetInterrupted);
      }
    }
    _recoveryLock = false;
    _linkFailure = null;
    _notifyRecovery();
  }

  @override
  Future<void> abandonRecovery() async {
    await _forceSignedOut();
    if (_client.auth.currentSession != null && _sessionIsRecovery) {
      _recoveryLock = true;
      _notifyRecovery();
      throw const RecoveryException(RecoveryFailure.resetInterrupted);
    }
    _recoveryLock = false;
    _notifyRecovery();
  }

  @override
  Future<void> acceptCallback(Uri uri) async {
    if (!RecoveryCallback.allows(uri)) {
      throw const RecoveryException(RecoveryFailure.untrustedCallback);
    }
    try {
      final response = await _client.auth.getSessionFromUrl(uri);
      final type = response.redirectType;
      final recovery = type == 'recovery' || type == 'passwordRecovery';
      final session = _client.auth.currentSession;
      if (!recovery || session == null || session.isExpired) {
        await _dropRecoverySession();
        _linkFailure = RecoveryFailure.expiredOrInvalidLink;
        _notifyRecovery();
        throw const RecoveryException(RecoveryFailure.expiredOrInvalidLink);
      }
      _recoveryLock = true;
      _linkFailure = null;
      _notifyRecovery();
    } on RecoveryException {
      rethrow;
    } on AuthException {
      await _dropRecoverySession();
      _linkFailure = RecoveryFailure.expiredOrInvalidLink;
      _notifyRecovery();
      throw const RecoveryException(RecoveryFailure.expiredOrInvalidLink);
    }
  }

  @override
  void clearLinkFailure() {
    _linkFailure = null;
    _notifyRecovery();
  }

  void _onAuth(AuthState state) {
    final session = state.session ?? _client.auth.currentSession;
    final recovery =
        state.event == AuthChangeEvent.passwordRecovery ||
        (session != null &&
            RecoverySessionClaims.accessTokenIsRecovery(session.accessToken));
    if (recovery) {
      if (session == null || session.isExpired) {
        _recoveryLock = false;
        _linkFailure = RecoveryFailure.expiredOrInvalidLink;
      } else {
        _recoveryLock = true;
      }
      _notifyRecovery();
      return;
    }
    if (state.event == AuthChangeEvent.signedOut &&
        _client.auth.currentSession == null) {
      _recoveryLock = false;
      _notifyRecovery();
    }
  }

  void _onAuthError(Object error) {
    if (error is! AuthException) return;
    final session = _client.auth.currentSession;
    if (session != null &&
        !RecoverySessionClaims.accessTokenIsRecovery(session.accessToken)) {
      return;
    }
    const codes = {
      'otp_expired',
      'flow_state_expired',
      'flow_state_not_found',
      'bad_code_verifier',
      'access_denied',
    };
    final callback =
        error is AuthPKCEGrantCodeExchangeError ||
        codes.contains(error.code) ||
        codes.contains(error.statusCode);
    if (!callback) return;
    _recoveryLock = false;
    _linkFailure = RecoveryFailure.expiredOrInvalidLink;
    _notifyRecovery();
  }

  bool _recoverySessionRejected(AuthException error) {
    const codes = {
      'session_expired',
      'session_not_found',
      'bad_jwt',
      'session_missing',
    };
    return error.statusCode == '401' ||
        codes.contains(error.code) ||
        codes.contains(error.statusCode);
  }

  Future<void> _dropRecoverySession() async {
    _recoveryLock = false;
    await _forceSignedOut();
  }

  void _notifyRecovery() {
    if (_recoveryEvents.isClosed) return;
    _recoveryEvents.add(recoveryPending);
  }
}
