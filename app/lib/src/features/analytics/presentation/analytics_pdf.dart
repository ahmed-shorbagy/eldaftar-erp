import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../theme/app_tokens.dart';
import '../../../theme/pdf_arabic.dart';
import '../../reports/domain/financial_day_report.dart';
import '../domain/period_analytics.dart';

Future<Uint8List> buildPeriodAnalyticsPdf(PeriodAnalytics report) async {
  final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo.ttf'));
  PdfColor color(Color c) => PdfColor(c.r, c.g, c.b);
  final ink = color(AppTokens.lightOnSurface);
  final document = pw.Document(title: 'التحليلات', author: report.shopName);
  pw.Widget text(String value, {bool digits = false, double size = 10}) =>
      pdfText(
        value,
        textDirection: digits ? pw.TextDirection.ltr : pw.TextDirection.rtl,
        style: pw.TextStyle(fontSize: size, color: ink),
      );
  pw.Widget pair(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 1),
    child: pw.Row(
      children: [
        pw.Expanded(child: text(label)),
        pw.SizedBox(width: 140, child: text(value, digits: true)),
      ],
    ),
  );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      maxPages: 40,
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: font, bold: font),
      header: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          text('التحليلات', size: 16),
          text(report.shopName, size: 14),
          text(
            '${analyticsPeriodLabel(report.periodKind)}: ${report.startDate} / ${report.endDate}',
            digits: true,
          ),
          text('وقت اللقطة ${report.generatedAtShop}', digits: true),
          pw.Divider(),
        ],
      ),
      build: (_) => [
        text(analyticsScope),
        pw.SizedBox(height: 8),
        text(
          report.containsOpenDay
              ? 'تشمل الفترة يومًا ماليًا مفتوحًا.'
              : 'كل الأيام المالية في الفترة مغلقة أو لا يوجد يوم مفتوح.',
        ),
        text('عدد الأيام المالية ${report.dayCount}', digits: true),
        pw.SizedBox(height: 12),
        text('النقد والعمليات', size: 12),
        for (final entry in reportSummaryLabels.entries)
          pair(entry.value, reportMoney(report.value(entry.key))),
        pw.SizedBox(height: 12),
        text('الأوزان حسب العيار', size: 12),
        for (final g in report.gold)
          pair(
            'عيار ${g.karat}',
            'مبيع ${reportGrams(g.sold)} / مشترى ${reportGrams(g.bought)}',
          ),
        if (report.isOwner) ...[
          pw.SizedBox(height: 12),
          text('أوزان الموظفين والمستخدمين', size: 12),
          if (report.actors.isEmpty)
            text('لا توجد أوزان بيع أو شراء مربوطة بمستخدم في هذه الفترة.')
          else
            for (final actor in report.actors) ...[
              text(actor.displayName, size: 11),
              pair(
                'الإجمالي',
                'مبيع ${reportGrams(actor.soldTotal)} / مشترى ${reportGrams(actor.boughtTotal)}',
              ),
              for (final g in actor.gold)
                if (g.sold != BigInt.zero || g.bought != BigInt.zero)
                  pair(
                    'عيار ${g.karat}',
                    'مبيع ${reportGrams(g.sold)} / مشترى ${reportGrams(g.bought)}',
                  ),
              pw.SizedBox(height: 6),
            ],
        ],
      ],
    ),
  );
  return document.save();
}
