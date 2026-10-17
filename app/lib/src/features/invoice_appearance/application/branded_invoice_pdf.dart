import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../theme/amount_format.dart';
import '../../daily_ledger/domain/opening_issue.dart';
import '../../daily_ledger/domain/quantities.dart';
import '../domain/appearance_rules.dart';
import '../domain/branded_invoice_document.dart';

/// Renders one branded copy. Paper stays light. A missing required logo throws.
Future<Uint8List> buildBrandedInvoicePdf(
  BrandedInvoiceDocument document, {
  Uint8List? logoBytes,
}) async {
  if (document.renderVersion != 1) {
    throw const FormatException('branded_invoice');
  }
  if (document.logoRequired && (logoBytes == null || logoBytes.isEmpty)) {
    throw const FormatException('logo_unverified');
  }
  final fontData = await rootBundle.load('assets/fonts/Cairo.ttf');
  final font = pw.Font.ttf(fontData);
  final accent = PdfColor.fromInt(
    InvoiceDocumentPalette.accent(document.accent),
  );
  final ink = PdfColor.fromInt(InvoiceDocumentPalette.ink);
  final paper = PdfColor.fromInt(InvoiceDocumentPalette.paper);
  final logo = !document.logoRequired || logoBytes == null
      ? null
      : pw.MemoryImage(logoBytes);
  final pdf = pw.Document();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: font, bold: font),
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.all(36),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : _row('تتمة النسخة', 'إصدار ${document.edition}', ink, accent),
      build: (_) => [
        if (document.template == InvoiceTemplate.header)
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(18),
            decoration: pw.BoxDecoration(
              color: accent,
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logo != null)
                  pw.Container(
                    height: 64,
                    alignment: pw.Alignment.centerRight,
                    child: pw.Image(logo, height: 64, fit: pw.BoxFit.contain),
                  ),
                pw.Text(
                  document.shopName,
                  style: pw.TextStyle(color: paper, fontSize: 18),
                ),
                if (document.slogan != null)
                  pw.Text(
                    document.slogan!,
                    style: pw.TextStyle(color: paper, fontSize: 12),
                  ),
                pw.Text(
                  document.kindLabel,
                  style: pw.TextStyle(color: paper, fontSize: 12),
                ),
              ],
            ),
          )
        else
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.only(bottom: 8),
            decoration: pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(color: accent, width: 2)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (logo != null)
                  pw.Image(logo, height: 48, fit: pw.BoxFit.contain),
                pw.Text(
                  document.shopName,
                  style: pw.TextStyle(color: ink, fontSize: 16),
                ),
                if (document.slogan != null)
                  pw.Text(document.slogan!, style: pw.TextStyle(color: accent)),
                pw.Text(document.kindLabel, style: pw.TextStyle(color: ink)),
              ],
            ),
          ),
        if (document.address != null) ...[
          pw.SizedBox(height: 8),
          pw.Text(
            document.address!,
            style: pw.TextStyle(color: ink, fontSize: 11),
          ),
        ],
        pw.SizedBox(height: 12),
        _row('رقم العملية', document.shopSequence, ink, accent),
        _row('إصدار النسخة', '${document.edition}', ink, accent),
        _row('وقت العملية', _clock(document.occurredAtShop), ink, accent),
        _row(
          'وقت إنشاء النسخة',
          _clock(document.copyCreatedAtShop),
          ink,
          accent,
        ),
        if (document.customerName != null)
          _row('الاسم على العملية', document.customerName!, ink, accent),
        if (document.customerPhone != null)
          _row('الهاتف على العملية', document.customerPhone!, ink, accent),
        pw.SizedBox(height: 12),
        pw.Text('الأصناف', style: pw.TextStyle(color: accent, fontSize: 14)),
        for (final line in document.lines)
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(top: 8),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: accent, width: .6),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  line.itemName,
                  style: pw.TextStyle(color: ink, fontSize: 12),
                ),
                pw.Text(
                  '${line.categoryLabel} · عيار ${line.karat}',
                  style: pw.TextStyle(color: ink, fontSize: 11),
                ),
                _value('${line.gramsText} جرام', ink),
                if (line.count != null) _value('العدد ${line.count}', ink),
                if (line.linePricePiastres != null)
                  _value(_pounds(line.linePricePiastres), ink)
                else
                  pw.Text(
                    'بلا تسعير',
                    style: pw.TextStyle(color: ink, fontSize: 11),
                  ),
              ],
            ),
          ),
        if (document.pricing != null) ...[
          pw.SizedBox(height: 12),
          pw.Text(
            'مكونات السعر',
            style: pw.TextStyle(color: accent, fontSize: 14),
          ),
          _row('الأساس', _pounds(document.pricing!.basePiastres), ink, accent),
          _row(
            'المصنعية',
            _pounds(document.pricing!.workmanshipPiastres),
            ink,
            accent,
          ),
          _row(
            document.pricing!.otherChargesLabel.isEmpty
                ? 'رسوم أخرى'
                : document.pricing!.otherChargesLabel,
            _pounds(document.pricing!.otherChargesPiastres),
            ink,
            accent,
          ),
          _row(
            'الخصم',
            _pounds(document.pricing!.discountPiastres),
            ink,
            accent,
          ),
        ],
        pw.SizedBox(height: 12),
        if (document.totalPiastres != null)
          _row('الإجمالي', _pounds(document.totalPiastres), ink, accent),
        pw.Text(
          'وسائل الدفع',
          style: pw.TextStyle(color: accent, fontSize: 14),
        ),
        if (document.tenders.isEmpty)
          pw.Text(
            'لا توجد مدفوعات على العملية',
            style: pw.TextStyle(color: ink),
          )
        else
          for (final tender in document.tenders)
            _row(tender.methodLabel, _pounds(tender.piastres), ink, accent),
        if (document.kind == 'purchase') ...[
          _row(
            'المدفوع عند الشراء',
            _pounds(document.purchasePaidPiastres ?? '0'),
            ink,
            accent,
          ),
          if (document.obligationPiastres != null) ...[
            _row(
              'المستحق عند التأكيد',
              _pounds(document.obligationPiastres),
              ink,
              accent,
            ),
            pw.Text(
              'كما سُجل عند تأكيد الشراء',
              style: pw.TextStyle(color: ink, fontSize: 10),
            ),
          ],
        ],
        if (document.description != null)
          pw.Text(document.description!, style: pw.TextStyle(color: ink)),
        if (document.note != null)
          pw.Text(document.note!, style: pw.TextStyle(color: ink)),
        if (document.synthetic)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 12),
            child: pw.Text(
              'معاينة تجريبية لا تُنشئ عملية أو إرسالاً',
              style: pw.TextStyle(color: accent, fontSize: 11),
            ),
          ),
      ],
    ),
  );
  return pdf.save();
}

pw.Widget _row(String label, String value, PdfColor ink, PdfColor accent) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            flex: 2,
            child: pw.Text(
              label,
              style: pw.TextStyle(color: accent, fontSize: 11),
            ),
          ),
          pw.Expanded(flex: 3, child: _value(value, ink)),
        ],
      ),
    );

pw.Widget _value(String value, PdfColor ink) {
  if (RegExp(r'[\u0600-\u06FF]').hasMatch(value)) {
    return pw.Text(value, style: pw.TextStyle(color: ink, fontSize: 11));
  }
  return _ltr(value, ink);
}

pw.Widget _ltr(String value, PdfColor ink) => pw.Directionality(
  textDirection: pw.TextDirection.ltr,
  child: pw.Text(
    value,
    textAlign: pw.TextAlign.end,
    style: pw.TextStyle(color: ink, fontSize: 11),
  ),
);

String _pounds(Object? value) {
  if (value is! String) throw const FormatException('branded_invoice');
  final parsed = Piastres.parseWire(value);
  if (parsed is! Accepted<Piastres>) {
    throw const FormatException('branded_invoice');
  }
  return displayPounds(parsed.value.poundsText);
}

String _clock(String value) {
  if (value.length < 16) return value;
  return '${value.substring(0, 10).replaceAll('-', '/')} ${value.substring(11, 16)}';
}
