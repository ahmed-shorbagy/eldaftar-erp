import 'dart:async';
import 'dart:convert';

import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/ledger_activity.dart';
import 'package:eldafttar/src/features/daily_ledger/application/opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/application/pending_opening_store.dart';
import 'package:eldafttar/src/features/daily_ledger/data/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/domain/financial_draft.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/daily_ledger_screen.dart';
import 'package:eldafttar/src/features/daily_notes/application/daily_note_submission.dart';
import 'package:eldafttar/src/features/daily_notes/application/note_draft_store.dart';
import 'package:eldafttar/src/features/daily_notes/application/notes_gateway.dart';
import 'package:eldafttar/src/features/daily_notes/domain/daily_note_draft.dart';
import 'package:eldafttar/src/features/daily_notes/presentation/daily_note_copy.dart';
import 'package:eldafttar/src/features/daily_notes/presentation/daily_notes_screen.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const shopId = '22222222-2222-4222-8222-222222222222';
const dayId = '33333333-3333-4333-8333-333333333333';
const userId = 'user-1';
const noteId = '66666666-6666-4666-8666-666666666666';
const pendingKey = '11111111-1111-4111-8111-111111111111';

class MemoryDrafts implements NoteDraftStore {
  StoredNoteDraft? saved;
  bool failClear = false;
  bool failSave = false;

  @override
  Future<void> clear({
    required String userId,
    required String shopId,
    required String idempotencyKey,
  }) async {
    if (failClear) throw StateError('local');
    if (saved?.idempotencyKey == idempotencyKey) saved = null;
  }

  @override
  Future<StoredNoteDraft?> read({
    required String userId,
    required String shopId,
  }) async => saved;

  @override
  Future<void> save({
    required String userId,
    required DailyNoteDraft draft,
  }) async {
    if (failSave) throw StateError('local');
    saved = StoredNoteDraft(
      userId: userId,
      shopId: draft.shopId,
      businessDayId: draft.businessDayId,
      idempotencyKey: draft.idempotencyKey,
      text: draft.text,
      attachment: draft.attachment,
    );
  }
}

class MemoryFiles implements NoteImageFileStore {
  final files = <String, List<int>>{};
  bool failWrite = false;
  bool failDelete = false;

  String _key(String userId, String shopId, String clientObjectId) =>
      '$userId/$shopId/$clientObjectId';

  @override
  Future<void> delete({
    required String userId,
    required String shopId,
    required String clientObjectId,
  }) async {
    if (failDelete) throw StateError('local');
    files.remove(_key(userId, shopId, clientObjectId));
  }

  @override
  Future<List<int>?> read({
    required String userId,
    required String shopId,
    required String clientObjectId,
  }) async => files[_key(userId, shopId, clientObjectId)];

  @override
  Future<void> write({
    required String userId,
    required String shopId,
    required String clientObjectId,
    required List<int> bytes,
  }) async {
    if (failWrite) throw StateError('local');
    files[_key(userId, shopId, clientObjectId)] = bytes;
  }
}

class ScriptImages implements NoteImageSource {
  final queue = <SelectedNoteImage?>[];

  @override
  Future<SelectedNoteImage?> pickImage() async {
    if (queue.isEmpty) return null;
    return queue.removeAt(0);
  }
}

class NoteScript implements NotesGateway {
  NoteScript({this.command});

  final List<DailyNoteView> notes = [];
  int lists = 0;
  int posts = 0;
  Completer<NoteCommandResult>? gate;
  NoteCommandResult? command;
  NoteStatusResult statusResult = const NoteStatusAbsent();
  Map<String, Object?>? postedPayload;
  bool holdLists = false;
  final listGates = <Completer<DailyNotePage>>[];

  @override
  Future<DailyNotePage> listNotes({
    required String callerUserId,
    required String shopId,
    String? dayId,
    String? beforeSequence,
    String? query,
    int limit = 30,
  }) async {
    lists += 1;
    if (holdLists) {
      final gate = Completer<DailyNotePage>();
      listGates.add(gate);
      return gate.future;
    }
    return DailyNotePage(
      shopId: shopId,
      dayId: dayId,
      limit: limit,
      hasMore: false,
      serverSequence: '1',
      snapshotSequence: '1',
      items: notes,
    );
  }

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
  }) async => 'https://example.test/memory';

  @override
  Future<NoteStatusResult> noteStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) async => statusResult;

  @override
  Future<NoteCommandResult> postNote({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) {
    posts += 1;
    postedPayload = payload;
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

class MemoryOpening implements PendingOpeningStore {
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

class LedgerScript
    implements
        OpeningGateway,
        FinancialGateway,
        NotesGateway,
        LedgerFeedGateway {
  LedgerScript(this.notes);

  final NoteScript notes;
  int olderLoads = 0;

  DailyLedgerView view() => DailyLedgerView(
    state: 'confirmed',
    entitlementStatus: 'active',
    canConfirm: false,
    businessDay: const LedgerBusinessDay(
      id: dayId,
      businessDate: '2026-01-02',
      openedAt: '2026-01-01T22:30:00Z',
    ),
    cash: const [
      LedgerCashLine(
        method: 'cash',
        labelAr: 'نقدي',
        piastres: '1000',
        pounds: '10.00',
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
    stock: const [],
    scrap: const [],
    feed: [
      LedgerFeedLine(
        kind: 'sale',
        labelAr: 'بيع',
        operationId: noteId,
        actorDisplayName: 'منى',
        occurredAt: '2026-01-01T22:30:00Z',
        occurredAtCairo: '2026-01-02T00:30:00',
        occurredAtShop: '2026-01-02T00:30:00',
        shopSequence: '2',
      ),
    ],
    feedCursor: const LedgerFeedCursor(
      limit: 100,
      hasMore: true,
      direction: 'desc',
      serverSequence: '2',
      snapshotSequence: '2',
      nextBeforeSequence: '2',
    ),
  );

  @override
  Future<ConfirmResult> confirm({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) async => const ConfirmUnknown();

  @override
  Future<DailyLedgerView> ledger({required String callerUserId}) async =>
      view();

  @override
  Future<StatusResult> status({
    required String callerUserId,
    required String idempotencyKey,
  }) async => const StatusAbsent();

  @override
  Future<FinancialDayState> dayState({required String callerUserId}) async =>
      const FinancialDayState(state: 'open', dayId: dayId, dayVersion: 1);

  @override
  Future<FinancialCommandResult> closeDay({
    required String callerUserId,
    required String idempotencyKey,
    required FinancialDayState expected,
    required Map<String, Object?> counted,
  }) async => const FinancialUnknown();

  @override
  Future<FinancialCommandResult> openDay({
    required String callerUserId,
    required String idempotencyKey,
  }) async => const FinancialUnknown();

  @override
  Future<Map<String, Object?>> operation({
    required String callerUserId,
    required String operationId,
  }) async => {};

  @override
  Future<FinancialCommandResult> postTrade({
    required String callerUserId,
    required String idempotencyKey,
    required FinancialDraft draft,
  }) async => const FinancialUnknown();

  @override
  Future<FinancialCommandResult> retryPending({
    required String callerUserId,
    required PendingFinancialCommand command,
  }) async => const FinancialUnknown();

  @override
  Future<DailyNotePage> listNotes({
    required String callerUserId,
    required String shopId,
    String? dayId,
    String? beforeSequence,
    String? query,
    int limit = 30,
  }) => notes.listNotes(
    callerUserId: callerUserId,
    shopId: shopId,
    dayId: dayId,
    beforeSequence: beforeSequence,
    query: query,
    limit: limit,
  );

  @override
  Future<DailyNoteView> noteDetail({
    required String callerUserId,
    required String shopId,
    required String noteId,
  }) => notes.noteDetail(
    callerUserId: callerUserId,
    shopId: shopId,
    noteId: noteId,
  );

  @override
  Future<String> noteReadUrl({
    required String callerUserId,
    required String objectName,
  }) => notes.noteReadUrl(callerUserId: callerUserId, objectName: objectName);

  @override
  Future<NoteStatusResult> noteStatus({
    required String callerUserId,
    required String idempotencyKey,
  }) => notes.noteStatus(
    callerUserId: callerUserId,
    idempotencyKey: idempotencyKey,
  );

  @override
  Future<NoteCommandResult> postNote({
    required String callerUserId,
    required String idempotencyKey,
    required Map<String, Object?> payload,
  }) => notes.postNote(
    callerUserId: callerUserId,
    idempotencyKey: idempotencyKey,
    payload: payload,
  );

  @override
  Future<NoteUploadResult> uploadNoteImage({
    required String callerUserId,
    required String objectName,
    required String mimeType,
    required List<int> bytes,
  }) => notes.uploadNoteImage(
    callerUserId: callerUserId,
    objectName: objectName,
    mimeType: mimeType,
    bytes: bytes,
  );

  @override
  Future<LedgerOperationPage> operationPage({
    required String callerUserId,
    required String shopId,
    required String? dayId,
    required String? beforeSequence,
    required String? afterSequence,
    required int limit,
  }) async {
    if (beforeSequence != null) {
      olderLoads += 1;
      return LedgerOperationPage(
        shopId: shopId,
        dayId: dayId,
        direction: 'desc',
        limit: limit,
        hasMore: false,
        serverSequence: '2',
        snapshotSequence: '2',
        items: [
          LedgerFeedLine(
            kind: 'opening_balances',
            labelAr: 'رصيد افتتاحي',
            operationId: '77777777-7777-4777-8777-777777777777',
            actorDisplayName: 'منى',
            occurredAt: '2026-01-01T22:00:00Z',
            occurredAtCairo: '2026-01-02T00:00:00',
            occurredAtShop: '2026-01-02T00:00:00',
            shopSequence: '1',
          ),
        ],
      );
    }
    return LedgerOperationPage(
      shopId: shopId,
      dayId: dayId,
      direction: 'asc',
      limit: limit,
      hasMore: false,
      serverSequence: '2',
      snapshotSequence: '2',
      items: const [],
    );
  }
}

Future<void> pumpApp(WidgetTester tester, Widget home) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: home,
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('shows a note as saved only after the RPC confirms', (
    tester,
  ) async {
    final notes = NoteScript()..gate = Completer<NoteCommandResult>();
    final drafts = MemoryDrafts();
    await pumpApp(
      tester,
      DailyNotesScreen(
        gateway: notes,
        userId: userId,
        shopId: shopId,
        businessDayId: dayId,
        drafts: drafts,
        files: MemoryFiles(),
        images: ScriptImages(),
        newKey: () => pendingKey,
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('daily-note-text')), findsOneWidget);
    expect(find.text(DailyNoteCopy.empty), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('daily-note-save')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const Key('daily-note-text')),
      'ملاحظة المحل',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('daily-note-save')));
    await tester.pump();
    expect(find.text(DailyNoteCopy.confirmed), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('daily-note-save')))
          .onPressed,
      isNull,
    );
    expect(drafts.saved?.idempotencyKey, pendingKey);
    notes.gate!.complete(
      const NoteCommitted(noteId: noteId, shopSequence: '8', replayed: false),
    );
    notes.notes.add(
      const DailyNoteView(
        noteId: noteId,
        shopSequence: '8',
        businessDayId: dayId,
        text: 'ملاحظة المحل',
        actorDisplayName: 'منى',
        createdAt: '2026-01-01T22:30:00Z',
        occurredAtShop: '2026-01-02T00:30:00',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text(DailyNoteCopy.confirmed), findsOneWidget);
    expect(find.text('ملاحظة المحل'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('daily-note-text')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('a stale day keeps the draft and explains the conflict', (
    tester,
  ) async {
    final notes = NoteScript()..command = const NoteRejected('stale_day');
    await pumpApp(
      tester,
      DailyNotesScreen(
        gateway: notes,
        userId: userId,
        shopId: shopId,
        businessDayId: dayId,
        drafts: MemoryDrafts(),
        files: MemoryFiles(),
        images: ScriptImages(),
        newKey: () => pendingKey,
      ),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('daily-note-text')),
      'ما زالت هنا',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('daily-note-save')));
    await tester.pump();
    await tester.pump();
    expect(find.text(noteFailureCopy('stale_day')), findsWidgets);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('daily-note-text')))
          .controller!
          .text,
      'ما زالت هنا',
    );
    expect(find.text(DailyNoteCopy.confirmed), findsNothing);
  });

  testWidgets(
    'an uncertain note keeps the stored payload when the day and text change',
    (tester) async {
      final drafts = MemoryDrafts();
      await drafts.save(
        userId: userId,
        draft: composeDailyNote(
          idempotencyKey: pendingKey,
          shopId: shopId,
          businessDayId: dayId,
          text: 'النص الأصلي',
        ).draft!,
      );
      final notes = NoteScript()..statusResult = const NoteStatusUnknown();
      final screenKey = GlobalKey();
      await pumpApp(
        tester,
        DailyNotesScreen(
          key: screenKey,
          gateway: notes,
          userId: userId,
          shopId: shopId,
          businessDayId: dayId,
          drafts: drafts,
          files: MemoryFiles(),
          images: ScriptImages(),
          newKey: () => pendingKey,
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('daily-note-text')))
            .enabled,
        isFalse,
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('daily-note-save')));
      await tester.pump();
      expect(notes.posts, 0);
      expect(drafts.saved?.text, 'النص الأصلي');
      expect(drafts.saved?.businessDayId, dayId);
      await pumpApp(
        tester,
        DailyNotesScreen(
          key: screenKey,
          gateway: notes,
          userId: userId,
          shopId: shopId,
          businessDayId: '77777777-7777-4777-8777-777777777777',
          drafts: drafts,
          files: MemoryFiles(),
          images: ScriptImages(),
          newKey: () => pendingKey,
        ),
      );
      await tester.pump();
      notes.statusResult = const NoteStatusAbsent();
      tester
              .widget<TextField>(find.byKey(const Key('daily-note-text')))
              .controller!
              .text =
          'يوم آخر';
      await tester.pump();
      await tester.tap(find.byKey(const Key('daily-note-save')));
      await tester.pump();
      await tester.pump();
      expect(notes.posts, 1);
      expect(notes.postedPayload?['text'], 'النص الأصلي');
      expect(notes.postedPayload?['business_day_id'], dayId);
      expect(notes.postedPayload?['idempotency_key'], isNull);
    },
  );

  testWidgets('a delayed search is dropped when the owner changes', (
    tester,
  ) async {
    final notes = NoteScript();
    final screenKey = GlobalKey();
    await pumpApp(
      tester,
      DailyNotesScreen(
        key: screenKey,
        gateway: notes,
        userId: userId,
        shopId: shopId,
        businessDayId: dayId,
        drafts: MemoryDrafts(),
        files: MemoryFiles(),
        images: ScriptImages(),
      ),
    );
    await tester.pump();
    notes.holdLists = true;
    await tester.enterText(find.byKey(const Key('daily-note-search')), 'ذهب');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(notes.listGates, hasLength(1));
    await pumpApp(
      tester,
      DailyNotesScreen(
        key: screenKey,
        gateway: notes,
        userId: 'user-2',
        shopId: shopId,
        businessDayId: dayId,
        drafts: MemoryDrafts(),
        files: MemoryFiles(),
        images: ScriptImages(),
      ),
    );
    await tester.pump();
    expect(notes.listGates.length, greaterThanOrEqualTo(2));
    notes.listGates[0].complete(
      DailyNotePage(
        shopId: shopId,
        dayId: dayId,
        limit: 30,
        hasMore: false,
        serverSequence: '1',
        snapshotSequence: '1',
        items: const [
          DailyNoteView(
            noteId: noteId,
            shopSequence: '8',
            businessDayId: dayId,
            text: 'نتيجة بحث قديمة',
            actorDisplayName: 'منى',
            createdAt: '2026-01-01T22:30:00Z',
            occurredAtShop: '2026-01-02T00:30:00',
          ),
        ],
      ),
    );
    notes.listGates[1].complete(
      DailyNotePage(
        shopId: shopId,
        dayId: dayId,
        limit: 30,
        hasMore: false,
        serverSequence: '1',
        snapshotSequence: '1',
        items: const [],
      ),
    );
    await tester.pump();
    expect(find.text('نتيجة بحث قديمة'), findsNothing);
  });

  testWidgets('changed image bytes receive a new object id', (tester) async {
    final drafts = MemoryDrafts();
    final images = ScriptImages()
      ..queue.add(
        const SelectedNoteImage(name: 'note.jpg', bytes: [1, 2, 3, 4]),
      );
    await pumpApp(
      tester,
      DailyNotesScreen(
        gateway: NoteScript(),
        userId: userId,
        shopId: shopId,
        businessDayId: dayId,
        drafts: drafts,
        files: MemoryFiles(),
        images: images,
        newKey: () => pendingKey,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('daily-note-attach')));
    await tester.pump();
    expect(drafts.saved?.attachment?.clientObjectId, pendingKey);
    images.queue.add(
      const SelectedNoteImage(name: 'note.jpg', bytes: [9, 9, 9, 9]),
    );
    await tester.tap(find.byKey(const Key('daily-note-attach')));
    await tester.pump();
    final second = drafts.saved?.attachment?.clientObjectId;
    expect(second, isNot(pendingKey));
    expect(second, isNotNull);
    expect(isCanonicalNoteId(second!), isTrue);
  });

  testWidgets('a local file failure stays visible and keeps the image', (
    tester,
  ) async {
    final files = MemoryFiles()..failWrite = true;
    final images = ScriptImages()
      ..queue.add(
        const SelectedNoteImage(name: 'note.jpg', bytes: [1, 2, 3, 4]),
      );
    await pumpApp(
      tester,
      DailyNotesScreen(
        gateway: NoteScript(),
        userId: userId,
        shopId: shopId,
        businessDayId: dayId,
        drafts: MemoryDrafts(),
        files: files,
        images: images,
        newKey: () => pendingKey,
      ),
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('daily-note-attach')));
    await tester.pump();
    expect(find.text(noteFailureCopy('local_persistence')), findsOneWidget);
    expect(find.text('تم اختيار صورة'), findsOneWidget);
    expect(files.files, isEmpty);
  });

  testWidgets('server confirmation stays success when local cleanup fails', (
    tester,
  ) async {
    final notes = NoteScript()..gate = Completer<NoteCommandResult>();
    final drafts = MemoryDrafts()..failClear = true;
    await pumpApp(
      tester,
      DailyNotesScreen(
        gateway: notes,
        userId: userId,
        shopId: shopId,
        businessDayId: dayId,
        drafts: drafts,
        files: MemoryFiles(),
        images: ScriptImages(),
        newKey: () => pendingKey,
      ),
    );
    await tester.pump();
    await tester.enterText(find.byKey(const Key('daily-note-text')), 'ملاحظة');
    await tester.pump();
    await tester.tap(find.byKey(const Key('daily-note-save')));
    await tester.pump();
    expect(notes.posts, 1);
    notes.gate!.complete(
      const NoteCommitted(noteId: noteId, shopSequence: '8', replayed: false),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text(DailyNoteCopy.confirmed), findsOneWidget);
    expect(notes.posts, 1);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('daily-note-text')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('notes stay available while a financial request is pending', (
    tester,
  ) async {
    await const PendingFinancialCommands().save(
      userId,
      shopId,
      PendingFinancialCommand(
        key: pendingKey,
        kind: 'sale',
        body: {
          'p_idempotency_key': pendingKey,
          'p_payload': {'kind': 'sale'},
        },
      ),
    );
    final ledger = LedgerScript(NoteScript());
    await pumpApp(
      tester,
      DailyLedgerScreen(
        shop: ShopAccount(
          id: shopId,
          name: 'ذهب الجيزة',
          role: 'owner',
          entitlement: ShopEntitlement.active,
        ),
        gateway: ledger,
        store: MemoryOpening(),
        userId: userId,
        onSignOut: () async {},
        onToggleTheme: (_) async {},
        onChangeShop: () {},
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('عملية مالية بانتظار تأكيد الحفظ'), findsOneWidget);
    expect(find.byKey(const Key('ledger-new-sale')), findsNothing);
    await tester.tap(find.byKey(const Key('ledger-quick-actions')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('المزيد من الإجراءات'));
    await tester.tap(find.text('المزيد من الإجراءات'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ledger-daily-notes')), findsOneWidget);
    expect(find.byKey(const Key('ledger-load-older')), findsNothing);
    final notesButton = find.byKey(const Key('ledger-daily-notes'));
    await revealInLedger(tester, notesButton);
    await tester.tap(notesButton);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const Key('daily-note-text')), findsOneWidget);
    navigatorPop(tester);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final raw = await const FlutterSecureStorage().read(
      key: 'pending_financial_${userId}_$shopId',
    );
    expect(jsonDecode(raw!)['key'], pendingKey);
    await revealInLedger(
      tester,
      find.byKey(const Key('ledger-other-movements')),
    );
    await tester.tap(find.byKey(const Key('ledger-other-movements')));
    await tester.pumpAndSettle();
    final older = find.byKey(const Key('ledger-load-older'));
    await tester.ensureVisible(older);
    await tester.tap(older);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(ledger.olderLoads, 1);
    await tester.tap(find.byKey(const Key('ledger-filter-all')));
    await tester.pumpAndSettle();
    expect(find.text('رصيد افتتاحي'), findsWidgets);
    expect(
      find.descendant(of: find.byType(BottomSheet), matching: find.text('بيع')),
      findsOneWidget,
    );
  });
}

void navigatorPop(WidgetTester tester) {
  Navigator.of(tester.element(find.byKey(const Key('daily-note-text')))).pop();
}

/// The ledger list builds its dashboard as one tall child, so a finder can
/// see a control that is still below the viewport. Move that control fully
/// into the window before tapping it.
Future<void> revealInLedger(WidgetTester tester, Finder target) async {
  final scrollable = find.descendant(
    of: find.byKey(const Key('ledger-scroll')),
    matching: find.byType(Scrollable),
  );
  final position = tester.state<ScrollableState>(scrollable).position;
  final height = tester.view.physicalSize.height / tester.view.devicePixelRatio;
  for (var attempt = 0; attempt < 20; attempt++) {
    final box = tester.renderObject<RenderBox>(target);
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = top + box.size.height;
    if (top >= 0 && bottom <= height) return;
    final delta = bottom > height ? bottom - height + 8 : top;
    final next = (position.pixels + delta).clamp(0.0, position.maxScrollExtent);
    if (next == position.pixels) break;
    position.jumpTo(next);
    await tester.pump();
  }
  throw TestFailure('ledger control stayed outside the viewport');
}
