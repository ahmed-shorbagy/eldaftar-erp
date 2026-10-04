import 'dart:convert';

/// Why an email recovery request or password reset stopped.
///
/// Account existence is not a failure. A well-formed address that the server
/// does not know still completes as the same acknowledgement.
enum RecoveryFailure {
  invalidEmail,
  unavailable,
  expiredOrInvalidLink,
  missingRecoverySession,
  rejectedPassword,
  resetInterrupted,
  untrustedCallback,
}

class RecoveryException implements Exception {
  const RecoveryException(this.failure);

  final RecoveryFailure failure;

  @override
  String toString() => 'RecoveryException($failure)';
}

/// The only redirect this client will send or accept for recovery.
///
/// Supabase must allow this exact URL. Callers cannot supply another.
abstract final class RecoveryCallback {
  static const redirectUrl = 'eldafttar://auth/recovery';

  static bool allows(Uri uri) {
    if (uri.scheme != 'eldafttar') return false;
    if (uri.host != 'auth') return false;
    if (uri.hasPort) return false;
    if (uri.userInfo.isNotEmpty) return false;
    final path = uri.path;
    return path == '/recovery' || path == '/recovery/';
  }
}

/// Reads the `amr` claim from an access token without storing it.
abstract final class RecoverySessionClaims {
  static bool accessTokenIsRecovery(String accessToken) {
    final claims = _payload(accessToken);
    final amr = claims?['amr'];
    if (amr is! List) return false;
    for (final entry in amr) {
      if (entry is Map && entry['method'] == 'recovery') return true;
      if (entry == 'recovery') return true;
    }
    return false;
  }

  static bool persistedSessionIsRecovery(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      final token = decoded['access_token'];
      if (token is! String || token.isEmpty) return false;
      return accessTokenIsRecovery(token);
    } on Object {
      return false;
    }
  }

  static Map<String, Object?>? _payload(String accessToken) {
    final parts = accessToken.split('.');
    if (parts.length < 2 || parts[1].isEmpty) return null;
    try {
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final json = jsonDecode(decoded);
      if (json is! Map) return null;
      return json.map((key, value) => MapEntry(key.toString(), value));
    } on Object {
      return null;
    }
  }
}

/// Email recovery, kept off the sign-in gateway so unrelated fakes stay unchanged.
abstract class PasswordRecoveryGateway {
  /// A recovery session is present and the new password is not saved yet.
  bool get recoveryPending;

  Stream<bool> get recoveryChanges;

  /// Set when a recovery callback was rejected. Null after a later success.
  RecoveryFailure? get linkFailure;

  /// Sends the recovery mail. Valid addresses share one acknowledgement,
  /// including when no account exists.
  Future<void> requestEmailReset(String email);

  /// Sets the password only while [recoveryPending], then ends that session.
  Future<void> completeReset(String password);

  /// Drops a recovery session without changing the password.
  Future<void> abandonRecovery();

  /// Exchanges a callback only when [RecoveryCallback.allows] is true.
  Future<void> acceptCallback(Uri uri);

  void clearLinkFailure();
}
