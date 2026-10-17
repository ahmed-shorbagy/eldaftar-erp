import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eldafttar/src/features/debts/application/debt_native_gateway.dart';
import 'package:eldafttar/src/features/debts/application/debt_reminder_coordinator.dart';
import 'package:eldafttar/src/features/debts/application/debt_reminder_device.dart';
import 'package:eldafttar/src/features/debts/data/debt_native_codec.dart';
import 'package:eldafttar/src/features/debts/domain/debt_rules.dart';
import 'package:eldafttar/src/features/debts/presentation/debt_native_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'debt_native_fixtures.dart';
import 'debt_due_fixtures.dart';
import 'customer_widget_test.dart' show customerHost, size;
import 'repair_command_flow_test.dart' show MemoryLocker;

Widget nativeScreen(
  FakeNative g,
  MemoryLocker store, {
  bool settings = false,
  bool Function()? read,
  bool Function()? write,
  Listenable? sync,
  DebtReminderCoordinator? device,
}) => DebtNativeScreen(
  gateway: g,
  store: store,
  userId: dueUser,
  shopId: dueShop,
  sourceKind: settings ? null : DebtSourceKind.standalone,
  sourceId: settings ? null : dueSourceId,
  canRead: read ?? () => true,
  canWrite: write ?? () => true,
  syncTicks: sync,
  reminders: device,
  newKey: () => dueKey,
);
Future<void> nativeTap(WidgetTester t, String key) async {
  final f = find.byKey(Key(key));
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      f,
      240,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await t.ensureVisible(f);
  await t.pumpAndSettle();
  await t.tap(f.hitTestable());
  await t.pumpAndSettle();
}

Future<void> nativeReview(WidgetTester t) async {
  final f = find.byKey(const Key('native-time'));
  if (f.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      f,
      200,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await t.ensureVisible(f);
  await t.enterText(f, '17:00');
  await nativeTap(t, 'native-prepare');
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = await File('assets/fonts/Cairo.ttf').readAsBytes();
    await (FontLoader(
      'Cairo',
    )..addFont(Future.value(ByteData.sublistView(font)))).load();
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
  testWidgets(
    'review precedes shared save; confirmed server intent independent of device scheduling',
    (t) async {
      size(t);
      final g = FakeNative(), s = MemoryLocker();
      await t.pumpWidget(customerHost(nativeScreen(g, s)));
      await t.pumpAndSettle();
      await nativeReview(t);
      expect(g.sent, isEmpty);
      expect(find.textContaining('2026-10-14T14:00:00.000Z'), findsOneWidget);
      expect(find.byKey(const Key('native-review')), findsOneWidget);
      await nativeTap(t, 'native-confirm');
      expect(g.sent.length, 1);
      expect(find.byKey(const Key('native-success')), findsOneWidget);
      expect(s.stored, isNull);
      expect(find.textContaining('حفظ الوقت لا يؤكد'), findsNothing);
    },
  );
  testWidgets(
    'sync invalidates preserved draft/review, blocks stale confirmation',
    (t) async {
      size(t);
      final g = FakeNative(), sync = ChangeNotifier();
      await t.pumpWidget(
        customerHost(nativeScreen(g, MemoryLocker(), sync: sync)),
      );
      await t.pumpAndSettle();
      await nativeReview(t);
      sync.notifyListeners();
      await t.pumpAndSettle();
      expect(find.byKey(const Key('native-stale')), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(find.byKey(const Key('native-confirm')))
            .onPressed,
        isNull,
      );
      await nativeTap(t, 'native-edit');
      expect(
        t
            .widget<TextFormField>(find.byKey(const Key('native-time')))
            .controller!
            .text,
        '17:00',
      );
      await t.pumpWidget(const SizedBox());
      sync.dispose();
    },
  );
  testWidgets('gap/fold review failure does not save and retains time draft', (
    t,
  ) async {
    size(t);
    final g = FakeNative()..error = 'unresolved_wall_time';
    await t.pumpWidget(customerHost(nativeScreen(g, MemoryLocker())));
    await t.pumpAndSettle();
    await nativeReview(t);
    expect(find.byKey(const Key('native-error')), findsOneWidget);
    expect(g.sent, isEmpty);
    expect(
      t
          .widget<TextFormField>(find.byKey(const Key('native-time')))
          .controller!
          .text,
      '17:00',
    );
  });
  testWidgets(
    'foreign pending request remains byte-equivalent and blocks metadata writes',
    (t) async {
      size(t);
      final g = FakeNative(),
          s = MemoryLocker()
            ..stored = const PendingFinancialCommand(
              key: dueKey,
              kind: 'future',
              body: {'private': 'original'},
            );
      final original = s.stored;
      await t.pumpWidget(customerHost(nativeScreen(g, s)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('native-foreign')), findsOneWidget);
      expect(find.byKey(const Key('native-prepare')), findsNothing);
      expect(s.stored, same(original));
    },
  );
  testWidgets('expired reader can disable device without any shared write', (
    t,
  ) async {
    size(t);
    final g = FakeNative(),
        store = MemoryDeviceStore(),
        port = FakeNotificationPort();
    final c = DebtReminderCoordinator(
      gateway: g,
      store: store,
      port: port,
      clock: FakeReminderClock(),
    );
    await c.bind(dueUser, dueShop);
    await c.enable();
    await t.pumpWidget(
      customerHost(
        nativeScreen(g, MemoryLocker(), write: () => false, device: c),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('native-prepare')), findsNothing);
    await nativeTap(t, 'native-disable');
    expect(port.pending, isEmpty);
    expect(g.sent, isEmpty);
  });
  testWidgets(
    'lost access removes party/amount and preserves local disable recovery',
    (t) async {
      size(t);
      final g = FakeNative(),
          sync = ChangeNotifier(),
          c = DebtReminderCoordinator(
            gateway: FakeNative(),
            store: MemoryDeviceStore(),
            port: FakeNotificationPort(),
            clock: FakeReminderClock(),
          );
      await c.bind(dueUser, dueShop);
      await c.enable();
      var access = true;
      await t.pumpWidget(
        customerHost(
          nativeScreen(
            g,
            MemoryLocker(),
            read: () => access,
            sync: sync,
            device: c,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('عميل اختبار عربي'), findsOneWidget);
      access = false;
      sync.notifyListeners();
      await t.pumpAndSettle();
      expect(find.text('عميل اختبار عربي'), findsNothing);
      expect(find.byKey(const Key('native-time')), findsNothing);
      await t.pumpWidget(const SizedBox());
      sync.dispose();
    },
  );
  testWidgets(
    'shop-zone audit displays current zone separately from stored appointment zone',
    (t) async {
      size(t);
      final g = FakeNative();
      g.data = {
        ...g.data,
        'time_zone': 'America/New_York',
        'created_at_shop': '2026-09-30T20:00:00',
        'native_history': [
          {
            ...(g.data['native_history'] as List).single as Map,
            'at_shop': '2026-10-13T08:00:00',
          },
        ],
      };
      await t.pumpWidget(customerHost(nativeScreen(g, MemoryLocker())));
      await t.pumpAndSettle();
      final history = find.text('سجل أوقات التذكير');
      await t.scrollUntilVisible(
        history,
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(history);
      await t.pumpAndSettle();
      expect(find.textContaining('2026-10-13 08:00:00'), findsOneWidget);
      expect(
        find.textContaining('تاريخ وتوقيت الموعد عند الحفظ:'),
        findsOneWidget,
      );
    },
  );
  for (final width in [320.0, 390.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.7]) {
        for (final scenario in [
          'selected',
          'settings',
          'preparing',
          'review',
          'pending',
          'failure',
          'stale',
          'confirmed',
          'expired',
          'archived',
          'permission',
          'unsupported',
          'missed',
          'keyboard',
        ]) {
          testWidgets('native RTL $scenario $width ${brightness.name} $scale', (
            t,
          ) async {
            size(t, width: width);
            final capture = GlobalKey(),
                g = FakeNative()..data = nativeFixture(karat: 21),
                s = MemoryLocker(),
                sync = ChangeNotifier();
            final waiting = Completer<DebtNativeDetail>(),
                device = DebtReminderCoordinator(
                  gateway: g,
                  store: MemoryDeviceStore(),
                  port: FakeNotificationPort(),
                  clock: FakeReminderClock(),
                );
            if (scenario == 'preparing') g.readOverride = () => waiting.future;
            if (scenario == 'archived') {
              g.data = nativeFixture(karat: 21, state: 'archived');
            }
            if (scenario == 'pending') g.unknown = true;
            device.report = ReminderDeviceReport(switch (scenario) {
              'permission' => DeviceReminderState.permissionDenied,
              'unsupported' => DeviceReminderState.unsupported,
              'missed' => DeviceReminderState.missed,
              _ => DeviceReminderState.disabled,
            });
            await t.pumpWidget(
              RepaintBoundary(
                key: capture,
                child: customerHost(
                  nativeScreen(
                    g,
                    s,
                    settings: [
                      'settings',
                      'permission',
                      'unsupported',
                      'missed',
                    ].contains(scenario),
                    sync: sync,
                    write: () => scenario != 'expired',
                    device: device,
                  ),
                  brightness: brightness,
                  scale: scale,
                ),
              ),
            );
            if (scenario == 'preparing') {
              await t.pump();
              await t.pump(const Duration(milliseconds: 250));
            } else {
              await t.pumpAndSettle();
            }
            if ([
              'review',
              'pending',
              'failure',
              'stale',
              'confirmed',
            ].contains(scenario)) {
              await nativeReview(t);
              if (scenario == 'failure') g.error = 'stale_native';
              if (scenario == 'stale') {
                sync.notifyListeners();
                await t.pumpAndSettle();
              }
              if (['pending', 'failure', 'confirmed'].contains(scenario)) {
                await nativeTap(t, 'native-confirm');
                FocusManager.instance.primaryFocus?.unfocus();
                await t.pumpAndSettle();
                t
                    .state<ScrollableState>(find.byType(Scrollable).first)
                    .position
                    .jumpTo(0);
                await t.pumpAndSettle();
              }
              if (['review', 'stale'].contains(scenario)) {
                await t.ensureVisible(find.byKey(const Key('native-review')));
                await t.pumpAndSettle();
              }
            }
            if (scenario == 'keyboard') {
              final field = find.byKey(const Key('native-time'));
              if (field.evaluate().isEmpty) {
                await t.scrollUntilVisible(
                  field,
                  250,
                  scrollable: find.byType(Scrollable).first,
                );
              }
              await t.ensureVisible(field);
              await t.tap(field);
              await t.sendKeyEvent(LogicalKeyboardKey.tab);
              await t.pumpAndSettle();
            }
            if (scenario == 'pending') {
              await Scrollable.ensureVisible(
                t.element(find.byKey(const Key('native-pending'))),
                alignment: 0,
              );
              await t.pump();
              await t.pump(const Duration(milliseconds: 100));
              expect(
                t.getTopLeft(find.byKey(const Key('native-pending'))).dy,
                greaterThanOrEqualTo(t.getBottomLeft(find.byType(AppBar)).dy),
              );
            }
            expect(t.takeException(), isNull);
            expect(
              Directionality.of(t.element(find.byType(Scaffold))),
              TextDirection.rtl,
            );
            for (final element in find.byType(OutlinedButton).evaluate()) {
              final box = element.renderObject;
              if (box is RenderBox && box.hasSize) {
                expect(box.size.height, greaterThanOrEqualTo(48));
              }
            }
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await t.runAsync(() async {
              final picture = await boundary.toImage(),
                  bytes = await picture.toByteData(
                    format: ui.ImageByteFormat.png,
                  );
              final file = File(
                'build/debt-native/$scenario-${brightness.name}-${width.toInt()}-$scale.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              picture.dispose();
            });
            await t.pumpWidget(const SizedBox());
            if (!waiting.isCompleted) {
              waiting.complete(parseDebtNativeDetail(g.data));
            }
            sync.dispose();
          });
        }
      }
    }
  }
}
