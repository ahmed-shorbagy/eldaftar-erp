import 'dart:async';
import 'dart:convert';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/application/ledger_trade_change.dart';
import 'package:eldafttar/src/features/daily_ledger/application/ledger_activity.dart';
import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/data/ledger_trade_change_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_trade_change_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_operation_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_trade_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'ledger_revision_test_support.dart';
import 'operation_details_test.dart' show line;
import 'ledger_feed_merge_test.dart' as feed;

Widget revisionHost(Widget child) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: AppTheme.dark(),
  home: child,
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  test(
    'a server trade-change revision invalidates cached older rows across sessions',
    () {
      final activity = LedgerActivityController();
      DailyLedgerView snapshot(String revision, List<LedgerFeedLine> rows) =>
          DailyLedgerView(
            state: 'confirmed',
            entitlementStatus: 'active',
            canConfirm: true,
            businessDay: const LedgerBusinessDay(
              id: revisionDay,
              businessDate: '2026-10-19',
              openedAt: '2026-10-19T00:00:00Z',
            ),
            cash: const [],
            stock: const [],
            scrap: const [],
            feed: rows,
            tradeChangeSequence: revision,
            feedCursor: const LedgerFeedCursor(
              limit: 100,
              hasMore: true,
              direction: 'desc',
              serverSequence: '300',
              snapshotSequence: '300',
              nextBeforeSequence: '200',
            ),
          );
      activity.adoptSummary(
        userId: revisionUser,
        shopId: revisionShop,
        ledger: snapshot('0', [feed.line(250), feed.line(10)]),
      );
      activity.adoptSummary(
        userId: revisionUser,
        shopId: revisionShop,
        ledger: snapshot('0', [feed.line(251), feed.line(250)]),
      );
      expect(
        activity.state.lines.any((line) => line.shopSequence == '10'),
        isTrue,
      );
      activity.adoptSummary(
        userId: revisionUser,
        shopId: revisionShop,
        ledger: snapshot('300', [feed.line(251), feed.line(250)]),
      );
      expect(
        activity.state.lines.any((line) => line.shopSequence == '10'),
        isFalse,
      );
      expect(activity.state.lines, hasLength(2));
    },
  );
  test(
    'review preserves signed integer effects and rejects malformed or duplicate buckets',
    () {
      final json = jsonDecode(jsonEncode(reviewJson())) as Map;
      final review = parseTradeChangeReview(
        json,
        shopId: revisionShop,
        operationId: revisionOperation,
        action: 'delete',
      );
      expect(
        (review.effects['cash'] as List).single['delta_piastres'],
        '-10000',
      );
      for (final bad in ['-0', '+1', '01', '1.5', '9223372036854775808', -1]) {
        ((json['effects'] as Map)['cash'] as List).single['delta_piastres'] =
            bad;
        expect(
          () => parseTradeChangeReview(
            json,
            shopId: revisionShop,
            operationId: revisionOperation,
            action: 'delete',
          ),
          throwsFormatException,
        );
      }
      final wrong = reviewJson()..['shop_id'] = revisionDay;
      expect(
        () => parseTradeChangeReview(
          wrong,
          shopId: revisionShop,
          operationId: revisionOperation,
          action: 'delete',
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'durable change roundtrips exact envelope and cannot overwrite another command',
    () async {
      const store = PendingFinancialCommands();
      final command = PendingFinancialCommand(
        key: revisionKey,
        kind: tradeChangeKind,
        body: changeReview().request(revisionKey, null),
      );
      await store.save(revisionUser, revisionShop, command);
      final restored = await store.read(revisionUser, revisionShop);
      expect(restored!.body, command.body);
      expect(
        matchesTradeChangeEnvelope(revisionKey, tradeChangeKind, {
          ...command.body,
          'p_replacement': sourceTrade(),
        }),
        isFalse,
      );
      expect(
        matchesTradeChangeEnvelope(revisionKey, tradeChangeKind, {
          ...command.body,
          'extra': true,
        }),
        isFalse,
      );
      await expectLater(
        store.save(
          revisionUser,
          revisionShop,
          PendingFinancialCommand(
            key: revisionDay,
            kind: tradeChangeKind,
            body: changeReview().request(revisionDay, null),
          ),
        ),
        throwsStateError,
      );
    },
  );
  test('an unpaid historical purchase may retain a JSON-null tender array', () {
    final json = reviewJson(kind: 'purchase');
    ((json['source'] as Map)['payload'] as Map)['tenders'] = null;
    final review = parseTradeChangeReview(
      json,
      shopId: revisionShop,
      operationId: revisionOperation,
      action: 'delete',
    );
    expect((review.source['payload'] as Map)['tenders'], isNull);
  });
  test(
    'HTTP owner checks, exact review, posting and retry use one body',
    () async {
      final seen = <Map<String, Object?>>[];
      final gateway = HttpOpeningGateway(
        supabaseUrl: 'https://example.test',
        publishableKey: 'public',
        accessToken: () => 'token',
        currentUserId: () => revisionUser,
        client: MockClient((request) async {
          seen.add(Map<String, Object?>.from(jsonDecode(request.body) as Map));
          return http.Response(
            jsonEncode(
              request.url.path.endsWith('review_ledger_trade_change_v1')
                  ? reviewJson()
                  : {
                      'ok': true,
                      'operation_id': revisionOperation,
                      'replayed': true,
                    },
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final review = await gateway.reviewTradeChange(
        userId: revisionUser,
        shopId: revisionShop,
        operationId: revisionOperation,
        action: 'delete',
      );
      final command = PendingFinancialCommand(
        key: revisionKey,
        kind: tradeChangeKind,
        body: review.request(revisionKey, null),
      );
      expect(
        await gateway.postTradeChange(userId: revisionUser, command: command),
        isA<FinancialCommitted>(),
      );
      expect(
        await gateway.retryPending(
          callerUserId: revisionUser,
          command: command,
        ),
        isA<FinancialCommitted>(),
      );
      expect(seen[1], seen[2]);
      expect(seen[1], command.body);
      expect(
        await gateway.postTradeChange(userId: 'other-owner', command: command),
        isA<FinancialRejected>(),
      );
      expect(seen, hasLength(3));
    },
  );
  for (final status in ['absent', 'completed', 'denied']) {
    test(
      'retired return retry reconciles $status without invoking a writer',
      () async {
        final paths = <String>[];
        final gateway = HttpOpeningGateway(
          supabaseUrl: 'https://example.test',
          publishableKey: 'public',
          accessToken: () => 'token',
          currentUserId: () => revisionUser,
          client: MockClient((request) async {
            paths.add(request.url.path);
            return http.Response(
              jsonEncode(
                status == 'denied'
                    ? {'code': 'P0001', 'message': 'forbidden'}
                    : {
                        'status': status,
                        if (status == 'completed')
                          'operation_id': revisionOperation,
                      },
              ),
              status == 'denied' ? 403 : 200,
            );
          }),
        );
        final result = await gateway.retryPending(
          callerUserId: revisionUser,
          command: const PendingFinancialCommand(
            key: revisionKey,
            kind: 'linked_return',
            body: {},
          ),
        );
        expect(
          result,
          status == 'absent'
              ? isA<FinancialRejected>()
              : status == 'completed'
              ? isA<FinancialCommitted>()
              : isA<FinancialUnknown>(),
        );
        expect(paths, ['/rest/v1/rpc/get_opening_status']);
      },
    );
  }
  Future<void> pumpReview(
    WidgetTester t,
    RevisionGateway gateway, {
    Listenable? ticks,
    bool Function()? canWrite,
  }) async {
    await t.pumpWidget(
      revisionHost(
        LedgerTradeChangeScreen(
          review: changeReview(),
          gateway: gateway,
          statusGateway: gateway,
          userId: revisionUser,
          canRead: () => true,
          canWrite: canWrite ?? () => true,
          syncTicks: ticks,
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'delete shows cash and inventory summary before durable submit, blocks duplicate tap',
    (t) async {
      final gateway = RevisionGateway()
        ..heldPost = Completer<FinancialCommandResult>();
      await pumpReview(t, gateway);
      expect(
        find.textContaining('المخزون · مشغولات · عيار 21'),
        findsOneWidget,
      );
      expect(find.textContaining('نقص \u2066100'), findsOneWidget);
      expect(gateway.posts, isEmpty);
      final confirm = find.byKey(const Key('trade-change-confirm'));
      await t.ensureVisible(confirm);
      await t.tap(confirm);
      await t.pump();
      await t.tap(confirm);
      await t.pump();
      expect(gateway.posts, hasLength(1));
      expect(gateway.pendingAtPost, isTrue);
      gateway.heldPost!.complete(
        const FinancialCommitted(revisionOperation, replayed: false),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('trade-change-done')), findsOneWidget);
      expect(
        await const PendingFinancialCommands().read(revisionUser, revisionShop),
        isNull,
      );
    },
  );
  testWidgets(
    'unknown result and denied retry retain exact pending envelope; expired reader can reconcile',
    (t) async {
      var writable = true;
      final gateway = RevisionGateway()..result = const FinancialUnknown();
      final ticks = ChangeNotifier();
      await pumpReview(t, gateway, ticks: ticks, canWrite: () => writable);
      await t.ensureVisible(find.byKey(const Key('trade-change-confirm')));
      await t.tap(find.byKey(const Key('trade-change-confirm')));
      await t.pumpAndSettle();
      final saved = await const PendingFinancialCommands().read(
        revisionUser,
        revisionShop,
      );
      gateway.result = const FinancialRejected('forbidden');
      await t.ensureVisible(find.byKey(const Key('trade-change-retry')));
      await t.tap(find.byKey(const Key('trade-change-retry')));
      await t.pumpAndSettle();
      expect(gateway.posts.last.body, saved!.body);
      expect(
        (await const PendingFinancialCommands().read(
          revisionUser,
          revisionShop,
        ))!.body,
        saved.body,
      );
      writable = false;
      ticks.notifyListeners();
      gateway.statusResult = const StatusCompleted(revisionOperation);
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('التحقق من النتيجة'));
      await t.tap(find.text('التحقق من النتيجة'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('trade-change-done')), findsOneWidget);
    },
  );
  testWidgets('sync invalidates unsent review', (t) async {
    final gateway = RevisionGateway();
    final ticks = ChangeNotifier();
    await pumpReview(t, gateway, ticks: ticks);
    ticks.notifyListeners();
    await t.pumpAndSettle();
    expect(
      t
          .widget<FilledButton>(find.byKey(const Key('trade-change-confirm')))
          .onPressed,
      isNull,
    );
    expect(gateway.posts, isEmpty);
  });
  testWidgets(
    'details replace returns with edit and delete; server refuses ineligible source before posting',
    (t) async {
      final gateway = RevisionGateway()..reviewFailure = 'trade_has_followups';
      await t.pumpWidget(
        revisionHost(
          FinancialOperationScreen(
            gateway: gateway,
            userId: revisionUser,
            shopId: revisionShop,
            line: line(),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('operation-create-return')), findsNothing);
      await t.scrollUntilVisible(
        find.byKey(const Key('operation-edit')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.byKey(const Key('operation-edit')), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('operation-delete')));
      await t.tap(find.byKey(const Key('operation-delete')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('operation-change-error')), findsOneWidget);
      expect(gateway.posts, isEmpty);
    },
  );
  testWidgets(
    'prefilled edit preserves original three-decimal gold and details without posting a new trade',
    (t) async {
      final gateway = RevisionGateway();
      Map<String, Object?>? replacement;
      await t.pumpWidget(
        revisionHost(
          FinancialTradeScreen(
            kind: FinancialKind.sale,
            gateway: gateway,
            statusGateway: gateway,
            userId: revisionUser,
            shopId: revisionShop,
            initialPayload: sourceTrade(),
            onDraftReviewed: (draft) async {
              replacement = draft.toJson();
              return false;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(find.byKey(const Key('trade-grams-0')))
            .controller!
            .text,
        '1.255',
      );
      await t.ensureVisible(find.byKey(const Key('trade-review')));
      await t.tap(find.byKey(const Key('trade-review')));
      await t.pumpAndSettle();
      expect(replacement, sourceTrade());
      expect(gateway.keys, isEmpty);
    },
  );
  testWidgets(
    'priced edit preserves line price, invoice components and exact source weight',
    (t) async {
      final gateway = RevisionGateway();
      final original = sourceTrade()..['version'] = 2;
      original['pricing'] = {
        'base_piastres': '8000',
        'workmanship_piastres': '2000',
        'other_charges_piastres': '0',
        'other_charges_label': '',
        'discount_piastres': '0',
      };
      ((original['items'] as List).single as Map)['line_price_piastres'] =
          '8000';
      Map<String, Object?>? replacement;
      await t.pumpWidget(
        revisionHost(
          FinancialTradeScreen(
            kind: FinancialKind.sale,
            gateway: gateway,
            statusGateway: gateway,
            userId: revisionUser,
            shopId: revisionShop,
            initialPayload: original,
            onDraftReviewed: (draft) async {
              replacement = draft.toJson();
              return false;
            },
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('trade-review')));
      await t.tap(find.byKey(const Key('trade-review')));
      await t.pumpAndSettle();
      expect(replacement, original);
      expect(gateway.keys, isEmpty);
    },
  );
}
