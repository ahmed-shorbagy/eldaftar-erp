// «بيانات العملاء» layout after the owner's 2026-11-09 design (ADR 0043).
import 'package:eldafttar/src/features/customers/application/customer_gateway.dart';
import 'package:eldafttar/src/features/customers/data/customer_codec.dart';
import 'package:eldafttar/src/features/customers/domain/customer_display.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'customer_fixtures.dart';
import 'customer_saved_number_test.dart' show savedPhones;
import 'customer_statistics_fixtures.dart';
import 'customer_widget_test.dart' show customerHost, customerScreen, size;
import 'repair_command_flow_test.dart' show MemoryLocker;

FakeCustomers _fake({bool overview = true}) {
  final g = FakeCustomers();
  g.row = {
    ...statisticsCustomerJson(),
    'is_vip': true,
    'latest_note_preview': 'يبحث عيار 18 عايز طقم لازورد',
    'phones': savedPhones('saved'),
  };
  if (overview) {
    g.overview = CustomerOverview(
      activeCount: BigInt.from(1250),
      vipCount: BigInt.from(86),
      active30Days: BigInt.from(312),
      openRequestCount: BigInt.from(18),
    );
  }
  return g;
}

void main() {
  group('customerSince', () {
    final today = DateTime(2026, 11, 9);
    test('days, months and years in Arabic', () {
      expect(customerSince('2026-11-09T10:00:00', today), 'اليوم');
      expect(customerSince('2026-11-08T23:59:00', today), 'أمس');
      expect(customerSince('2026-11-07T00:00:00', today), 'منذ يومين');
      expect(customerSince('2026-11-02T00:00:00', today), 'منذ 7 أيام');
      expect(customerSince('2026-10-20T00:00:00', today), 'منذ 20 يوم');
      expect(customerSince('2026-10-05T00:00:00', today), 'منذ شهر');
      expect(customerSince('2026-08-01T00:00:00', today), 'منذ 3 أشهر');
      expect(customerSince('2025-11-01T00:00:00', today), 'منذ سنة');
    });
    test('a future or unreadable date gives null so the date is shown', () {
      expect(customerSince('2026-11-10T00:00:00', today), isNull);
      expect(customerSince('bad', today), isNull);
    });
    test('card karats: 18, 21, 24 always; 22 and 14 only when bought', () {
      final stats = parseCustomer(statisticsCustomerJson()).statistics!;
      expect(customerCardKarats(stats), [18, 21, 24, 14]);
      final empty = parseCustomer(
        statisticsCustomerJson(empty: true),
      ).statistics!;
      expect(customerCardKarats(empty), [18, 21, 24]);
      expect(customerCount(BigInt.from(1250)), '1,250');
    });
  });

  testWidgets('search, then four figures in one row, then the list', (t) async {
    size(t);
    final g = _fake();
    await t.pumpWidget(customerHost(customerScreen(g, MemoryLocker())));
    await t.pumpAndSettle();
    expect(find.text('بيانات العملاء'), findsOneWidget);
    expect(find.text('1,250'), findsOneWidget);
    expect(find.text('86'), findsOneWidget);
    expect(find.text('312'), findsOneWidget);
    expect(find.text('18'), findsWidgets);
    final search = t.getRect(find.byKey(const Key('customer-search')));
    final header = t.getRect(find.byKey(const Key('customer-overview')));
    final list = t.getRect(find.text('قائمة العملاء'));
    expect(search.bottom <= header.top, isTrue);
    expect(header.bottom <= list.top, isTrue);
    final tiles = [
      for (final name in ['total', 'vip', 'active', 'open'])
        t.getRect(find.byKey(Key('customer-overview-$name'))),
    ];
    for (final tile in tiles) {
      expect(tile.top, tiles.first.top, reason: 'one row at phone width');
    }
    expect(t.takeException(), isNull);
  });

  testWidgets('a card shows the design: phone, karats, note, saved', (t) async {
    size(t);
    final g = _fake();
    await t.pumpWidget(customerHost(customerScreen(g, MemoryLocker())));
    await t.pumpAndSettle();
    final name = find.byKey(const Key('customer-$customerId'));
    expect(t.widget<Text>(name).data, 'عميل اختبار');
    expect(find.byKey(const Key('customer-card-$customerId')), findsOneWidget);
    expect(find.text('18K'), findsOneWidget);
    expect(find.text('21K'), findsOneWidget);
    expect(find.text('24K'), findsOneWidget);
    expect(find.text('14K'), findsOneWidget);
    expect(find.text('22K'), findsNothing);
    expect(find.text('3.00 g'), findsOneWidget);
    expect(find.text('6.00 g'), findsOneWidget);
    expect(find.text('يبحث عيار 18 عايز طقم لازورد'), findsOneWidget);
    expect(find.text('محفوظ'), findsOneWidget);
    expect(find.text('آخر عملية'), findsOneWidget);
    expect(find.textContaining('حالة حفظ الرقم الأساسي لواتساب'), findsNothing);
    expect(find.textContaining('صافي العمليات المؤكدة'), findsNothing);
    expect(
      find.byKey(const Key('customer-whatsapp-$customerId')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('customer-call-$customerId')), findsOneWidget);
  });

  testWidgets('add customer button is pinned and opens the form', (t) async {
    size(t);
    final g = _fake();
    await t.pumpWidget(customerHost(customerScreen(g, MemoryLocker())));
    await t.pumpAndSettle();
    expect(find.text('إضافة عميل جديد'), findsOneWidget);
    await t.tap(find.byKey(const Key('customer-create')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('customer-name')), findsOneWidget);
  });

  testWidgets('detail: header, purchase summary, notes and actions', (t) async {
    size(t, width: 390);
    final g = _fake();
    for (var i = 0; i < 5; i++) {
      g.notes.add({
        'note_id': 'n$i',
        'body': 'ملاحظة رقم $i',
        'created_at': '2026-10-1${i}T09:00:00.000000Z',
        'created_at_shop': '2026-10-1${i}T12:00:00',
        'actor_display_name': 'المالك',
      });
    }
    await t.pumpWidget(customerHost(customerScreen(g, MemoryLocker())));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('customer-$customerId')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('customer-detail-header')), findsOneWidget);
    expect(find.byKey(const Key('customer-detail-vip')), findsOneWidget);
    expect(find.text('ملخص المشتريات'), findsOneWidget);
    expect(find.text('إجمالي الفواتير'), findsOneWidget);
    expect(find.text('1 فاتورة'), findsOneWidget);
    expect(find.text('ملاحظة رقم 3'), findsOneWidget);
    expect(find.text('ملاحظة رقم 4'), findsNothing);
    await t.scrollUntilVisible(
      find.byKey(const Key('customer-notes-all')),
      200,
      scrollable: find
          .ancestor(
            of: find.byKey(const Key('customer-detail-notes')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('customer-notes-all')));
    await t.pumpAndSettle();
    expect(find.text('ملاحظة رقم 4'), findsOneWidget);
    await t.ensureVisible(find.byKey(const Key('customer-detail-actions')));
    await t.pumpAndSettle();
    expect(find.text('إجراءات سريعة'), findsOneWidget);
    expect(find.text('تعديل بيانات العميل'), findsOneWidget);
    expect(find.text('أرشفة الملف'), findsOneWidget);
    expect(find.text('مشاركة العميل'), findsNothing);
    expect(find.text('محادثة'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('a missing overview hides the figures, not the list', (t) async {
    size(t);
    final g = _fake(overview: false);
    await t.pumpWidget(customerHost(customerScreen(g, MemoryLocker())));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('customer-overview')), findsNothing);
    expect(find.byKey(const Key('customer-$customerId')), findsOneWidget);
    expect(find.textContaining('تعذر'), findsNothing);
  });

  for (final brightness in Brightness.values) {
    testWidgets('list and detail fit 375 px in ${brightness.name} mode', (
      t,
    ) async {
      size(t, width: 375);
      final g = _fake();
      await t.pumpWidget(
        customerHost(customerScreen(g, MemoryLocker()), brightness: brightness),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.tap(find.byKey(const Key('customer-$customerId')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  }
}
