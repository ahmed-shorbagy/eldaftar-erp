import 'dart:async';

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_trade_screen.dart';
import 'package:eldafttar/src/features/inventory/application/inventory_gateway.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const tradeOperationId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const tradeCompletedId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';

class Batch2TradeGateway implements FinancialGateway, OpeningGateway {
  Batch2TradeGateway({this.result, this.statusResult = const StatusAbsent()});

  FinancialCommandResult? result;
  StatusResult statusResult;
  Completer<FinancialCommandResult>? postGate;
  final keys = <String>[];
  final payloads = <Map<String, Object?>>[];
  final operationIds = <String>[];
  bool pendingExistedAtPost = false;
  Map<String, Object?>? operationBody;

  FinancialCommandResult get _result =>
      result ?? const FinancialCommitted(tradeOperationId, replayed: false);

  @override
  Future<FinancialCommandResult> retryPending({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async => _result;

  @override
  Future<FinancialCommandResult> postTrade({
    required String callerUserId,
    required String idempotencyKey,
    required FinancialDraft draft,
  }) async {
    pendingExistedAtPost =
        (await const PendingFinancialCommands().read(
          'owner-1',
          'shop-1',
        ))?.key ==
        idempotencyKey;
    keys.add(idempotencyKey);
    payloads.add(draft.toJson());
    final gate = postGate;
    if (gate != null) return gate.future;
    return _result;
  }

  @override
  Future<StatusResult> status({
    required String callerUserId,
    required String idempotencyKey,
  }) async => statusResult;

  @override
  Future<ConfirmResult> confirm({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) async => const ConfirmUnknown();

  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async =>
      throw UnimplementedError();

  @override
  Future<FinancialDayState> dayState({required String callerUserId}) async =>
      const FinancialDayState(state: 'open');

  @override
  Future<FinancialCommandResult> closeDay({
    required String callerUserId,
    required String idempotencyKey,
    required FinancialDayState expected,
    required Map<String, Object?> counted,
  }) async => _result;

  @override
  Future<FinancialCommandResult> openDay({
    required String callerUserId,
    required String idempotencyKey,
  }) async => _result;

  @override
  Future<Map<String, Object?>> operation({
    required String callerUserId,
    required String operationId,
  }) async {
    operationIds.add(operationId);
    return operationBody ?? const {};
  }
}

class Batch2DispatchGateway extends Batch2TradeGateway
    implements InvoiceDispatchGateway {
  @override
  Future<PendingInvoicePage> pendingInvoiceSends({
    required String callerUserId,
    int? beforeSequence,
  }) async => const PendingInvoicePage([], null);

  @override
  Future<InvoiceDispatchState> dispatchState({
    required String callerUserId,
    required String operationId,
  }) async => const InvoiceDispatchState(ownerConfirmed: false);

  @override
  Future<FinancialCommandResult> confirmWhatsappSend({
    required String callerUserId,
    required String operationId,
    required String idempotencyKey,
  }) async => _result;
}

class Batch2Catalog implements InventoryGateway {
  Batch2Catalog({
    this.productsPage = const ReadPage.ready([], null),
    this.denomPage = const ReadPage.ready([], null),
    this.coinPage = const ReadPage.ready([], null),
  });

  ReadPage<CatalogProduct> productsPage;
  ReadPage<CatalogDenomination> denomPage;
  ReadPage<CatalogCoin> coinPage;
  final productCursors = <String?>[];
  final denomCursors = <String?>[];
  final coinCursors = <String?>[];
  var productFailures = 0;
  var nominalFailures = 0;
  Map<String, ReadPage<CatalogProduct>> laterProducts = const {};
  Map<String, ReadPage<CatalogDenomination>> laterDenoms = const {};
  Map<String, ReadPage<CatalogCoin>> laterCoins = const {};

  @override
  Future<ReadPage<CatalogProduct>> products({
    required String callerUserId,
    String? query,
    String? cursor,
  }) async {
    productCursors.add(cursor);
    if (productFailures > 0) {
      productFailures--;
      throw Exception('products');
    }
    if (cursor == null) return productsPage;
    return laterProducts[cursor] ?? const ReadPage.missing();
  }

  @override
  Future<ReadPage<CatalogDenomination>> denominations({
    required String callerUserId,
    String? query,
    String? cursor,
  }) async {
    denomCursors.add(cursor);
    if (nominalFailures > 0) {
      nominalFailures--;
      throw Exception('denoms');
    }
    if (cursor == null) return denomPage;
    return laterDenoms[cursor] ?? const ReadPage.missing();
  }

  @override
  Future<ReadPage<CatalogCoin>> coins({
    required String callerUserId,
    String? query,
    String? cursor,
  }) async {
    coinCursors.add(cursor);
    if (nominalFailures > 0) {
      nominalFailures--;
      throw Exception('coins');
    }
    if (cursor == null) return coinPage;
    return laterCoins[cursor] ?? const ReadPage.missing();
  }

  @override
  Future<InventoryTotals> totals({
    required String callerUserId,
    String? category,
    int? karat,
  }) => throw UnimplementedError();

  @override
  Future<LotPage> lots({
    required String callerUserId,
    String? category,
    int? karat,
    String? stockClass,
    String? query,
    String? cursor,
  }) => throw UnimplementedError();

  @override
  Future<MovementPage> movements({
    required String callerUserId,
    required String lotId,
    String? cursor,
  }) => throw UnimplementedError();

  @override
  Future<TraderPage> traders({
    required String callerUserId,
    String? query,
    String? cursor,
  }) => throw UnimplementedError();

  @override
  Future<TraderDetail> trader({
    required String callerUserId,
    required String traderId,
  }) => throw UnimplementedError();

  @override
  Future<TraderActivityPage> traderActivity({
    required String callerUserId,
    required String traderId,
    String? cursor,
  }) => throw UnimplementedError();

  @override
  Future<ReceiptPage> receipts({
    required String callerUserId,
    String? ownerKind,
    String? traderId,
    String? recognition,
    String? cursor,
  }) => throw UnimplementedError();

  @override
  Future<ReadPage<GoldObligationView>> goldObligations({
    required String callerUserId,
    String? cursor,
  }) => throw UnimplementedError();

  @override
  Future<ReadPage<TraderObligation>> traderObligations({
    required String callerUserId,
    required String traderId,
    String? unit,
    String? cursor,
  }) => throw UnimplementedError();

  @override
  Future<StatusResult> catalogStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<FinancialCommandResult> postStored({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) => throw UnimplementedError();
}

CatalogProduct tradeProduct({
  required String id,
  required String name,
  String category = 'worked_jewelry',
  int karat = 21,
}) => CatalogProduct(
  id: id,
  name: name,
  category: category,
  karat: karat,
  createdAt: '2026-10-01T00:00:00Z',
);

CatalogCoin tradeCoin({
  required String id,
  required String label,
  BigInt? nominalMilligrams,
  bool active = true,
}) => CatalogCoin(
  id: id,
  label: label,
  nominalMilligrams: nominalMilligrams,
  active: active,
  createdAt: '2026-10-01T00:00:00Z',
);

CatalogDenomination tradeDenom({
  required String id,
  required String label,
  required BigInt nominalMilligrams,
  bool active = true,
}) => CatalogDenomination(
  id: id,
  label: label,
  nominalMilligrams: nominalMilligrams,
  active: active,
  createdAt: '2026-10-01T00:00:00Z',
);

Future<void> pumpTradeScreen(
  WidgetTester tester, {
  required FinancialGateway gateway,
  required OpeningGateway statusGateway,
  required FinancialKind kind,
  Size size = const Size(390, 844),
  InventoryGateway? catalog,
  WidgetBuilder? inventoryPage,
  Map<String, Object?>? exchangeReturnPayload,
  bool sheet = false,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final navigators = find.byType(Navigator);
  if (navigators.evaluate().isNotEmpty) {
    final navigator = tester.state<NavigatorState>(navigators.first);
    var guard = 0;
    while (navigator.canPop() && guard < 5) {
      navigator.pop();
      guard++;
    }
    await tester.pumpAndSettle();
  }
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      theme: theme ?? AppTheme.light(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: FinancialTradeScreen(
          key: UniqueKey(),
          sheet: sheet,
          kind: kind,
          gateway: gateway,
          statusGateway: statusGateway,
          userId: 'owner-1',
          shopId: 'shop-1',
          catalog: catalog,
          inventoryPage: inventoryPage,
          exchangeReturnPayload: exchangeReturnPayload,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _tradeTargetInList(Finder finder) {
  if (finder.evaluate().isEmpty) return false;
  var inside = false;
  finder.evaluate().first.visitAncestorElements((ancestor) {
    if (ancestor.widget is Scrollable) {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

double _tradeTopLimit(WidgetTester tester) {
  final bars = find.byType(AppBar);
  if (bars.evaluate().isEmpty) return 8;
  final box = tester.renderObject<RenderBox>(bars.last);
  return box.localToGlobal(Offset.zero).dy + box.size.height + 8;
}

double _tradeBottomLimit(WidgetTester tester) {
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  for (final name in [
    'trade-review',
    'trade-confirm',
    'trade-check-status',
    'trade-done',
    'trade-next',
  ]) {
    final button = find.byKey(Key(name));
    if (button.evaluate().isEmpty) continue;
    final box = tester.renderObject<RenderBox>(button);
    return box.localToGlobal(Offset.zero).dy - 8;
  }
  return height - 24;
}

ScrollPosition? _tradeScroll(WidgetTester tester) {
  final lists = find.byType(ListView).evaluate();
  if (lists.isEmpty) return null;
  ScrollableState? found;
  void visit(Element element) {
    if (found != null) return;
    if (element is StatefulElement && element.state is ScrollableState) {
      found = element.state as ScrollableState;
      return;
    }
    element.visitChildren(visit);
  }

  visit(lists.first);
  return found?.position;
}

/// Scrolls a list target into the open area above the pinned action button.
///
/// A missing target is sought from the top downward, so a choice that scrolled
/// off the top stays reachable.
Future<void> revealTrade(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty && !_tradeTargetInList(finder)) return;
  var rewound = false;
  for (var attempt = 0; attempt < 40; attempt++) {
    final topLimit = _tradeTopLimit(tester);
    final bottomLimit = _tradeBottomLimit(tester);
    if (finder.evaluate().isNotEmpty) {
      final box = tester.renderObject<RenderBox>(finder);
      if (box.hasSize && box.size.height > 0) {
        final top = box.localToGlobal(Offset.zero).dy;
        final bottom = top + box.size.height;
        if (top >= topLimit - 1 && bottom <= bottomLimit + 1) return;
        if (!_tradeTargetInList(finder)) return;
        final scroll = _tradeScroll(tester);
        if (scroll == null) return;
        final safe = bottomLimit - topLimit;
        final double delta;
        if (box.size.height >= safe) {
          delta = top - topLimit;
          if (delta.abs() < 2) return;
        } else if (top < topLimit) {
          delta = top - topLimit - 12;
        } else {
          delta = bottom - bottomLimit + 12;
        }
        final target = (scroll.pixels + delta).clamp(
          scroll.minScrollExtent,
          scroll.maxScrollExtent,
        );
        if (target == scroll.pixels) return;
        scroll.jumpTo(target.toDouble());
        await tester.pump();
        continue;
      }
    }
    final scroll = _tradeScroll(tester);
    if (scroll == null) return;
    if (!rewound) {
      scroll.jumpTo(scroll.minScrollExtent);
      rewound = true;
      await tester.pump();
      continue;
    }
    if (scroll.pixels >= scroll.maxScrollExtent - 1) return;
    final room = scroll.maxScrollExtent - scroll.pixels;
    scroll.jumpTo(scroll.pixels + (room < 220 ? room : 220));
    await tester.pump();
  }
}

Future<void> chooseTradeItem(WidgetTester tester, String label) async {
  final target = find.byKey(Key('trade-select-$label'));
  await revealTrade(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Future<void> enterTradeField(WidgetTester tester, Key key, String value) async {
  final finder = find.byKey(key);
  await revealTrade(tester, finder);
  await tester.enterText(finder, value);
  await tester.pumpAndSettle();
}

Future<void> reviewTrade(WidgetTester tester) async {
  final button = find.byKey(const Key('trade-review'));
  await revealTrade(tester, button);
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Map<String, Object?> confirmedSaleOperation({
  String operationId = tradeOperationId,
  String? occurredAt = '2026-10-12T12:04:05+00:00',
  String? occurredAtCairo = '2026-10-12T15:04:05',
}) => {
  'operation_id': operationId,
  'shop_id': 'shop-1',
  'kind': 'sale',
  'shop_sequence': '42',
  'actor_display_name': 'المالك',
  'occurred_at': ?occurredAt,
  'occurred_at_cairo': ?occurredAtCairo,
  'payload': {
    'total_piastres': '420025',
    'customer_name': '',
    'customer_phone': '01012345678',
    'note': '',
    'items': [
      {
        'item_name': 'خاتم',
        'category': 'worked_jewelry',
        'karat': 18,
        'milligrams': '1830',
        'count': '1',
      },
    ],
    'tenders': [
      {'method': 'cash', 'piastres': '420025'},
    ],
  },
};
