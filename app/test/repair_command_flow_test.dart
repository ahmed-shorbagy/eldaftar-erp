import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/repairs/application/repair_command_flow.dart';
import 'package:eldafttar/src/features/repairs/application/repair_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

const key = '55555555-5555-4555-8555-555555555555';
const repairId = '66666666-6666-4666-8666-666666666666';

Map<String, Object?> intakeBody() => {
  'p_idempotency_key': key,
  'p_payload': {
    'version': 1,
    'kind': 'repair_intake',
    'customer_name': 'عميل',
    'customer_phone': '',
    'item_description': 'خاتم',
    'measured_milligrams': '1255',
    'karat': 21,
    'issue': 'مفصص',
    'intake_notes': '',
    'estimated_fee_piastres': null,
  },
};

class MemoryLocker implements FinancialCommandLocker {
  PendingFinancialCommand? stored;
  Object? saveError;
  Object? clearError;

  @override
  Future<void> clear(String userId, String shopId, String key) async {
    if (clearError != null) throw clearError!;
    if (stored?.key == key) stored = null;
  }

  @override
  Future<PendingFinancialCommand?> read(String userId, String shopId) async =>
      stored;

  @override
  Future<void> save(
    String userId,
    String shopId,
    PendingFinancialCommand command,
  ) async {
    if (saveError != null) throw saveError!;
    if (stored != null && stored!.key != command.key) {
      throw StateError('pending_financial_exists');
    }
    stored = command;
  }
}

class ScriptGateway implements RepairGateway {
  ScriptGateway(this.postResult, {this.status = const RepairRemoteAbsent()});

  RepairRpcResult postResult;
  RepairRemoteStatus status;
  var posts = 0;
  var throwOnPost = false;

  @override
  Future<RepairRemoteStatus> commandStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async => status;

  @override
  Future<RepairContext> context({required String callerUserId}) =>
      Future.error(UnimplementedError());

  @override
  Future<RepairDetail> detail({
    required String callerUserId,
    required String repairId,
  }) => Future.error(UnimplementedError());

  @override
  Future<RepairPage> list({
    required String callerUserId,
    required String query,
    required String filter,
    required int limit,
    required String? cursor,
  }) => Future.error(UnimplementedError());

  @override
  Future<RepairRpcResult> post({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async {
    posts++;
    if (throwOnPost) throw Exception('timeout');
    return postResult;
  }
}

void main() {
  test('failed persistence does not send', () async {
    final locker = MemoryLocker()..saveError = Exception('disk');
    final gateway = ScriptGateway(
      const RepairRpcCommitted(repairId: repairId, replayed: false, result: {}),
    );
    final result = await RepairCommandFlow(gateway: gateway, store: locker)
        .submit(
          userId: 'owner',
          shopId: 'shop',
          idempotencyKey: key,
          kind: 'repair_intake',
          payload: Map<String, Object?>.from(intakeBody()['p_payload']! as Map),
          readOnly: false,
        );
    expect(result, isA<RepairNotSent>());
    expect((result as RepairNotSent).code, 'storage');
    expect(gateway.posts, 0);
  });

  test('unknown post freezes the original command', () async {
    final locker = MemoryLocker();
    final gateway = ScriptGateway(
      const RepairRpcUnknown(),
      status: const RepairRemoteUnknown(),
    );
    final flow = RepairCommandFlow(gateway: gateway, store: locker);
    final result = await flow.submit(
      userId: 'owner',
      shopId: 'shop',
      idempotencyKey: key,
      kind: 'repair_intake',
      payload: Map<String, Object?>.from(intakeBody()['p_payload']! as Map),
      readOnly: false,
    );
    expect(result, isA<RepairUnconfirmed>());
    expect((result as RepairUnconfirmed).statusUnknown, isTrue);
    expect(locker.stored?.key, key);
    expect(locker.stored?.body, intakeBody());
  });

  test(
    'thrown gateway leaves the command and a later match can clear it',
    () async {
      final locker = MemoryLocker();
      final gateway = ScriptGateway(const RepairRpcUnknown())
        ..throwOnPost = true;
      final flow = RepairCommandFlow(gateway: gateway, store: locker);
      final payload = Map<String, Object?>.from(
        intakeBody()['p_payload']! as Map,
      );
      final first = await flow.submit(
        userId: 'owner',
        shopId: 'shop',
        idempotencyKey: key,
        kind: 'repair_intake',
        payload: payload,
        readOnly: false,
      );
      expect((first as RepairUnconfirmed).statusUnknown, isTrue);
      expect(locker.stored?.key, key);
      final again = await flow.reconcile(
        userId: 'owner',
        shopId: 'shop',
        command: locker.stored!,
        retry: true,
      );
      expect((again as RepairUnconfirmed).statusUnknown, isTrue);
      expect(locker.stored?.body, intakeBody());
      gateway.status = const RepairRemoteCompleted(
        repairId: repairId,
        kind: 'repair_intake',
      );
      final confirmed = await flow.reconcile(
        userId: 'owner',
        shopId: 'shop',
        command: locker.stored!,
        retry: false,
      );
      expect(confirmed, isA<RepairSaved>());
      expect(locker.stored, isNull);
    },
  );

  test('clear failure still reports the known commit', () async {
    final locker = MemoryLocker()..clearError = Exception('locked');
    final gateway = ScriptGateway(
      const RepairRpcCommitted(repairId: repairId, replayed: false, result: {}),
    );
    final result = await RepairCommandFlow(gateway: gateway, store: locker)
        .submit(
          userId: 'owner',
          shopId: 'shop',
          idempotencyKey: key,
          kind: 'repair_intake',
          payload: Map<String, Object?>.from(intakeBody()['p_payload']! as Map),
          readOnly: false,
        );
    expect(result, isA<RepairSaved>());
    expect(locker.stored?.key, key);
  });

  test('read only and a second command are not sent', () async {
    final locker = MemoryLocker();
    final gateway = ScriptGateway(const RepairRpcUnknown());
    final flow = RepairCommandFlow(gateway: gateway, store: locker);
    final payload = Map<String, Object?>.from(
      intakeBody()['p_payload']! as Map,
    );
    final blocked = await flow.submit(
      userId: 'owner',
      shopId: 'shop',
      idempotencyKey: key,
      kind: 'repair_intake',
      payload: payload,
      readOnly: true,
    );
    expect((blocked as RepairNotSent).code, 'shop_not_active');
    expect(gateway.posts, 0);
    await flow.submit(
      userId: 'owner',
      shopId: 'shop',
      idempotencyKey: key,
      kind: 'repair_intake',
      payload: payload,
      readOnly: false,
    );
    final second = await flow.submit(
      userId: 'owner',
      shopId: 'shop',
      idempotencyKey: '77777777-7777-4777-8777-777777777777',
      kind: 'repair_intake',
      payload: payload,
      readOnly: false,
    );
    expect((second as RepairNotSent).code, 'other_pending');
    expect(gateway.posts, 1);
  });

  for (final code in [
    'invalid_input',
    'session_expired',
    'forbidden',
    'shop_unavailable',
  ]) {
    test(
      'failed status read $code preserves the original unknown request',
      () async {
        final locker = MemoryLocker()
          ..stored = PendingFinancialCommand(
            key: key,
            kind: 'repair_intake',
            body: intakeBody(),
          );
        final gateway = ScriptGateway(
          const RepairRpcUnknown(),
          status: RepairRemoteRejected(code),
        );
        final result = await RepairCommandFlow(gateway: gateway, store: locker)
            .reconcile(
              userId: 'owner',
              shopId: 'shop',
              command: locker.stored!,
              retry: true,
            );
        expect(result, isA<RepairUnconfirmed>());
        expect((result as RepairUnconfirmed).statusUnknown, isTrue);
        expect(locker.stored!.body, intakeBody());
        expect(gateway.posts, 0);
      },
    );
  }

  test(
    'a different completed command does not acknowledge this request',
    () async {
      final locker = MemoryLocker()
        ..stored = PendingFinancialCommand(
          key: key,
          kind: 'repair_intake',
          body: intakeBody(),
        );
      final gateway = ScriptGateway(
        const RepairRpcUnknown(),
        status: const RepairRemoteCompleted(
          repairId: repairId,
          kind: 'repair_handover',
        ),
      );
      final result = await RepairCommandFlow(gateway: gateway, store: locker)
          .reconcile(
            userId: 'owner',
            shopId: 'shop',
            command: locker.stored!,
            retry: true,
          );
      expect(result, isA<RepairUnconfirmed>());
      expect(locker.stored!.body, intakeBody());
      expect(gateway.posts, 0);
    },
  );

  test('a definitive write rejection clears the matching command', () async {
    final locker = MemoryLocker();
    final gateway = ScriptGateway(const RepairRpcRejected('invalid_input'));
    final result = await RepairCommandFlow(gateway: gateway, store: locker)
        .submit(
          userId: 'owner',
          shopId: 'shop',
          idempotencyKey: key,
          kind: 'repair_intake',
          payload: Map<String, Object?>.from(intakeBody()['p_payload'] as Map),
          readOnly: false,
        );
    expect((result as RepairFailed).code, 'invalid_input');
    expect(locker.stored, isNull);
    expect(gateway.posts, 1);
  });
}
