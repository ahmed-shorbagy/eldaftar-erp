import 'dart:async';
import 'dart:convert';
import 'package:eldafttar/src/features/closing_delegation/application/closing_delegation_gateway.dart';
import 'package:eldafttar/src/features/closing_delegation/application/delegation_flow.dart';
import 'package:eldafttar/src/features/closing_delegation/data/closing_delegation_codec.dart';
import 'package:eldafttar/src/features/closing_delegation/data/secure_delegation_pending_store.dart';
import 'package:eldafttar/src/features/closing_delegation/presentation/staff_count_portal.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const delegateShop = '22222222-2222-4222-8222-222222222222';
const delegateTask = '33333333-3333-4333-8333-333333333333';
const delegateKey = '44444444-4444-4444-8444-444444444444';
Map<String, Object?> assignmentJson() => {
  'state': 'assigned',
  'task_id': delegateTask,
  'shop_name': 'متجر تجريبي',
  'staff_name': 'موظف تجريبي',
  'business_date': '2026-10-20',
  'server_now': '2026-10-20T10:00:00Z',
  'expires_at': '2026-10-20T10:00:10Z',
  'stock': [
    {'category': 'worked_jewelry', 'karat': 21},
  ],
  'scrap_karats': [21],
};

class DelegateFake implements ClosingDelegationGateway {
  StaffCountAssignment assignment = parseStaffCountAssignment(assignmentJson());
  DelegationResult result = const DelegationCommitted();
  DelegationStatus status = DelegationStatus.absent;
  final keys = <String>[], bodies = <Map<String, Object?>>[];
  Completer<DelegationResult>? gate;
  @override
  Future<StaffCountAssignment> myClosingAssignment({
    required String userId,
  }) async => assignment;
  @override
  Future<ClosingStaffDirectory> closingStaff({
    required String userId,
    required String shopId,
  }) async => ClosingStaffDirectory(shopId, [], []);
  @override
  Future<DelegationResult> createClosingStaff({
    required String userId,
    required String key,
    required String name,
    required String phone,
    required String password,
  }) async {
    keys.add(key);
    bodies.add({'name': name, 'phone': phone});
    return gate?.future ?? result;
  }

  @override
  Future<DelegationStatus> closingStaffCreationStatus({
    required String userId,
    required String key,
  }) async => status;
  @override
  Future<DelegationStatus> closingDelegationStatus({
    required String userId,
    required String key,
  }) async => status;
  @override
  Future<DelegationResult> changeClosingAssignment({
    required String userId,
    required String key,
    required String action,
    required String target,
    String? dayId,
    String? dayVersion,
  }) async => result;
  @override
  Future<DelegationResult> submitClosingCount({
    required String userId,
    required String key,
    required String taskId,
    required Map<String, Object?> observations,
  }) async {
    keys.add(key);
    bodies.add(observations);
    final resolved = await (gate?.future ?? Future.value(result));
    if (resolved is DelegationCommitted) {
      assignment = const StaffCountAssignment(state: 'unassigned');
    }
    return resolved;
  }

  @override
  Future<FinancialCommandResult> closeFromStaffCount({
    required String userId,
    required String key,
    required String taskId,
    required Map<String, Object?> cash,
  }) async => const FinancialUnknown();
}

Widget delegateHost(Widget child) => MaterialApp(
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  home: child,
);
Future<void> delegateTap(WidgetTester t, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      finder,
      180,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await t.ensureVisible(finder);
  await t.pumpAndSettle();
  await t.tap(finder);
  await t.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'staff task contains only count-form specification and server-derived expiry',
    () {
      final assignment = parseStaffCountAssignment(assignmentJson());
      expect(assignment.remaining, const Duration(seconds: 10));
      expect(assignment.stock.single.karat, 21);
      expect(assignment.itemNames, isEmpty);
      for (final field in ['cash', 'counts', 'customer', 'milligrams']) {
        expect(assignmentJson().containsKey(field), isFalse);
      }
      final named = parseStaffCountAssignment({
        ...assignmentJson(),
        'item_names': [
          {'name': 'دبلة', 'category': 'worked_jewelry', 'karat': 21},
        ],
      });
      expect(named.itemNames.single.name, 'دبلة');
      expect(named.itemNames.single.category, 'worked_jewelry');
      expect(named.itemNames.single.karat, 21);
      expect(
        () => parseStaffCountAssignment({
          ...assignmentJson(),
          'item_names': [
            {
              'name': 'دبلة',
              'category': 'worked_jewelry',
              'karat': 21,
              'count': '4',
            },
          ],
        }),
        throwsFormatException,
      );
      final malformed = assignmentJson()
        ..['expires_at'] = '2026-10-20T09:59:59Z';
      expect(() => parseStaffCountAssignment(malformed), throwsFormatException);
    },
  );
  test(
    'durable creation recovery never stores password and retains the key after a timeout',
    () async {
      final g = DelegateFake()..result = const DelegationUnknown();
      const store = SecureDelegationPendingStore();
      final flow = DelegationFlow(
        gateway: g,
        store: store,
        userId: 'owner-1',
        scope: 'owner:$delegateShop',
      );
      const command = PendingDelegation(delegateKey, 'create', {
        'name': 'موظف تجريبي',
        'phone': '201000000001',
      });
      await flow.run(command, password: 'test-password');
      final stored = await const FlutterSecureStorage().readAll();
      expect(stored.values.join(), isNot(contains('test-password')));
      expect(stored.values.join(), isNot(contains('password')));
      g.status = DelegationStatus.prepared;
      final resumed = DelegationFlow(
        gateway: g,
        store: store,
        userId: 'owner-1',
        scope: 'owner:$delegateShop',
      );
      await resumed.restore();
      expect(resumed.pending?.key, delegateKey);
      g.result = const DelegationRejected('payload_mismatch');
      await resumed.run(resumed.pending!, password: 'wrong-password');
      expect(resumed.pending?.key, delegateKey);
      expect(resumed.status, DelegationStatus.prepared);
      g.result = const DelegationCommitted();
      await resumed.run(resumed.pending!, password: 'test-password');
      expect(g.keys, [delegateKey, delegateKey, delegateKey]);
      expect(await store.read('owner-1', 'owner:$delegateShop'), isNull);
    },
  );
  test(
    'simultaneous pending envelopes cannot replace another in-flight command',
    () async {
      const store = SecureDelegationPendingStore();
      final results = await Future.wait([
        store
            .save(
              'owner-1',
              'owner:$delegateShop',
              const PendingDelegation(delegateKey, 'disable', {
                'target': delegateTask,
              }),
            )
            .then((_) => true, onError: (Object error) => false),
        store
            .save(
              'owner-1',
              'owner:$delegateShop',
              const PendingDelegation(
                '55555555-5555-4555-8555-555555555555',
                'revoke',
                {'target': delegateTask},
              ),
            )
            .then((_) => true, onError: (Object error) => false),
      ]);
      expect(results.where((success) => success), hasLength(1));
      expect(
        (await store.read('owner-1', 'owner:$delegateShop'))?.key,
        delegateKey,
      );
    },
  );
  test(
    'an owner switch during staff provisioning stays unknown and sends no later request as the next owner',
    () async {
      var owner = 'owner-1';
      final gate = Completer<http.Response>();
      var calls = 0;
      final gateway = HttpOpeningGateway(
        client: MockClient((request) {
          calls++;
          return gate.future;
        }),
        supabaseUrl: 'https://example.test',
        publishableKey: 'test',
        accessToken: () => 'token-$owner',
        currentUserId: () => owner,
      );
      final pending = gateway.createClosingStaff(
        userId: 'owner-1',
        key: delegateKey,
        name: 'موظف',
        phone: '201000000001',
        password: 'test-password',
      );
      owner = 'owner-2';
      gate.complete(
        http.Response(
          jsonEncode({'ok': true, 'staff_id': delegateTask, 'replayed': false}),
          200,
        ),
      );
      expect(await pending, isA<DelegationUnknown>());
      expect(
        await gateway.createClosingStaff(
          userId: 'owner-1',
          key: delegateKey,
          name: 'موظف',
          phone: '201000000001',
          password: 'test-password',
        ),
        isA<DelegationRejected>(),
      );
      expect(calls, 1);
    },
  );
  testWidgets(
    'staff reviews exact physical count and loses the form only after confirmed submission',
    (t) async {
      final g = DelegateFake();
      await t.pumpWidget(
        delegateHost(
          StaffCountPortal(
            gateway: g,
            userId: 'staff-1',
            onSignOut: () async {},
            onToggleTheme: (_) async {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('خاتم'), findsOneWidget);
      expect(find.text('حلق'), findsOneWidget);
      expect(find.text('سلسلة'), findsOneWidget);
      expect(find.text('تعليقة'), findsOneWidget);
      expect(find.text('مشغولات'), findsNothing);
      await t.enterText(find.byKey(const Key('close-count-0-21')), '5');
      await t.enterText(find.byKey(const Key('close-count-0-21')), '2.5');
      expect(
        t
            .widget<TextField>(find.byKey(const Key('close-count-0-21')))
            .controller!
            .text,
        '5',
      );
      await t.enterText(find.byKey(const Key('staff-scrap-21')), '1.000');
      await delegateTap(t, find.byKey(const Key('staff-count-review')));
      expect(g.keys, isEmpty);
      expect(find.textContaining('لم يُوزن'), findsOneWidget);
      await delegateTap(t, find.text('رجوع للتعديل'));
      expect(
        t
            .widget<TextField>(find.byKey(const Key('close-count-0-21')))
            .controller!
            .text,
        '5',
      );
      await delegateTap(t, find.byKey(const Key('staff-count-review')));
      await delegateTap(t, find.byKey(const Key('staff-count-submit')));
      expect(g.keys, hasLength(1));
      expect((g.bodies.single['stock'] as List).single['item_name'], 'خاتم');
      expect((g.bodies.single['stock'] as List).single['milligrams'], isNull);
      expect(find.byKey(const Key('close-count-0-21')), findsNothing);
      expect(find.textContaining('تم إرسال العد إلى المالك'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'staff count accepts Arabic-indic grams and keeps milligrams exact',
    (t) async {
      final g = DelegateFake();
      await t.pumpWidget(
        delegateHost(
          StaffCountPortal(
            gateway: g,
            userId: 'staff-1',
            onSignOut: () async {},
            onToggleTheme: (_) async {},
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('close-count-0-21')), '٥');
      expect(
        t
            .widget<TextField>(find.byKey(const Key('close-count-0-21')))
            .controller!
            .text,
        '5',
      );
      await delegateTap(t, find.byKey(const Key('close-weights-toggle')));
      await t.enterText(find.byKey(const Key('close-weight-0-21')), '١٫٥٠٠');
      expect(
        t
            .widget<TextField>(find.byKey(const Key('close-weight-0-21')))
            .controller!
            .text,
        '1.500',
      );
      await t.enterText(find.byKey(const Key('staff-scrap-21')), '٢');
      final scrapField = t.widget<TextField>(
        find.byKey(const Key('staff-scrap-21')),
      );
      expect(scrapField.decoration!.labelText, 'الوزن بالجرام');
      expect(scrapField.decoration!.helperText, 'مطلوب');
      await delegateTap(t, find.byKey(const Key('staff-count-review')));
      expect(g.keys, isEmpty);
      expect(find.textContaining('لم يُوزن'), findsNothing);
      await delegateTap(t, find.byKey(const Key('staff-count-submit')));
      expect(g.keys, hasLength(1));
      expect((g.bodies.single['stock'] as List).single['count'], '5');
      expect((g.bodies.single['stock'] as List).single['milligrams'], '1500');
      expect((g.bodies.single['scrap'] as List).single['milligrams'], '2000');
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'server-derived expiry removes the count form before any submission',
    (t) async {
      final g = DelegateFake();
      await t.pumpWidget(
        delegateHost(
          StaffCountPortal(
            gateway: g,
            userId: 'staff-1',
            onSignOut: () async {},
            onToggleTheme: (_) async {},
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('close-count-0-21')), findsOneWidget);
      g.assignment = const StaffCountAssignment(state: 'unassigned');
      await t.pump(const Duration(seconds: 11));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('close-count-0-21')), findsNothing);
      expect(g.keys, isEmpty);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'staff grid lists built-in names plus server names and caps a count at four digits',
    (t) async {
      final g = DelegateFake()
        ..assignment = parseStaffCountAssignment({
          ...assignmentJson(),
          'item_names': [
            {'name': 'دبلة', 'category': 'worked_jewelry', 'karat': 21},
            {'name': 'جنيه خارج المهمة', 'category': 'coin', 'karat': 21},
          ],
        });
      await t.pumpWidget(
        delegateHost(
          StaffCountPortal(
            gateway: g,
            userId: 'staff-1',
            onSignOut: () async {},
            onToggleTheme: (_) async {},
          ),
        ),
      );
      await t.pumpAndSettle();
      for (final name in ['خاتم', 'حلق', 'سلسلة', 'تعليقة', 'دبلة']) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('جنيه خارج المهمة'), findsNothing);
      expect(find.text('مشغولات'), findsNothing);
      expect(find.byKey(const Key('close-add-item')), findsNothing);
      await t.enterText(find.byKey(const Key('close-count-4-21')), '12345');
      expect(
        t
            .widget<TextField>(find.byKey(const Key('close-count-4-21')))
            .controller!
            .text,
        '1234',
      );
      await t.enterText(find.byKey(const Key('close-count-4-21')), '05');
      await t.enterText(find.byKey(const Key('staff-scrap-21')), '1');
      await delegateTap(t, find.byKey(const Key('staff-count-review')));
      await delegateTap(t, find.byKey(const Key('staff-count-submit')));
      final stock = g.bodies.single['stock'] as List;
      expect(stock, hasLength(1));
      expect(stock.single['item_name'], 'دبلة');
      expect(stock.single['category'], 'worked_jewelry');
      expect(stock.single['karat'], 21);
      expect(stock.single['count'], '5');
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('an untouched zero bucket is sent as a zero count', (t) async {
    final g = DelegateFake()
      ..assignment = parseStaffCountAssignment({
        ...assignmentJson(),
        'stock': [
          {'category': 'worked_jewelry', 'karat': 18},
          {'category': 'worked_jewelry', 'karat': 21},
        ],
      });
    await t.pumpWidget(
      delegateHost(
        StaffCountPortal(
          gateway: g,
          userId: 'staff-1',
          onSignOut: () async {},
          onToggleTheme: (_) async {},
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('عيار 18'), findsOneWidget);
    expect(find.text('عيار 21'), findsWidgets);
    await t.enterText(find.byKey(const Key('close-count-0-21')), '2');
    await t.enterText(find.byKey(const Key('staff-scrap-21')), '1.000');
    await delegateTap(t, find.byKey(const Key('staff-count-review')));
    await delegateTap(t, find.byKey(const Key('staff-count-submit')));
    final stock = (g.bodies.single['stock'] as List).cast<Map>();
    expect(stock, hasLength(2));
    expect(
      stock.singleWhere((row) => row['karat'] == 21),
      containsPair('item_name', 'خاتم'),
    );
    expect(stock.singleWhere((row) => row['karat'] == 21)['count'], '2');
    expect(stock.singleWhere((row) => row['karat'] == 18), {
      'item_name': 'خاتم',
      'category': 'worked_jewelry',
      'karat': 18,
      'count': '0',
      'milligrams': null,
    });
    await t.pumpWidget(const SizedBox());
  });
}
