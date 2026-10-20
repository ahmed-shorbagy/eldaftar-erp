import 'dart:io';
import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_journal_table.dart';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_notes/application/notes_gateway.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:eldafttar/src/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'daily_ledger_widget_test.dart' show MemoryStore;

import 'batch2_ledger_capture_test.dart' show ItemReviewGateway;

class FullActionReviewGateway extends ItemReviewGateway
    implements CashTransferGateway, ScrapToStockGateway, NotesGateway {
  @override
  Future<FinancialCommandResult> transferCash({
    required String callerUserId,
    required String idempotencyKey,
    required String fromMethod,
    required String toMethod,
    required String amountPiastres,
    required String note,
  }) async => throw StateError('Visual fixtures cannot post cash transfers');

  @override
  Future<FinancialCommandResult> convertScrapToStock({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) async => throw StateError('Visual fixtures cannot post inventory changes');

  @override
  Future<NoteCommandResult> postNote({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) async => throw StateError('Visual fixtures cannot post notes');
  @override
  Future<NoteStatusResult> noteStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async => throw StateError('No pending visual note');
  @override
  Future<DailyNotePage> listNotes({
    required String callerUserId,
    required String shopId,
    String? dayId,
    String? beforeSequence,
    String? query,
    int limit = 30,
  }) async => DailyNotePage(
    shopId: shopId,
    dayId: dayId,
    limit: limit,
    hasMore: false,
    serverSequence: '0',
    snapshotSequence: '0',
    items: const [],
  );
  @override
  Future<DailyNoteView> noteDetail({
    required String callerUserId,
    required String shopId,
    required String noteId,
  }) async => throw StateError('No visual note');
  @override
  Future<NoteUploadResult> uploadNoteImage({
    required String callerUserId,
    required String objectName,
    required String mimeType,
    required List<int> bytes,
  }) async => throw StateError('Visual fixtures cannot upload images');
  @override
  Future<String> noteReadUrl({
    required String callerUserId,
    required String objectName,
    required String bucket,
  }) async => throw StateError('No visual note image');
}

Future<void> capture(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: name);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('batch2-ledger-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/borderless-ledger/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'Cairo',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  for (final viewport in [
    (320.0, 1.0),
    (390.0, 1.0),
    (430.0, 1.0),
    (1440.0, 1.0),
    (320.0, 1.6),
  ]) {
    final (width, scale) = viewport;
    for (final dark in [false, true]) {
      testWidgets(
        'Ledger UI refinement RTL ${dark ? 'dark' : 'light'} $width scale $scale',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          FlutterSecureStorage.setMockInitialValues({});
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            RepaintBoundary(
              key: const Key('batch2-ledger-capture'),
              child: MaterialApp(
                locale: const Locale('ar'),
                supportedLocales: const [Locale('ar')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: dark ? AppTheme.dark() : AppTheme.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: ShopWorkspace(
                  shop: const ShopAccount(
                    id: 'shop-1',
                    name: 'متجر تجريبي',
                    role: 'owner',
                    entitlement: ShopEntitlement.active,
                  ),
                  gateway: FullActionReviewGateway(),
                  store: MemoryStore(),
                  userId: 'owner-1',
                  onSignOut: () async {},
                  onToggleTheme: (_) async {},
                ),
              ),
            ),
          );
          final label = '${dark ? 'dark' : 'light'}-${width.toInt()}-$scale';
          await capture(tester, 'ledger-top-$label');
          expect(find.text('الرئيسية'), findsNothing);
          expect(find.byTooltip('تسجيل الخروج'), findsNothing);
          await tester.ensureVisible(find.byKey(const Key('ledger-new-sale')));
          await capture(tester, 'ledger-sale-$label');
          final journal = find.byKey(const Key('ledger-journal-sale'));
          if (width < AppTokens.wideBreakpoint) {
            expect(
              tester.getSize(journal).width,
              closeTo(width - 2 * AppTokens.ledgerPhoneGutter, 0.1),
            );
          }
          if (scale == 1) {
            final table = find.descendant(
              of: journal,
              matching: find.byType(LedgerOperationTable),
            );
            expect(
              tester.getSize(table).width,
              closeTo(tester.getSize(journal).width, 0.1),
            );
          }
          await tester.ensureVisible(
            find.byKey(const Key('ledger-new-purchase')),
          );
          await capture(tester, 'ledger-purchase-$label');
          await tester.ensureVisible(
            find.byKey(const Key('ledger-journal-details-purchase')),
          );
          await tester.tap(
            find.byKey(const Key('ledger-journal-details-purchase')),
          );
          await capture(tester, 'ledger-details-$label');
          await tester.tap(find.byKey(const Key('ledger-quick-actions')));
          await tester.pumpAndSettle();
          expect(find.text('المزيد من الإجراءات'), findsNothing);
          for (final id in [
            'ledger-new-expense',
            'ledger-new-scrap-sale',
            'ledger-new-cash-transfer',
            'ledger-new-scrap-to-stock',
            'ledger-daily-notes',
          ]) {
            expect(find.byKey(Key(id)), findsOneWidget);
          }
          await capture(tester, 'quick-actions-$label');
          final sheet = find.byType(BottomSheet);
          expect(
            find.descendant(
              of: sheet,
              matching: find.byKey(const Key('ledger-new-sale')),
            ),
            findsNothing,
          );
          expect(
            find.descendant(
              of: sheet,
              matching: find.byKey(const Key('ledger-new-purchase')),
            ),
            findsNothing,
          );
          await tester.tap(find.byKey(const Key('ledger-close-quick-actions')));
          await tester.pumpAndSettle();
          expect(find.byType(BottomSheet), findsNothing);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}
