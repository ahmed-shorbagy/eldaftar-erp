import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/audit_trail.dart';

class SupabaseAuditTrailGateway implements AuditTrailGateway {
  const SupabaseAuditTrailGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<AuditTrailPage> list({
    AuditTrailFamily? family,
    DateTime? beforeAt,
    String? beforeId,
    int limit = 20,
  }) async {
    try {
      final raw = await _client
          .rpc(
            'list_shop_audit_trail_v1',
            params: {
              'p_family': auditTrailFamilyToApi(family),
              'p_before_at': beforeAt?.toUtc().toIso8601String(),
              'p_before_id': beforeId,
              'p_limit': limit,
            },
          )
          .timeout(const Duration(seconds: 15));
      if (raw is! Map) {
        throw const AuditTrailException(AuditTrailFailure.unavailable);
      }
      return decodeAuditTrailPage(Map<String, dynamic>.from(raw));
    } on AuditTrailException {
      rethrow;
    } on PostgrestException catch (error) {
      throw AuditTrailException(auditTrailFailureFromPostgrest(error));
    } catch (_) {
      throw const AuditTrailException(AuditTrailFailure.unavailable);
    }
  }
}

AuditTrailFailure auditTrailFailureFromPostgrest(PostgrestException error) {
  final message = error.message.toLowerCase();
  if (message.contains('stale_cursor')) return AuditTrailFailure.staleCursor;
  if (error.code == '42501' ||
      message.contains('unauthenticated') ||
      message.contains('session_expired') ||
      message.contains('forbidden') ||
      message.contains('shop_unavailable') ||
      message.contains('unauthorized')) {
    return AuditTrailFailure.accessLost;
  }
  return AuditTrailFailure.unavailable;
}
