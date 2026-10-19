import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eldafttar/src/features/invoice_message/presentation/message_handoff_dialog.dart';
import 'package:eldafttar/src/features/invoice_message/application/message_gateway.dart';
import 'package:eldafttar/src/features/invoice_message/application/message_handoff.dart';
import 'customer_widget_test.dart' show customerHost, size;
import 'invoice_message_test.dart';
import 'invoice_message_widget_test.dart'
    show messageSettings, tapMessage, showMessageControl;

Widget captureHost(
  Widget child, {
  required Brightness brightness,
  required double scale,
}) {
  final base =
      customerHost(child, brightness: brightness, scale: scale) as MaterialApp;
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: base.locale,
    supportedLocales: base.supportedLocales,
    localizationsDelegates: base.localizationsDelegates,
    theme: base.theme,
    darkTheme: base.darkTheme,
    themeMode: base.themeMode,
    builder: base.builder,
    home: child,
  );
}

/// Artifact harness: opt in with --dart-define=MESSAGE_CAPTURE=true --update-goldens.
void main() {
  if (!const bool.fromEnvironment('MESSAGE_CAPTURE')) return;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = await File('assets/fonts/Cairo.ttf').readAsBytes();
    await (FontLoader(
      'Cairo',
    )..addFont(Future.value(ByteData.sublistView(font)))).load();
    final icons = await File(
      r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
  });
  for (final width in [320.0, 390.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.7]) {
        final suffix = '${width.toInt()}-${brightness.name}-$scale';
        testWidgets('message captures $suffix', (t) async {
          size(t, width: width);
          final g = MessageFake(), locker = MessageLocker();
          final sync = ChangeNotifier();
          var readable = true;
          Future<void> capture(String state) async {
            await t.pump();
            expect(t.takeException(), isNull);
            await expectLater(
              find.byKey(const Key('message-capture')),
              matchesGoldenFile(
                '../../docs/reviews/invoice-messaging-2026-10-18/captures/$state-$suffix.png',
              ),
            );
          }

          Widget host() => captureHost(
            RepaintBoundary(
              key: const Key('message-capture'),
              child: messageSettings(
                g,
                locker,
                sync: sync,
                readable: () => readable,
              ),
            ),
            brightness: brightness,
            scale: scale,
          );
          final held = Completer<void>();
          g.beforeRead = () => held.future;
          await t.pumpWidget(host());
          await t.pump();
          await capture('loading');
          held.complete();
          g.beforeRead = null;
          await t.pumpAndSettle();
          await t.sendKeyEvent(LogicalKeyboardKey.tab);
          await t.pumpAndSettle();
          await capture('keyboard-focus');
          await capture('default');
          await tapMessage(t, find.byKey(const Key('message-tokens')));
          await capture('tokens');
          await tapMessage(t, find.byKey(const Key('message-tokens')));
          final editor = find.byKey(const Key('message-editor'));
          await t.enterText(
            editor,
            'شكراً لزيارتكم\n{shop_name}\nالعملية {sequence}\nالإجمالي {total}\nعيار ١٨: {grams_18}',
          );
          await t.pumpAndSettle();
          await capture('edited');
          await t.enterText(editor, 'نص {remaining}');
          await t.pumpAndSettle();
          await capture('invalid');
          await t.enterText(editor, 'ع' * 401);
          await t.pumpAndSettle();
          await capture('overflow');
          await t.enterText(editor, 'العملية {sequence}\nالإجمالي {total}');
          await t.pumpAndSettle();
          await tapMessage(t, find.byKey(const Key('message-review')));
          await t.scrollUntilVisible(
            find.byKey(const Key('message-save')),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await capture('review');
          g.revision++;
          g.template = 'من جلسة أخرى';
          sync.notifyListeners();
          await t.pumpAndSettle();
          await t.scrollUntilVisible(
            editor,
            -500,
            scrollable: find.byType(Scrollable).first,
          );
          await capture('stale');
          await tapMessage(t, find.text('مراجعة مسودتي مع المراجعة الحالية'));
          await tapMessage(t, find.byKey(const Key('message-review')));
          g.unknown = true;
          final saveHeld = Completer<void>();
          g.beforeSend = () => saveHeld.future;
          await showMessageControl(t, find.byKey(const Key('message-save')));
          await t.tap(find.byKey(const Key('message-save')));
          await t.pump();
          await t.pump(const Duration(milliseconds: 100));
          await capture('submitting');
          saveHeld.complete();
          g.beforeSend = null;
          await t.pumpAndSettle();
          await t.scrollUntilVisible(
            find.byKey(const Key('message-recover')),
            300,
            scrollable: find.byType(Scrollable).first,
          );
          await capture('unknown');
          g.unknown = false;
          await tapMessage(t, find.text('إعادة إرسال الطلب الأصلي'));
          await t.scrollUntilVisible(
            editor,
            -500,
            scrollable: find.byType(Scrollable).first,
          );
          await capture('confirmed');
          g.writable = false;
          sync.notifyListeners();
          await t.pumpAndSettle();
          await capture('expired');
          g.error = 'unavailable';
          sync.notifyListeners();
          await t.pumpAndSettle();
          await capture('settings-failure');
          readable = false;
          sync.notifyListeners();
          await t.pumpAndSettle();
          await capture('access-loss');
          await t.pumpWidget(const SizedBox());
          await t.pumpAndSettle();
          final source = MessageFake(), launcher = MessageLauncherFake();
          Widget handoffHost() => RepaintBoundary(
            key: const Key('message-capture'),
            child: captureHost(
              Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (_) => MessageHandoffDialog(
                        handoff: MessageHandoff(source, launcher),
                        user: messageUser,
                        shop: messageShop,
                        operation: messageOperation,
                        canRead: () => true,
                      ),
                    ),
                    child: const Text('مراجعة الرسالة'),
                  ),
                ),
              ),
              brightness: brightness,
              scale: scale,
            ),
          );
          await t.pumpWidget(handoffHost());
          await t.pumpAndSettle();
          final sourceHeld = Completer<void>();
          source.beforeSource = () => sourceHeld.future;
          await t.tap(find.text('مراجعة الرسالة'));
          await t.pump();
          await t.pump(const Duration(milliseconds: 200));
          await capture('preparing');
          sourceHeld.complete();
          source.beforeSource = null;
          await t.pumpAndSettle();
          await capture('handoff-preview');
          source.revision++;
          source.template = 'نص حالي {total}';
          await tapMessage(t, find.byKey(const Key('message-open')));
          await capture('handoff-stale');
          for (final result in MessageLaunch.values) {
            launcher.result = result;
            await tapMessage(t, find.byKey(const Key('message-open')));
            await capture('handoff-${result.name}');
          }
          await tapMessage(t, find.text('العودة للمستند'));
          (source.operation['payload'] as Map)['customer_phone'] = '';
          await tapMessage(t, find.text('مراجعة الرسالة'));
          await capture('missing-phone');
          expect(launcher.uris.length, 4);
          expect(source.sends, 0);
          await tapMessage(t, find.text('العودة للمستند'));
        });
      }
    }
  }
}
