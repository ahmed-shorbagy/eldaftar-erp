import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../theme/amount_format.dart';
import '../../../theme/pdf_arabic.dart';
import '../../daily_ledger/domain/opening_issue.dart';
import '../../daily_ledger/domain/quantities.dart';
import '../domain/appearance_rules.dart';
import '../domain/branded_invoice_document.dart';

/// `print` is an A4 document. `image` is one tall phone-width page meant to
/// be rasterized and sent as a picture.
enum BrandedInvoiceOutput { print, image }

/// Frozen render-v1 editions keep their palette. New editions support cream
/// paper and an explicit dark/gold template. A required missing logo throws.
Future<Uint8List> buildBrandedInvoicePdf(
  BrandedInvoiceDocument document, {
  Uint8List? logoBytes,
  BrandedInvoiceOutput output = BrandedInvoiceOutput.print,
}) async {
  if (!const [1, 2].contains(document.renderVersion) ||
      (document.renderVersion == 1 &&
          document.template == InvoiceTemplate.dark)) {
    throw const FormatException('branded_invoice');
  }
  if (document.logoRequired && (logoBytes == null || logoBytes.isEmpty)) {
    throw const FormatException('logo_unverified');
  }
  final fontData = await rootBundle.load('assets/fonts/Cairo.ttf');
  final font = pw.Font.ttf(fontData);
  final style = _Style.of(document);
  final theme = pw.ThemeData.withFont(
    base: font,
    bold: font,
  ).copyWith(defaultTextStyle: pw.TextStyle(color: style.ink, fontSize: 10));
  final logo = !document.logoRequired || logoBytes == null
      ? null
      : pw.MemoryImage(logoBytes);
  final body = _Body(document, style, logo);
  final pdf = pw.Document(
    title: '${document.titleLabel} ${document.shopSequence}',
  );
  if (output == BrandedInvoiceOutput.image) {
    pdf.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(420, double.infinity, marginAll: 0),
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        build: (_) => pw.Container(
          color: style.footerBand,
          child: pw.Column(
            children: [
              pw.Container(
                color: style.paper,
                padding: const pw.EdgeInsets.all(14),
                child: pw.Container(
                  decoration: style.frame(),
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Container(
                    decoration: style.innerFrame(),
                    padding: const pw.EdgeInsets.fromLTRB(16, 18, 16, 16),
                    child: pw.Column(
                      children: body.widgets(compactFooter: true),
                    ),
                  ),
                ),
              ),
              _imageFooter(document, style),
            ],
          ),
        ),
      ),
    );
    return pdf.save();
  }
  pdf.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.fromLTRB(46, 44, 46, 40),
        buildBackground: (_) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Container(
            color: style.paper,
            padding: const pw.EdgeInsets.all(18),
            child: document.template == InvoiceTemplate.compact
                ? null
                : pw.Container(
                    decoration: style.frame(),
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Container(decoration: style.innerFrame()),
                  ),
          ),
        ),
      ),
      header: (context) => context.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 10),
              child: pdfText(
                'تتمة ${document.titleLabel} رقم ${document.shopSequence}',
                style: pw.TextStyle(color: style.muted, fontSize: 9),
              ),
            ),
      build: (_) => body.widgets(compactFooter: false),
    ),
  );
  return pdf.save();
}

final class _Style {
  const _Style({
    required this.paper,
    required this.panel,
    required this.line,
    required this.frameColor,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.footerBand,
    required this.footerInk,
  });

  factory _Style.of(BrandedInvoiceDocument document) {
    if (document.template == InvoiceTemplate.dark) {
      return _Style(
        paper: _c(InvoiceDocumentPalette.darkPaper),
        panel: _c(InvoiceDocumentPalette.darkPanel),
        line: _c(InvoiceDocumentPalette.darkLine),
        frameColor: _c(InvoiceDocumentPalette.darkGold),
        ink: _c(InvoiceDocumentPalette.darkInk),
        muted: _c(InvoiceDocumentPalette.darkMuted),
        accent: _c(InvoiceDocumentPalette.darkGold),
        footerBand: _c(InvoiceDocumentPalette.footerBand),
        footerInk: _c(InvoiceDocumentPalette.darkGold),
      );
    }
    return _Style(
      paper: _c(
        document.renderVersion == 1
            ? InvoiceDocumentPalette.paper
            : InvoiceDocumentPalette.cream,
      ),
      panel: _c(InvoiceDocumentPalette.creamPanel),
      line: _c(InvoiceDocumentPalette.creamLine),
      frameColor: _c(InvoiceDocumentPalette.frameGold),
      ink: _c(InvoiceDocumentPalette.ink),
      muted: _c(InvoiceDocumentPalette.muted),
      accent: _c(InvoiceDocumentPalette.accent(document.accent)),
      footerBand: _c(InvoiceDocumentPalette.footerBand),
      footerInk: _c(InvoiceDocumentPalette.darkGold),
    );
  }

  final PdfColor paper, panel, line, frameColor, ink, muted, accent;
  final PdfColor footerBand, footerInk;

  pw.BoxDecoration frame() => pw.BoxDecoration(
    border: pw.Border.all(color: frameColor, width: 1.6),
    borderRadius: pw.BorderRadius.circular(10),
  );

  pw.BoxDecoration innerFrame() => pw.BoxDecoration(
    border: pw.Border.all(color: frameColor, width: .6),
    borderRadius: pw.BorderRadius.circular(8),
  );

  pw.BoxDecoration box({PdfColor? fill}) => pw.BoxDecoration(
    color: fill,
    border: pw.Border.all(color: line, width: .8),
    borderRadius: pw.BorderRadius.circular(8),
  );

  static PdfColor _c(int argb) => PdfColor.fromInt(argb);
}

final class _Body {
  const _Body(this.document, this.style, this.logo);
  final BrandedInvoiceDocument document;
  final _Style style;
  final pw.MemoryImage? logo;

  List<pw.Widget> widgets({required bool compactFooter}) => [
    _header(),
    pw.SizedBox(height: 12),
    _title(),
    pw.SizedBox(height: 12),
    _meta(),
    if (document.customerName != null || document.customerPhone != null) ...[
      pw.SizedBox(height: 10),
      _customer(),
    ],
    pw.SizedBox(height: 12),
    _tableHeader(),
    for (var i = 0; i < document.lines.length; i++)
      _tableRow(document.lines[i], i.isOdd),
    pw.Container(height: .8, color: style.line),
    pw.SizedBox(height: 12),
    _summaryBoxes(),
    if (document.pricing != null) ...[pw.SizedBox(height: 10), _pricing()],
    if (document.totalPiastres != null) ...[pw.SizedBox(height: 10), _total()],
    if (document.kind == 'purchase' && document.obligationPiastres != null) ...[
      pw.SizedBox(height: 8),
      _pair(
        'المستحق عند التأكيد',
        _money(document.obligationPiastres!),
        note: 'كما سُجل عند تأكيد الشراء',
      ),
    ],
    if (document.description != null || document.note != null) ...[
      pw.SizedBox(height: 10),
      pw.Container(
        width: double.infinity,
        padding: const pw.EdgeInsets.all(10),
        decoration: style.box(),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (document.description != null)
              pdfText(
                document.description!,
                style: const pw.TextStyle(fontSize: 10),
              ),
            if (document.note != null)
              pdfText(
                document.note!,
                style: pw.TextStyle(color: style.muted, fontSize: 9.5),
              ),
          ],
        ),
      ),
    ],
    if (document.synthetic) ...[
      pw.SizedBox(height: 10),
      pdfText(
        'معاينة تجريبية لا تُنشئ عملية أو إرسالاً',
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(color: style.accent, fontSize: 10),
      ),
    ],
    pw.SizedBox(height: 16),
    if (!compactFooter) _thanks(),
    _contacts(),
    pw.SizedBox(height: 6),
    pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        _auto(
          'نسخة رقم ${document.edition} · أُنشئت ${_clock(document.copyCreatedAtShop)}',
          7.5,
          color: style.muted,
        ),
      ],
    ),
  ];

  pw.Widget _header() {
    final compact = document.template == InvoiceTemplate.compact;
    return pw.SizedBox(
      width: double.infinity,
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          if (logo != null)
            pw.Image(logo!, height: compact ? 40 : 56, fit: pw.BoxFit.contain)
          else
            _diamond(style.frameColor, compact ? 28 : 38),
          pw.SizedBox(height: 6),
          pdfText(
            document.shopName,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
              color: style.accent,
              fontSize: compact ? 18 : 22,
            ),
          ),
          if (document.slogan != null)
            pdfText(
              document.slogan!,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(color: style.muted, fontSize: 9.5),
            ),
        ],
      ),
    );
  }

  pw.Widget _title() => pw.Row(
    children: [
      pw.Expanded(child: pw.Container(height: .8, color: style.frameColor)),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 12),
        child: pdfText(
          document.titleLabel,
          style: pw.TextStyle(color: style.ink, fontSize: 15),
        ),
      ),
      pw.Expanded(child: pw.Container(height: .8, color: style.frameColor)),
    ],
  );

  pw.Widget _meta() => pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(
        child: _labelled('رقم الفاتورة', _ltr('#${document.shopSequence}', 12)),
      ),
      pw.Expanded(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pdfText(
              'التاريخ',
              style: pw.TextStyle(color: style.muted, fontSize: 8.5),
            ),
            _ltr(_clock(document.occurredAtShop), 11),
          ],
        ),
      ),
    ],
  );

  pw.Widget _customer() => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: style.box(fill: style.panel),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pdfText(
          document.kind == 'sale' ? 'العميل' : 'البائع',
          style: pw.TextStyle(color: style.muted, fontSize: 8.5),
        ),
        if (document.customerName != null)
          pdfText(
            document.customerName!,
            style: const pw.TextStyle(fontSize: 11.5),
          ),
        if (document.customerPhone != null)
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: _ltr(document.customerPhone!, 10.5),
          ),
      ],
    ),
  );

  static const _flex = [5, 1, 2, 3, 3];

  pw.Widget _tableHeader() => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: pw.BoxDecoration(
      color: style.panel,
      border: pw.Border(
        top: pw.BorderSide(color: style.line, width: .8),
        bottom: pw.BorderSide(color: style.frameColor, width: .8),
      ),
    ),
    child: pw.Row(
      children: [
        for (final (index, label) in const [
          'الصنف',
          'ع',
          'العيار',
          'الوزن',
          'السعر',
        ].indexed)
          pw.Expanded(
            flex: _flex[index],
            child: pdfText(
              label,
              textAlign: index == 0 ? pw.TextAlign.right : pw.TextAlign.center,
              style: pw.TextStyle(color: style.accent, fontSize: 9.5),
            ),
          ),
      ],
    ),
  );

  pw.Widget _tableRow(BrandedInvoiceLine line, bool shaded) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: pw.BoxDecoration(
      color: shaded ? style.panel : null,
      border: pw.Border(bottom: pw.BorderSide(color: style.line, width: .5)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Expanded(
          flex: _flex[0],
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pdfText(line.itemName, style: const pw.TextStyle(fontSize: 10.5)),
              pdfText(
                line.categoryLabel,
                style: pw.TextStyle(color: style.muted, fontSize: 8),
              ),
            ],
          ),
        ),
        pw.Expanded(flex: _flex[1], child: _cell(line.count ?? '—')),
        pw.Expanded(flex: _flex[2], child: _cell('${line.karat}')),
        pw.Expanded(flex: _flex[3], child: _cell('${line.gramsText} جم')),
        pw.Expanded(
          flex: _flex[4],
          child: _cell(
            line.linePricePiastres == null
                ? '—'
                : _money(line.linePricePiastres!),
          ),
        ),
      ],
    ),
  );

  pw.Widget _cell(String value) => pw.Center(child: _auto(value, 10));

  pw.Widget _summaryBoxes() {
    final payment = pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: style.box(),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _boxTitle(document.kind == 'sale' ? 'طريقة الدفع' : 'المدفوع للبائع'),
          if (document.tenders.isEmpty)
            pdfText(
              'لا توجد مدفوعات',
              style: pw.TextStyle(color: style.muted, fontSize: 9.5),
            )
          else
            for (final tender in document.tenders)
              _boxLine(tender.methodLabel, _money(tender.piastres)),
        ],
      ),
    );
    final weights = pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: style.box(),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _boxTitle('إجمالي الوزن'),
          for (final row in document.weightByKarat)
            _boxLine('عيار ${row.karat}', '${row.gramsText} جم'),
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 4),
            padding: const pw.EdgeInsets.only(top: 4),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                top: pw.BorderSide(color: style.line, width: .6),
              ),
            ),
            child: _boxLine(
              'الإجمالي',
              '${document.totalGramsText} جم',
              strong: true,
            ),
          ),
        ],
      ),
    );
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(child: payment),
        pw.SizedBox(width: 10),
        pw.Expanded(child: weights),
      ],
    );
  }

  pw.Widget _pricing() {
    final pricing = document.pricing!;
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: style.box(),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _boxTitle('تفاصيل السعر'),
          _boxLine('الأساس', _money(pricing.basePiastres)),
          _boxLine('المصنعية', _money(pricing.workmanshipPiastres)),
          _boxLine(
            pricing.otherChargesLabel.isEmpty
                ? 'رسوم أخرى'
                : pricing.otherChargesLabel,
            _money(pricing.otherChargesPiastres),
          ),
          _boxLine('الخصم', _money(pricing.discountPiastres)),
        ],
      ),
    );
  }

  pw.Widget _total() => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: pw.BoxDecoration(
      color: style.panel,
      border: pw.Border.all(color: style.frameColor, width: 1.2),
      borderRadius: pw.BorderRadius.circular(10),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pdfText('الإجمالي', style: const pw.TextStyle(fontSize: 13)),
              pdfText(
                'المبلغ بالجنيه المصري',
                style: pw.TextStyle(color: style.muted, fontSize: 8),
              ),
            ],
          ),
        ),
        pw.Directionality(
          textDirection: pw.TextDirection.ltr,
          child: pdfText(
            _money(document.totalPiastres!),
            style: pw.TextStyle(color: style.accent, fontSize: 24),
          ),
        ),
      ],
    ),
  );

  pw.Widget _pair(String label, String value, {String? note}) => pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: style.box(),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _boxLine(label, value, strong: true),
        if (note != null)
          pdfText(note, style: pw.TextStyle(color: style.muted, fontSize: 8.5)),
      ],
    ),
  );

  pw.Widget _thanks() => pw.Column(
    children: [
      pw.Row(
        children: [
          pw.Expanded(child: pw.Container(height: .6, color: style.line)),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10),
            child: pdfText(
              'شكراً لتعاملكم معنا',
              style: pw.TextStyle(color: style.accent, fontSize: 13),
            ),
          ),
          pw.Expanded(child: pw.Container(height: .6, color: style.line)),
        ],
      ),
      pw.SizedBox(height: 6),
    ],
  );

  pw.Widget _contacts() {
    if (document.address == null) return pw.SizedBox();
    return pw.SizedBox(
      width: double.infinity,
      child: pdfText(
        document.address!,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(color: style.muted, fontSize: 9),
      ),
    );
  }

  pw.Widget _boxTitle(String label) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 4),
    child: pdfText(
      label,
      style: pw.TextStyle(color: style.accent, fontSize: 10),
    ),
  );

  pw.Widget _boxLine(String label, String value, {bool strong = false}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
        child: pw.Row(
          children: [
            pw.Expanded(
              child: pw.Align(
                alignment: pw.Alignment.centerRight,
                child: _auto(
                  label,
                  strong ? 10 : 9.5,
                  color: strong ? style.ink : style.muted,
                ),
              ),
            ),
            _auto(value, strong ? 10.5 : 10),
          ],
        ),
      );

  pw.Widget _labelled(String label, pw.Widget value) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pdfText(label, style: pw.TextStyle(color: style.muted, fontSize: 8.5)),
      value,
    ],
  );

  /// Arabic-only text stays one RTL run, numbers stay LTR, and mixed text is
  /// laid out word by word so digits never flip around Arabic units.
  pw.Widget _auto(String text, double size, {PdfColor? color}) {
    final arabic = RegExp(r'[\u0600-\u06FF]').hasMatch(text);
    if (!arabic) return _ltr(text, size, color: color);
    if (!RegExp(r'[0-9]').hasMatch(text)) {
      return pdfText(
        text,
        style: pw.TextStyle(color: color ?? style.ink, fontSize: size),
      );
    }
    return _mixed(
      text.split(' ').where((part) => part.isNotEmpty).toList(),
      size,
      color: color,
    );
  }

  pw.Widget _mixed(List<String> parts, double size, {PdfColor? color}) {
    final isArabic = RegExp(r'[\u0600-\u06FF]');
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        for (final (index, part) in parts.indexed) ...[
          if (index > 0) pw.SizedBox(width: size * .3),
          isArabic.hasMatch(part)
              ? pdfText(
                  part,
                  style: pw.TextStyle(
                    color: color ?? style.ink,
                    fontSize: size,
                  ),
                )
              : pw.Directionality(
                  textDirection: pw.TextDirection.ltr,
                  child: pdfText(
                    part,
                    style: pw.TextStyle(
                      color: color ?? style.ink,
                      fontSize: size,
                    ),
                  ),
                ),
        ],
      ],
    );
  }

  pw.Widget _ltr(String value, double size, {PdfColor? color}) =>
      pw.Directionality(
        textDirection: pw.TextDirection.ltr,
        child: pdfText(
          value,
          style: pw.TextStyle(color: color ?? style.ink, fontSize: size),
        ),
      );
}

pw.Widget _imageFooter(BrandedInvoiceDocument document, _Style style) =>
    pw.Container(
      width: double.infinity,
      color: style.footerBand,
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          _diamond(style.footerInk, 30),
          pw.SizedBox(width: 12),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pdfText(
                'شكراً لتعاملكم معنا',
                style: pw.TextStyle(color: style.footerInk, fontSize: 15),
              ),
              pdfText(
                document.shopName,
                style: pw.TextStyle(
                  color: PdfColor.fromInt(InvoiceDocumentPalette.darkInk),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );

pw.Widget _diamond(PdfColor color, double size) => pw.SizedBox(
  width: size * 1.25,
  height: size,
  child: pw.CustomPaint(
    painter: (canvas, area) {
      final w = area.x, h = area.y;
      PdfPoint p(double x, double y) => PdfPoint(x * w, y * h);
      void line(PdfPoint a, PdfPoint b) => canvas
        ..moveTo(a.x, a.y)
        ..lineTo(b.x, b.y);
      final tl = p(.24, .9), tr = p(.76, .9), ml = p(.02, .6), mr = p(.98, .6);
      final tip = p(.5, .04), tm = p(.5, .9), il = p(.36, .6), ir = p(.64, .6);
      canvas
        ..setStrokeColor(color)
        ..setLineWidth(size / 22)
        ..setLineJoin(PdfLineJoin.round)
        ..moveTo(tl.x, tl.y)
        ..lineTo(tr.x, tr.y)
        ..lineTo(mr.x, mr.y)
        ..lineTo(tip.x, tip.y)
        ..lineTo(ml.x, ml.y)
        ..closePath();
      line(ml, mr);
      line(tl, il);
      line(il, tip);
      line(tr, ir);
      line(ir, tip);
      line(tm, il);
      line(tm, ir);
      canvas.strokePath();
    },
  ),
);

String _money(String value) {
  final parsed = Piastres.parseWire(value);
  if (parsed is! Accepted<Piastres>) {
    throw const FormatException('branded_invoice');
  }
  return displayPounds(parsed.value.poundsText);
}

String _clock(String value) {
  if (value.length < 16) return value;
  return '${value.substring(0, 10).replaceAll('-', '/')}  ${value.substring(11, 16)}';
}
