import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_operation_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'financial_trade_screen_test.dart' show FakeFinancialGateway;

class DetailsGateway extends FakeFinancialGateway {
  DetailsGateway(this.payload);
  final Map<String, Object?> payload;

  @override
  Future<Map<String, Object?>> operation({
    required String callerUserId,
    required String operationId,
  }) async => {
    'kind': 'sale',
    'shop_id': 'shop-1',
    'operation_id': operationId,
    'shop_sequence': '7',
    'actor_display_name': 'بائع المحل',
    'payload': payload,
  };
}

class ReturnCapableDetailsGateway extends DetailsGateway
    implements LinkedReturnGateway, PartialReturnGateway {
  ReturnCapableDetailsGateway(super.payload);

  var remainderReads = 0;

  @override
  Future<FinancialCommandResult> returnOperation({
    required String callerUserId,
    required String idempotencyKey,
    required String originalOperationId,
    required String note,
  }) async => result;

  @override
  Future<Map<String, Object?>> remainder({
    required String callerUserId,
    required String operationId,
  }) async {
    remainderReads += 1;
    return {
      'operation_id': operationId,
      'kind': 'sale',
      'remainder_consideration_piastres': '10000',
      'items': const <Object?>[],
    };
  }

  @override
  Future<FinancialCommandResult> postPartialReturn({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) async => result;
}

LedgerFeedLine line({bool hasNote = false}) => LedgerFeedLine(
  kind: 'sale',
  labelAr: 'بيع',
  operationId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
  actorDisplayName: 'بائع المحل',
  occurredAt: '2026-09-26T12:30:00Z',
  occurredAtCairo: '2026-09-26T15:30:00',
  hasNote: hasNote,
);

Future<void> pumpDetails(
  WidgetTester tester,
  DetailsGateway gateway, {
  bool hasNote = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      theme: AppTheme.dark(),
      home: FinancialOperationScreen(
        gateway: gateway,
        userId: 'owner-1',
        line: line(hasNote: hasNote),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('details omit the day and use 12-hour Arabic time', (
    tester,
  ) async {
    await pumpDetails(
      tester,
      DetailsGateway(const {
        'customer_name': '',
        'customer_phone': '',
        'note': '',
      }),
    );
    expect(find.textContaining('سبتمبر'), findsNothing);
    expect(find.textContaining('\u20663:30\u2069 م'), findsOneWidget);
    expect(find.text('اسم البائع: بائع المحل'), findsOneWidget);
    expect(find.text('لا توجد بيانات عميل'), findsOneWidget);
    expect(find.text('لا توجد ملاحظات'), findsOneWidget);
  });

  testWidgets('partial customer data stays honest', (tester) async {
    await pumpDetails(
      tester,
      DetailsGateway(const {
        'customer_name': 'عميل جزئي',
        'customer_phone': '',
        'note': '',
      }),
    );
    expect(find.text('لا توجد بيانات عميل'), findsNothing);
    expect(find.text('اسم العميل: عميل جزئي'), findsOneWidget);
    expect(find.text('الجوال: لا يوجد رقم'), findsOneWidget);
  });

  testWidgets('notes flag discloses the actual text', (tester) async {
    await pumpDetails(
      tester,
      DetailsGateway(const {
        'customer_name': 'سارة',
        'customer_phone': '01011111111',
        'note': 'تسليم مساءً',
      }),
      hasNote: true,
    );
    expect(find.text('توجد ملاحظات'), findsOneWidget);
    await tester.tap(find.byKey(const Key('operation-notes')));
    await tester.pumpAndSettle();
    expect(find.text('تسليم مساءً'), findsOneWidget);
  });

  testWidgets('sale details offer linked return or exchange', (tester) async {
    final gateway = ReturnCapableDetailsGateway(const {
      'customer_name': '',
      'customer_phone': '',
      'note': '',
      'total_piastres': '10000',
      'items': <Object?>[],
      'tenders': <Object?>[],
    });
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.dark(),
        home: FinancialOperationScreen(
          gateway: gateway,
          userId: 'owner-1',
          shopId: 'shop-1',
          line: line(),
          canWrite: () => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('operation-create-return')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('تسجيل مرتجع أو استبدال'), findsOneWidget);
    expect(find.byKey(const Key('operation-create-return')), findsOneWidget);
  });
}
