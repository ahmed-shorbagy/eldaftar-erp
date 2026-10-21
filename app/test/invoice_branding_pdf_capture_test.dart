import 'dart:io';
import 'dart:typed_data';

import 'package:eldafttar/src/features/daily_ledger/application/confirmed_operation_pdf.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/branded_invoice_pdf.dart';
import 'package:eldafttar/src/features/invoice_appearance/domain/appearance_rules.dart';
import 'package:eldafttar/src/features/invoice_appearance/domain/branded_invoice_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _operation = 'a1333333-3333-4333-8333-333333333333';
const _out = '../docs/reviews/invoice-branding-2026-10-21/pdf';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'synthetic branded pages rasterize',
    () async {
      final directory = Directory(_out);
      await directory.create(recursive: true);
      final logo = img.Image(width: 32, height: 32);
      img.fill(logo, color: img.ColorRgba8(111, 78, 27, 0));
      final logoBytes = Uint8List.fromList(img.encodePng(logo));
      final cases = <String, BrandedInvoiceDocument>{
        'long-names': _document(
          shopName:
              'متجر الذهب الأمين للمشغولات والمقتنيات التراثية في القاهرة الفاطمية',
          address:
              '١٢ شارع المعز لدين الله، الجمالية، القاهرة\nبجوار سبيل عبد الرحمن كتخدا\nالطابق الثاني، محل ٤\nبجانب سوق خان الخليلي',
          slogan: 'ذهب أمين يوزن بالجرام ويُسجل كما أُكد دون إضافة أو خصم لاحق',
          items: [
            _item(
              'عقد طويل الاسم من المشغولات التراثية المتفق عليها قبل التأكيد',
              21,
              '12500',
              '1',
            ),
          ],
        ),
        'many-items': _document(
          items: [
            for (var index = 0; index < 28; index++)
              _item('صنف معاينة ${index + 1}', 21, '${1000 + index}', '1'),
          ],
        ),
        'transparent-logo': _document(
          items: [_item('خاتم', 21, '2500', '1')],
          logo: true,
        ),
        'missing-logo': _document(
          items: [_item('سبيكة', 24, '10000', '1', category: 'bullion')],
        ),
        'karats': _document(
          items: [
            for (final karat in [14, 18, 21, 22, 24])
              _item(
                'عيار $karat',
                karat,
                '3000',
                '1',
                category: karat == 24 ? 'bullion' : 'worked_jewelry',
              ),
          ],
        ),
        'partial-purchase': _document(
          kind: 'purchase',
          items: [
            _item('كسر', 18, '4500', null, category: 'scrap'),
            _item('عملة', 21, '8000', '2', category: 'coin'),
          ],
          obligation: '250000',
          tenders: [
            {'method': 'cash', 'piastres': '100000'},
            {'method': 'wallet', 'piastres': '50000'},
          ],
        ),
      };
      for (final entry in cases.entries) {
        final bytes = await buildBrandedInvoicePdf(
          entry.value,
          logoBytes: entry.key == 'transparent-logo' ? logoBytes : null,
        );
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        final pdf = File('${directory.path}/${entry.key}.pdf');
        await pdf.writeAsBytes(bytes);
        await _raster(bytes, pdf.path, '${directory.path}/${entry.key}');
      }
      for (final template in [InvoiceTemplate.header, InvoiceTemplate.dark]) {
        final sale = _document(
          shopName: 'مجوهرات النور',
          address: 'شبرا - القاهرة',
          items: [
            _item('خاتم', 21, '1830', '1', price: '500000'),
            _item('سلسلة', 18, '2560', '1', price: '200000'),
          ],
          tenders: [
            {'method': 'cash', 'piastres': '500000'},
            {'method': 'card', 'piastres': '200000'},
          ],
          total: '700000',
          phone: '01012345678',
          template: template,
        );
        for (final output in BrandedInvoiceOutput.values) {
          final bytes = await buildBrandedInvoicePdf(sale, output: output);
          final name = 'design-${template.wire}-${output.name}';
          final pdf = File('${directory.path}/$name.pdf');
          await pdf.writeAsBytes(bytes);
          await _raster(bytes, pdf.path, '${directory.path}/$name');
        }
      }
      final legacy = await buildConfirmedOperationPdf({
        'kind': 'sale',
        'shop_name': 'متجر المعاينة',
        'shop_sequence': '44',
        'occurred_at_cairo': '2026-10-17T10:00:00',
        'payload': cases['karats']!.documentSource,
      });
      final legacyFile = File('${directory.path}/legacy-karats.pdf');
      await legacyFile.writeAsBytes(legacy);
      await _raster(legacy, legacyFile.path, '${directory.path}/legacy-karats');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _raster(Uint8List bytes, String pdfPath, String prefix) async {
  final python = await Process.run('python', [
    '-c',
    '''
import sys
import pypdfium2 as pdfium
document = pdfium.PdfDocument(sys.argv[1])
count = 0
for index, page in enumerate(document, start=1):
    image = page.render(scale=1).to_pil()
    image.save(f"{sys.argv[2]}-page-{index}.png")
    count += 1
if count < 1:
    raise SystemExit("no_pages")
print(count)
''',
    pdfPath,
    prefix,
  ]);
  if (python.exitCode == 0) return;
  fail(
    'raster_unavailable ${python.stderr} ${python.stdout} bytes=${bytes.length}',
  );
}

BrandedInvoiceDocument _document({
  String kind = 'sale',
  String shopName = 'متجر المعاينة',
  String? slogan,
  String? address,
  required List<Map<String, Object?>> items,
  bool logo = false,
  String? obligation,
  List<Map<String, Object?>>? tenders,
  String total = '100000',
  String customer = 'طرف معاينة',
  String? phone,
  InvoiceTemplate template = InvoiceTemplate.header,
}) {
  return BrandedInvoiceDocument.fromConfirmed(
    source: {
      'operation_id': _operation,
      'kind': kind,
      'shop_name': shopName,
      'shop_sequence': '44',
      'time_zone': 'Africa/Cairo',
      'occurred_at': '2026-10-17T08:00:00.000000Z',
      'occurred_at_shop': '2026-10-17T10:00:00',
      'payload': {
        'total_piastres': total,
        'customer_name': customer,
        'customer_phone': ?phone,
        'items': items,
        'tenders':
            tenders ??
            [
              {'method': 'cash', 'piastres': '60000'},
              {'method': 'instant_transfer', 'piastres': '40000'},
            ],
        'purchase_obligation_piastres': ?obligation,
      },
    },
    edition: 1,
    contentSha256: 'ab' * 32,
    appearanceRevision: 3,
    template: template,
    accent: InvoiceAccent.gold,
    renderVersion: phone == null ? 1 : 2,
    copyCreatedAtUtc: '2026-10-17T09:00:00.000000Z',
    copyCreatedAtShop: '2026-10-17T11:00:00',
    slogan: slogan,
    address: address,
    logoAssetId: logo ? _operation : null,
    logoSha256: logo ? 'cd' * 32 : null,
    logoRequired: logo,
  );
}

Map<String, Object?> _item(
  String name,
  int karat,
  String milligrams,
  String? count, {
  String category = 'worked_jewelry',
  String? price,
}) => {
  'item_name': name,
  'category': category,
  'karat': karat,
  'milligrams': milligrams,
  'count': count,
  'line_price_piastres': price,
};

extension on BrandedInvoiceDocument {
  Map<String, Object?> get documentSource => {
    'total_piastres': totalPiastres,
    'customer_name': customerName,
    'items': [
      for (final line in lines)
        {
          'item_name': line.itemName,
          'karat': line.karat,
          'milligrams': line.milligrams,
          'count': line.count,
          'line_price_piastres': line.linePricePiastres,
        },
    ],
    'tenders': [
      for (final tender in tenders)
        {'method': tender.method, 'piastres': tender.piastres},
    ],
  };
}
