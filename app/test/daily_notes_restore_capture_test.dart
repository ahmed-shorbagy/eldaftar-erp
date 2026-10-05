import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/daily_notes/application/note_draft_store.dart';
import 'package:eldafttar/src/features/daily_notes/application/notes_gateway.dart';
import 'package:eldafttar/src/features/daily_notes/presentation/daily_note_copy.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'daily_notes_restore_test.dart' as restore;
import 'daily_notes_widget_test.dart' as fixtures;

const captureDirectory = 'build/daily-note-restore-review';

Future<void> captureRestore(WidgetTester tester, String name) async {
  // Finish enabled/disabled color transitions without waiting on the
  // deliberately indeterminate restore progress indicator.
  await tester.pump(const Duration(milliseconds: 300));
  expect(tester.takeException(), isNull);
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('restore-capture')),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File('$captureDirectory/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(
      'Cairo',
    )..addFont(rootBundle.load('assets/fonts/Cairo.ttf'))).load();
    final sdkRoot = Platform.resolvedExecutable
        .split(RegExp(r'[/\\]bin[/\\]cache[/\\]'))
        .first;
    final bytes = await File(
      '$sdkRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
  });

  for (final width in [320.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'restore states Arabic RTL ${width.toInt()} ${brightness.name}',
        (tester) async {
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          final label = '${width.toInt()}-${brightness.name}';
          Future<void> pump(
            restore.RestoreDrafts drafts,
            restore.RestoreNotes notes,
          ) async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpWidget(
              MaterialApp(
                locale: const Locale('ar'),
                supportedLocales: const [Locale('ar')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                theme: brightness == Brightness.light
                    ? AppTheme.light()
                    : AppTheme.dark(),
                home: RepaintBoundary(
                  key: const Key('restore-capture'),
                  child: restore.restoreScreen(drafts: drafts, notes: notes),
                ),
              ),
            );
            await tester.pump();
            expect(
              Directionality.of(
                tester.element(find.byKey(const Key('daily-note-text'))),
              ),
              TextDirection.rtl,
            );
          }

          final read = Completer<StoredNoteDraft?>();
          final status = Completer<NoteStatusResult>();
          final drafts = restore.RestoreDrafts()..readGate = read;
          final notes = restore.RestoreNotes()..statusGate = status;
          await pump(drafts, notes);
          restore.expectLocked(tester, saveLocked: true);
          await captureRestore(tester, 'loading-$label');
          read.complete(restore.storedDraft());
          await tester.pump();
          restore.expectLocked(tester, saveLocked: true);
          await captureRestore(tester, 'lookup-$label');
          status.complete(const NoteStatusUnknown());
          await tester.pump();
          restore.expectLocked(tester, saveLocked: false);
          expect(find.text(DailyNoteCopy.frozen), findsOneWidget);
          await captureRestore(tester, 'unknown-$label');
          notes.statusGate = null;
          notes.statusResult = const NoteStatusAbsent();
          await tester.tap(find.byKey(const Key('daily-note-reconcile')));
          await tester.pump();
          expect(restore.noteField(tester).enabled, isTrue);
          await captureRestore(tester, 'absent-$label');

          await pump(
            restore.RestoreDrafts()..saved = restore.storedDraft(),
            restore.RestoreNotes()
              ..statusResult = const NoteStatusCompleted(fixtures.noteId),
          );
          await tester.pump();
          expect(find.text(DailyNoteCopy.confirmed), findsOneWidget);
          await captureRestore(tester, 'confirmed-$label');

          await pump(
            restore.RestoreDrafts()..failRead = true,
            restore.RestoreNotes(),
          );
          restore.expectLocked(tester, saveLocked: true);
          expect(find.text(DailyNoteCopy.restoreFailed), findsOneWidget);
          await captureRestore(tester, 'storage-error-$label');
        },
      );
    }
  }
}
