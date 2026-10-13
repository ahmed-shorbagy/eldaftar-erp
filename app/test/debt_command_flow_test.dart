import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/debts/application/debt_command_flow.dart';
import 'package:eldafttar/src/features/debts/application/debt_gateway.dart';
import 'package:eldafttar/src/features/debts/domain/debt_rules.dart';
import 'package:flutter_test/flutter_test.dart';

const key = 'd3000000-0000-4000-8000-000000000202';
const sourceId = 'd3000000-0000-4000-8000-000000000201';

Map<String, Object?> declarePayload() => {
  'version': 1,
  'kind': 'debt_declare',
  'direction': 'shop_owes',
  'unit': 'money',
  'karat': null,
  'amount': '1500',
  'party_name': 'طرف',
  'contact_phone': '',
  'reason': 'سبب تاريخي',
  'external_reference': null,
};

DebtRpcCommitted committed({
  bool replayed = false,
  String kind = 'debt_declare',
  String id = sourceId,
  String sourceKind = 'standalone',
}) => DebtRpcCommitted(
  sourceId: id,
  sourceKind: sourceKind,
  commandKind: kind,
  replayed: replayed,
  effect: DebtEffect.zero,
  displayStatus: 'open',
  original: BigInt.from(1500),
  settled: BigInt.zero,
  remaining: BigInt.from(1500),
  ledgerEffect: 'none',
  operationId: null,
  result: {
    'display_status': 'open',
    'original_amount': '1500',
    'settled_amount': '0',
    'remaining_amount': '1500',
    'ledger_effect': 'none',
    'operation_id': null,
    'cash_piastres': '0',
    'gold_milligrams': '0',
    'gold_count': '0',
    'custody_milligrams': '0',
    'saleable_stock_milligrams': '0',
  },
);

class MemoryLocker implements FinancialCommandLocker {
  PendingFinancialCommand? stored;
  Object? saveError;

  @override
  Future<void> clear(String userId, String shopId, String key) async {
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

class ScriptGateway implements DebtGateway {
  ScriptGateway(this.postResult, {this.status = const DebtRemoteAbsent()});

  DebtRpcResult postResult;
  DebtRemoteStatus status;
  var posts = 0;
  var throwOnPost = false;

  @override
  Future<DebtContext> readContext({required String callerUserId}) =>
      Future.error(UnimplementedError());

  @override
  Future<DebtRemoteStatus> readCommandStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async => status;

  @override
  Future<DebtDetail> readDetail({
    required String callerUserId,
    required String sourceKind,
    required String sourceId,
  }) => Future.error(UnimplementedError());

  @override
  Future<DebtPage> readList({
    required String callerUserId,
    required String query,
    required String filter,
    required int limit,
    required String? cursor,
  }) => Future.error(UnimplementedError());

  @override
  Future<DebtRpcResult> submitCommand({
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
    final gateway = ScriptGateway(committed());
    final result = await DebtCommandFlow(gateway: gateway, store: locker)
        .submit(
          userId: 'owner',
          shopId: 'shop',
          idempotencyKey: key,
          kind: 'debt_declare',
          payload: declarePayload(),
          readOnly: false,
        );
    expect((result as DebtNotSent).code, 'storage');
    expect(gateway.posts, 0);
    expect(locker.stored, isNull);
  });

  test('unknown post freezes the original command', () async {
    final locker = MemoryLocker();
    final gateway = ScriptGateway(const DebtRpcUnknown());
    final flow = DebtCommandFlow(gateway: gateway, store: locker);
    final result = await flow.submit(
      userId: 'owner',
      shopId: 'shop',
      idempotencyKey: key,
      kind: 'debt_declare',
      payload: declarePayload(),
      readOnly: false,
    );
    expect(result, isA<DebtUnconfirmed>());
    expect(locker.stored?.key, key);
    expect(locker.stored?.body['p_payload'], declarePayload());
  });

  test('rejected command clears the pending key', () async {
    final locker = MemoryLocker();
    final gateway = ScriptGateway(const DebtRpcRejected('stale_debt'));
    final result = await DebtCommandFlow(gateway: gateway, store: locker)
        .submit(
          userId: 'owner',
          shopId: 'shop',
          idempotencyKey: key,
          kind: 'debt_declare',
          payload: declarePayload(),
          readOnly: false,
        );
    expect((result as DebtFailed).code, 'stale_debt');
    expect(locker.stored, isNull);
  });

  test('completed status of another subject stays unconfirmed', () async {
    final locker = MemoryLocker();
    final command = PendingFinancialCommand(
      key: key,
      kind: 'debt_settle',
      body: {
        'p_idempotency_key': key,
        'p_payload': {
          'version': 1,
          'kind': 'debt_settle',
          'amount': '1500',
          'deliveries': null,
          'direction': 'shop_owes',
          'expected_day_id': null,
          'expected_day_version': null,
          'expected_remaining': '1500',
          'expected_version': '1',
          'karat': null,
          'ledger_effect': 'none',
          'reason': 'سبب تاريخي',
          'receipt': null,
          'settlement_reference': key,
          'source_id': sourceId,
          'source_kind': 'standalone',
          'tenders': null,
          'unit': 'money',
        },
      },
    );
    locker.stored = command;
    final gateway = ScriptGateway(
      const DebtRpcUnknown(),
      status: DebtRemoteCompleted(
        committed: committed(
          id: 'd3000000-0000-4000-8000-000000000299',
          kind: 'debt_settle',
        ),
      ),
    );
    final result = await DebtCommandFlow(gateway: gateway, store: locker)
        .reconcile(
          userId: 'owner',
          shopId: 'shop',
          command: command,
          retry: false,
        );
    expect(result, isA<DebtUnconfirmed>());
    expect((result as DebtUnconfirmed).statusUnknown, isTrue);
    expect(locker.stored?.key, key);
  });

  test('matching completed status reconciles and clears', () async {
    final locker = MemoryLocker();
    final command = PendingFinancialCommand(
      key: key,
      kind: 'debt_declare',
      body: {'p_idempotency_key': key, 'p_payload': declarePayload()},
    );
    locker.stored = command;
    final gateway = ScriptGateway(
      const DebtRpcUnknown(),
      status: DebtRemoteCompleted(committed: committed(replayed: true)),
    );
    final result = await DebtCommandFlow(gateway: gateway, store: locker)
        .reconcile(
          userId: 'owner',
          shopId: 'shop',
          command: command,
          retry: false,
        );
    expect((result as DebtSaved).committed.replayed, isTrue);
    expect(locker.stored, isNull);
    expect(gateway.posts, 0);
  });
}
