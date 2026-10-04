import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../theme/app_tokens.dart';
import '../application/inventory_gateway.dart';
import 'inventory_copy.dart';

/// Bookkeeping custody statement. It is not a legal title or an approval.
Future<Uint8List> buildTraderStatementPdf({
  required String shopName,
  required TraderDetail trader,
  required List<TraderActivity> activity,
  required bool activityHasOlder,
}) async {
  final fontData = await rootBundle.load('assets/fonts/NotoSansArabic.ttf');
  final font = pw.Font.ttf(fontData);
  final document = pw.Document();
  final primary = PdfColor(
    AppTokens.seed.r,
    AppTokens.seed.g,
    AppTokens.seed.b,
  );
  final ink = PdfColor(
    AppTokens.lightOnSurface.r,
    AppTokens.lightOnSurface.g,
    AppTokens.lightOnSurface.b,
  );
  final paper = PdfColor(
    AppTokens.lightSurface.r,
    AppTokens.lightSurface.g,
    AppTokens.lightSurface.b,
  );
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
                shopName,
                style: pw.TextStyle(color: paper, fontSize: 18),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'كشف أمانة محاسبي',
                style: pw.TextStyle(color: paper, fontSize: 12),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 16),
        _line('التاجر', trader.displayName, ink),
        if (trader.phone.isNotEmpty) _line('الهاتف', trader.phone, ink),
        if (trader.note.isNotEmpty) _line('ملاحظة', trader.note, ink),
        _line('الحالة', trader.active ? 'نشط' : 'موقوف', ink),
        pw.SizedBox(height: 12),
        _line(
          'ما استُلم أصلاً',
          '${gramsOf(trader.originalHeldMilligrams)} جرام',
          ink,
        ),
        _line(
          'ما زال في الحيازة',
          '${gramsOf(trader.currentHeldMilligrams)} جرام',
          ink,
        ),
        _line('استلامات معلّقة', trader.pendingReceiptCount.toString(), ink),
        _line(
          'مستحق الجنيه المتبقي',
          '${poundsOf(trader.cashPayableRemainingPiastres)} جنيه (${trader.cashPayableRemainingPiastres} قرشاً)',
          ink,
        ),
        for (final gold in trader.goldRemaining)
          _line(
            'ذهب عيار ${gold.karat}',
            'المتبقي ${gramsOf(gold.remainingMilligrams)} من أصل ${gramsOf(gold.initialMilligrams)} جرام',
            ink,
          ),
        if (trader.goldRemaining.isEmpty)
          _line('ذهب مربوط', 'لا يوجد متبقي ذهب لهذا التاجر', ink),
        pw.SizedBox(height: 16),
        pw.Text(
          'حسب الفئة والعيار',
          style: pw.TextStyle(color: primary, fontSize: 14),
        ),
        for (final bucket in trader.buckets)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              '${inventoryCategoryLabel(bucket.category)} عيار ${bucket.karat}: '
              'الأصل ${gramsOf(bucket.originalMilligrams)} جرام، '
              'الحالي ${gramsOf(bucket.currentMilligrams)} جرام'
              '${bucket.currentCount == null ? '' : '، العدد ${bucket.currentCount}'}',
              style: pw.TextStyle(color: ink, fontSize: 11),
            ),
          ),
        pw.SizedBox(height: 16),
        pw.Text(
          activityHasOlder
              ? 'النشاط أدناه أحدث ${activity.length} حركة فقط. توجد حركات أقدم ولم يكتمل الكشف.'
              : 'النشاط المحمّل ${activity.length} حركة. لا يوجد مؤشر لصفحة أقدم.',
          style: pw.TextStyle(color: primary, fontSize: 14),
        ),
        if (activity.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              'لا يوجد نشاط مؤكد في هذه الصفحة.',
              style: pw.TextStyle(color: ink),
            ),
          ),
        for (final line in activity)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 8),
            child: pw.Text(
              '${line.kind} — تسلسل ${line.shopSequence} — ${line.createdAt}',
              style: pw.TextStyle(color: ink, fontSize: 11),
            ),
          ),
        pw.SizedBox(height: 18),
        pw.Text(
          'هذا كشف محاسبي من الأرصدة المؤكدة. ليس سند ملكية ولا اعتماداً قانونياً. '
          'أمانة التاجر لا تدخل مخزون المحل المملوك ولا تفتح مستحقاً قبل نقل ملكية صريح.',
          style: pw.TextStyle(color: ink, fontSize: 10),
        ),
      ],
    ),
  );
  return document.save();
}

pw.Widget _line(String label, String value, PdfColor ink) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 6),
  child: pw.Row(
    children: [
      pw.Expanded(
        child: pw.Text(label, style: pw.TextStyle(color: ink, fontSize: 11)),
      ),
      pw.Text(value, style: pw.TextStyle(color: ink, fontSize: 11)),
    ],
  ),
);
