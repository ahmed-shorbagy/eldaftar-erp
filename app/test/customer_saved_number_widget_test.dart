import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eldafttar/src/features/customers/presentation/customer_screen.dart';
import 'package:eldafttar/src/features/customers/domain/customer_contact.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'customer_saved_number_test.dart';
import 'customer_fixtures.dart';
import 'customer_widget_test.dart' show customerHost, size;
import 'customer_contact_test.dart' show ContactLauncherFake;
import 'repair_command_flow_test.dart' show MemoryLocker;

CustomerScreen savedScreen(
  SavedFake g,
  MemoryLocker store, {
  bool readOnly = false,
  Listenable? sync,
  bool Function()? canRead,
  String owner = savedOwner,
  CustomerContactLauncher? launcher,
}) => CustomerScreen(
  gateway: g,
  store: store,
  userId: owner,
  shopId: 'shop',
  readOnly: readOnly,
  syncTicks: sync,
  canRead: canRead,
  newKey: () => commandKey,
  contactLauncher: launcher ?? ContactLauncherFake(),
);
Future<void> openSaved(WidgetTester t) async {
  await t.tap(find.byKey(const Key('customer-$customerId')));
  await t.pumpAndSettle();
  await showSavedControl(t);
  await t.tap(find.byKey(const Key('saved-number-$numberId')));
  await t.pumpAndSettle();
}

Future<void> showSavedControl(WidgetTester t) async {
  await t.scrollUntilVisible(
    find.byKey(const Key('saved-number-$numberId')),
    300,
    scrollable: find.byType(Scrollable).last,
  );
  await t.pumpAndSettle();
}

Future<void> reviewSaved(
  WidgetTester t, {
  String label = 'أكد المالك حفظ الرقم',
}) async {
  await t.tap(find.text(label).last);
  await t.pumpAndSettle();
  await t.ensureVisible(find.text('مراجعة إقرار المالك'));
  await t.tap(find.text('مراجعة إقرار المالك'));
  await t.pumpAndSettle();
}

class SessionSavedFake extends SavedFake implements CustomerContactSession {
  Object? stamp = 'token';
  @override
  Object? contactSession(String callerUserId) => stamp;
}

void main() {
  testWidgets('revoked mutation clears cached customer data', (t) async {
    size(t);
    final g = SavedFake()..rejected = 'forbidden';
    final store = MemoryLocker();
    await t.pumpWidget(customerHost(savedScreen(g, store)));
    await t.pumpAndSettle();
    await openSaved(t);
    await reviewSaved(t);
    await t.tap(find.byKey(const Key('customer-confirm')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('customer-success')), findsNothing);
    expect(find.byKey(const Key('customer-$customerId')), findsNothing);
    expect(find.textContaining('انتهى الوصول'), findsWidgets);
  });
  testWidgets(
    'no phone is unavailable; revision refreshes current primary declaration',
    (t) async {
      size(t);
      final g = SavedFake()..row['phones'] = <Object?>[];
      final store = MemoryLocker();
      final sync = ChangeNotifier();
      addTearDown(sync.dispose);
      await t.pumpWidget(customerHost(savedScreen(g, store, sync: sync)));
      await t.pumpAndSettle();
      expect(find.textContaining('غير متاحة؛ بدون هاتف'), findsOneWidget);
      g.row['phones'] = savedPhones('saved');
      sync.notifyListeners();
      await t.pumpAndSettle();
      expect(
        find.textContaining(
          'حالة حفظ الرقم الأساسي لواتساب: أكد المالك حفظ الرقم',
        ),
        findsOneWidget,
      );
      expect(g.sent, isEmpty);
    },
  );
  testWidgets(
    'number incarnation change during preparation cannot transfer declaration',
    (t) async {
      size(t);
      final g = SavedFake();
      final store = MemoryLocker();
      await t.pumpWidget(customerHost(savedScreen(g, store)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('customer-$customerId')));
      await t.pumpAndSettle();
      await showSavedControl(t);
      final held = Completer<void>();
      g.readHold = held.future;
      await t.tap(find.byKey(const Key('saved-number-$numberId')));
      await t.pump();
      final phones = savedPhones('unknown', declared: false);
      (phones.first as Map)['saved_number'] = savedJson(
        'unknown',
        id: commandKey,
        declared: false,
      );
      g.row['phones'] = phones;
      held.complete();
      await t.pumpAndSettle();
      expect(find.text('مراجعة إقرار المالك'), findsNothing);
      expect(g.sent, isEmpty);
      expect(find.textContaining('تغيّر رقم الهاتف'), findsOneWidget);
    },
  );
  for (final state in ['saved', 'not_saved', 'unknown']) {
    testWidgets(
      'review and server-confirmed $state with zero financial effects',
      (t) async {
        size(t);
        final g = SavedFake();
        final store = MemoryLocker();
        await t.pumpWidget(customerHost(savedScreen(g, store)));
        await t.pumpAndSettle();
        expect(
          find.textContaining('حالة حفظ الرقم الأساسي لواتساب'),
          findsOneWidget,
        );
        await openSaved(t);
        expect(find.textContaining('إقرار من المالك'), findsOneWidget);
        await reviewSaved(
          t,
          label: switch (state) {
            'saved' => 'أكد المالك حفظ الرقم',
            'not_saved' => 'حدد المالك أن الرقم غير محفوظ',
            _ => 'مسح الإقرار — لم يحدد المالك الحالة',
          },
        );
        expect(find.textContaining('لا يتغير النقد'), findsOneWidget);
        expect(g.sent, isEmpty);
        await t.tap(find.byKey(const Key('customer-confirm')));
        await t.pumpAndSettle();
        expect(find.byKey(const Key('customer-success')), findsOneWidget);
        expect((g.sent.single.body['p_payload'] as Map)['state'], state);
        expect(store.stored, isNull);
        await t.tap(find.text('عرض ملف العميل'));
        await t.pumpAndSettle();
        expect(g.row['record_version'], '2');
      },
    );
  }
  testWidgets('preparing review and pending disable duplicate submissions', (
    t,
  ) async {
    size(t);
    final g = SavedFake();
    final store = MemoryLocker();
    await t.pumpWidget(customerHost(savedScreen(g, store)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('customer-$customerId')));
    await t.pumpAndSettle();
    final preparation = Completer<void>();
    g.readHold = preparation.future;
    await showSavedControl(t);
    await t.tap(find.byKey(const Key('saved-number-$numberId')));
    await t.pump();
    expect(find.text('جارٍ تجهيز حالة الرقم الحالية…'), findsOneWidget);
    expect(g.sent, isEmpty);
    preparation.complete();
    await t.pumpAndSettle();
    g.readHold = null;
    await reviewSaved(t);
    final commit = Completer<void>();
    g.hold = commit.future;
    g.unknown = true;
    await t.tap(find.byKey(const Key('customer-confirm')));
    await t.pump();
    expect(
      t
          .widget<FilledButton>(find.byKey(const Key('customer-confirm')))
          .onPressed,
      isNull,
    );
    commit.complete();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('customer-pending')), findsOneWidget);
    expect(find.byKey(const Key('customer-success')), findsNothing);
    expect(g.sent.length, 1);
    g.unknown = false;
    g.hold = null;
    await t.tap(find.byKey(const Key('customer-retry')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('customer-success')), findsOneWidget);
    expect(g.sent.length, 1);
  });
  testWidgets(
    'stale number rejection and revision disable review until reopened',
    (t) async {
      size(t);
      final g = SavedFake()..rejected = 'stale_number';
      final store = MemoryLocker();
      final sync = ChangeNotifier();
      addTearDown(sync.dispose);
      await t.pumpWidget(customerHost(savedScreen(g, store, sync: sync)));
      await t.pumpAndSettle();
      await openSaved(t);
      await reviewSaved(t);
      await t.tap(find.byKey(const Key('customer-confirm')));
      await t.pumpAndSettle();
      expect(find.textContaining('تغيّر رقم الهاتف'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('customer-confirm')))
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'sync invalidates a status review; unknown and foreign locker remain untouched',
    (t) async {
      size(t);
      final g = SavedFake();
      final store = MemoryLocker();
      final sync = ChangeNotifier();
      addTearDown(sync.dispose);
      await t.pumpWidget(customerHost(savedScreen(g, store, sync: sync)));
      await t.pumpAndSettle();
      await openSaved(t);
      await reviewSaved(t);
      sync.notifyListeners();
      await t.pumpAndSettle();
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('customer-confirm')))
            .onPressed,
        isNull,
      );
      expect(g.sent, isEmpty);
      await t.pumpWidget(const SizedBox());
      const foreign = PendingFinancialCommand(
        key: commandKey,
        kind: 'expense',
        body: {},
      );
      store.stored = foreign;
      await t.pumpWidget(customerHost(savedScreen(g, store)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('customer-$customerId')));
      await t.pumpAndSettle();
      await showSavedControl(t);
      expect(
        t
            .widget<OutlinedButton>(
              find.byKey(const Key('saved-number-$numberId')),
            )
            .onPressed,
        isNull,
      );
      expect(store.stored, same(foreign));
    },
  );
  testWidgets(
    'expired readers have honest states and no write controls; archived owners can edit',
    (t) async {
      size(t);
      final g = SavedFake()..row['status'] = 'archived';
      final store = MemoryLocker();
      await t.pumpWidget(customerHost(savedScreen(g, store, readOnly: true)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('customer-$customerId')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('saved-number-$numberId')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(customerHost(savedScreen(g, store)));
      await t.pumpAndSettle();
      await openSaved(t);
      expect(find.text('مراجعة إقرار المالك'), findsOneWidget);
    },
  );
  testWidgets(
    'keyboard selects declaration; contact handoff leaves declarations and locker unchanged',
    (t) async {
      size(t);
      final g = SavedFake();
      final store = MemoryLocker();
      final launcher = ContactLauncherFake();
      await t.pumpWidget(
        customerHost(savedScreen(g, store, launcher: launcher)),
      );
      await t.pumpAndSettle();
      await openSaved(t);
      final client =
          t.state(find.byType(RadioListTile<String>).first)
              as RadioClient<String>;
      client.focusNode.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pumpAndSettle();
      expect(
        t
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        'saved',
      );
      await t.tap(find.byTooltip('رجوع'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('واتساب'));
      await t.tap(find.text('واتساب'));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('customer-contact-open')));
      await t.tap(find.byKey(const Key('customer-contact-open')));
      await t.pumpAndSettle();
      expect(g.sent, isEmpty);
      expect(store.stored, isNull);
      expect(
        (g.row['phones'] as List).first['saved_number']['state'],
        'unknown',
      );
    },
  );
  testWidgets(
    'late result after token change clears data and never displays confirmed',
    (t) async {
      size(t);
      final g = SessionSavedFake();
      final store = MemoryLocker();
      await t.pumpWidget(customerHost(savedScreen(g, store)));
      await t.pumpAndSettle();
      await openSaved(t);
      await reviewSaved(t);
      final held = Completer<void>();
      g.hold = held.future;
      await t.tap(find.byKey(const Key('customer-confirm')));
      await t.pump();
      g.stamp = null;
      held.complete();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('customer-success')), findsNothing);
      expect(find.textContaining('انتهى الوصول'), findsWidgets);
      expect(find.byKey(const Key('customer-$customerId')), findsNothing);
    },
  );
}
