import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/data/daily_ledger_codec.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/confirmed_ledger_dashboard.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/daily_ledger_screen.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'financial_trade_screen_test.dart' show FakeFinancialGateway;
import 'daily_ledger_widget_test.dart' show MemoryStore;
import 'daily_notes_widget_test.dart' show pumpApp;
import 'daily_ledger_http_test.dart' show dayId;
import 'meeting_calendar_and_count_test.dart' show calendarBody;

class RolloverGateway extends FakeFinancialGateway {
  var reads = 0;
  @override
  Future<FinancialDayState> dayState({required String callerUserId}) async =>
      const FinancialDayState(
        state: 'open',
        dayId: dayId,
        dayVersion: 1,
        businessDate: '2026-10-19',
      );
  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async {
    reads++;
    final data = calendarBody();
    (data['business_day'] as Map)['business_date'] = '2026-10-19';
    data['journal_context'] = reads == 1
        ? {
            'business_date': '2026-10-19',
            'day_ids': <String>[],
            'server_now': '2026-10-19T20:59:59Z',
            'next_midnight_at': '2026-10-19T21:00:00Z',
            'return_count': 0,
            'note_count': 0,
          }
        : {
            'business_date': '2026-10-20',
            'day_ids': <String>[],
            'server_now': '2026-10-19T21:00:00Z',
            'next_midnight_at': '2026-10-20T21:00:00Z',
            'return_count': 0,
            'note_count': 0,
          };
    return parseDailyLedger(data);
  }
}

void main() {
  testWidgets(
    'server midnight refreshes the calendar journal without financially closing the open day',
    (t) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final gateway = RolloverGateway();
      await pumpApp(
        t,
        DailyLedgerScreen(
          shop: const ShopAccount(
            id: 'shop-1',
            name: 'متجر تجريبي',
            role: 'owner',
            entitlement: ShopEntitlement.active,
          ),
          gateway: gateway,
          store: MemoryStore(),
          userId: 'owner-1',
          onToggleTheme: (_) async {},
        ),
      );
      await t.pumpAndSettle();
      expect(
        t
            .widget<ConfirmedLedgerDashboard>(
              find.byType(ConfirmedLedgerDashboard),
            )
            .ledger!
            .journalContext
            ?.businessDate,
        '2026-10-19',
      );
      await t.pump(const Duration(seconds: 1));
      await t.pumpAndSettle();
      final ledger = t
          .widget<ConfirmedLedgerDashboard>(
            find.byType(ConfirmedLedgerDashboard),
          )
          .ledger!;
      expect(gateway.reads, greaterThanOrEqualTo(2));
      expect(ledger.journalContext?.businessDate, '2026-10-20');
      expect(ledger.feed, isEmpty);
      expect(ledger.cash.first.piastres, '1000000');
      expect(ledger.businessDay?.businessDate, '2026-10-19');
      expect(gateway.closeCounts, isEmpty);
      expect(gateway.keys, isEmpty);
      expect(
        find.textContaining('أغلق يوم العمل السابق صراحةً'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
    },
  );
}
