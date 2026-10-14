import 'dart:convert';
import '../../daily_ledger/application/pending_financial_command.dart';
import 'customer_contract.dart';
import 'customer_gateway.dart';

class CustomerOutcome {
  const CustomerOutcome({this.receipt, this.pending, this.error});
  final CustomerReceipt? receipt;
  final PendingFinancialCommand? pending;
  final String? error;
}

class CustomerCommandFlow {
  const CustomerCommandFlow(this.gateway, this.store);
  final CustomerGateway gateway;
  final FinancialCommandLocker store;
  Future<CustomerOutcome> submit(
    String user,
    String shop,
    String key,
    Map<String, Object?> payload,
  ) async {
    final frozen = Map<String, Object?>.from(
      jsonDecode(jsonEncode(payload)) as Map,
    );
    final kind = frozen['kind'];
    if (kind is! String) return const CustomerOutcome(error: 'invalid_input');
    final command = PendingFinancialCommand(
      key: key,
      kind: kind,
      body: {'p_idempotency_key': key, 'p_payload': frozen},
    );
    if (!matchesCustomerEnvelope(key, kind, command.body)) {
      return const CustomerOutcome(error: 'invalid_input');
    }
    try {
      await store.save(user, shop, command);
    } catch (_) {
      return const CustomerOutcome(error: 'other_pending');
    }
    return reconcile(user, shop, command, retry: true, first: true);
  }

  Future<CustomerOutcome> reconcile(
    String user,
    String shop,
    PendingFinancialCommand command, {
    bool retry = false,
    bool first = false,
  }) async {
    if (!matchesCustomerEnvelope(command.key, command.kind, command.body)) {
      return CustomerOutcome(pending: command, error: 'invalid_input');
    }
    var sent = first;
    CustomerTransport transport;
    try {
      transport = first
          ? await gateway.sendCustomer(callerUserId: user, command: command)
          : await gateway.customerStatus(callerUserId: user, command: command);
    } catch (_) {
      return CustomerOutcome(pending: command);
    }
    if (transport.receipt == null && transport.error == null && first) {
      try {
        transport = await gateway.customerStatus(
          callerUserId: user,
          command: command,
        );
      } catch (_) {
        return CustomerOutcome(pending: command);
      }
    }
    if (transport.absent && retry && !first) {
      sent = true;
      try {
        transport = await gateway.sendCustomer(
          callerUserId: user,
          command: command,
        );
      } catch (_) {
        return CustomerOutcome(pending: command);
      }
    }
    if (transport.receipt != null || sent && transport.error != null) {
      final receipt = transport.receipt;
      final p = command.body['p_payload'] as Map;
      final matching = receipt?.customer.phones.where(
        (n) =>
            n.normalized == p['normalized_number'] &&
            n.saved?.id == p['number_id'],
      );
      if (receipt != null &&
          (receipt.kind != command.kind ||
              command.kind == 'customer_saved_number' &&
                  (receipt.declarationEventId == null ||
                      matching?.length != 1 ||
                      matching!.single.saved!.state != p['state'] ||
                      matching.single.saved!.actorId != user ||
                      matching.single.saved!.actorName == null ||
                      matching.single.saved!.declaredAt !=
                          receipt.customer.updatedAt) ||
              p['expected_version'] != null &&
                  receipt.customer.version !=
                      BigInt.parse(p['expected_version'] as String) +
                          BigInt.one ||
              p['customer_id'] != null &&
                  p['customer_id'] != receipt.customer.id ||
              p['operation_id'] != null &&
                  p['operation_id'] != receipt.operationId)) {
        return CustomerOutcome(pending: command);
      }
      try {
        await store.clear(user, shop, command.key);
      } catch (_) {
        return CustomerOutcome(
          receipt: receipt,
          pending: command,
          error: 'storage',
        );
      }
      return CustomerOutcome(receipt: receipt, error: transport.error);
    }
    return CustomerOutcome(pending: command);
  }
}
