import 'dart:async';
import 'package:eldafttar/src/features/customers/presentation/customer_screen.dart';
import 'package:eldafttar/src/features/customers/application/customer_gateway.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'customer_fixtures.dart';
import 'repair_command_flow_test.dart' show MemoryLocker;

Widget customerHost(
  Widget child, {
  Brightness brightness = Brightness.light,
  double scale = 1,
}) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: GlobalMaterialLocalizations.delegates,
  theme: AppTheme.light(),
  darkTheme: AppTheme.dark(),
  themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);
CustomerScreen customerScreen(
  FakeCustomers g,
  MemoryLocker store, {
  Listenable? sync,
  bool readOnly = false,
}) => CustomerScreen(
  gateway: g,
  store: store,
  userId: 'owner',
  shopId: 'shop',
  syncTicks: sync,
  readOnly: readOnly,
);
void size(WidgetTester t, {double width = 390}) {
  t.view.physicalSize = Size(width, 1000);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('creates no-phone customer only after confirmation', (t) async {
    size(t);
    final g = FakeCustomers();
    final store = MemoryLocker();
    await t.pumpWidget(customerHost(customerScreen(g, store)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('customer-create')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('customer-name')), 'عميل جديد');
    await t.ensureVisible(find.byKey(const Key('customer-save')));
    await t.tap(find.byKey(const Key('customer-save')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('customer-success')), findsOneWidget);
    expect((g.sent.single.body['p_payload'] as Map)['phones'], isEmpty);
    expect(store.stored, isNull);
  });
  testWidgets('normalized duplicate phones never reach gateway', (t) async {
    size(t);
    final g = FakeCustomers();
    await t.pumpWidget(customerHost(customerScreen(g, MemoryLocker())));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('customer-create')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('customer-name')), 'عميل جديد');
    for (var i = 0; i < 2; i++) {
      await t.ensureVisible(find.byKey(const Key('customer-add-phone')));
      await t.tap(find.byKey(const Key('customer-add-phone')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(Key('customer-phone-$i')),
        i == 0 ? '01011111111' : '+201011111111',
      );
    }
    await t.ensureVisible(find.byKey(const Key('customer-save')));
    await t.tap(find.byKey(const Key('customer-save')));
    await t.pumpAndSettle();
    expect(find.text('رقم الهاتف مكرر في هذا الملف.'), findsOneWidget);
    expect(g.sent, isEmpty);
  });
  testWidgets(
    'unknown request freezes writes and original retry confirms without repost',
    (t) async {
      size(t);
      final g = FakeCustomers()..unknown = true;
      final store = MemoryLocker();
      await t.pumpWidget(customerHost(customerScreen(g, store)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('customer-create')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('customer-name')), 'عميل جديد');
      await t.tap(find.byKey(const Key('customer-save')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('customer-pending')), findsOneWidget);
      expect(find.byKey(const Key('customer-success')), findsNothing);
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('customer-save')))
            .onPressed,
        isNull,
      );
      g.statusOverride = CustomerTransport(receipt: g.committed);
      await t.ensureVisible(find.byKey(const Key('customer-retry')));
      await t.tap(find.byKey(const Key('customer-retry')));
      await t.pumpAndSettle();
      expect(g.sent, hasLength(1));
      expect(find.byKey(const Key('customer-success')), findsOneWidget);
    },
  );
  testWidgets('duplicate taps while transport in flight submit once', (
    t,
  ) async {
    size(t);
    final hold = Completer<void>();
    final g = FakeCustomers()..hold = hold.future;
    await t.pumpWidget(customerHost(customerScreen(g, MemoryLocker())));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('customer-create')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('customer-name')), 'عميل جديد');
    await t.tap(find.byKey(const Key('customer-save')));
    await t.pump();
    await t.tap(find.byKey(const Key('customer-save')), warnIfMissed: false);
    await t.pump();
    expect(g.sent, hasLength(1));
    hold.complete();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('customer-success')), findsOneWidget);
  });
  testWidgets('sync preserves edit draft and disables stale save', (t) async {
    size(t);
    final sync = ChangeNotifier();
    addTearDown(sync.dispose);
    final g = FakeCustomers();
    await t.pumpWidget(
      customerHost(customerScreen(g, MemoryLocker(), sync: sync)),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('customer-$customerId')));
    await t.pumpAndSettle();
    await t.tap(find.text('تعديل بيانات العميل'));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('customer-name')), 'مسودة العميل');
    sync.notifyListeners();
    await t.pumpAndSettle();
    expect(find.text('مسودة العميل'), findsOneWidget);
    expect(
      t.widget<FilledButton>(find.byKey(const Key('customer-save'))).onPressed,
      isNull,
    );
    expect(g.sent, isEmpty);
  });
  testWidgets(
    'explicit link review uses original party and zero financial effect',
    (t) async {
      size(t);
      final g = FakeCustomers();
      await t.pumpWidget(customerHost(customerScreen(g, MemoryLocker())));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('customer-$customerId')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('ربط عملية مؤكدة'));
      await t.tap(find.text('ربط عملية مؤكدة'));
      await t.pumpAndSettle();
      await t.tap(find.text('شراء · رقم 7'));
      await t.pumpAndSettle();
      expect(find.text('طرف العملية الأصلي'), findsOneWidget);
      expect(find.textContaining('لا يتغير النقد'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('customer-confirm')));
      await t.tap(find.byKey(const Key('customer-confirm')));
      await t.pumpAndSettle();
      expect(g.sent.single.kind, 'customer_link');
      expect(
        (g.sent.single.body['p_payload'] as Map)['operation_id'],
        operationId,
      );
    },
  );
  testWidgets('expiry preserves detail and hides mutation controls', (t) async {
    size(t);
    final g = FakeCustomers();
    await t.pumpWidget(
      customerHost(customerScreen(g, MemoryLocker(), readOnly: true)),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('customer-create')), findsNothing);
    await t.tap(find.byKey(const Key('customer-$customerId')));
    await t.pumpAndSettle();
    expect(find.text('تعديل بيانات العميل'), findsNothing);
    expect(find.text('إضافة ملاحظة'), findsNothing);
    expect(find.text('لا توجد عمليات مرتبطة بهذا العميل.'), findsOneWidget);
  });
  testWidgets('customer sync catches up list without manual reload', (t) async {
    size(t);
    final sync = ChangeNotifier();
    addTearDown(sync.dispose);
    final g = FakeCustomers();
    await t.pumpWidget(
      customerHost(customerScreen(g, MemoryLocker(), sync: sync)),
    );
    await t.pumpAndSettle();
    g.row['display_name'] = 'اسم من جلسة ثانية';
    sync.notifyListeners();
    await t.pumpAndSettle();
    expect(find.text('اسم من جلسة ثانية'), findsOneWidget);
    expect(g.reads, 2);
  });
  testWidgets(
    'revocation clears loaded customer data and disables mutation controls',
    (t) async {
      size(t);
      final sync = ChangeNotifier();
      addTearDown(sync.dispose);
      final g = FakeCustomers();
      await t.pumpWidget(
        customerHost(customerScreen(g, MemoryLocker(), sync: sync)),
      );
      await t.pumpAndSettle();
      expect(find.text('عميل اختبار'), findsOneWidget);
      g.readError = 'forbidden';
      sync.notifyListeners();
      await t.pumpAndSettle();
      expect(find.text('عميل اختبار'), findsNothing);
      expect(find.byKey(const Key('customer-create')), findsNothing);
      expect(g.sent, isEmpty);
    },
  );
}
