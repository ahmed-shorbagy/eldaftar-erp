import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:eldafttar/src/features/inventory/application/inventory_command_flow.dart';
import 'package:eldafttar/src/features/inventory/application/inventory_gateway.dart';
import 'package:eldafttar/src/features/inventory/domain/inventory_models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const dayId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const operationId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const key = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const userId = 'owner-a';
const shopId = 'shop-a';

DayAnchor get day =>
    (DayAnchor.tryCreate(dayId, '7') as InventoryAccepted<DayAnchor>).value;

ReviewedCommand addition() =>
    (reviewAddition(
              day: day,
              reason: 'إضافة',
              lines: [
                AdditionLine(
                  itemName: 'خاتم',
                  category: 'worked_jewelry',
                  karat: 21,
                  milligrams: BigInt.from(10000),
                  count: BigInt.one,
                ),
              ],
            )
            as InventoryAccepted<ReviewedCommand>)
        .value;

class ScriptInventory implements InventoryGateway {
  ScriptInventory(this.results, {List<StatusResult>? catalog})
    : catalog = catalog ?? <StatusResult>[];
  final List<FinancialCommandResult> results;
  final List<StatusResult> catalog;
  final bodies = <Map<String, Object?>>[];
  int catalogCalls = 0;

  @override
  Future<FinancialCommandResult> postStored({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async {
    bodies.add(Map<String, Object?>.from(command.body));
    if (results.isEmpty) return const FinancialUnknown();
    return results.removeAt(0);
  }

  @override
  Future<InventoryTotals> totals({
    required String callerUserId,
    String? category,
    int? karat,
  }) => Future.error(const InventoryReadException());

  @override
  Future<LotPage> lots({
    required String callerUserId,
    String? category,
    int? karat,
    String? stockClass,
    String? query,
    String? cursor,
  }) => Future.error(const InventoryReadException());

  @override
  Future<MovementPage> movements({
    required String callerUserId,
    required String lotId,
    String? cursor,
  }) => Future.error(const InventoryReadException());

  @override
  Future<TraderPage> traders({
    required String callerUserId,
    String? query,
    String? cursor,
  }) => Future.error(const InventoryReadException());

  @override
  Future<TraderDetail> trader({
    required String callerUserId,
    required String traderId,
  }) => Future.error(const InventoryReadException());

  @override
  Future<TraderActivityPage> traderActivity({
    required String callerUserId,
    required String traderId,
    String? cursor,
  }) => Future.error(const InventoryReadException());

  @override
  Future<ReceiptPage> receipts({
    required String callerUserId,
    String? ownerKind,
    String? traderId,
    String? recognition,
    String? cursor,
  }) => Future.error(const InventoryReadException());

  @override
  Future<ReadPage<CatalogProduct>> products({
    required String callerUserId,
    String? query,
    String? cursor,
  }) => Future.error(const InventoryReadException());

  @override
  Future<ReadPage<CatalogDenomination>> denominations({
    required String callerUserId,
    String? query,
    String? cursor,
  }) => Future.error(const InventoryReadException());

  @override
  Future<ReadPage<CatalogCoin>> coins({
    required String callerUserId,
    String? query,
    String? cursor,
  }) => Future.error(const InventoryReadException());

  @override
  Future<ReadPage<GoldObligationView>> goldObligations({
    required String callerUserId,
    String? cursor,
  }) => Future.error(const InventoryReadException());

  @override
  Future<ReadPage<TraderObligation>> traderObligations({
    required String callerUserId,
    required String traderId,
    String? unit,
    String? cursor,
  }) => Future.error(const InventoryReadException());

  @override
  Future<StatusResult> catalogStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async {
    catalogCalls++;
    if (catalog.isEmpty) return const StatusAbsent();
    return catalog.removeAt(0);
  }
}

class ScriptStatus implements OpeningGateway {
  ScriptStatus(this.results);
  final List<StatusResult> results;
  int calls = 0;

  @override
  Future<StatusResult> status({
    required String callerUserId,
    required String idempotencyKey,
  }) async {
    calls++;
    if (results.isEmpty) return const StatusUnknown();
    return results.removeAt(0);
  }

  @override
  Future<ConfirmResult> confirm({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) => Future.error(UnimplementedError());

  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) =>
      Future.error(UnimplementedError());
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'timeout before commit stays unconfirmed and keeps the envelope',
    () async {
      final inventory = ScriptInventory([const FinancialUnknown()]);
      final status = ScriptStatus([const StatusAbsent()]);
      const store = PendingFinancialCommands();
      final flow = InventoryCommandFlow(
        gateway: inventory,
        statusGateway: status,
        store: store,
      );
      final command = addition();
      final result = await flow.submit(
        userId: userId,
        shopId: shopId,
        idempotencyKey: key,
        command: command,
        readOnly: false,
      );
      expect(result, isA<InventoryUnconfirmed>());
      expect((result as InventoryUnconfirmed).statusUnknown, isFalse);
      final stored = await store.read(userId, shopId);
      expect(stored?.body, command.envelope(key));
      expect(inventory.bodies.single, command.envelope(key));
      expect(result, isNot(isA<InventorySaved>()));
    },
  );

  test('timeout after commit becomes saved without a second post', () async {
    final inventory = ScriptInventory([const FinancialUnknown()]);
    final status = ScriptStatus([StatusCompleted(operationId)]);
    const store = PendingFinancialCommands();
    final result =
        await InventoryCommandFlow(
          gateway: inventory,
          statusGateway: status,
          store: store,
        ).submit(
          userId: userId,
          shopId: shopId,
          idempotencyKey: key,
          command: addition(),
          readOnly: false,
        );
    expect(result, isA<InventorySaved>());
    expect((result as InventorySaved).replayed, isTrue);
    expect(result.id, operationId);
    expect(inventory.bodies, hasLength(1));
    expect(await store.read(userId, shopId), isNull);
  });

  test('a new flow retries the stored envelope after restart', () async {
    final command = addition();
    const store = PendingFinancialCommands();
    final first = ScriptInventory([const FinancialUnknown()]);
    await InventoryCommandFlow(
      gateway: first,
      statusGateway: ScriptStatus([const StatusAbsent()]),
      store: store,
    ).submit(
      userId: userId,
      shopId: shopId,
      idempotencyKey: key,
      command: command,
      readOnly: false,
    );
    final stored = await store.read(userId, shopId);
    final second = ScriptInventory([
      const FinancialCommitted(operationId, replayed: true),
    ]);
    final result = await InventoryCommandFlow(
      gateway: second,
      statusGateway: ScriptStatus([const StatusAbsent()]),
      store: store,
    ).reconcile(userId: userId, shopId: shopId, command: stored!, retry: true);
    expect(result, isA<InventorySaved>());
    expect(second.bodies.single, command.envelope(key));
    expect(await store.read(userId, shopId), isNull);
  });

  test('stale day clears the pending command and requires rereview', () async {
    const store = PendingFinancialCommands();
    final result =
        await InventoryCommandFlow(
          gateway: ScriptInventory([const FinancialRejected('stale_day')]),
          statusGateway: ScriptStatus([]),
          store: store,
        ).submit(
          userId: userId,
          shopId: shopId,
          idempotencyKey: key,
          command: addition(),
          readOnly: false,
        );
    expect((result as InventoryFailed).rereview, isTrue);
    expect(result.code, 'stale_day');
    expect(await store.read(userId, shopId), isNull);
  });

  test('a read-only shop sends nothing', () async {
    final inventory = ScriptInventory([]);
    const store = PendingFinancialCommands();
    final result =
        await InventoryCommandFlow(
          gateway: inventory,
          statusGateway: ScriptStatus([]),
          store: store,
        ).submit(
          userId: userId,
          shopId: shopId,
          idempotencyKey: key,
          command: addition(),
          readOnly: true,
        );
    expect((result as InventoryNotSent).code, 'shop_not_active');
    expect(inventory.bodies, isEmpty);
    expect(await store.read(userId, shopId), isNull);
  });

  test('session expiry is a rejection, not a saved balance', () async {
    const store = PendingFinancialCommands();
    final result =
        await InventoryCommandFlow(
          gateway: ScriptInventory([
            const FinancialRejected('session_expired'),
          ]),
          statusGateway: ScriptStatus([]),
          store: store,
        ).submit(
          userId: userId,
          shopId: shopId,
          idempotencyKey: key,
          command: addition(),
          readOnly: false,
        );
    expect(result, isA<InventoryFailed>());
    expect((result as InventoryFailed).code, 'session_expired');
    expect(await store.read(userId, shopId), isNull);
  });

  test(
    'catalog timeout stays unconfirmed until the same envelope replays',
    () async {
      final reviewed =
          (reviewTraderSave(
                    day: day,
                    displayName: 'تاجر',
                    phone: '01000000000',
                    note: '',
                    active: true,
                  )
                  as InventoryAccepted<ReviewedCommand>)
              .value;
      const store = PendingFinancialCommands();
      final inventory = ScriptInventory(
        [
          const FinancialUnknown(),
          FinancialCommitted(operationId, replayed: true),
        ],
        catalog: [const StatusAbsent(), const StatusAbsent()],
      );
      final status = ScriptStatus([const StatusAbsent(), const StatusAbsent()]);
      final flow = InventoryCommandFlow(
        gateway: inventory,
        statusGateway: status,
        store: store,
      );
      final pending = await flow.submit(
        userId: userId,
        shopId: shopId,
        idempotencyKey: key,
        command: reviewed,
        readOnly: false,
      );
      expect(pending, isA<InventoryUnconfirmed>());
      expect(status.calls, 0);
      expect(inventory.catalogCalls, 1);
      final stored = await store.read(userId, shopId);
      expect(stored?.body, reviewed.envelope(key));
      final saved = await flow.reconcile(
        userId: userId,
        shopId: shopId,
        command: stored!,
        retry: true,
      );
      expect((saved as InventorySaved).replayed, isTrue);
      expect(status.calls, 0);
      expect(inventory.bodies, [
        reviewed.envelope(key),
        reviewed.envelope(key),
      ]);
    },
  );

  test('a completed catalog row is not posted again', () async {
    final reviewed =
        (reviewTraderSave(
                  day: day,
                  displayName: 'تاجر',
                  phone: '01000000000',
                  note: '',
                  active: true,
                )
                as InventoryAccepted<ReviewedCommand>)
            .value;
    const store = PendingFinancialCommands();
    final inventory = ScriptInventory(
      [const FinancialUnknown()],
      catalog: [StatusCompleted(operationId)],
    );
    final status = ScriptStatus([]);
    final saved =
        await InventoryCommandFlow(
          gateway: inventory,
          statusGateway: status,
          store: store,
        ).submit(
          userId: userId,
          shopId: shopId,
          idempotencyKey: key,
          command: reviewed,
          readOnly: false,
        );
    expect((saved as InventorySaved).replayed, isTrue);
    expect(saved.id, operationId);
    expect(inventory.bodies, [reviewed.envelope(key)]);
    expect(status.calls, 0);
    expect(await store.read(userId, shopId), isNull);
  });
}
