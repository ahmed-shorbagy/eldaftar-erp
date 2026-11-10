import 'dart:convert';
import 'dart:io';

import 'package:eldafttar/src/features/daily_ledger/application/confirmed_operation_pdf.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/branded_invoice_pdf.dart';
import 'package:eldafttar/src/features/invoice_appearance/domain/appearance_rules.dart';
import 'package:eldafttar/src/features/invoice_appearance/domain/branded_invoice_document.dart';
import 'package:flutter_test/flutter_test.dart';

const _operation = 'a1333333-3333-4333-8333-333333333333';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'branded and legacy invoices print the shop name and omit notes',
    () async {
      final branded = await buildBrandedInvoicePdf(
        BrandedInvoiceDocument.fromConfirmed(
          source: _source(kind: 'sale'),
          edition: 1,
          contentSha256: 'ab' * 32,
          appearanceRevision: 1,
          template: InvoiceTemplate.header,
          accent: InvoiceAccent.brown,
          renderVersion: 1,
          copyCreatedAtUtc: '2026-10-17T10:00:00.000000Z',
          copyCreatedAtShop: '2026-10-17T12:00:00',
        ),
      );
      final brandedText = await _pdfText(branded);
      expect(brandedText, contains('مجوهرات الاختبار'));
      expect(brandedText, isNot(contains('بائع الاختبار')));
      expect(brandedText, contains('وصف ظاهر'));
      expect(brandedText, isNot(contains('ملاحظة داخلية')));
      expect(brandedText, isNot(contains('ملاحظة:')));

      final legacy = await buildConfirmedOperationPdf(_source(kind: 'sale'));
      final legacyText = await _pdfText(legacy);
      expect(legacyText, contains('مجوهرات الاختبار'));
      expect(legacyText, isNot(contains('بائع الاختبار')));
      expect(legacyText, isNot(contains('ملاحظة داخلية')));

      final purchase = await buildBrandedInvoicePdf(
        BrandedInvoiceDocument.fromConfirmed(
          source: _source(kind: 'purchase'),
          edition: 1,
          contentSha256: 'cd' * 32,
          appearanceRevision: 1,
          template: InvoiceTemplate.header,
          accent: InvoiceAccent.brown,
          renderVersion: 1,
          copyCreatedAtUtc: '2026-10-17T10:00:00.000000Z',
          copyCreatedAtShop: '2026-10-17T12:00:00',
        ),
      );
      final purchaseText = await _pdfText(purchase);
      expect(purchaseText, contains('العميل'));
      expect(purchaseText, isNot(contains('البائع')));
    },
  );
}

Map<String, Object?> _source({required String kind}) => {
  'operation_id': _operation,
  'kind': kind,
  'shop_name': 'مجوهرات الاختبار',
  'shop_sequence': '44',
  'actor_display_name': 'بائع الاختبار',
  'time_zone': 'Africa/Cairo',
  'occurred_at': '2026-10-17T08:00:00.000000Z',
  'occurred_at_shop': '2026-10-17T10:00:00',
  'payload': {
    'total_piastres': '104002',
    'customer_name': 'طرف معاينة',
    'description': 'وصف ظاهر',
    'note': 'ملاحظة داخلية',
    'items': [
      {
        'item_name': 'خواتم',
        'category': 'worked_jewelry',
        'karat': 18,
        'milligrams': '1830',
        'count': '1',
        'line_price_piastres': null,
      },
    ],
    'tenders': [
      {'method': 'cash', 'piastres': '104002'},
    ],
    if (kind == 'purchase') 'purchase_obligation_piastres': '0',
  },
};

Future<String> _pdfText(List<int> bytes) async {
  final dir = await Directory.systemTemp.createTemp('eldaftar-pdf-');
  final path = '${dir.path}${Platform.pathSeparator}invoice.pdf';
  await File(path).writeAsBytes(bytes);
  final python = await Process.run(
    'python',
    [
      '-c',
      '''
import sys
import pypdfium2 as pdfium
document = pdfium.PdfDocument(sys.argv[1])
parts = []
for page in document:
    parts.append(page.get_textpage().get_text_bounded())
print("\\n".join(parts))
''',
      path,
    ],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
    environment: const {'PYTHONIOENCODING': 'utf-8'},
  );
  if (python.exitCode != 0) {
    fail('pdf_text_unavailable ${python.stderr} ${python.stdout}');
  }
  return '${python.stdout}';
}
