import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eldafttar/src/features/debts/application/debt_due_gateway.dart';
import 'package:eldafttar/src/features/debts/application/debt_due_contract.dart';
import 'package:eldafttar/src/features/debts/application/debt_gateway.dart';
import 'package:eldafttar/src/features/debts/data/debt_due_codec.dart';
import 'package:eldafttar/src/features/debts/domain/debt_rules.dart';
import 'package:eldafttar/src/features/debts/presentation/debt_due_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'debt_due_fixtures.dart';
import 'customer_widget_test.dart' show customerHost, size;
import 'repair_command_flow_test.dart' show MemoryLocker;

class DelayedDueLocker extends MemoryLocker {
  final oldRead = Completer<PendingFinancialCommand?>();
  int reads = 0;
  @override
  Future<PendingFinancialCommand?> read(String user, String shop) async {
    reads++;
    return reads == 1 ? oldRead.future : stored;
  }
}

Widget dueScreen(
  FakeDue g,
  MemoryLocker store, {
  bool list = false,
  Listenable? sync,
  bool Function()? canRead,
  bool Function()? canWrite,
}) => DebtDueScreen(
  gateway: g,
  store: store,
  userId: dueUser,
  shopId: dueShop,
  sourceKind: list ? null : DebtSourceKind.standalone,
  sourceId: list ? null : dueSourceId,
  canRead: canRead ?? () => true,
  canWrite: canWrite ?? () => true,
  syncTicks: sync,
  newKey: () => dueKey,
);
Future<void> tap(WidgetTester t, String key) async {
  final finder = find.byKey(Key(key));
  if (finder.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await t.ensureVisible(finder);
  await t.tap(finder);
  await t.pumpAndSettle();
}

Future<void> review(WidgetTester t) async {
  final field = find.byKey(const Key('due-date-field'));
  if (field.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      field,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await t.enterText(find.byKey(const Key('due-date-field')), '2026-10-15');
  await tap(t, 'due-prepare');
}

void main() {
  testWidgets(
    'calendar leap-month choices retain full scale and 48-pixel targets',
    (t) async {
      size(t, width: 320);
      final g = FakeDue();
      await t.pumpWidget(
        customerHost(dueScreen(g, MemoryLocker()), scale: 1.7),
      );
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('due-date-field')), '2024-02-29');
      await tap(t, 'due-picker');
      final day = find.byKey(const Key('due-calendar-day-2024-02-01'));
      expect(t.getSize(day).height, greaterThanOrEqualTo(48));
      expect(t.getSize(day).width, greaterThanOrEqualTo(48));
      expect(
        MediaQuery.textScalerOf(t.element(day)).scale(16),
        closeTo(27.2, .01),
      );
      expect(
        find.byKey(const Key('due-calendar-day-2024-02-30')),
        findsNothing,
      );
      await t.enterText(
        find.byKey(const Key('due-calendar-input')),
        '2023-02-29',
      );
      await t.tap(find.byKey(const Key('due-calendar-confirm')));
      await t.pumpAndSettle();
      expect(find.text('أدخل تاريخًا صحيحًا.'), findsOneWidget);
      await t.enterText(
        find.byKey(const Key('due-calendar-input')),
        '2024-02-29',
      );
      await t.tap(find.byKey(const Key('due-calendar-next')));
      await t.pumpAndSettle();
      final chosen = find.byKey(const Key('due-calendar-day-2024-03-15'));
      await t.scrollUntilVisible(
        chosen,
        250,
        scrollable: find
            .descendant(
              of: find.byType(Dialog),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await t.pumpAndSettle();
      await t.ensureVisible(chosen);
      await t.pumpAndSettle();
      await t.tap(chosen.hitTestable());
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('due-calendar-confirm')));
      await t.pumpAndSettle();
      expect(
        t
            .widget<TextFormField>(find.byKey(const Key('due-date-field')))
            .controller!
            .text,
        '2024-03-15',
      );
      expect(g.sent, isEmpty);
    },
  );
  testWidgets('late old-account locker read never contaminates new source', (
    t,
  ) async {
    size(t);
    final g = FakeDue();
    final store = DelayedDueLocker();
    await t.pumpWidget(customerHost(dueScreen(g, store)));
    await t.pump();
    const otherUser = 'a9999999-9999-4999-8999-999999999999';
    await t.pumpWidget(
      customerHost(
        DebtDueScreen(
          gateway: g,
          store: store,
          userId: otherUser,
          shopId: dueShop,
          sourceKind: DebtSourceKind.standalone,
          sourceId: dueSourceId,
          canRead: () => true,
          canWrite: () => true,
        ),
      ),
    );
    await t.pumpAndSettle();
    final p = {
      ...g.payload(),
      'source_id': 'a8888888-8888-4888-8888-888888888888',
    };
    store.oldRead.complete(
      PendingFinancialCommand(
        key: dueKey,
        kind: debtDueKind,
        body: {'p_idempotency_key': dueKey, 'p_payload': p},
      ),
    );
    await t.pumpAndSettle();
    expect(g.readRequests.length, 1);
    expect(g.readRequests.single, contains(otherUser));
    expect(g.readRequests.single, endsWith(dueSourceId));
    expect(find.textContaining('a8888888'), findsNothing);
  });
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
    'unchanged-content token refresh invalidates review on background poll',
    (t) async {
      size(t);
      final g = FakeDue();
      await t.pumpWidget(customerHost(dueScreen(g, MemoryLocker())));
      await t.pumpAndSettle();
      await review(t);
      g.session = 'new-token';
      await t.pump(const Duration(seconds: 45));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('due-review-stale')), findsOneWidget);
      expect(
        t
            .widget<OutlinedButton>(find.byKey(const Key('due-confirm')))
            .onPressed,
        isNull,
      );
      expect(g.sent, isEmpty);
    },
  );
  testWidgets(
    'pending original source takes precedence over another selected source',
    (t) async {
      size(t);
      final g = FakeDue();
      final pending = PendingFinancialCommand(
        key: dueKey,
        kind: debtDueKind,
        body: {'p_idempotency_key': dueKey, 'p_payload': g.payload()},
      );
      final store = MemoryLocker()..stored = pending;
      await t.pumpWidget(
        customerHost(
          DebtDueScreen(
            gateway: g,
            store: store,
            userId: dueUser,
            shopId: dueShop,
            sourceKind: DebtSourceKind.standalone,
            sourceId: 'a8888888-8888-4888-8888-888888888888',
            canRead: () => true,
            canWrite: () => true,
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.textContaining(dueSourceId), findsOneWidget);
      expect(find.textContaining('a8888888'), findsNothing);
      await tap(t, 'due-retry');
      expect(find.byKey(const Key('due-success')), findsOneWidget);
      expect(g.sent.single.body, pending.body);
    },
  );
  testWidgets(
    'duplicate confirmation taps while awaiting reply send only once',
    (t) async {
      size(t);
      final g = FakeDue();
      final waiting = Completer<DebtDueTransport>();
      g.sendOverride = (_) => waiting.future;
      await t.pumpWidget(customerHost(dueScreen(g, MemoryLocker())));
      await t.pumpAndSettle();
      await review(t);
      await t.ensureVisible(find.byKey(const Key('due-confirm')));
      await t.tap(find.byKey(const Key('due-confirm')));
      await t.pump();
      expect(
        t
            .widget<OutlinedButton>(find.byKey(const Key('due-confirm')))
            .onPressed,
        isNull,
      );
      expect(g.sent.length, 1);
      waiting.complete(
        DebtDueTransport(
          receipt: parseDebtDueReceipt(dueReceipt(g.sent.single)),
        ),
      );
      await t.pumpAndSettle();
      expect(g.sent.length, 1);
    },
  );
  testWidgets(
    'add/change/clear requires fresh source review and backend confirmation',
    (t) async {
      size(t);
      final g = FakeDue();
      final store = MemoryLocker();
      await t.pumpWidget(customerHost(dueScreen(g, store)));
      await t.pumpAndSettle();
      await review(t);
      expect(g.reads, 2);
      expect(g.sent, isEmpty);
      expect(find.byKey(const Key('due-review')), findsOneWidget);
      await tap(t, 'due-confirm');
      expect(g.sent.length, 1);
      expect(
        (g.sent.single.body['p_payload'] as Map)['due_date'],
        '2026-10-15',
      );
      expect(find.byKey(const Key('due-success')), findsOneWidget);
      await tap(t, 'due-clear');
      await tap(t, 'due-confirm');
      expect((g.sent.last.body['p_payload'] as Map)['due_date'], isNull);
      expect(store.stored, isNull);
    },
  );
  testWidgets('invalid leap date stays inline and never reaches review', (
    t,
  ) async {
    size(t);
    final g = FakeDue();
    await t.pumpWidget(customerHost(dueScreen(g, MemoryLocker())));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('due-date-field')), '2023-02-29');
    await tap(t, 'due-prepare');
    expect(find.text('أدخل تاريخًا صحيحًا بصيغة سنة-شهر-يوم.'), findsOneWidget);
    expect(g.reads, 1);
    expect(g.sent, isEmpty);
  });
  testWidgets('sync invalidates review without destroying date draft', (
    t,
  ) async {
    size(t);
    final g = FakeDue();
    final sync = ChangeNotifier();
    await t.pumpWidget(customerHost(dueScreen(g, MemoryLocker(), sync: sync)));
    await t.pumpAndSettle();
    await review(t);
    sync.notifyListeners();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('due-review-stale')), findsOneWidget);
    expect(
      t.widget<OutlinedButton>(find.byKey(const Key('due-confirm'))).onPressed,
      isNull,
    );
    await tap(t, 'due-edit');
    expect(
      t
          .widget<TextFormField>(find.byKey(const Key('due-date-field')))
          .controller!
          .text,
      '2026-10-15',
    );
    expect(g.sent, isEmpty);
    await t.pumpWidget(const SizedBox());
    sync.dispose();
  });
  testWidgets('unknown and duplicate taps freeze the original request', (
    t,
  ) async {
    size(t);
    final g = FakeDue()..unknown = true;
    final store = MemoryLocker();
    await t.pumpWidget(customerHost(dueScreen(g, store)));
    await t.pumpAndSettle();
    await review(t);
    await tap(t, 'due-confirm');
    expect(find.byKey(const Key('due-pending')), findsOneWidget);
    expect(find.byKey(const Key('due-date-field')), findsNothing);
    final original = canonicalDueJson(store.stored!.body);
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(customerHost(dueScreen(g, store)));
    await t.pumpAndSettle();
    await tap(t, 'due-retry');
    expect(canonicalDueJson(g.sent.last.body), original);
    expect(find.byKey(const Key('due-success')), findsNothing);
  });
  testWidgets('foreign financial envelope stays blocked and untouched', (
    t,
  ) async {
    size(t);
    final g = FakeDue();
    final foreign = PendingFinancialCommand(
      key: dueKey,
      kind: 'sale',
      body: {
        'p_payload': {'kind': 'sale'},
      },
    );
    final store = MemoryLocker()..stored = foreign;
    await t.pumpWidget(customerHost(dueScreen(g, store)));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('due-foreign')), findsOneWidget);
    expect(find.byKey(const Key('due-date-field')), findsNothing);
    expect(identical(store.stored, foreign), true);
    expect(g.sent, isEmpty);
  });
  for (final state in ['expired', 'archived']) {
    testWidgets('$state dates remain readable without write controls', (
      t,
    ) async {
      size(t);
      final g = FakeDue()
        ..data = dueFixture(state: state == 'archived' ? 'archived' : 'open');
      await t.pumpWidget(
        customerHost(
          dueScreen(g, MemoryLocker(), canWrite: () => state != 'expired'),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('due-date-field')), findsNothing);
      expect(find.textContaining('2026-10-14'), findsWidgets);
    });
  }
  testWidgets('lost access clears exposed data, drafts and late replies', (
    t,
  ) async {
    size(t);
    final g = FakeDue();
    var readable = true;
    final sync = ChangeNotifier();
    await t.pumpWidget(
      customerHost(
        dueScreen(g, MemoryLocker(), sync: sync, canRead: () => readable),
      ),
    );
    await t.pumpAndSettle();
    await review(t);
    readable = false;
    sync.notifyListeners();
    await t.pumpAndSettle();
    expect(find.text('عميل اختبار عربي'), findsNothing);
    expect(find.byKey(const Key('due-review')), findsNothing);
    expect(g.sent, isEmpty);
    await t.pumpWidget(const SizedBox());
    sync.dispose();
  });
  testWidgets('stale cursor has explicit restart and no completeness claim', (
    t,
  ) async {
    size(t);
    final g = FakeDue();
    g.page = duePageFixture(total: 2, cursor: 'first');
    g.pageOverride = (cursor) async {
      if (cursor != null) throw const DebtReadException('stale_due_cursor');
      return parseDebtReminderPage(g.page);
    };
    await t.pumpWidget(customerHost(dueScreen(g, MemoryLocker(), list: true)));
    await t.pumpAndSettle();
    await tap(t, 'due-more');
    expect(find.byKey(const Key('due-list-stale')), findsOneWidget);
    expect(find.byKey(const Key('due-restart')), findsOneWidget);
    expect(find.textContaining('المعروض:'), findsNothing);
    await tap(t, 'due-restart');
    expect(find.byKey(const Key('due-list-stale')), findsNothing);
  });
  testWidgets('server day changes invalidate preserved list and date review', (
    t,
  ) async {
    size(t);
    final g = FakeDue();
    final sync = ChangeNotifier();
    await t.pumpWidget(
      customerHost(dueScreen(g, MemoryLocker(), list: true, sync: sync)),
    );
    await t.pumpAndSettle();
    g.page = {
      ...g.page,
      'freshness': List.filled(64, 'b').join(),
      'local_date': '2026-10-15',
      'snapshot_at': '2026-10-15T00:00:00Z',
      'snapshot_at_shop': '2026-10-15T03:00:00',
      'items': [
        {...dueFixture(), 'local_date': '2026-10-15', 'due_state': 'overdue'},
      ],
    };
    sync.notifyListeners();
    await t.pumpAndSettle();
    expect(find.byKey(const Key('due-list-stale')), findsOneWidget);
    await tap(t, 'due-restart');
    expect(find.textContaining('متأخرة'), findsWidgets);
    await t.pumpWidget(const SizedBox());
    sync.dispose();
  });
  testWidgets(
    'Arabic calendar uses supplied server date and keyboard controls',
    (t) async {
      size(t);
      final g = FakeDue();
      await t.pumpWidget(customerHost(dueScreen(g, MemoryLocker())));
      await t.pumpAndSettle();
      await tap(t, 'due-picker');
      expect(find.text('اختر موعد الاستحقاق'), findsOneWidget);
      expect(find.text('اختيار'), findsOneWidget);
      await t.sendKeyEvent(LogicalKeyboardKey.escape);
      await t.pumpAndSettle();
      expect(find.text('اختر موعد الاستحقاق'), findsNothing);
    },
  );
  for (final width in [320.0, 390.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 1.7]) {
        for (final scenario in [
          'populated',
          'empty',
          'preparing',
          'review',
          'pending',
          'failure',
          'stale',
          'confirmed',
          'expired',
          'archived',
          'picker',
          'keyboard',
        ]) {
          testWidgets('RTL capture $scenario $width ${brightness.name} $scale', (
            t,
          ) async {
            size(t, width: width);
            final capture = GlobalKey();
            final g = FakeDue()..data = dueFixture(karat: 21);
            final store = MemoryLocker();
            final sync = ChangeNotifier();
            final waiting = Completer<DebtDueDetail>();
            final list = ['populated', 'empty'].contains(scenario);
            if (scenario == 'empty') g.page = duePageFixture(rows: []);
            if (scenario == 'populated') {
              g.page = duePageFixture(
                rows: [
                  dueFixture(
                    source: 'gold_obligation',
                    karat: 21,
                    date: '2026-10-13',
                  ),
                  {
                    ...dueFixture(),
                    'source_id': 'a7777777-7777-4777-8777-777777777777',
                    'debt_key':
                        'standalone:a7777777-7777-4777-8777-777777777777',
                    'direction': 'owed_to_shop',
                    'due_date': '2026-10-15',
                    'due_state': 'upcoming',
                  },
                ],
              );
            }
            if (scenario == 'preparing') g.readOverride = () => waiting.future;
            if (scenario == 'archived') {
              g.data = dueFixture(karat: 21, state: 'archived');
            }
            if (scenario == 'pending') g.unknown = true;
            if (scenario == 'failure') g.error = 'stale_due';
            await t.pumpWidget(
              RepaintBoundary(
                key: capture,
                child: customerHost(
                  dueScreen(
                    g,
                    store,
                    list: list,
                    sync: sync,
                    canWrite: () => scenario != 'expired',
                  ),
                  brightness: brightness,
                  scale: scale,
                ),
              ),
            );
            if (scenario == 'preparing') {
              await t.pump();
              await t.pump(const Duration(milliseconds: 300));
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
              await review(t);
              if (scenario == 'stale') {
                sync.notifyListeners();
                await t.pumpAndSettle();
              }
              if (['pending', 'failure', 'confirmed'].contains(scenario)) {
                await tap(t, 'due-confirm');
              }
              if (['review', 'stale'].contains(scenario)) {
                await t.ensureVisible(find.byKey(const Key('due-review')));
              }
              await t.pumpAndSettle();
            }
            if (scenario == 'picker') await tap(t, 'due-picker');
            if (scenario == 'keyboard') {
              await t.ensureVisible(find.byKey(const Key('due-date-field')));
              await t.tap(find.byKey(const Key('due-date-field')));
              await t.sendKeyEvent(LogicalKeyboardKey.tab);
              await t.pumpAndSettle();
            }
            expect(t.takeException(), isNull);
            final boundary =
                capture.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            await t.runAsync(() async {
              final picture = await boundary.toImage();
              final bytes = await picture.toByteData(
                format: ui.ImageByteFormat.png,
              );
              final file = File(
                'build/debt-due/$scenario-${brightness.name}-${width.toInt()}-$scale.png',
              );
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes!.buffer.asUint8List());
              picture.dispose();
            });
            await t.pumpWidget(const SizedBox());
            if (!waiting.isCompleted) {
              waiting.complete(parseDebtDueDetail(g.data));
            }
            sync.dispose();
          });
        }
      }
    }
  }
}
