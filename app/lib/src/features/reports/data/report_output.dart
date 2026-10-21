import 'dart:ui' show Rect;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

Future<String> outputReportPdf(
  Uint8List bytes,
  String filename,
  bool Function() allowed,
) async {
  if (!allowed()) return 'denied';
  if (!kIsWeb &&
      {
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }.contains(defaultTargetPlatform)) {
    final target = await getSaveLocation(
      suggestedName: filename,
      acceptedTypeGroups: const [
        XTypeGroup(label: 'ملف PDF', extensions: ['pdf']),
      ],
    );
    if (!allowed()) return 'denied';
    if (target == null) return 'cancelled';
    await XFile.fromData(
      bytes,
      mimeType: 'application/pdf',
      name: filename,
    ).saveTo(target.path);
    return allowed() ? 'saved' : 'denied';
  }
  final result = await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'application/pdf')],
      fileNameOverrides: [filename],
      title: 'تقرير اليوم المالي',
      sharePositionOrigin: const Rect.fromLTWH(0, 0, 1, 1),
    ),
  );
  if (!allowed()) return 'denied';
  return switch (result.status) {
    ShareResultStatus.success => 'opened',
    ShareResultStatus.dismissed => 'cancelled',
    ShareResultStatus.unavailable => 'unavailable',
  };
}
