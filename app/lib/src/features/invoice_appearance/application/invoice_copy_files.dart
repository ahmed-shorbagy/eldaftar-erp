import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Temporary branded and legacy copies. Cleared on logout and access loss.
final class InvoiceCopyFiles {
  const InvoiceCopyFiles();

  static const folderName = 'eldaftar-invoice-copies';

  Future<Directory> _directory() async {
    final root = await getTemporaryDirectory();
    final folder = Directory('${root.path}/$folderName');
    if (!folder.existsSync()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  Future<File> write(String name, List<int> bytes) async {
    final folder = await _directory();
    final file = File('${folder.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> clear() async {
    try {
      final root = await getTemporaryDirectory();
      final folder = Directory('${root.path}/$folderName');
      if (folder.existsSync()) {
        await folder.delete(recursive: true);
      }
    } catch (_) {
      // Logout and access loss still proceed when the temporary folder
      // cannot be reached. The next successful clear removes any remainder.
    }
  }
}
