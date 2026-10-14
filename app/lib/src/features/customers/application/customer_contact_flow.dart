import '../domain/customer_contact.dart';
import 'customer_gateway.dart';

class CustomerContactFlow {
  CustomerContactFlow(this.gateway, this.launcher);
  final CustomerGateway gateway;
  final CustomerContactLauncher launcher;
  bool _busy = false;

  Future<ContactHandoff> launch({
    required String userId,
    required CustomerRecord reviewed,
    required String number,
    required CustomerContactAction action,
    required bool Function() stillAuthorized,
  }) async {
    if (_busy) return ContactHandoff.busy;
    if (!stillAuthorized()) return ContactHandoff.stale;
    _busy = true;
    try {
      final current = (await gateway.customer(
        callerUserId: userId,
        id: reviewed.id,
      )).customer;
      if (!stillAuthorized()) return ContactHandoff.stale;
      if (current.id != reviewed.id ||
          !mayContactCustomer(authorizedReader: true, status: current.status)) {
        return ContactHandoff.unavailable;
      }
      if (current.version != reviewed.version ||
          current.phones.length != reviewed.phones.length ||
          current.phones.any(
            (p) => !reviewed.phones.any(
              (old) =>
                  old.normalized == p.normalized && old.primary == p.primary,
            ),
          )) {
        return ContactHandoff.changed;
      }
      final uri = customerContactUri(action, number);
      if (uri == null || !current.phones.any((p) => p.normalized == number)) {
        return ContactHandoff.unavailable;
      }
      final result = await launcher.open(
        action,
        uri,
        stillAuthorized: stillAuthorized,
      );
      return stillAuthorized() ? result : ContactHandoff.stale;
    } finally {
      _busy = false;
    }
  }
}
