import 'package:eldafttar/src/features/daily_ledger/presentation/financial_trade_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_balance_sections.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'owner_feedback_completion_test.dart' show host, tapVisible;
import 'ledger_trade_change_test.dart' show revisionHost;
import 'ledger_revision_test_support.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  testWidgets(
    'normalization selector persists default21 and switches all equivalent figures',
    (t) async {
      await host(t);
      await tapVisible(t, find.byKey(const Key('ledger-customize')));
      await tapVisible(t, find.byKey(const ValueKey('ledger-normalize-21')));
      await t.tap(find.text('عيار 24').last);
      await t.pumpAndSettle();
      final tile = t.widget<LedgerMetricTile>(
        find.byKey(const Key('ledger-metric-sale_gold')),
      );
      expect(tile.unit, 'جرام محيف عيار 24');
      expect(
        (await SharedPreferences.getInstance()).getStringList(
          'ledger_layout_feedback-shop',
        ),
        contains('normalize:24'),
      );
      await tapVisible(t, find.byKey(const Key('ledger-scrap-karat-14')));
      await tapVisible(t, find.byKey(const Key('ledger-scrap-karat-22')));
      final saved = (await SharedPreferences.getInstance()).getStringList(
        'ledger_layout_feedback-shop',
      )!;
      expect(
        saved,
        containsAll(['normalize:24', 'hide-scrap:14', 'hide-scrap:22']),
      );
      expect(saved.where((v) => v.startsWith('metric:')), hasLength(6));
    },
  );
  testWidgets(
    'hidden scrap karats do not appear in new purchase entry but a saved karat survives editing',
    (t) async {
      SharedPreferences.setMockInitialValues({
        'ledger_layout_$revisionShop': ['hide-scrap:14', 'hide-scrap:22'],
      });
      final g = RevisionGateway();
      Widget form({Map<String, Object?>? initial}) => revisionHost(
        FinancialTradeScreen(
          kind: FinancialKind.purchase,
          gateway: g,
          statusGateway: g,
          userId: revisionUser,
          shopId: revisionShop,
          initialPayload: initial,
        ),
      );
      await t.pumpWidget(form());
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('trade-select-كسر')));
      await t.pumpAndSettle();
      final field = find.byKey(const Key('trade-karat-0-scrap-18'));
      await t.ensureVisible(field);
      await t.pumpAndSettle();
      await t.tap(field);
      await t.pumpAndSettle();
      expect(find.text('14'), findsNothing);
      expect(find.text('22'), findsNothing);
      expect(find.text('21'), findsOneWidget);
      expect(find.text('24'), findsOneWidget);
      await t.tap(find.text('21'));
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox.shrink());
      final initial = sourceTrade(kind: 'purchase');
      (initial['items'] as List)[0] = {
        'category': 'scrap',
        'karat': 14,
        'milligrams': '1255',
        'count': null,
        'item_name': 'كسر',
        'line_price_piastres': null,
      };
      await t.pumpWidget(form(initial: initial));
      await t.pumpAndSettle();
      final inherited = find.byKey(const Key('trade-karat-0-scrap-14'));
      await t.scrollUntilVisible(
        inherited,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(inherited, findsOneWidget);
      expect(
        t.widget<DropdownButtonFormField<int>>(inherited).initialValue,
        14,
      );
    },
  );
}
