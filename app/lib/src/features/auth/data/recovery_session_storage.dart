import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/password_recovery.dart';

/// Forwards ordinary Auth sessions and refuses to keep a recovery session.
///
/// The recovery access token stays in the Auth client's memory only long
/// enough to set a new password. It is not written to application storage.
class RecoverySessionStorage implements LocalStorage {
  RecoverySessionStorage(this._inner);

  final LocalStorage _inner;

  @override
  Future<void> initialize() => _inner.initialize();

  @override
  Future<bool> hasAccessToken() async {
    final raw = await _inner.accessToken();
    if (raw != null && RecoverySessionClaims.persistedSessionIsRecovery(raw)) {
      await _inner.removePersistedSession();
      return false;
    }
    return raw != null;
  }

  @override
  Future<String?> accessToken() async {
    final raw = await _inner.accessToken();
    if (raw != null && RecoverySessionClaims.persistedSessionIsRecovery(raw)) {
      await _inner.removePersistedSession();
      return null;
    }
    return raw;
  }

  @override
  Future<void> removePersistedSession() => _inner.removePersistedSession();

  @override
  Future<void> persistSession(String persistSessionString) async {
    if (RecoverySessionClaims.persistedSessionIsRecovery(
      persistSessionString,
    )) {
      return;
    }
    await _inner.persistSession(persistSessionString);
  }
}
