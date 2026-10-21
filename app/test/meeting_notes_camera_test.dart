import 'package:eldafttar/src/features/daily_notes/application/notes_gateway.dart';
import 'package:eldafttar/src/features/daily_notes/presentation/daily_note_copy.dart';
import 'package:eldafttar/src/features/daily_notes/presentation/daily_notes_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'daily_notes_widget_test.dart'
    show
        NoteScript,
        MemoryDrafts,
        MemoryFiles,
        ScriptImages,
        pumpApp,
        userId,
        shopId,
        dayId,
        pendingKey,
        noteId;

class MeetingCamera extends ScriptImages implements CameraNoteImageSource {
  var captures = 0;
  @override
  bool get canCapture => true;
  @override
  Future<SelectedNoteImage?> captureImage() async {
    captures++;
    return const SelectedNoteImage(name: 'camera.jpg', bytes: [1, 2, 3, 4]);
  }
}

class FailingCamera extends ScriptImages implements CameraNoteImageSource {
  @override
  bool get canCapture => true;
  @override
  Future<SelectedNoteImage?> captureImage() async {
    throw StateError('permission');
  }
}

class MeetingNoteScript extends NoteScript {
  @override
  Future<DailyNoteView> noteDetail({
    required String callerUserId,
    required String shopId,
    required String noteId,
  }) async => notes.singleWhere((note) => note.noteId == noteId);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  testWidgets(
    'camera choice stores a pending attachment without claiming a saved note',
    (t) async {
      final drafts = MemoryDrafts(),
          camera = MeetingCamera(),
          gateway = NoteScript();
      await pumpApp(
        t,
        DailyNotesScreen(
          gateway: gateway,
          userId: userId,
          shopId: shopId,
          businessDayId: dayId,
          drafts: drafts,
          files: MemoryFiles(),
          images: camera,
          newKey: () => pendingKey,
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('daily-note-attach')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('daily-note-camera')), findsOneWidget);
      await t.tap(find.byKey(const Key('daily-note-camera')));
      await t.pumpAndSettle();
      expect(camera.captures, 1);
      expect(drafts.saved?.attachment, isNotNull);
      expect(gateway.posts, 0);
    },
  );
  testWidgets('saved attachment opens a zoomable image and closes explicitly', (
    t,
  ) async {
    final gateway = MeetingNoteScript()
      ..notes.add(
        const DailyNoteView(
          noteId: noteId,
          shopSequence: '8',
          businessDayId: dayId,
          text: 'ملاحظة بصورة تجريبية',
          actorDisplayName: 'مالك تجريبي',
          createdAt: '2026-10-20T10:00:00Z',
          occurredAtShop: '2026-10-20T13:00:00',
          attachment: DailyNoteAttachmentView(
            bucket: 'eldafttar-private-notes',
            objectName: 'synthetic/image.jpg',
            mimeType: 'image/jpeg',
            byteSize: '4',
          ),
        ),
      );
    await pumpApp(
      t,
      DailyNotesScreen(
        gateway: gateway,
        userId: userId,
        shopId: shopId,
        businessDayId: dayId,
        drafts: MemoryDrafts(),
        files: MemoryFiles(),
        images: ScriptImages(),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('daily-note-$noteId')));
    await t.tap(find.byKey(const Key('daily-note-$noteId')));
    await t.pumpAndSettle();
    await t.ensureVisible(find.byKey(const Key('daily-note-open-image')));
    await t.tap(find.byKey(const Key('daily-note-open-image')));
    await t.pumpAndSettle();
    final viewer = t.widget<InteractiveViewer>(
      find.byKey(const Key('daily-note-image-zoom')),
    );
    expect(viewer.maxScale, 5);
    expect(find.text('صورة الملاحظة'), findsOneWidget);
    await t.tap(find.byTooltip('إغلاق الصورة'));
    await t.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(gateway.posts, 0);
  });

  testWidgets(
    'a camera failure keeps the local draft editable and does not freeze it',
    (t) async {
      final drafts = MemoryDrafts();
      final camera = FailingCamera()
        ..queue.add(
          const SelectedNoteImage(name: 'gallery.jpg', bytes: [1, 2, 3, 4]),
        );
      await pumpApp(
        t,
        DailyNotesScreen(
          gateway: NoteScript(),
          userId: userId,
          shopId: shopId,
          businessDayId: dayId,
          drafts: drafts,
          files: MemoryFiles(),
          images: camera,
          newKey: () => pendingKey,
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('daily-note-attach')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('daily-note-gallery')));
      await t.pumpAndSettle();
      expect(
        find.byKey(const Key('daily-note-compose-preview')),
        findsOneWidget,
      );
      expect(
        t.widget<TextField>(find.byKey(const Key('daily-note-text'))).enabled,
        isTrue,
      );
      await t.tap(find.byKey(const Key('daily-note-attach')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('daily-note-camera')));
      await t.pumpAndSettle();
      expect(find.text(DailyNoteCopy.imageSourceFailed), findsOneWidget);
      expect(find.text(DailyNoteCopy.frozen), findsNothing);
      expect(
        t.widget<TextField>(find.byKey(const Key('daily-note-text'))).enabled,
        isTrue,
      );
      expect(
        find.byKey(const Key('daily-note-compose-preview')),
        findsOneWidget,
      );
      expect(find.text(DailyNoteCopy.retrySameRequest), findsNothing);
      expect(drafts.saved?.attachment, isNotNull);
    },
  );
}
