import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
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
    'shop_sequence': '7',
    'actor_display_name': 'بائع المحل',
    'payload': payload,
  };
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
}
