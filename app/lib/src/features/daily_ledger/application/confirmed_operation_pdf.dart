import '../../../theme/amount_format.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/opening_issue.dart';
import '../domain/quantities.dart';
import '../../../theme/app_tokens.dart';

/// A stable customer copy of one confirmed server operation. No client draft is used.
Future<Uint8List> buildConfirmedOperationPdf(
  Map<String, Object?> operation,
) async {
  final kind = operation['kind'];
  final payload = operation['payload'];
  if ((kind != 'sale' && kind != 'purchase') ||
      payload is! Map ||
      operation['shop_sequence'] is! String) {
    throw const FormatException('confirmed_operation_pdf');
  }
  final fontData = await rootBundle.load('assets/fonts/Cairo.ttf');
  final font = pw.Font.ttf(fontData);
  final document = pw.Document();
  final primary = _pdfColor(AppTokens.seed);
  final ink = _pdfColor(AppTokens.lightOnSurface);
  final paper = _pdfColor(AppTokens.lightSurface);
  final items = payload['items'];
  final tenders = payload['tenders'];
  final pricing = payload['pricing'];
  final amount = _pounds(payload['total_piastres']);
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: font, bold: font),
      textDirection: pw.TextDirection.rtl,
      margin: const pw.EdgeInsets.all(36),
      build: (_) => [
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(18),
          decoration: pw.BoxDecoration(
            color: primary,
            borderRadius: pw.BorderRadius.circular(12),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '${operation['shop_name'] ?? 'الدفتر'}',
                style: pw.TextStyle(color: paper, fontSize: 18),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                kind == 'sale' ? 'مستند بيع مؤكد' : 'مستند شراء مؤكد',
                style: pw.TextStyle(color: paper, fontSize: 12),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 18),
        _row('رقم العملية', '${operation['shop_sequence']}', ink),
        _row('وقت العملية', _displayTime(operation['occurred_at_cairo']), ink),
        if ((payload['customer_name'] ?? '').toString().isNotEmpty)
          _row('العميل', '${payload['customer_name']}', ink),
        pw.SizedBox(height: 18),
        pw.Text('الأصناف', style: pw.TextStyle(color: primary, fontSize: 14)),
        if (items is List)
          for (final raw in items)
            if (raw is Map)
              pw.Container(
                width: double.infinity,
                margin: const pw.EdgeInsets.only(top: 8),
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: primary, width: .5),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      '${raw['item_name'] ?? 'صنف'} · عيار ${raw['karat'] ?? '—'}',
                    ),
                    pw.Text(
                      '${_grams(raw['milligrams'])} جرام'
                      '${raw['count'] == null ? '' : ' · ${raw['count']} قطعة'}',
                    ),
                    if (raw['line_price_piastres'] is String)
                      pw.Text(
                        'سعر الصنف: ${_pounds(raw['line_price_piastres'])}',
                      ),
                  ],
                ),
              ),
        pw.SizedBox(height: 18),
        if (pricing is Map) ...[
          _row('السعر الأساسي', _pounds(pricing['base_piastres']), ink),
          _row('المصنعية', _pounds(pricing['workmanship_piastres']), ink),
          _row(
            'الرسوم الأخرى (${pricing['other_charges_label'] ?? ''})',
            _pounds(pricing['other_charges_piastres']),
            ink,
          ),
          _row('الخصم', _pounds(pricing['discount_piastres']), ink),
          pw.SizedBox(height: 12),
        ],
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          color: paper,
          child: _row(
            'إجمالي ${kind == 'sale' ? 'البيع' : 'الشراء'}',
            amount,
            ink,
          ),
        ),
        if (kind == 'purchase') ...[
          _row('المدفوع عند الشراء', _paidPounds(tenders), ink),
          if (payload['purchase_obligation_piastres'] is String)
            _row(
              'المستحق عند الشراء',
              _pounds(payload['purchase_obligation_piastres']),
              ink,
            ),
        ],
        pw.SizedBox(height: 14),
        pw.Text(
          'وسائل الدفع',
          style: pw.TextStyle(color: primary, fontSize: 14),
        ),
        if (tenders is List)
          for (final raw in tenders)
            if (raw is Map)
              _row(_method(raw['method']), _pounds(raw['piastres']), ink),
        if ((payload['note'] ?? '').toString().isNotEmpty) ...[
          pw.SizedBox(height: 12),
          pw.Text('ملاحظة: ${payload['note']}'),
        ],
      ],
    ),
  );
  return document.save();
}

pw.Widget _row(String label, String value, PdfColor ink) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(vertical: 4),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Expanded(
        flex: 2,
        child: pw.Text(label, style: pw.TextStyle(color: ink)),
      ),
      pw.Expanded(
        child: pw.Text(
          value,
          textAlign: pw.TextAlign.end,
          style: pw.TextStyle(color: ink),
        ),
      ),
    ],
  ),
);

PdfColor _pdfColor(dynamic color) => PdfColor(color.r, color.g, color.b);

String _pounds(Object? value) {
  if (value is! String) throw const FormatException('pdf_amount');
  final parsed = Piastres.parseWire(value);
  if (parsed is! Accepted<Piastres>) throw const FormatException('pdf_amount');
  return displayPounds(parsed.value.poundsText);
}

String _paidPounds(Object? tenders) {
  if (tenders is! List) throw const FormatException('pdf_tenders');
  var total = BigInt.zero;
  for (final raw in tenders) {
    if (raw is! Map || raw['piastres'] is! String) {
      throw const FormatException('pdf_tenders');
    }
    final parsed = Piastres.parseWire(raw['piastres'] as String);
    if (parsed is! Accepted<Piastres>) {
      throw const FormatException('pdf_tenders');
    }
    total += parsed.value.value;
  }
  return _pounds(total.toString());
}

String _grams(Object? value) {
  if (value is! String) throw const FormatException('pdf_weight');
  final parsed = Milligrams.parseWire(value);
  if (parsed is! Accepted<Milligrams>) {
    throw const FormatException('pdf_weight');
  }
  return parsed.value.gramsText;
}

String _method(Object? value) => switch (value) {
  'cash' => 'نقدي',
  'instant_transfer' => 'تحويل فوري',
  'wallet' => 'محفظة',
  'card' => 'بطاقة',
  _ => 'وسيلة دفع',
};

String _displayTime(Object? value) {
  if (value is! String || value.length < 16) return '—';
  return '${value.substring(0, 10).replaceAll('-', '/')} '
      '${value.substring(11, 16)}';
}
