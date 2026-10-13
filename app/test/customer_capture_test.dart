import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eldafttar/src/features/customers/application/customer_gateway.dart';
import 'customer_fixtures.dart';
import 'customer_widget_test.dart';
import 'repair_command_flow_test.dart' show MemoryLocker;

Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  await t.pumpAndSettle();
  expect(t.takeException(), isNull);
  final boundary =
      key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  await t.runAsync(() async {
    final picture = await boundary.toImage();
    final data = await picture.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/customers/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final cairo = await File('assets/fonts/Cairo.ttf').readAsBytes();
    await (FontLoader(
      'Cairo',
    )..addFont(Future.value(ByteData.sublistView(cairo)))).load();
    final sdk = Platform.resolvedExecutable
        .split(RegExp(r'[/\\]bin[/\\]cache[/\\]'))
        .first;
    final icons = await File(
      '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
  });
  for (final width in [320.0, 390.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      final suffix = '${width.toInt()}-${brightness.name}';
      testWidgets('RTL customer list detail note status link archive $suffix', (
        t,
      ) async {
        size(t, width: width);
        final key = GlobalKey();
        final g = FakeCustomers();
        g.row['phones'] = [
          {
            'raw': '01011111111',
            'normalized': '+201011111111',
            'is_primary': true,
          },
          {
            'raw': '+33123456789',
            'normalized': '+33123456789',
            'is_primary': false,
          },
        ];
        g.notes.addAll([
          {
            'note_id': operationId,
            'body': 'طلب خاتم عيار 21 ومتابعة مساءً\nتفاصيل الطلب محفوظة.',
            'created_at': '2026-10-13T09:00:00.000000Z',
            'created_at_shop': '2026-10-13T12:00:00',
            'actor_display_name': 'مالك الاختبار',
          },
          {
            'note_id': commandKey,
            'body': 'ملاحظة أقدم محفوظة دون تعديل.',
            'created_at': '2026-10-12T09:00:00.000000Z',
            'created_at_shop': '2026-10-12T12:00:00',
            'actor_display_name': 'مالك الاختبار',
          },
        ]);
        g.events.add({
          'event_id': commandKey,
          'event_type': 'status_changed',
          'created_at_shop': '2026-10-13T12:00:00',
          'actor_display_name': 'مالك الاختبار',
          'payload': {'is_vip': true, 'has_open_request': true},
        });
        final store = MemoryLocker();
        await t.pumpWidget(
          customerHost(
            RepaintBoundary(key: key, child: customerScreen(g, store)),
            brightness: brightness,
          ),
        );
        await capture(t, key, 'list-$suffix');
        expect(
          Directionality.of(t.element(find.text('العملاء').first)),
          TextDirection.rtl,
        );
        await t.tap(find.byKey(const Key('customer-$customerId')));
        await capture(t, key, 'detail-$suffix');
        await t.ensureVisible(find.text('إضافة ملاحظة'));
        await t.tap(find.text('إضافة ملاحظة'));
        await t.pumpAndSettle();
        await t.enterText(
          find.byKey(const Key('customer-note')),
          'طلب خاتم\nمتابعة الطلب مساءً',
        );
        await capture(t, key, 'note-$suffix');
        await t.tap(find.byTooltip('رجوع'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('حالة العميل'));
        await t.tap(find.text('حالة العميل'));
        await capture(t, key, 'status-$suffix');
        await t.tap(find.byTooltip('رجوع'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('ربط عملية مؤكدة'));
        await t.tap(find.text('ربط عملية مؤكدة'));
        await t.pumpAndSettle();
        await t.tap(find.text('شراء · رقم 7'));
        await capture(t, key, 'link-review-$suffix');
        await t.tap(find.byTooltip('رجوع'));
        await t.pumpAndSettle();
        await t.ensureVisible(find.text('أرشفة الملف'));
        await t.tap(find.text('أرشفة الملف'));
        await capture(t, key, 'archive-review-$suffix');
      });
      testWidgets('RTL customer create pending error success $suffix', (
        t,
      ) async {
        size(t, width: width);
        final key = GlobalKey();
        final g = FakeCustomers()..unknown = true;
        final store = MemoryLocker();
        await t.pumpWidget(
          customerHost(
            RepaintBoundary(key: key, child: customerScreen(g, store)),
            brightness: brightness,
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('customer-create')));
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('customer-name')), 'عميل جديد');
        await capture(t, key, 'create-$suffix');
        await t.tap(find.byKey(const Key('customer-save')));
        await t.pumpAndSettle();
        await capture(t, key, 'pending-$suffix');
        g.statusOverride = CustomerTransport(receipt: g.committed);
        await t.ensureVisible(find.byKey(const Key('customer-retry')));
        await t.tap(find.byKey(const Key('customer-retry')));
        await t.pumpAndSettle();
        await capture(t, key, 'success-$suffix');
        await t.tap(find.text('قائمة العملاء'));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('customer-create')));
        await t.pumpAndSettle();
        await t.enterText(find.byKey(const Key('customer-name')), 'عميل آخر');
        g.unknown = false;
        g.rejected = 'phone_conflict';
        await t.tap(find.byKey(const Key('customer-save')));
        await t.pumpAndSettle();
        await capture(t, key, 'error-$suffix');
      });
    }
  }
  for (final brightness in Brightness.values) {
    testWidgets('large text keyboard and phone LTR ${brightness.name}', (
      t,
    ) async {
      size(t, width: 320);
      final key = GlobalKey();
      final g = FakeCustomers();
      await t.pumpWidget(
        customerHost(
          RepaintBoundary(key: key, child: customerScreen(g, MemoryLocker())),
          brightness: brightness,
          scale: 1.7,
        ),
      );
      await capture(t, key, 'text-scale-${brightness.name}');
      await t.tap(find.byKey(const Key('customer-create')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('customer-name')), 'عميل اختبار');
      await t.ensureVisible(find.byKey(const Key('customer-add-phone')));
      await t.tap(find.byKey(const Key('customer-add-phone')));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('customer-phone-0')),
        '+201011111111',
      );
      expect(
        t
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const Key('customer-phone-0')),
                matching: find.byType(EditableText),
              ),
            )
            .textDirection,
        TextDirection.ltr,
      );
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(t.view.resetViewInsets);
      await capture(t, key, 'keyboard-${brightness.name}');
    });
  }
}
