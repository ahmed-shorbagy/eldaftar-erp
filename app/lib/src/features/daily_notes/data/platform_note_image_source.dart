import 'package:file_selector/file_selector.dart';

import '../application/notes_gateway.dart';
import '../domain/daily_note_draft.dart';

/// Android, iOS, and Windows document picker for a private note image.
final class PlatformNoteImageSource implements NoteImageSource {
  const PlatformNoteImageSource();

  @override
  Future<SelectedNoteImage?> pickImage() async {
    const group = XTypeGroup(
      label: 'صور الملاحظات',
      extensions: ['jpg', 'jpeg', 'png', 'webp'],
      mimeTypes: ['image/jpeg', 'image/png', 'image/webp'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return null;
    final length = await file.length();
    if (length <= 0 || length > noteImageMaxBytes) {
      return SelectedNoteImage(name: file.name, bytes: const []);
    }
    return SelectedNoteImage(
      name: file.name,
      mimeType: mimeFromFileName(file.name),
      bytes: await file.readAsBytes(),
    );
  }
}
