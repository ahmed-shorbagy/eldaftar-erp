import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/ledger_activity.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_opening_store.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/daily_ledger_screen.dart';
import 'package:eldafttar/src/features/daily_notes/application/note_draft_store.dart';
import 'package:eldafttar/src/features/daily_notes/application/notes_gateway.dart';
import 'package:eldafttar/src/features/daily_notes/domain/daily_note_draft.dart';
import 'package:eldafttar/src/features/daily_notes/presentation/daily_note_copy.dart';
import 'package:eldafttar/src/features/daily_notes/presentation/daily_notes_screen.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

const shopId = '22222222-2222-4222-8222-222222222222';
const dayId = '33333333-3333-4333-8333-333333333333';
const captureDir = 'build/m03-notes-review';

class CaptureStore implements PendingOpeningStore {
  @override
  Future<PendingOpening?> read({
    required String userId,
    required String shopId,
  }) async => null;

  @override
  Future<void> retire({required String userId, required String shopId}) async {}

  @override
  Future<void> save({
    required String userId,
    required String shopId,
    required PendingOpening pending,
  }) async {}
}

class CaptureNotes implements OpeningGateway, NotesGateway, LedgerFeedGateway {
  DailyLedgerView get view => const DailyLedgerView(
    state: 'confirmed',
    entitlementStatus: 'active',
    canConfirm: false,
    businessDay: LedgerBusinessDay(
      id: dayId,
      businessDate: '2026-01-02',
      openedAt: '2026-01-01T22:30:00Z',
    ),
    cash: [
      LedgerCashLine(
        method: 'cash',
        labelAr: 'نقدي',
        piastres: '1000000',
        pounds: '10000.00',
      ),
      LedgerCashLine(
        method: 'instant_transfer',
        labelAr: 'انستا',
        piastres: '0',
        pounds: '0.00',
      ),
      LedgerCashLine(
        method: 'wallet',
        labelAr: 'محفظة',
        piastres: '0',
        pounds: '0.00',
      ),
      LedgerCashLine(
        method: 'card',
        labelAr: 'فيزا',
        piastres: '0',
        pounds: '0.00',
      ),
    ],
    stock: [],
    scrap: [],
    feed: [
      LedgerFeedLine(
        kind: 'daily_note',
        labelAr: 'ملاحظة يومية',
        operationId: '66666666-6666-4666-8666-666666666666',
        actorDisplayName: 'منى حسن',
        occurredAt: '2026-01-01T22:30:00Z',
        occurredAtCairo: '2026-01-02T00:30:00',
        occurredAtShop: '2026-01-02T00:30:00',
        shopSequence: '4',
        isDailyNote: true,
        hasNote: true,
      ),
    ],
    feedCursor: LedgerFeedCursor(
      limit: 100,
      hasMore: true,
      direction: 'desc',
      serverSequence: '4',
      snapshotSequence: '4',
      nextBeforeSequence: '4',
    ),
  );

  @override
  Future<ConfirmResult> confirm({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) async => const ConfirmUnknown();

  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async => view;

  @override
  Future<StatusResult> status({
    required String callerUserId,
    required String idempotencyKey,
  }) async => const StatusUnknown();

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
    serverSequence: '4',
    snapshotSequence: '4',
    items: const [],
  );

  @override
  Future<DailyNoteView> noteDetail({
    required String callerUserId,
    required String shopId,
    required String noteId,
  }) => throw UnimplementedError();

  @override
  Future<String> noteReadUrl({
    required String callerUserId,
    required String objectName,
  }) async => 'https://example.test/not-stored';

  @override
  Future<NoteStatusResult> noteStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async => const NoteStatusAbsent();

  @override
  Future<NoteCommandResult> postNote({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) async => const NoteUnknown();

  @override
  Future<NoteUploadResult> uploadNoteImage({
    required String callerUserId,
    required String objectName,
    required String mimeType,
    required List<int> bytes,
  }) async => const NoteUploadResult(NoteUploadDisposition.unknown);

  @override
  Future<LedgerOperationPage> operationPage({
    required String callerUserId,
    required String shopId,
    required String? dayId,
    required String? beforeSequence,
    required String? afterSequence,
    required int limit,
  }) async => LedgerOperationPage(
    shopId: shopId,
    dayId: dayId,
    direction: beforeSequence == null ? 'asc' : 'desc',
    limit: limit,
    hasMore: false,
    serverSequence: '4',
    snapshotSequence: '4',
    items: const [],
  );
}

Future<void> capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('notes-capture-boundary')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final bytes = data!.buffer.asUint8List();
    expect(bytes.length, greaterThan(8));
    final file = File('$captureDir/$name');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  });
}

void main() {
  testWidgets(
    'captures notes and older-page controls at phone and desktop sizes',
    (tester) async {
      for (final brightness in Brightness.values) {
        for (final width in const [320.0, 1440.0]) {
          await tester.pumpWidget(const SizedBox.shrink());
          tester.view.physicalSize = Size(width, 800);
          tester.view.devicePixelRatio = 1;
          final theme = brightness == Brightness.light
              ? AppTheme.light()
              : AppTheme.dark();
          await tester.pumpWidget(
            MaterialApp(
              locale: const Locale('ar'),
              supportedLocales: const [Locale('ar')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: theme,
              builder: (context, child) => Directionality(
                textDirection: TextDirection.rtl,
                child: child ?? const SizedBox.shrink(),
              ),
              home: RepaintBoundary(
                key: const Key('notes-capture-boundary'),
                child: DailyLedgerScreen(
                  shop: ShopAccount(
                    id: shopId,
                    name: 'ذهب الجيزة',
                    role: 'owner',
                    entitlement: ShopEntitlement.active,
                  ),
                  gateway: CaptureNotes(),
                  store: CaptureStore(),
                  userId: 'user-1',
                  onSignOut: () async {},
                  onToggleTheme: (_) async {},
                  onChangeShop: () {},
                ),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(tester.takeException(), isNull);
          final label = '${brightness.name}-${width.toInt()}';
          await capture(tester, 'ledger-notes-top-$label.png');
          await tester.ensureVisible(find.text('المزيد من الإجراءات'));
          await tester.tap(find.text('المزيد من الإجراءات'));
          await tester.pumpAndSettle();
          final notes = find.byKey(const Key('ledger-daily-notes'));
          expect(notes, findsOneWidget);
          await tester.ensureVisible(notes);
          await tester.pump();
          await capture(tester, 'ledger-notes-actions-$label.png');
          final older = find.byKey(const Key('ledger-load-older'));
          expect(older, findsOneWidget);
          await tester.ensureVisible(older);
          await tester.pump();
          await capture(tester, 'ledger-notes-older-$label.png');
          expect(
            Directionality.of(
              tester.element(find.byKey(const Key('ledger-title'))),
            ),
            TextDirection.rtl,
          );
        }
      }
      tester.view.resetPhysicalSize();
    },
  );

  testWidgets(
    'captures the note form, image, retry, and error in both themes',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final brightness in Brightness.values) {
        for (final width in const [320.0, 1440.0]) {
          final label = '${brightness.name}-${width.toInt()}';
          await _pumpNote(
            tester,
            brightness: brightness,
            width: width,
            images: CaptureImages(),
            notes: _FormNotes(),
          );
          await tester.enterText(
            find.byKey(const Key('daily-note-text')),
            'ملاحظة المحل',
          );
          await tester.pump();
          expect(find.byKey(const Key('daily-note-text')), findsOneWidget);
          expect(find.byKey(const Key('daily-note-save')), findsOneWidget);
          expect(
            Directionality.of(
              tester.element(find.byKey(const Key('daily-note-text'))),
            ),
            TextDirection.rtl,
          );
          await capture(tester, 'note-form-$label.png');

          final images = CaptureImages()
            ..next = const SelectedNoteImage(
              name: 'note.jpg',
              bytes: [1, 2, 3, 4],
            );
          await _pumpNote(
            tester,
            brightness: brightness,
            width: width,
            images: images,
            notes: _FormNotes(),
          );
          await tester.tap(find.byKey(const Key('daily-note-attach')));
          await tester.pump();
          expect(find.text('تم اختيار صورة'), findsOneWidget);
          await capture(tester, 'note-image-$label.png');

          final gate = Completer<NoteCommandResult>();
          await _pumpNote(
            tester,
            brightness: brightness,
            width: width,
            images: CaptureImages(),
            notes: _FormNotes(gate: gate),
          );
          await tester.enterText(
            find.byKey(const Key('daily-note-text')),
            'بانتظار التأكيد',
          );
          await tester.pump();
          await tester.tap(find.byKey(const Key('daily-note-save')));
          await tester.pump();
          expect(find.text(DailyNoteCopy.confirming), findsOneWidget);
          await tester.ensureVisible(
            find.byKey(const Key('daily-note-status')),
          );
          await tester.pump();
          await capture(tester, 'note-retry-$label.png');
          gate.complete(
            const NoteCommitted(
              noteId: '66666666-6666-4666-8666-666666666666',
              shopSequence: '8',
              replayed: false,
            ),
          );
          await tester.pump();

          await _pumpNote(
            tester,
            brightness: brightness,
            width: width,
            images: CaptureImages(),
            notes: _FormNotes(command: const NoteRejected('stale_day')),
          );
          await tester.enterText(
            find.byKey(const Key('daily-note-text')),
            'اليوم تغيّر',
          );
          await tester.pump();
          await tester.tap(find.byKey(const Key('daily-note-save')));
          await tester.pump();
          await tester.pump();
          expect(find.byKey(const Key('daily-note-error')), findsOneWidget);
          await tester.ensureVisible(find.byKey(const Key('daily-note-error')));
          await tester.pump();
          await capture(tester, 'note-error-$label.png');
        }
      }
    },
  );
}

Future<void> _pumpNote(
  WidgetTester tester, {
  required Brightness brightness,
  required double width,
  required NotesGateway notes,
  required NoteImageSource images,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  tester.view.physicalSize = Size(width, 1200);
  tester.view.devicePixelRatio = 1;
  final theme = brightness == Brightness.light
      ? AppTheme.light()
      : AppTheme.dark();
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: theme,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: RepaintBoundary(
        key: const Key('notes-capture-boundary'),
        child: DailyNotesScreen(
          gateway: notes,
          userId: 'user-1',
          shopId: shopId,
          businessDayId: dayId,
          drafts: _CaptureDrafts(),
          files: _CaptureFiles(),
          images: images,
        ),
      ),
    ),
  );
  await tester.pump();
  expect(tester.takeException(), isNull);
}

class _CaptureDrafts implements NoteDraftStore {
  @override
  Future<void> clear({
    required String userId,
    required String shopId,
    required String idempotencyKey,
  }) async {}

  @override
  Future<StoredNoteDraft?> read({
    required String userId,
    required String shopId,
  }) async => null;

  @override
  Future<void> save({
    required String userId,
    required DailyNoteDraft draft,
  }) async {}
}

class _CaptureFiles implements NoteImageFileStore {
  @override
  Future<void> delete({
    required String userId,
    required String shopId,
    required String clientObjectId,
  }) async {}

  @override
  Future<List<int>?> read({
    required String userId,
    required String shopId,
    required String clientObjectId,
  }) async => null;

  @override
  Future<void> write({
    required String userId,
    required String shopId,
    required String clientObjectId,
    required List<int> bytes,
  }) async {}
}

class CaptureImages implements NoteImageSource {
  SelectedNoteImage? next;

  @override
  Future<SelectedNoteImage?> pickImage() async => next;
}

class _FormNotes implements NotesGateway {
  _FormNotes({this.gate, this.command});

  final Completer<NoteCommandResult>? gate;
  final NoteCommandResult? command;

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
  }) => throw UnimplementedError();

  @override
  Future<String> noteReadUrl({
    required String callerUserId,
    required String objectName,
  }) async => 'https://example.test/not-stored';

  @override
  Future<NoteStatusResult> noteStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async => const NoteStatusAbsent();

  @override
  Future<NoteCommandResult> postNote({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) {
    final pending = gate;
    if (pending != null) return pending.future;
    return Future.value(command ?? const NoteUnknown());
  }

  @override
  Future<NoteUploadResult> uploadNoteImage({
    required String callerUserId,
    required String objectName,
    required String mimeType,
    required List<int> bytes,
  }) async => const NoteUploadResult(NoteUploadDisposition.stored);
}
