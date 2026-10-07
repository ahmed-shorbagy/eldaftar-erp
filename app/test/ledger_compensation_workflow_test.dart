import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/partial_return_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_correction_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const operationId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const dayId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const ownerId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc';
const shopId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
const book = <String, Object?>{
  'cash': {
    'cash': '500000',
    'card': '1000',
    'wallet': '0',
    'instant_transfer': '0',
  },
  'stock': [
    {
      'category': 'worked_jewelry',
      'karat': 18,
      'milligrams': '10000',
      'count': '4',
    },
  ],
  'scrap': <Object?>[],
};
const day = FinancialDayState(
  state: 'open',
  dayId: dayId,
  businessDate: '2026-10-06',
  dayVersion: 7,
  counts: book,
);
const syntheticRemainder = <String, Object?>{
  'operation_id': operationId,
  'kind': 'sale',
  'fully_returned': false,
  'original_immutable': true,
  'original_total_piastres': '8000',
  'returned_consideration_piastres': '0',
  'remainder_consideration_piastres': '8000',
  'payable_remaining_piastres': '0',
  'has_pricing': false,
  'pricing': <String, Object?>{},
  'refundable_by_method': {
    'cash': '7000',
    'card': '1000',
    'instant_transfer': '0',
    'wallet': '0',
  },
  'items': [
    {
      'item_index': '0',
      'category': 'worked_jewelry',
      'karat': 18,
      'item_name': 'خاتم',
      'original_milligrams': '4000',
      'original_count': '2',
      'returned_milligrams': '0',
      'returned_count': '0',
      'remainder_milligrams': '4000',
      'remainder_count': '2',
    },
  ],
};

class CompensationReviewGateway
    implements
        FinancialGateway,
        OpeningGateway,
        PartialReturnGateway,
        LedgerCorrectionGateway,
        ExchangeGateway {
  FinancialCommandResult result = const FinancialCommitted(
    operationId,
    replayed: false,
  );
  StatusResult statusResult = const StatusAbsent();
  FinancialDayState currentDay = day;
  final bodies = <Map<String, Object?>>[];
  final keys = <String>[];
  Future<FinancialCommandResult> record(
    String key,
    Map<String, Object?> payload,
  ) async {
    final pending = await const PendingFinancialCommands().read(
      ownerId,
      shopId,
    );
    expect(pending?.key, key);
    expect(pending?.body['p_payload'], payload);
    keys.add(key);
    bodies.add(
      Map<String, Object?>.from(jsonDecode(jsonEncode(payload)) as Map),
    );
    return result;
  }

  @override
  Future<FinancialCommandResult> postPartialReturn({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) => record(idempotencyKey, payload);
  @override
  Future<FinancialCommandResult> postCorrection({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) => record(idempotencyKey, payload);
  @override
  Future<FinancialCommandResult> postExchange({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) => record(idempotencyKey, payload);
  @override
  Future<FinancialCommandResult> retryPending({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) => record(
    command.key,
    Map<String, Object?>.from(command.body['p_payload']! as Map),
  );
  @override
  Future<FinancialDayState> dayState({required String callerUserId}) async =>
      currentDay;
  @override
  Future<StatusResult> status({
    required String callerUserId,
    required String idempotencyKey,
  }) async => statusResult;
  @override
  Future<Map<String, Object?>> remainder({
    required String callerUserId,
    required String operationId,
  }) async => remainderData;
  Map<String, Object?> get remainderData => syntheticRemainder;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Widget reviewHost(Widget child, {Brightness brightness = Brightness.dark}) =>
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: brightness == Brightness.dark
          ? ThemeMode.dark
          : ThemeMode.light,
      builder: (_, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: RepaintBoundary(
          key: const Key('compensation-capture'),
          child: child!,
        ),
      ),
      home: child,
    );
Widget partial(CompensationReviewGateway gateway) => PartialReturnScreen(
  gateway: gateway,
  statusGateway: gateway,
  dayGateway: gateway,
  userId: ownerId,
  shopId: shopId,
  remainder: syntheticRemainder,
);
Widget correction(CompensationReviewGateway gateway) => LedgerCorrectionScreen(
  gateway: gateway,
  statusGateway: gateway,
  dayGateway: gateway,
  userId: ownerId,
  shopId: shopId,
  book: book,
  counted: {
    ...book,
    'cash': {
      'cash': '499900',
      'card': '1000',
      'wallet': '0',
      'instant_transfer': '0',
    },
  },
);
Future<void> enter(WidgetTester tester, String key, String value) async {
  final f = find.byKey(Key(key));
  if (f.evaluate().isEmpty) {
    await tester.dragUntilVisible(
      f,
      find.byType(ListView).last,
      const Offset(0, -250),
    );
  }
  await tester.ensureVisible(f);
  await tester.enterText(f, value);
}

Future<void> tap(WidgetTester tester, String key) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final f = find.byKey(Key(key));
  if (f.evaluate().isEmpty) {
    await tester.dragUntilVisible(
      f,
      find.byType(ListView).last,
      const Offset(0, -250),
    );
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> preparePartial(WidgetTester tester) async {
  await enter(tester, 'partial-grams-0', '1.999');
  await enter(tester, 'partial-count-0', '1');
  await enter(tester, 'partial-consideration', '30');
  await enter(tester, 'partial-tender', '20');
  await enter(tester, 'partial-tender-card', '10');
  await tap(tester, 'partial-review');
  expect(find.byKey(const Key('partial-confirm')), findsOneWidget);
}

Future<void> prepareExchange(WidgetTester tester) async {
  await preparePartial(tester);
  await tap(tester, 'partial-exchange');
  await tap(tester, 'trade-select-خاتم');
  await tap(tester, 'trade-next');
  await enter(tester, 'trade-grams-0', '1.500');
  await tap(tester, 'trade-next');
  await enter(tester, 'trade-tender-amount-0', '40');
  await tap(tester, 'trade-next');
  await tap(tester, 'trade-review');
  final effects = find.byKey(const Key('exchange-effects'));
  if (effects.evaluate().isEmpty) {
    await tester.dragUntilVisible(
      effects,
      find.byType(ListView).last,
      const Offset(0, -250),
    );
  }
  expect(effects, findsOneWidget);
}

Future<void> captureCompensation(WidgetTester tester, String name) async {
  final context = tester.element(find.byType(Scaffold).last);
  expect(Directionality.of(context), TextDirection.rtl);
  await tester.pump();
  final root = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('compensation-capture')),
  );
  await tester.runAsync(() async {
    final image = await root.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final directory = Directory('build/compensation-review');
    await directory.create(recursive: true);
    await File(
      '${directory.path}/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
  });
  expect(tester.takeException(), isNull);
}

void compensationWorkflowTests() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final bytes = await File('assets/fonts/Cairo.ttf').readAsBytes();
    final sdk =
        Platform.environment['FLUTTER_ROOT'] ??
        File(
          Platform.resolvedExecutable,
        ).parent.parent.parent.parent.parent.parent.path;
    final icons = await File(
      '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
    await (FontLoader(
      'Cairo',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  testWidgets('partial split refund stays exact and saves before sending', (
    tester,
  ) async {
    final gateway = CompensationReviewGateway();
    await tester.pumpWidget(reviewHost(partial(gateway)));
    await tester.pumpAndSettle();
    await preparePartial(tester);
    await tap(tester, 'partial-confirm');
    expect(gateway.bodies.single['consideration_piastres'], '3000');
    expect((gateway.bodies.single['items'] as List).single, {
      'item_index': '0',
      'milligrams': '1999',
      'count': '1',
    });
    expect(gateway.bodies.single['tenders'], [
      {'method': 'cash', 'piastres': '2000'},
      {'method': 'card', 'piastres': '1000'},
    ]);
    expect(
      await const PendingFinancialCommands().read(ownerId, shopId),
      isNull,
    );
  });
  testWidgets(
    'full remaining return fills only remainders and requires explicit refund',
    (tester) async {
      final gateway = CompensationReviewGateway();
      final originalItem = Map<String, Object?>.from(
        (syntheticRemainder['items']! as List).single as Map,
      );
      final source = {
        ...syntheticRemainder,
        'returned_consideration_piastres': '3000',
        'remainder_consideration_piastres': '5000',
        'refundable_by_method': {
          'cash': '5000',
          'card': '0',
          'wallet': '0',
          'instant_transfer': '0',
        },
        'items': [
          {
            ...originalItem,
            'returned_milligrams': '1999',
            'returned_count': '1',
            'remainder_milligrams': '2001',
            'remainder_count': '1',
          },
        ],
      };
      await tester.pumpWidget(
        reviewHost(
          PartialReturnScreen(
            gateway: gateway,
            statusGateway: gateway,
            dayGateway: gateway,
            userId: ownerId,
            shopId: shopId,
            remainder: source,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('إرجاع كامل المتبقي'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('partial-consideration')))
            .controller!
            .text,
        '50.00',
      );
      final tenderField = find.byKey(const Key('partial-tender'));
      if (tenderField.evaluate().isEmpty) {
        await tester.dragUntilVisible(
          tenderField,
          find.byType(ListView).last,
          const Offset(0, -200),
        );
        await tester.pumpAndSettle();
      }
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('partial-tender')))
            .controller!
            .text,
        isEmpty,
      );
      await enter(tester, 'partial-tender', '50');
      await tap(tester, 'partial-review');
      expect(find.text('تأكيد مرتجع المتبقي بالكامل'), findsOneWidget);
      await tap(tester, 'partial-confirm');
      expect(gateway.bodies.single['consideration_piastres'], '5000');
      expect(gateway.bodies.single['items'], [
        {'item_index': '0', 'milligrams': '2001', 'count': '1'},
      ]);
    },
  );
  testWidgets(
    'unknown partial preserves body and original key across restore',
    (tester) async {
      final gateway = CompensationReviewGateway()
        ..result = const FinancialUnknown();
      await tester.pumpWidget(reviewHost(partial(gateway)));
      await tester.pumpAndSettle();
      await preparePartial(tester);
      await tap(tester, 'partial-confirm');
      final pending = await const PendingFinancialCommands().read(
        ownerId,
        shopId,
      );
      expect(pending, isNotNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(reviewHost(partial(gateway)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('partial-check-status')), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('partial-consideration')))
            .readOnly,
        isTrue,
      );
      gateway.result = const FinancialCommitted(operationId, replayed: true);
      await tap(tester, 'partial-check-status');
      expect(gateway.keys, [pending!.key, pending.key]);
      expect(gateway.bodies[1], gateway.bodies[0]);
      expect(
        await const PendingFinancialCommands().read(ownerId, shopId),
        isNull,
      );
    },
  );
  testWidgets(
    'stale return rejection clears only rejected key and requires review',
    (tester) async {
      final gateway = CompensationReviewGateway()
        ..result = const FinancialRejected('stale_day');
      await tester.pumpWidget(reviewHost(partial(gateway)));
      await tester.pumpAndSettle();
      await preparePartial(tester);
      await tap(tester, 'partial-confirm');
      expect(
        await const PendingFinancialCommands().read(ownerId, shopId),
        isNull,
      );
      expect(find.byKey(const Key('partial-review')), findsOneWidget);
    },
  );
  testWidgets('exchange sends both sides under one durable envelope', (
    tester,
  ) async {
    final gateway = CompensationReviewGateway();
    await tester.pumpWidget(reviewHost(partial(gateway)));
    await tester.pumpAndSettle();
    await prepareExchange(tester);
    await tap(tester, 'trade-confirm');
    expect(gateway.bodies.single['kind'], 'exchange');
    expect(
      (gateway.bodies.single['return'] as Map)['consideration_piastres'],
      '3000',
    );
    expect(
      (gateway.bodies.single['replacement'] as Map)['total_piastres'],
      '4000',
    );
    expect(find.byKey(const Key('trade-done')), findsOneWidget);
  });
  testWidgets('correction rejects a changed snapshot before submission', (
    tester,
  ) async {
    final gateway = CompensationReviewGateway()
      ..currentDay = FinancialDayState(
        state: 'open',
        dayId: dayId,
        businessDate: '2026-10-06',
        dayVersion: 8,
        counts: {
          ...book,
          'cash': {
            'cash': '500001',
            'card': '1000',
            'wallet': '0',
            'instant_transfer': '0',
          },
        },
      );
    await tester.pumpWidget(reviewHost(correction(gateway)));
    await tester.pumpAndSettle();
    await enter(tester, 'correction-reason', 'فرق العد');
    await tap(tester, 'correction-review');
    expect(find.byKey(const Key('correction-confirm')), findsNothing);
    expect(gateway.bodies, isEmpty);
  });
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 1440.0]) {
      for (final flow in ['partial', 'correction', 'exchange']) {
        testWidgets('RTL $flow ${brightness.name} ${width.toInt()}', (
          tester,
        ) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 1200);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final gateway = CompensationReviewGateway();
          await tester.pumpWidget(
            reviewHost(
              flow == 'correction' ? correction(gateway) : partial(gateway),
              brightness: brightness,
            ),
          );
          await tester.pumpAndSettle();
          if (flow == 'correction') {
            await enter(tester, 'correction-reason', 'فرق العد الفعلي');
            await tap(tester, 'correction-review');
            await tester.ensureVisible(
              find.text('يلزم عدّ فعلي جديد مطابق بعد التسوية قبل التقفيل.'),
            );
          } else if (flow == 'exchange') {
            await prepareExchange(tester);
            await tester.ensureVisible(
              find.byKey(const Key('exchange-effects')),
            );
          } else {
            await preparePartial(tester);
            await tester.ensureVisible(
              find.byKey(const Key('partial-exchange')),
            );
          }
          await tester.pumpAndSettle();
          await captureCompensation(
            tester,
            '$flow-${brightness.name}-${width.toInt()}',
          );
        });
      }
    }
  }
}

void main() => compensationWorkflowTests();
