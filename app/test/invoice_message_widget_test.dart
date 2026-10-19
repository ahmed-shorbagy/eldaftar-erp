import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eldafttar/src/features/invoice_message/presentation/message_settings_screen.dart';
import 'package:eldafttar/src/features/invoice_message/presentation/message_handoff_dialog.dart';
import 'package:eldafttar/src/features/invoice_message/application/message_gateway.dart';
import 'package:eldafttar/src/features/invoice_message/application/message_handoff.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'customer_widget_test.dart' show customerHost, size;
import 'invoice_message_test.dart';

Widget messageSettings(
  MessageFake g,
  MessageLocker locker, {
  Listenable? sync,
  bool Function()? readable,
}) => MessageSettingsScreen(
  gateway: g,
  store: locker,
  userId: messageUser,
  shopId: messageShop,
  canRead: readable ?? () => true,
  canWrite: () => g.writable,
  syncTicks: sync,
  newKey: () => messageKey,
);
Future<void> showMessageControl(WidgetTester t, Finder f) async {
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      f,
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }
  for (var i = 0; i < 5; i++) {
    await Scrollable.ensureVisible(t.element(f), alignment: 0.5);
    await t.pumpAndSettle();
    if (f.hitTestable().evaluate().isNotEmpty) return;
  }
  expect(f.hitTestable(), findsOneWidget);
}

Future<void> tapMessage(WidgetTester t, Finder f) async {
  await showMessageControl(t, f);
  await t.tap(f);
  await t.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = await File('assets/fonts/Cairo.ttf').readAsBytes();
    await (FontLoader(
      'Cairo',
    )..addFont(Future.value(ByteData.sublistView(font)))).load();
  });
  testWidgets('More opens the direct message settings sibling', (t) async {
    size(t);
    final g = MessageFake(), locker = MessageLocker();
    await t.pumpWidget(
      customerHost(
        ShopWorkspace(
          shop: const ShopAccount(
            id: messageShop,
            name: 'متجر تجريبي',
            role: 'owner',
            entitlement: ShopEntitlement.active,
          ),
          onSignOut: () async {},
          onToggleTheme: (_) async {},
          messageBuilder: (_) => messageSettings(g, locker),
        ),
      ),
    );
    await t.pumpAndSettle();
    await tapMessage(t, find.byKey(const Key('workspace-nav-4')));
    await tapMessage(t, find.byKey(const Key('workspace-invoice-message')));
    expect(find.byKey(const Key('message-editor')), findsOneWidget);
    expect(g.sends, 0);
  });
  testWidgets(
    'default, token insertion, invalid syntax, review-save and reviewed reset',
    (t) async {
      size(t);
      final g = MessageFake(), locker = MessageLocker();
      await t.pumpWidget(customerHost(messageSettings(g, locker)));
      await t.pumpAndSettle();
      expect(find.textContaining('لم يُحفظ تخصيص'), findsOneWidget);
      final editor = find.byKey(const Key('message-editor'));
      await t.enterText(editor, 'رسالة {remaining}');
      await t.pumpAndSettle();
      expect(find.textContaining('حقل متغير غير مسموح'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('message-review')))
            .onPressed,
        isNull,
      );
      await t.enterText(editor, 'الإجمالي: ');
      await tapMessage(t, find.byKey(const Key('message-tokens')));
      await tapMessage(t, find.widgetWithText(OutlinedButton, 'الإجمالي'));
      expect(t.widget<TextField>(editor).controller!.text, contains('{total}'));
      await tapMessage(t, find.byKey(const Key('message-review')));
      expect(g.sends, 0);
      expect(find.textContaining('لا أثر على النقد'), findsOneWidget);
      await tapMessage(t, find.byKey(const Key('message-save')));
      expect(g.sends, 1);
      expect(g.revision, 1);
      expect(locker.command, isNull);
      expect(find.text('أكد الخادم حفظ نص الرسالة.'), findsOneWidget);
      await tapMessage(t, find.byKey(const Key('message-reset')));
      expect(g.revision, 1);
      await tapMessage(t, find.byKey(const Key('message-review')));
      expect(find.text('سيُستعاد النص الافتراضي.'), findsOneWidget);
      await tapMessage(t, find.byKey(const Key('message-save')));
      expect(g.template, isNull);
      expect(g.revision, 2);
    },
  );
  testWidgets(
    'sync keeps dirty draft and requires stale review; late identity replies discarded',
    (t) async {
      size(t);
      final g = MessageFake(),
          locker = MessageLocker(),
          sync = ChangeNotifier();
      await t.pumpWidget(customerHost(messageSettings(g, locker, sync: sync)));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('message-editor')),
        'مسودتي {total}',
      );
      g.revision = 1;
      g.template = 'جلسة أخرى {total}';
      sync.notifyListeners();
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(find.byKey(const Key('message-editor')))
            .controller!
            .text,
        'مسودتي {total}',
      );
      expect(find.textContaining('تغيّرت المراجعة المحفوظة'), findsOneWidget);
      await tapMessage(t, find.text('مراجعة مسودتي مع المراجعة الحالية'));
      await tapMessage(t, find.byKey(const Key('message-review')));
      await tapMessage(t, find.byKey(const Key('message-save')));
      expect(g.revision, 2);
      final held = Completer<void>();
      g.beforeRead = () => held.future;
      sync.notifyListeners();
      await t.pump();
      g.session = 'epoch2';
      held.complete();
      await t.pumpAndSettle();
      expect(find.text('لم يعد هذا الحساب يصل إلى المتجر.'), findsOneWidget);
      expect(find.byKey(const Key('message-editor')), findsNothing);
    },
  );
  testWidgets(
    'original pending recovery, expired reconciliation and foreign command preservation',
    (t) async {
      size(t);
      final g = MessageFake()..unknown = true;
      final locker = MessageLocker();
      await t.pumpWidget(customerHost(messageSettings(g, locker)));
      await t.pumpAndSettle();
      await tapMessage(t, find.byKey(const Key('message-review')));
      await tapMessage(t, find.byKey(const Key('message-save')));
      expect(locker.command, isNotNull);
      expect(find.byKey(const Key('message-recover')), findsOneWidget);
      g.unknown = false;
      await tapMessage(t, find.text('إعادة إرسال الطلب الأصلي'));
      expect(g.sends, 2);
      expect(locker.command, isNull);
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      locker.command = const PendingFinancialCommand(
        key: 'foreign',
        kind: 'unknown_future',
        body: {'exact': 'preserved'},
      );
      await t.pumpWidget(customerHost(messageSettings(g, locker)));
      await t.pumpAndSettle();
      expect(find.textContaining('يوجد طلب آخر محفوظ'), findsOneWidget);
      expect(locker.command!.body, {'exact': 'preserved'});
      await t.pumpWidget(const SizedBox());
      g.writable = false;
      locker.command = null;
      await t.pumpWidget(customerHost(messageSettings(g, locker)));
      await t.pumpAndSettle();
      expect(find.textContaining('انتهى الاشتراك'), findsOneWidget);
      expect(
        t
            .widget<FilledButton>(find.byKey(const Key('message-review')))
            .onPressed,
        isNull,
      );
    },
  );
  testWidgets(
    'handoff review refreshes changed text and exposes honest opened/unavailable states',
    (t) async {
      size(t);
      final g = MessageFake(), launcher = MessageLauncherFake();
      await t.pumpWidget(
        customerHost(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => MessageHandoffDialog(
                    handoff: MessageHandoff(g, launcher),
                    user: messageUser,
                    shop: messageShop,
                    operation: messageOperation,
                    canRead: () => true,
                  ),
                ),
                child: const Text('مراجعة'),
              ),
            ),
          ),
        ),
      );
      await tapMessage(t, find.text('مراجعة'));
      expect(launcher.uris, isEmpty);
      g.revision++;
      g.template = 'نص حالي {total}';
      await tapMessage(t, find.byKey(const Key('message-open')));
      expect(find.textContaining('تغيّر القالب'), findsOneWidget);
      expect(launcher.uris, isEmpty);
      await tapMessage(t, find.byKey(const Key('message-open')));
      expect(launcher.uris.length, 1);
      expect(g.sends, 0);
      expect(find.textContaining('فُتح رابط واتساب'), findsOneWidget);
      launcher.result = MessageLaunch.unavailable;
      await tapMessage(t, find.byKey(const Key('message-open')));
      expect(find.textContaining('لا يتوفر تطبيق'), findsOneWidget);
      g.session = 'epoch2';
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('message-operation-preview')), findsNothing);
      await tapMessage(t, find.text('العودة للمستند'));
    },
  );
  testWidgets(
    'post-save refresh freezes editing until the confirmed profile arrives',
    (t) async {
      size(t);
      final g = MessageFake(), locker = MessageLocker();
      await t.pumpWidget(customerHost(messageSettings(g, locker)));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('message-editor')),
        'مسودة {total}',
      );
      await tapMessage(t, find.byKey(const Key('message-review')));
      final held = Completer<void>();
      g.beforeSend = () async {
        g.beforeRead = () => held.future;
      };
      await showMessageControl(t, find.byKey(const Key('message-save')));
      await t.tap(find.byKey(const Key('message-save')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(g.sends, 1);
      expect(
        t.widget<TextField>(find.byKey(const Key('message-editor'))).enabled,
        isFalse,
      );
      held.complete();
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextField>(find.byKey(const Key('message-editor')))
            .controller!
            .text,
        'مسودة {total}',
      );
      expect(
        t.widget<TextField>(find.byKey(const Key('message-editor'))).enabled,
        isTrue,
      );
    },
  );
  testWidgets(
    'keyboard focus and Arabic semantics remain available without pointer actions',
    (t) async {
      size(t, width: 390);
      final g = MessageFake(), locker = MessageLocker();
      final semantics = t.ensureSemantics();
      await t.pumpWidget(customerHost(messageSettings(g, locker)));
      await t.pumpAndSettle();
      final editor = find.byKey(const Key('message-editor'));
      expect(find.bySemanticsLabel(RegExp('نص الرسالة')), findsWidgets);
      await t.tap(editor);
      await t.pump();
      expect(
        t
            .widget<EditableText>(
              find.descendant(of: editor, matching: find.byType(EditableText)),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      final next = FocusManager.instance.primaryFocus;
      expect(next, isNotNull);
      expect(
        t
            .widget<EditableText>(
              find.descendant(of: editor, matching: find.byType(EditableText)),
            )
            .focusNode
            .hasFocus,
        isFalse,
      );
      await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await t.pumpAndSettle();
      expect(
        t
            .widget<EditableText>(
              find.descendant(of: editor, matching: find.byType(EditableText)),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('رقم العملية'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(t.widget<TextField>(editor).controller!.text, '{sequence}');
      await showMessageControl(t, find.byKey(const Key('message-review')));
      await t.sendKeyEvent(LogicalKeyboardKey.tab);
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('مراجعة النص قبل الحفظ'), findsOneWidget);
      expect(find.bySemanticsLabel('استعادة النص الافتراضي'), findsOneWidget);
      semantics.dispose();
    },
  );
  testWidgets(
    'handoff keyboard activation exposes Arabic semantics and opens only after review',
    (t) async {
      size(t);
      final g = MessageFake(), launcher = MessageLauncherFake();
      final semantics = t.ensureSemantics();
      await t.pumpWidget(
        customerHost(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  builder: (_) => MessageHandoffDialog(
                    handoff: MessageHandoff(g, launcher),
                    user: messageUser,
                    shop: messageShop,
                    operation: messageOperation,
                    canRead: () => true,
                  ),
                ),
                child: const Text('مراجعة'),
              ),
            ),
          ),
        ),
      );
      await tapMessage(t, find.text('مراجعة'));
      expect(find.bySemanticsLabel('فتح واتساب بعد المراجعة'), findsOneWidget);
      final focus = Focus.of(t.element(find.text('فتح واتساب بعد المراجعة')));
      for (var i = 0; i < 8 && !focus.hasFocus; i++) {
        await t.sendKeyEvent(LogicalKeyboardKey.tab);
        await t.pumpAndSettle();
      }
      expect(focus.hasFocus, isTrue);
      expect(launcher.uris, isEmpty);
      await t.sendKeyEvent(LogicalKeyboardKey.enter);
      await t.pumpAndSettle();
      expect(launcher.uris.length, 1);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.byType(MessageHandoffDialog), findsNothing);
      semantics.dispose();
    },
  );
  testWidgets('handoff access errors are Arabic and discard the preview', (
    t,
  ) async {
    size(t);
    final g = MessageFake(), launcher = MessageLauncherFake();
    await t.pumpWidget(
      customerHost(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => MessageHandoffDialog(
                  handoff: MessageHandoff(g, launcher),
                  user: messageUser,
                  shop: messageShop,
                  operation: messageOperation,
                  canRead: () => true,
                ),
              ),
              child: const Text('مراجعة'),
            ),
          ),
        ),
      ),
    );
    await tapMessage(t, find.text('مراجعة'));
    g.error = 'forbidden';
    await tapMessage(t, find.byKey(const Key('message-open')));
    expect(find.textContaining('لم يعد الحساب يصل'), findsOneWidget);
    expect(find.text('forbidden'), findsNothing);
    expect(find.byKey(const Key('message-operation-preview')), findsNothing);
    expect(launcher.uris, isEmpty);
    await tapMessage(t, find.text('العودة للمستند'));
  });
  testWidgets(
    'server denial clears visible draft and preserves its durable request',
    (t) async {
      size(t);
      final g = MessageFake(), locker = MessageLocker();
      await t.pumpWidget(customerHost(messageSettings(g, locker)));
      await t.pumpAndSettle();
      await t.enterText(
        find.byKey(const Key('message-editor')),
        'مسودة {total}',
      );
      await tapMessage(t, find.byKey(const Key('message-review')));
      g.error = 'forbidden';
      await tapMessage(t, find.byKey(const Key('message-save')));
      expect(find.byKey(const Key('message-editor')), findsNothing);
      expect(find.text('لم يعد هذا الحساب يصل إلى المتجر.'), findsOneWidget);
      expect(locker.command, isNotNull);
    },
  );
  for (final width in [320.0, 390.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.7]) {
        testWidgets('RTL layout ${width.toInt()} ${brightness.name} $scale', (
          t,
        ) async {
          size(t, width: width);
          final g = MessageFake(), locker = MessageLocker();
          await t.pumpWidget(
            customerHost(
              messageSettings(g, locker),
              brightness: brightness,
              scale: scale,
            ),
          );
          await t.pumpAndSettle();
          expect(
            Directionality.of(
              t.element(find.byKey(const Key('message-editor'))),
            ),
            TextDirection.rtl,
          );
          final context = t.element(find.byKey(const Key('message-editor')));
          final colors = Theme.of(context).colorScheme;
          final a = colors.onSurface.computeLuminance(),
              b = colors.surface.computeLuminance();
          expect(
            ((a > b ? a : b) + 0.05) / ((a < b ? a : b) + 0.05),
            greaterThanOrEqualTo(4.5),
          );
          await t.enterText(
            find.byKey(const Key('message-editor')),
            'نص {total}',
          );
          await tapMessage(t, find.byKey(const Key('message-review')));
          await showMessageControl(t, find.byKey(const Key('message-save')));
          expect(
            t.getSize(find.byKey(const Key('message-save'))).height,
            greaterThanOrEqualTo(48),
          );
          await tapMessage(t, find.byKey(const Key('message-save')));
          expect(t.takeException(), isNull);
        });
      }
    }
  }
}
