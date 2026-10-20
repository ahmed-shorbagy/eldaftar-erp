import 'dart:io';
import 'package:eldafttar/src/features/invoice_appearance/application/branded_invoice_pdf.dart';
import 'package:eldafttar/src/features/invoice_appearance/domain/appearance_rules.dart';
import 'package:eldafttar/src/features/invoice_appearance/domain/branded_invoice_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'invoice_appearance_test.dart' show meetingInvoiceSource;

void main() {
  if (!const bool.fromEnvironment('OWNER_MEETING_PDF')) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'synthetic legacy, white and dark PDFs retain exact source weights',
    () async {
      const output = String.fromEnvironment(
        'MEETING_PDF_OUTPUT',
        defaultValue: 'build/owner-meeting-pdf',
      );
      await Directory(output).create(recursive: true);
      for (final entry in {
        'legacy': (1, InvoiceTemplate.header),
        'white': (2, InvoiceTemplate.header),
        'dark': (2, InvoiceTemplate.dark),
      }.entries) {
        final document = BrandedInvoiceDocument.fromConfirmed(
          source: meetingInvoiceSource(),
          edition: 1,
          contentSha256: 'ab' * 32,
          appearanceRevision: 1,
          template: entry.value.$2,
          accent: InvoiceAccent.gold,
          renderVersion: entry.value.$1,
          copyCreatedAtUtc: '2026-10-20T10:00:00Z',
          copyCreatedAtShop: '2026-10-20T13:00:00',
          slogan: 'معاينة تجريبية',
          address: 'عنوان تجريبي — القاهرة',
        );
        expect(document.lines.single.gramsText, '1.830');
        final bytes = await buildBrandedInvoicePdf(document);
        await File('$output/${entry.key}.pdf').writeAsBytes(bytes);
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
      }
    },
  );
}
