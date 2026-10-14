import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eldafttar/src/features/customers/presentation/customer_screen.dart';
import 'package:eldafttar/src/features/customers/domain/customer_contact.dart';
import 'customer_contact_test.dart';
import 'customer_fixtures.dart';
import 'customer_widget_test.dart' show customerHost, size;
import 'repair_command_flow_test.dart' show MemoryLocker;
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';

Widget contactScreen(
  ContactFake g,
  ContactLauncherFake l, {
  Listenable? sync,
  bool readOnly = false,
  bool Function()? canRead,
  String shop = 'shop',
  MemoryLocker? store,
}) => CustomerScreen(
  gateway: g,
  store: store ?? MemoryLocker(),
  userId: 'owner',
  shopId: shop,
  contactLauncher: l,
  syncTicks: sync,
  readOnly: readOnly,
  canRead: canRead,
);

Future<void> chooseWhatsapp(WidgetTester t) async {
  await t.tap(find.byTooltip('محادثة واتساب مع عميل اختبار'));
  await t.pumpAndSettle();
}

void main() {
  testWidgets(
    'late platform success after logout is discarded and contact data cleared',
    (t) async {
      size(t);
      final g = ContactFake()..row = customerJson(phones: contactPhones());
      final l = ContactLauncherFake();
      await t.pumpWidget(customerHost(contactScreen(g, l)));
      await t.pumpAndSettle();
      await chooseWhatsapp(t);
      final held = Completer<void>();
      l.resultHold = held.future;
      await t.tap(find.byKey(const Key('customer-contact-open')));
      await t.pump();
      expect(l.destinations, hasLength(1));
      g.token = null;
      held.complete();
      await t.pumpAndSettle();
      expect(find.textContaining('تم تسليم طلب'), findsNothing);
      expect(find.text('+33123456789'), findsNothing);
      expect(find.text('عميل اختبار'), findsNothing);
      expect(g.sent, isEmpty);
    },
  );
  testWidgets(
    'list chat does not open details; primary and selected LTR number precede launch',
    (t) async {
      size(t);
      final g = ContactFake()..row = customerJson(phones: contactPhones());
      final l = ContactLauncherFake();
      await t.pumpWidget(customerHost(contactScreen(g, l)));
      await t.pumpAndSettle();
      await chooseWhatsapp(t);
      expect(find.text('إحصائيات العملاء'), findsNothing);
      expect(l.destinations, isEmpty);
      expect(find.text('الرقم الأساسي'), findsOneWidget);
      await t.tap(find.text('+33123456789'));
      await t.pumpAndSettle();
      expect(
        t.widget<Text>(find.text('+33123456789').last).textDirection,
        TextDirection.ltr,
      );
      await t.tap(find.byKey(const Key('customer-contact-open')));
      await t.pumpAndSettle();
      expect(
        l.destinations.single.toString(),
        'whatsapp://send?phone=33123456789',
      );
      expect(g.sent, isEmpty);
      expect(find.textContaining('لم يُؤكد إرسال أي رسالة'), findsOneWidget);
    },
  );
  testWidgets(
    'detail call uses current directory and expired archived read access',
    (t) async {
      size(t);
      final g = ContactFake()
        ..row = customerJson(phones: contactPhones(), status: 'archived');
      final l = ContactLauncherFake();
      await t.pumpWidget(customerHost(contactScreen(g, l, readOnly: true)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('customer-$customerId')));
      await t.pumpAndSettle();
      expect(find.text('تعديل بيانات العميل'), findsNothing);
      await t.tap(find.text('الاتصال'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('customer-contact-open')));
      await t.pumpAndSettle();
      expect(l.destinations.single.toString(), 'tel:+201011111111');
      expect(g.sent, isEmpty);
    },
  );
  testWidgets(
    'missing phones disable actions and authorized edit stays available',
    (t) async {
      size(t);
      final g = ContactFake();
      final l = ContactLauncherFake();
      await t.pumpWidget(customerHost(contactScreen(g, l)));
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextButton>(
              find.byKey(const Key('customer-whatsapp-$customerId')),
            )
            .onPressed,
        isNull,
      );
      await t.tap(find.byKey(const Key('customer-$customerId')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'الاتصال'),
            )
            .onPressed,
        isNull,
      );
      await t.ensureVisible(find.text('تعديل بيانات العميل'));
      await t.tap(find.text('تعديل بيانات العميل'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('customer-name')), findsOneWidget);
      expect(l.destinations, isEmpty);
    },
  );
  testWidgets('missing WhatsApp offers explicitly chosen external link only', (
    t,
  ) async {
    size(t);
    final g = ContactFake()..row = customerJson(phones: contactPhones());
    final l = ContactLauncherFake()..outcome = ContactHandoff.unavailable;
    await t.pumpWidget(customerHost(contactScreen(g, l)));
    await t.pumpAndSettle();
    await chooseWhatsapp(t);
    await t.tap(find.byKey(const Key('customer-contact-open')));
    await t.pumpAndSettle();
    expect(l.destinations, hasLength(1));
    expect(find.text('فتح رابط واتساب خارجيًا'), findsOneWidget);
    l.outcome = ContactHandoff.opened;
    await t.ensureVisible(find.text('فتح رابط واتساب خارجيًا'));
    await t.tap(find.text('فتح رابط واتساب خارجيًا'));
    await t.pumpAndSettle();
    expect(l.destinations.last.toString(), 'https://wa.me/201011111111');
    expect(find.textContaining('قد يظهر في المتصفح'), findsOneWidget);
  });
  for (final outcome in [
    ContactHandoff.failed,
    ContactHandoff.cancelled,
    ContactHandoff.denied,
    ContactHandoff.permanentlyDenied,
  ]) {
    testWidgets('Arabic $outcome result is not a sending receipt', (t) async {
      size(t);
      final g = ContactFake()..row = customerJson(phones: contactPhones());
      final l = ContactLauncherFake()..outcome = outcome;
      await t.pumpWidget(customerHost(contactScreen(g, l)));
      await t.pumpAndSettle();
      await chooseWhatsapp(t);
      await t.tap(find.byKey(const Key('customer-contact-open')));
      await t.pumpAndSettle();
      expect(find.textContaining('تم تسليم'), findsNothing);
      expect(g.sent, isEmpty);
      expect(find.byKey(const Key('customer-success')), findsNothing);
    });
  }
  testWidgets(
    'double tap is blocked and sync during launch discards result and refreshes phones',
    (t) async {
      size(t);
      final sync = ValueNotifier(0);
      addTearDown(sync.dispose);
      final g = ContactFake()..row = customerJson(phones: contactPhones());
      final l = ContactLauncherFake();
      final held = Completer<void>();
      l.hold = held.future;
      await t.pumpWidget(customerHost(contactScreen(g, l, sync: sync)));
      await t.pumpAndSettle();
      await chooseWhatsapp(t);
      await t.tap(find.byKey(const Key('customer-contact-open')));
      await t.pump();
      expect(
        t
            .widget<FilledButton>(
              find.byKey(const Key('customer-contact-open')),
            )
            .onPressed,
        isNull,
      );
      g.row['phones'] = [
        {
          'raw': '+966500000000',
          'normalized': '+966500000000',
          'is_primary': true,
        },
      ];
      g.row['record_version'] = '2';
      sync.value++;
      held.complete();
      await t.pumpAndSettle();
      expect(l.destinations, isEmpty);
      expect(find.text('+33123456789'), findsNothing);
      expect(find.text('+966500000000'), findsNWidgets(2));
      expect(
        find.text('تم تحديث الأرقام. راجع اختيارك قبل الفتح.'),
        findsOneWidget,
      );
    },
  );
  for (final change in ['token', 'shop', 'read access']) {
    testWidgets('$change loss during launch discards handoff result', (
      t,
    ) async {
      size(t);
      final g = ContactFake()..row = customerJson(phones: contactPhones());
      final l = ContactLauncherFake();
      var canRead = true;
      final held = Completer<void>();
      l.hold = held.future;
      await t.pumpWidget(
        customerHost(contactScreen(g, l, canRead: () => canRead)),
      );
      await t.pumpAndSettle();
      await chooseWhatsapp(t);
      await t.tap(find.byKey(const Key('customer-contact-open')));
      await t.pump();
      if (change == 'token') g.token = null;
      if (change == 'read access') canRead = false;
      if (change == 'shop') {
        await t.pumpWidget(
          customerHost(
            contactScreen(g, l, shop: 'other', canRead: () => canRead),
          ),
        );
        await t.pump();
      }
      held.complete();
      await t.pumpAndSettle();
      expect(l.destinations, isEmpty);
      expect(find.textContaining('تم تسليم طلب'), findsNothing);
    });
  }
  testWidgets('server edit after chooser blocks launch until fresh review', (
    t,
  ) async {
    size(t);
    final g = ContactFake()..row = customerJson(phones: contactPhones());
    final l = ContactLauncherFake();
    await t.pumpWidget(customerHost(contactScreen(g, l)));
    await t.pumpAndSettle();
    await chooseWhatsapp(t);
    g.row['record_version'] = '2';
    await t.tap(find.byKey(const Key('customer-contact-open')));
    await t.pumpAndSettle();
    expect(l.destinations, isEmpty);
    expect(
      t
          .widget<FilledButton>(find.byKey(const Key('customer-contact-open')))
          .onPressed,
      isNull,
    );
    await t.ensureVisible(find.text('تحديث أرقام الاتصال'));
    await t.tap(find.text('تحديث أرقام الاتصال'));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('customer-contact-open')));
    await t.pumpAndSettle();
    expect(l.destinations, hasLength(1));
  });
  testWidgets(
    'revoked read clears customer data without invoking external handler',
    (t) async {
      size(t);
      final g = ContactFake()..row = customerJson(phones: contactPhones());
      final l = ContactLauncherFake();
      await t.pumpWidget(customerHost(contactScreen(g, l)));
      await t.pumpAndSettle();
      await chooseWhatsapp(t);
      g.readError = 'forbidden';
      await t.tap(find.byKey(const Key('customer-contact-open')));
      await t.pumpAndSettle();
      expect(find.text('عميل اختبار'), findsNothing);
      expect(find.text('+33123456789'), findsNothing);
      expect(l.destinations, isEmpty);
    },
  );
  testWidgets(
    'keyboard selects number and cancel returns without a launch or metadata command',
    (t) async {
      size(t);
      final g = ContactFake()..row = customerJson(phones: contactPhones());
      final l = ContactLauncherFake();
      await t.pumpWidget(customerHost(contactScreen(g, l)));
      await t.pumpAndSettle();
      await chooseWhatsapp(t);
      final radios = find.byType(RadioListTile<String>);
      await t.ensureVisible(radios.first);
      final client = t.state(radios.first) as RadioClient<String>;
      client.focusNode.requestFocus();
      await t.pump();
      await t.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await t.pump();
      expect(
        t
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        '+33123456789',
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pump();
      await t.ensureVisible(find.text('إلغاء'));
      await t.tap(find.text('إلغاء'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('customer-search')), findsOneWidget);
      expect(l.destinations, isEmpty);
      expect(g.sent, isEmpty);
    },
  );
  testWidgets(
    'back during preparation discards delayed read and never opens a destination',
    (t) async {
      size(t);
      final g = ContactFake()..row = customerJson(phones: contactPhones());
      final l = ContactLauncherFake();
      await t.pumpWidget(customerHost(contactScreen(g, l)));
      await t.pumpAndSettle();
      final held = Completer<void>();
      g.readHold = held.future;
      await t.tap(find.byTooltip('محادثة واتساب مع عميل اختبار'));
      await t.pump();
      await t.tap(find.byTooltip('رجوع'));
      await t.pumpAndSettle();
      held.complete();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('customer-search')), findsOneWidget);
      expect(find.text('اختر رقم الهاتف'), findsNothing);
      expect(l.destinations, isEmpty);
    },
  );
  testWidgets(
    'sync during preparation queues fresh directory without losing unknown command',
    (t) async {
      size(t);
      final sync = ValueNotifier(0);
      addTearDown(sync.dispose);
      final g = ContactFake()..row = customerJson(phones: contactPhones());
      final l = ContactLauncherFake();
      final pending = createCustomerCommand();
      final store = MemoryLocker()..stored = pending;
      await t.pumpWidget(
        customerHost(contactScreen(g, l, sync: sync, store: store)),
      );
      await t.pumpAndSettle();
      final held = Completer<void>();
      g.readHold = held.future;
      await t.tap(find.byTooltip('محادثة واتساب مع عميل اختبار'));
      await t.pump();
      g.row['phones'] = [
        {
          'raw': '+966500000000',
          'normalized': '+966500000000',
          'is_primary': true,
        },
      ];
      g.row['record_version'] = '2';
      sync.value++;
      held.complete();
      await t.pumpAndSettle();
      expect(find.text('+33123456789'), findsNothing);
      expect(find.text('+966500000000'), findsNWidgets(2));
      expect(store.stored, same(pending));
      expect(find.byKey(const Key('customer-pending')), findsOneWidget);
      expect(g.sent, isEmpty);
    },
  );
  testWidgets('foreign unknown command survives contact and reconnect', (
    t,
  ) async {
    size(t);
    final sync = ValueNotifier(0);
    addTearDown(sync.dispose);
    final g = ContactFake()..row = customerJson(phones: contactPhones());
    final l = ContactLauncherFake();
    final pending = PendingFinancialCommand(
      key: commandKey,
      kind: 'sale',
      body: const {'synthetic': 'frozen'},
    );
    final store = MemoryLocker()..stored = pending;
    await t.pumpWidget(
      customerHost(contactScreen(g, l, sync: sync, store: store)),
    );
    await t.pumpAndSettle();
    await chooseWhatsapp(t);
    await t.tap(find.byKey(const Key('customer-contact-open')));
    await t.pumpAndSettle();
    sync.value++;
    await t.pumpAndSettle();
    expect(store.stored, same(pending));
    expect(g.sent, isEmpty);
    expect(find.textContaining('طلب محفوظ في قسم آخر'), findsOneWidget);
  });
  for (final draft in ['edit', 'note']) {
    testWidgets('$draft is preserved and blocked after contact feature sync', (
      t,
    ) async {
      size(t);
      final sync = ValueNotifier(0);
      addTearDown(sync.dispose);
      final g = ContactFake()..row = customerJson(phones: contactPhones());
      final l = ContactLauncherFake();
      await t.pumpWidget(customerHost(contactScreen(g, l, sync: sync)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('customer-$customerId')));
      await t.pumpAndSettle();
      final label = draft == 'edit' ? 'تعديل بيانات العميل' : 'إضافة ملاحظة';
      await t.ensureVisible(find.text(label));
      await t.tap(find.text(label));
      await t.pumpAndSettle();
      final key = Key(draft == 'edit' ? 'customer-name' : 'customer-note');
      await t.enterText(find.byKey(key), 'مسودة محفوظة');
      sync.value++;
      await t.pumpAndSettle();
      final editable = find.descendant(
        of: find.byKey(key),
        matching: find.byType(EditableText),
      );
      expect(t.widget<EditableText>(editable).controller.text, 'مسودة محفوظة');
      expect(find.textContaining('لم تُحفظ المسودة'), findsOneWidget);
      expect(g.sent, isEmpty);
      expect(l.destinations, isEmpty);
    });
  }
}
