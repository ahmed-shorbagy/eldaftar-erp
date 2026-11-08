import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../application/invoice_whatsapp_share.dart';

final class PlatformInvoiceWhatsappShare implements InvoiceWhatsappShare {
  const PlatformInvoiceWhatsappShare();

  static const _channel = MethodChannel('eldafttar/whatsapp_share');

  @override
  Future<WhatsappShareResult> sharePdf({
    required Uint8List pdf,
    required String filename,
    required String? phoneDigits,
    required String text,
    Rect? origin,
  }) async {
    if (Platform.isAndroid) {
      return _android(pdf, filename, phoneDigits, text);
    }
    if (Platform.isIOS) return _ios(pdf, filename, text, origin);
    if (Platform.isWindows) return _windows(pdf, filename, phoneDigits, text);
    return WhatsappShareResult.failed;
  }

  Future<WhatsappShareResult> _android(
    Uint8List pdf,
    String filename,
    String? phoneDigits,
    String text,
  ) async {
    final directory = Directory(
      _join((await getTemporaryDirectory()).path, 'invoices'),
    );
    await directory.create(recursive: true);
    final file = File(_join(directory.path, filename));
    await file.writeAsBytes(pdf, flush: true);
    try {
      final result = await _channel.invokeMethod<String>('sharePdf', {
        'path': file.path,
        'phone': phoneDigits,
        'text': text,
      });
      return switch (result) {
        'opened' => WhatsappShareResult.opened,
        'not_installed' => WhatsappShareResult.notInstalled,
        _ => WhatsappShareResult.failed,
      };
    } catch (_) {
      return WhatsappShareResult.failed;
    }
  }

  Future<WhatsappShareResult> _ios(
    Uint8List pdf,
    String filename,
    String text,
    Rect? origin,
  ) async {
    final directory = Directory(
      _join((await getTemporaryDirectory()).path, 'invoices'),
    );
    await directory.create(recursive: true);
    final file = File(_join(directory.path, filename));
    await file.writeAsBytes(pdf, flush: true);
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          text: text,
          sharePositionOrigin: origin,
        ),
      );
      return result.status == ShareResultStatus.success
          ? WhatsappShareResult.sheetOpened
          : WhatsappShareResult.failed;
    } catch (_) {
      return WhatsappShareResult.failed;
    }
  }

  Future<WhatsappShareResult> _windows(
    Uint8List pdf,
    String filename,
    String? phoneDigits,
    String text,
  ) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(_join(_join(root.path, 'الدفتر'), 'الفواتير'));
    await directory.create(recursive: true);
    final file = File(_join(directory.path, filename));
    await file.writeAsBytes(pdf, flush: true);
    final encoded = Uri.encodeComponent(text);
    final direct = phoneDigits == null
        ? Uri.parse('whatsapp://send?text=$encoded')
        : Uri.parse('whatsapp://send?phone=$phoneDigits&text=$encoded');
    final https = phoneDigits == null
        ? Uri.https('wa.me', '/', {'text': text})
        : Uri.https('wa.me', '/$phoneDigits', {'text': text});
    try {
      final opened = await launchUrl(
        direct,
        mode: LaunchMode.externalNonBrowserApplication,
      );
      if (!opened) {
        await launchUrl(https, mode: LaunchMode.externalApplication);
      }
    } on PlatformException {
      try {
        await launchUrl(https, mode: LaunchMode.externalApplication);
      } catch (_) {
        return WhatsappShareResult.failed;
      }
    }
    await Process.run('explorer.exe', ['/select,', file.path]);
    return WhatsappShareResult.opened;
  }
}

String _join(String directory, String name) {
  final separator = Platform.pathSeparator;
  return directory.endsWith(separator)
      ? '$directory$name'
      : '$directory$separator$name';
}
