import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eldafttar/src/features/shop_accounts/application/shop_sync_ticks.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_sync.dart';
import 'package:eldafttar/src/features/customers/application/customer_gateway.dart';
import 'customer_fixtures.dart';
import 'customer_statistics_fixtures.dart';
import 'customer_widget_test.dart';
import 'repair_command_flow_test.dart' show MemoryLocker;

class _UnreadableCustomers extends FakeCustomers {
  bool broken = false;
  @override
  Future<CustomerPage> customers({
    required String callerUserId,
    required String query,
    required String sort,
    required String filter,
    required String? cursor,
  }) {
    if (broken) throw const CustomerReadException();
    return super.customers(
      callerUserId: callerUserId,
      query: query,
      sort: sort,
      filter: filter,
      cursor: cursor,
    );
  }

  @override
  Future<CustomerDetail> customer({
    required String callerUserId,
    required String id,
    String? notesCursor,
    String? historyCursor,
    String? linksCursor,
  }) {
    if (broken) throw const CustomerReadException();
    return super.customer(
      callerUserId: callerUserId,
      id: id,
      notesCursor: notesCursor,
      historyCursor: historyCursor,
      linksCursor: linksCursor,
    );
  }
}

Future<void> _capture(WidgetTester t, GlobalKey key, String name) async {
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await t.runAsync(() async {
    final picture = await boundary.toImage();
    final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/customer-statistics/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  testWidgets('failed detail read retries the selected customer', (t) async {
    size(t);
    final g = _UnreadableCustomers()..row = statisticsCustomerJson();
    await t.pumpWidget(customerHost(customerScreen(g, MemoryLocker())));
    await t.pumpAndSettle();
    g.broken = true;
    await t.tap(find.byKey(const Key('customer-$customerId')));
    await t.pumpAndSettle();
    expect(find.text('إعادة المحاولة'), findsOneWidget);
    g.broken = false;
    await t.tap(find.text('إعادة المحاولة'));
    await t.pumpAndSettle();
    expect(find.text('إحصائيات العملاء'), findsOneWidget);
    expect(find.text('6.000'), findsOneWidget);
  });
  testWidgets('failed statistics refresh visibly marks cached figures stale', (
    t,
  ) async {
    size(t);
    final ticks = ShopSyncTicks();
    addTearDown(ticks.dispose);
    final g = _UnreadableCustomers()..row = statisticsCustomerJson();
    await t.pumpWidget(
      customerHost(customerScreen(g, MemoryLocker(), sync: ticks)),
    );
    await t.pumpAndSettle();
    g.broken = true;
    ticks.apply({ShopSyncScope.ledger});
    await t.pumpAndSettle();
    expect(
      find.textContaining('البيانات المعروضة قد تكون قديمة'),
      findsOneWidget,
    );
    expect(find.text('6.000'), findsOneWidget);
  });
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('Cairo')..addFont(
          Future.value(
            ByteData.sublistView(
              await File('assets/fonts/Cairo.ttf').readAsBytes(),
            ),
          ),
        ))
        .load();
    final sdk = Platform.resolvedExecutable
        .split(RegExp(r'[/\\]bin[/\\]cache[/\\]'))
        .first;
    await (FontLoader('MaterialIcons')..addFont(
          Future.value(
            ByteData.sublistView(
              await File(
                '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
              ).readAsBytes(),
            ),
          ),
        ))
        .load();
  });
  for (final width in [320.0, 390.0, 1440.0]) {
    for (final theme in Brightness.values) {
      for (final scale in [1.0, 1.7]) {
        final suffix = '${width.toInt()}-${theme.name}-$scale';
        testWidgets('Arabic statistics list and detail $suffix', (t) async {
          size(t, width: width);
          final key = GlobalKey();
          final g = FakeCustomers()..row = statisticsCustomerJson();
          g.links.addAll([
            {...candidateJson(), 'link_status': 'active'},
            {
              ...candidateJson(),
              'operation_id': 'ca444444-4444-4444-8444-444444444444',
              'operation_kind': 'sale',
              'label_ar': 'بيع',
              'shop_sequence': '5',
              'link_status': 'active',
            },
          ]);
          await t.pumpWidget(
            customerHost(
              RepaintBoundary(
                key: key,
                child: customerScreen(g, MemoryLocker()),
              ),
              brightness: theme,
              scale: scale,
            ),
          );
          await _capture(t, key, 'list-$suffix');
          expect(find.text('اشترى العميل من المحل (جرام)'), findsOneWidget);
          expect(find.text('6.000'), findsOneWidget);
          final label = t.widget<Text>(find.text('عيار 18'));
          final labelTheme = Theme.of(t.element(find.text('عيار 18')));
          final foreground = label.style!.color!.computeLuminance();
          final background = labelTheme.colorScheme.surfaceContainerLow
              .computeLuminance();
          final contrast = foreground > background
              ? (foreground + 0.05) / (background + 0.05)
              : (background + 0.05) / (foreground + 0.05);
          expect(contrast, greaterThanOrEqualTo(4.5));
          expect(
            Directionality.of(t.element(find.text('6.000'))),
            TextDirection.rtl,
          );
          expect(
            t.widget<Text>(find.text('6.000')).textDirection,
            TextDirection.ltr,
          );
          await t.tap(find.byKey(const Key('customer-$customerId')));
          await t.pumpAndSettle();
          await _capture(t, key, 'detail-$suffix');
          expect(find.text('عيار 14'), findsOneWidget);
          expect(find.text('عيار 22'), findsOneWidget);
          expect(find.text('1.255'), findsOneWidget);
          await t.scrollUntilVisible(
            find.textContaining('عدد عمليات شراء العميل من المحل:'),
            150,
            scrollable: find.byType(Scrollable).first,
          );
          expect(
            find.textContaining('عدد عمليات شراء العميل من المحل:'),
            findsOneWidget,
          );
          await _capture(t, key, 'counts-$suffix');
          await t.scrollUntilVisible(
            find.textContaining('مرتجع شراء العميل'),
            100,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.textContaining('مرتجع شراء العميل'), findsOneWidget);
          expect(find.textContaining('2026-10-14 00:30:00'), findsWidgets);
          await _capture(t, key, 'activity-$suffix');
          await t.scrollUntilVisible(
            find.textContaining('آخر تحديث للملف:'),
            150,
            scrollable: find.byType(Scrollable).first,
          );
          expect(find.textContaining('آخر تحديث للملف:'), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      }
    }
  }
  testWidgets(
    'financial refresh changes net grams while keeping transaction count',
    (t) async {
      size(t);
      final ticks = ShopSyncTicks();
      addTearDown(ticks.dispose);
      final g = FakeCustomers()..row = statisticsCustomerJson();
      await t.pumpWidget(
        customerHost(customerScreen(g, MemoryLocker(), sync: ticks)),
      );
      await t.pumpAndSettle();
      ((g.row['statistics'] as Map)['weights']
              as List)[2]['bought_milligrams'] =
          '0';
      ticks.apply({ShopSyncScope.ledger});
      await t.pumpAndSettle();
      expect(find.text('6.000'), findsNothing);
      expect(find.text('0.000'), findsOneWidget);
      expect(g.reads, 2);
      await t.tap(find.byKey(const Key('customer-$customerId')));
      await t.pumpAndSettle();
      expect(
        find.textContaining('عدد عمليات شراء العميل من المحل: \u20661\u2069'),
        findsOneWidget,
      );
    },
  );
  testWidgets('empty and archived summaries have honest Arabic states', (
    t,
  ) async {
    size(t);
    final g = FakeCustomers()
      ..row = {...statisticsCustomerJson(empty: true), 'status': 'archived'};
    await t.pumpWidget(
      customerHost(customerScreen(g, MemoryLocker(), readOnly: true)),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('customer-$customerId')));
    await t.pumpAndSettle();
    expect(find.textContaining('جميع الأوزان والأعداد صفر'), findsOneWidget);
    expect(
      find.text('لا توجد عملية مؤكدة مرتبطة لعرض تاريخها.'),
      findsOneWidget,
    );
    expect(find.text('ربط عملية مؤكدة'), findsNothing);
  });
  testWidgets('financial refresh keeps an edit draft and blocks stale submit', (
    t,
  ) async {
    size(t);
    final ticks = ShopSyncTicks();
    addTearDown(ticks.dispose);
    final g = FakeCustomers()..row = statisticsCustomerJson();
    await t.pumpWidget(
      customerHost(customerScreen(g, MemoryLocker(), sync: ticks)),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('customer-$customerId')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('تعديل بيانات العميل'));
    await t.tap(find.text('تعديل بيانات العميل'));
    await t.pumpAndSettle();
    await t.enterText(
      find.byKey(const Key('customer-name')),
      'مسودة بعد المرتجع',
    );
    ticks.apply({ShopSyncScope.ledger});
    await t.pumpAndSettle();
    expect(find.text('مسودة بعد المرتجع'), findsOneWidget);
    expect(
      t.widget<FilledButton>(find.byKey(const Key('customer-save'))).onPressed,
      isNull,
    );
  });
}
