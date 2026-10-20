import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/invoice_pdf_share_dialog.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'financial_trade_screen_test.dart' show FakeFinancialGateway;

class PdfGateway extends FakeFinancialGateway {
  String customer = 'عميل تجريبي';
  String? changedOnRead;
  int reads = 0;
  @override
  Future<Map<String,Object?>> operation({required String callerUserId,
    required String operationId}) async {
    reads++;
    if (reads > 1 && changedOnRead != null) customer = changedOnRead!;
    return {'operation_id':operationId, 'shop_id':'shop-1', 'kind':'sale',
      'shop_name':'متجر تجريبي', 'shop_sequence':'7', 'occurred_at':'2026-10-20T10:30:00Z', 'occurred_at_cairo':'2026-10-20T13:30:00',
      'payload':{'customer_name':customer,'customer_phone':'01000000000',
        'total_piastres':'10000','items':<Object?>[],'tenders':<Object?>[]}};
  }
}
void main() {
  testWidgets('PDF preview rechecks changed customer and requires a second explicit share', (t) async {
    final gateway=PdfGateway();
    var launched=0;
    await t.pumpWidget(MaterialApp(theme:AppTheme.light(),
      home: Scaffold(body:InvoicePdfShareDialog(gateway:gateway, userId:'owner-1',
        shopId:'shop-1', operationId:'operation-1', canRead:()=>true,canWrite:()=>true,
        share:(bytes,name) async { launched++; return true; }))));
    await t.pumpAndSettle();
    expect(find.textContaining('عميل تجريبي'), findsOneWidget);
    expect(find.text('تأكيد الإرسال بعد إرساله'), findsNothing);
    gateway.changedOnRead='عميل محدّث';
    await t.tap(find.byKey(const Key('invoice-pdf-share')));
    await t.pumpAndSettle();
    expect(launched,0);
    expect(find.textContaining('عميل محدّث'),findsOneWidget);
    expect(find.textContaining('تغيّرت الفاتورة'),findsOneWidget);
  });
  testWidgets('access invalidation clears protected destination before sharing', (t) async {
    final signal=ValueNotifier<int>(0);
    var allowed=true, launched=0;
    await t.pumpWidget(MaterialApp(theme:AppTheme.dark(),
      home:Scaffold(body:InvoicePdfShareDialog(gateway:PdfGateway(), userId:'owner-1',
        shopId:'shop-1', operationId:'operation-1',canRead:()=>allowed,canWrite:()=>allowed,
        invalidations:signal, share:(bytes,name) async {launched++;return true;}))));
    await t.pumpAndSettle();
    allowed=false;signal.value++;
    await t.pumpAndSettle();
    expect(find.textContaining('عميل تجريبي'),findsNothing);
    expect(find.byKey(const Key('invoice-pdf-share')),findsNothing);
    expect(launched,0);
    await t.pumpWidget(const SizedBox());signal.dispose();
  });
}
