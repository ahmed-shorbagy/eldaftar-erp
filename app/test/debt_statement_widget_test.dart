import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eldafttar/src/features/debts/application/debt_statement_flow.dart';
import 'package:eldafttar/src/features/debts/data/debt_statement_codec.dart';
import 'package:eldafttar/src/features/debts/domain/debt_rules.dart';
import 'package:eldafttar/src/features/debts/domain/debt_statement.dart';
import 'package:eldafttar/src/features/debts/presentation/debt_statement_screen.dart';
import 'customer_widget_test.dart' show customerHost, size;
import 'debt_statement_test.dart' show StatementFake, StatementPlatformFake;
import 'debt_statement_fixtures.dart';
import 'debt_widget_test.dart' as debt;
import 'repair_command_flow_test.dart' show MemoryLocker;
import 'package:eldafttar/src/features/debts/presentation/debt_screen.dart';
import 'package:eldafttar/src/features/debts/application/debt_statement_gateway.dart';

class StatementDebtFake extends debt.FakeDebts implements DebtStatementGateway {
  int statementReads = 0;
  @override
  Object? statementSession(String user) => 'synthetic-session';
  @override
  Future<DebtStatement> readStatement({
    required String callerUserId,
    required String shopId,
    required DebtSourceKind sourceKind,
    required String sourceId,
  }) async {
    statementReads++;
    final j = statementFixture()
      ..['shop_id'] = shopId
      ..['source_id'] = sourceId;
    return parseDebtStatement(j);
  }
}

// Adapter-only tests work from a clean checkout; visual evidence uses the
// actual Poppler page generated in build/debt-statement before capture review.
Uint8List previewFixture() {
  final file = File('build/debt-statement/money-1.png');
  return file.existsSync()
      ? file.readAsBytesSync()
      : base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aMfoAAAAASUVORK5CYII=',
        );
}

Widget statementScreen(
  StatementFake g,
  StatementPlatformFake p, {
  Listenable? sync,
  StatementRasterizer? raster,
  bool Function()? canRead,
}) => DebtStatementScreen(
  gateway: g,
  platform: p,
  userId: statementUser,
  shopId: statementShop,
  sourceKind: DebtSourceKind.standalone,
  sourceId: statementSourceId,
  syncTicks: sync,
  canRead: canRead ?? () => true,
  render: (_) async => Uint8List.fromList(utf8.encode('%PDF synthetic')),
  raster: raster ?? (_) async => [previewFixture()],
);
Future<void> capture(WidgetTester t, GlobalKey key, String name) async {
  // Image codecs finish on the real event loop, outside the widget fake clock.
  await t.runAsync(() async {
    for (final image in t.widgetList<Image>(find.byType(Image))) {
      final stream = image.image.resolve(ImageConfiguration.empty);
      final decoded = Completer<void>();
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (_, _) {
          if (!decoded.isCompleted) decoded.complete();
        },
        onError: (Object e, StackTrace? s) {
          if (!decoded.isCompleted) decoded.completeError(e, s);
        },
      );
      stream.addListener(listener);
      try {
        await decoded.future;
      } finally {
        stream.removeListener(listener);
      }
    }
  });
  await t.pump();
  expect(t.takeException(), isNull);
  await t.runAsync(() async {
    final image =
        await (key.currentContext!.findRenderObject() as RenderRepaintBoundary)
            .toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/debt-statement/screens/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  testWidgets('duplicate detail action opens only one statement generation', (
    t,
  ) async {
    size(t);
    final g = StatementDebtFake();
    await t.pumpWidget(
      customerHost(
        DebtScreen(
          gateway: g,
          store: MemoryLocker(),
          userId: debt.userId,
          shopId: debt.shopId,
          readOnly: true,
          statementPlatform: StatementPlatformFake(),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('debt-item-${debt.sourceId}')));
    await t.pumpAndSettle();
    final button = t.widget<FilledButton>(
      find.byKey(const Key('debt-statement')),
    );
    button.onPressed!();
    button.onPressed!();
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byType(DebtStatementScreen), findsOneWidget);
    expect(g.statementReads, 1);
    await t.pumpWidget(const SizedBox());
    await t.pump();
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
  for (final width in [320.0, 390.0, 1440.0]) {
    for (final theme in Brightness.values) {
      for (final scale in [1.0, 1.7]) {
        final suffix = '${width.toInt()}-${theme.name}-$scale';
        testWidgets('Arabic statement states $suffix', (t) async {
          size(t, width: width);
          final key = GlobalKey(), sync = ChangeNotifier();
          final g = StatementFake(),
              p = StatementPlatformFake(),
              loading = Completer<DebtStatement>();
          final png = previewFixture();
          g.read = () => loading.future;
          await t.pumpWidget(
            customerHost(
              RepaintBoundary(
                key: key,
                child: statementScreen(
                  g,
                  p,
                  sync: sync,
                  raster: (_) async => [Uint8List.fromList(png)],
                ),
              ),
              brightness: theme,
              scale: scale,
            ),
          );
          await t.pump();
          expect(find.text('جارٍ إعداد كشف الحساب من الخادم…'), findsOneWidget);
          await capture(t, key, 'preparing-$suffix');
          g.read = null;
          loading.complete(parseDebtStatement(g.data));
          await t.pumpAndSettle();
          expect(find.byKey(const Key('statement-share')), findsOneWidget);
          await capture(t, key, 'preview-$suffix');
          await t.ensureVisible(find.byKey(const Key('statement-share')));
          await t.tap(find.byKey(const Key('statement-share')));
          await t.pumpAndSettle();
          expect(p.calls, 1);
          await capture(t, key, 'handoff-$suffix');
          sync.notifyListeners();
          await t.pump();
          expect(find.byKey(const Key('statement-page-0')), findsNothing);
          await capture(t, key, 'stale-$suffix');
          g.read = () async => throw StateError('synthetic');
          await t.ensureVisible(find.byKey(const Key('statement-prepare')));
          await t.tap(find.byKey(const Key('statement-prepare')));
          await t.pumpAndSettle();
          await capture(t, key, 'failure-$suffix');
          g.read = null;
          await t.tap(find.byKey(const Key('statement-prepare')));
          await t.pumpAndSettle();
          p.outcome = StatementOutcome.cancelled;
          await t.ensureVisible(find.byKey(const Key('statement-save')));
          await t.tap(find.byKey(const Key('statement-save')));
          await t.pumpAndSettle();
          await capture(t, key, 'cancelled-$suffix');
          await t.sendKeyEvent(LogicalKeyboardKey.tab);
          await t.pump();
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          sync.dispose();
        });
      }
    }
  }
  testWidgets(
    'unavailable controls absent and token loss removes cached pages',
    (t) async {
      size(t);
      final g = StatementFake(), p = StatementPlatformFake();
      p.caps = const StatementCapabilities();
      final png = previewFixture();
      await t.pumpWidget(
        customerHost(
          statementScreen(g, p, raster: (_) async => [Uint8List.fromList(png)]),
        ),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('statement-print')), findsNothing);
      expect(find.byKey(const Key('statement-share')), findsNothing);
      g.session = null;
      await t.pump(const Duration(seconds: 1));
      expect(find.byKey(const Key('statement-page-0')), findsNothing);
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets('late raster on logout never exposes pages or actions', (
    t,
  ) async {
    final g = StatementFake(),
        p = StatementPlatformFake(),
        pending = Completer<List<Uint8List>>();
    await t.pumpWidget(
      customerHost(statementScreen(g, p, raster: (_) => pending.future)),
    );
    await t.pump();
    g.session = null;
    await t.pump(const Duration(seconds: 1));
    final bytes = previewFixture();
    pending.complete([bytes]);
    await t.pumpAndSettle();
    expect(find.byKey(const Key('statement-share')), findsNothing);
    expect(bytes.every((b) => b == 0), true);
    await t.pumpWidget(const SizedBox());
  });
}
