import 'customer_rules.dart';

enum CustomerContactAction { dialer, whatsapp, whatsappLink }

enum ContactHandoff {
  opened,
  unavailable,
  cancelled,
  denied,
  permanentlyDenied,
  failed,
  stale,
  changed,
  busy,
}

/// Entitlement expiry and archive do not remove authorized reader contact access.
bool mayContactCustomer({
  required bool authorizedReader,
  required String status,
}) => authorizedReader && (status == 'active' || status == 'archived');

Uri? customerContactUri(CustomerContactAction action, String normalized) {
  // Accept only the canonical current-directory value, never snapshots/raw URIs.
  if (normalizeCustomerPhone(normalized) != normalized) return null;
  final digits = normalized.substring(1);
  return switch (action) {
    CustomerContactAction.dialer => Uri(scheme: 'tel', path: normalized),
    CustomerContactAction.whatsapp => Uri(
      scheme: 'whatsapp',
      host: 'send',
      query: 'phone=${Uri.encodeComponent(digits)}',
    ),
    CustomerContactAction.whatsappLink => Uri.https('wa.me', '/$digits'),
  };
}

bool isCustomerContactUri(CustomerContactAction action, Uri uri) {
  final number = switch (action) {
    CustomerContactAction.dialer => uri.path,
    CustomerContactAction.whatsapp => '+${uri.queryParameters['phone'] ?? ''}',
    CustomerContactAction.whatsappLink => '+${uri.path.replaceFirst('/', '')}',
  };
  return customerContactUri(action, number) == uri;
}

abstract class CustomerContactLauncher {
  /// Recheck the caller after asynchronous handler discovery, immediately before launch.
  Future<ContactHandoff> open(
    CustomerContactAction action,
    Uri destination, {
    required bool Function() stillAuthorized,
  });
}

abstract class CustomerContactSession {
  /// Opaque, memory-only session identity. Never persist or display this value.
  Object? contactSession(String callerUserId);
}
