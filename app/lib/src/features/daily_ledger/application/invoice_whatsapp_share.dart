import 'dart:typed_data';
import 'dart:ui' show Rect;

enum WhatsappShareResult { opened, sheetOpened, notInstalled, failed }

abstract interface class InvoiceWhatsappShare {
  Future<WhatsappShareResult> sharePdf({
    required Uint8List pdf,
    required String filename,
    required String? phoneDigits,
    required String text,

    /// Anchor for the iPad share popover; ignored elsewhere.
    Rect? origin,
  });
}
