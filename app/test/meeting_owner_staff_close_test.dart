import 'package:eldafttar/src/features/closing_delegation/presentation/staff_count_review_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'closing_delegation_test.dart'
    show delegateShop, delegateTask, delegateHost, delegateTap;
import 'owner_meeting_capture_test.dart' show StaffCaptureGateway, CountGateway;

class OwnerCloseGateway extends StaffCaptureGateway {
  final closeKeys = <String>[];
  final counted = <Map<String, Object?>>[];
  bool protectedBeforeSend = false;
  @override
  Future<FinancialCommandResult> closeFromStaffCount({
    required String userId,
    required String key,
    required String taskId,
    required Map<String, Object?> cash,
  }) async {
    protectedBeforeSend =
        (await const PendingFinancialCommands().read(
          userId,
          delegateShop,
        ))?.key ==
        key;
    closeKeys.add(key);
    counted.add(cash);
    return closeKeys.length == 1
        ? const FinancialUnknown()
        : const FinancialCommitted('closed-operation', replayed: true);
  }
}

void main() {
  testWidgets(
    'only owner review commits; mismatches block and unknown close retries one durable key',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      t.view.physicalSize = const Size(700, 1100);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final gateway = OwnerCloseGateway(), day = CountGateway();
      var closed = false;
      await t.pumpWidget(
        delegateHost(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  closed =
                      await Navigator.push<bool>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => StaffCountReviewScreen(
                            gateway: gateway,
                            dayGateway: day,
                            statusGateway: day,
                            userId: 'owner-1',
                            shopId: delegateShop,
                            taskId: delegateTask,
                            canRead: () => true,
                            canWrite: () => true,
                          ),
                        ),
                      ) ??
                      false;
                },
                child: const Text('فتح'),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('فتح'));
      await t.pumpAndSettle();
      for (final method in ['cash', 'instant_transfer', 'wallet', 'card']) {
        await t.enterText(
          find.byKey(Key('owner-staff-cash-$method')),
          method == 'cash' ? '2' : '0',
        );
      }
      await delegateTap(t, find.byKey(const Key('owner-staff-close')));
      expect(find.textContaining('يوجد فرق'), findsOneWidget);
      expect(gateway.closeKeys, isEmpty);
      await t.enterText(find.byKey(const Key('owner-staff-cash-cash')), '1');
      await delegateTap(t, find.byKey(const Key('owner-staff-close')));
      expect(
        find.textContaining('دون تغيير أرصدة النقد أو الذهب'),
        findsOneWidget,
      );
      expect(gateway.closeKeys, isEmpty);
      await delegateTap(t, find.text('تأكيد تقفيل اليومية بصفتي المالك'));
      expect(closed, isFalse);
      expect(gateway.protectedBeforeSend, isTrue);
      expect(gateway.closeKeys.length, 1);
      await delegateTap(t, find.text('التحقق من حالة التقفيل'));
      await delegateTap(t, find.text('إعادة طلب التقفيل نفسه'));
      expect(closed, isTrue);
      expect(gateway.closeKeys.toSet().length, 1);
      expect(gateway.counted.first, {
        'cash': '100',
        'instant_transfer': '0',
        'wallet': '0',
        'card': '0',
      });
      expect(
        await const PendingFinancialCommands().read('owner-1', delegateShop),
        isNull,
      );
    },
  );
}
