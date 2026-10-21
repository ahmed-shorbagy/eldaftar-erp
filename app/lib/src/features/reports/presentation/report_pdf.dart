import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../theme/app_tokens.dart';
import '../../../theme/pdf_arabic.dart';
import '../domain/financial_day_report.dart';
import '../domain/financial_week_report.dart';

Future<Uint8List> buildFinancialDayPdf(FinancialDayReport report) =>
    _buildFinancialPdf(_ReportPdfSource(report, null));

Future<Uint8List> buildFinancialWeekPdf(FinancialWeekReport report) =>
    _buildFinancialPdf(_ReportPdfSource(null, report));

class _ReportPdfSource {
  const _ReportPdfSource(this.daily, this.weekly);
  final FinancialDayReport? daily;
  final FinancialWeekReport? weekly;
  String get shopName => weekly?.shopName ?? daily!.shopName;
  String get generatedAtShop =>
      weekly?.generatedAtShop ?? daily!.generatedAtShop;
  String get title =>
      weekly == null ? 'تقرير اليوم المالي' : 'التقرير الأسبوعي';
  String get period => weekly == null
      ? daily!.day.date
      : '${weekly!.startDate} / ${weekly!.endDate}';
  List<FinancialDayReport> get days => weekly?.days ?? [daily!];
  Iterable<ReportTransaction> get transactions =>
      days.expand((d) => d.transactions);
  List<ReportGold> get gold => weekly?.gold ?? daily!.gold;
  BigInt value(String key) => (weekly?.summary ?? daily!.summary)[key]!;
}

Future<Uint8List> _buildFinancialPdf(_ReportPdfSource report) async {
  final week = report.weekly;
  final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo.ttf'));
  PdfColor color(Color c) => PdfColor(c.r, c.g, c.b);
  final ink = color(AppTokens.lightOnSurface), accent = color(AppTokens.seed);
  final document = pw.Document(title: report.title, author: report.shopName);
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
  pw.Widget cell(String value, {bool digits = false}) => pw.Padding(
    padding: const pw.EdgeInsets.all(5),
    child: text(value, digits: digits),
  );
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      maxPages: report.transactions.fold<int>(
        20,
        (pages, t) =>
            pages +
            5 +
            t.items.length * 2 +
            t.inventory.length +
            t.description.length ~/ 160,
      ),
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: font, bold: font),
      header: (_) => pw.Column(
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              text(report.title, size: 16),
              pw.SizedBox(width: 280, child: text(report.shopName, size: 14)),
            ],
          ),
          pw.Divider(color: accent),
        ],
      ),
      footer: (c) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          text(report.period, digits: true),
          text('${c.pageNumber} / ${c.pagesCount}', digits: true),
        ],
      ),
      build: (_) => [
        if (week != null) ...[
          pair('من', week.startDate),
          pair('إلى، شاملًا', week.endDate),
          text(weeklyReportScope),
          if (week.containsOpenDay)
            text('الفترة تتضمن يومًا ماليًا مفتوحًا؛ الأرقام حتى وقت اللقطة.'),
        ] else ...[
          pair('اليوم المالي', report.daily!.day.date),
          pair('فتح اليوم حسب توقيت المتجر', report.daily!.day.openedAtShop),
          text(
            report.daily!.day.status == 'open'
                ? 'حالة اليوم: مفتوح — حتى وقت إعداد التقرير'
                : 'حالة اليوم: مغلق',
          ),
        ],
        pair('وقت إعداد اللقطة حسب توقيت المتجر', report.generatedAtShop),
        text(reportScope),
        pw.SizedBox(height: 10),
        text('الإجماليات بالجنيه', size: 14),
        for (final e in reportSummaryLabels.entries.where(
          (e) => !e.key.endsWith('count'),
        ))
          pair(e.value, reportMoney(report.value(e.key))),
        pw.Wrap(
          spacing: 12,
          runSpacing: 2,
          children: [
            for (final e in reportSummaryLabels.entries.where(
              (e) => e.key.endsWith('count'),
            ))
              pw.SizedBox(
                width: 250,
                child: pw.Row(
                  children: [
                    pw.Expanded(child: text(e.value)),
                    pw.SizedBox(
                      width: 35,
                      child: text(report.value(e.key).toString(), digits: true),
                    ),
                  ],
                ),
              ),
          ],
        ),
        pw.SizedBox(height: 10),
        text('الذهب بالجرام حسب العيار — صافٍ بعد المرتجعات', size: 13),
        pw.Table(
          border: pw.TableBorder.all(color: accent, width: .5),
          children: [
            pw.TableRow(
              repeat: true,
              children: [cell('المشترى'), cell('المباع'), cell('العيار')],
            ),
            for (final g in report.gold)
              pw.TableRow(
                children: [
                  cell(reportGrams(g.bought), digits: true),
                  cell(reportGrams(g.sold), digits: true),
                  cell('${g.karat}', digits: true),
                ],
              ),
          ],
        ),
        pw.SizedBox(height: 12),
        if (week != null) ...[
          text('التجميع حسب الصنف والعيار', size: 14),
          text(weeklyCategoryScope),
          text(
            'أعداد الحركات تشمل المرتجعات، وقد تظهر العملية في أكثر من صنف أو عيار.',
          ),
          if (week.groups.isEmpty)
            text('لا توجد حركة بيع أو شراء ذهب في هذه الفترة.')
          else
            pw.Table(
              border: pw.TableBorder.all(color: accent, width: .5),
              columnWidths: const {
                0: pw.FlexColumnWidth(),
                1: pw.FlexColumnWidth(),
                2: pw.FlexColumnWidth(1.6),
                3: pw.FlexColumnWidth(1.6),
                4: pw.FlexColumnWidth(.7),
                5: pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  repeat: true,
                  children: [
                    cell('حركات شراء'),
                    cell('حركات بيع'),
                    cell('المشترى'),
                    cell('المباع'),
                    cell('العيار'),
                    cell('الصنف'),
                  ],
                ),
                for (final g in week.groups)
                  pw.TableRow(
                    children: [
                      cell(g.purchaseMovements.toString(), digits: true),
                      cell(g.saleMovements.toString(), digits: true),
                      cell(reportGrams(g.bought), digits: true),
                      cell(reportGrams(g.sold), digits: true),
                      cell('${g.karat}', digits: true),
                      cell(reportCategory(g.category)),
                    ],
                  ),
              ],
            ),
          pw.SizedBox(height: 12),
        ],
        text('السجل الكامل الداعم للإجماليات', size: 14),
        if (report.transactions.isEmpty)
          text(
            report.weekly == null
                ? 'لا توجد عمليات لهذا اليوم المالي.'
                : 'لا توجد عمليات لهذه الفترة.',
          ),
        for (final day in report.days) ...[
          if (report.weekly != null) ...[
            pw.NewPage(freeSpace: 180),
            pair('اليوم المالي', day.day.date),
            pair('فتح اليوم', day.day.openedAtShop),
            text(day.day.status == 'open' ? 'اليوم مفتوح' : 'اليوم مغلق'),
            pair('صافي المبيعات', reportMoney(day.value('net_sales'))),
            pair('صافي المشتريات', reportMoney(day.value('net_purchases'))),
            pair('المصروفات', reportMoney(day.value('expenses'))),
            pair('صافي حركة النقد', reportMoney(day.value('net_cash'))),
            if (day.transactions.isEmpty)
              text('لا توجد عمليات لهذا اليوم المالي.'),
          ],
          for (final t in day.transactions) ...[
            pw.NewPage(freeSpace: 160),
            pw.Table(
              columnWidths: const {0: pw.FlexColumnWidth()},
              children: [
                pw.TableRow(
                  repeat: true,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                      children: [
                        pw.Divider(color: accent),
                        text(t.label, size: 12),
                        if (report.weekly != null)
                          pair('اليوم المالي', day.day.date),
                        pair('رقم العملية', t.sequence),
                        pair('توقيت المتجر', t.atShop),
                        text(t.stateLabel),
                      ],
                    ),
                  ],
                ),
                for (final part in <pw.Widget>[
                  if (t.sourceId != null) ...[
                    text('مرجع العملية الأصلية'),
                    text(t.sourceId!, digits: true, size: 8),
                  ],
                  for (
                    var start = 0;
                    start < t.description.length;
                    start += 160
                  )
                    text(
                      t.description.substring(
                        start,
                        (start + 160).clamp(0, t.description.length),
                      ),
                    ),
                  pair('قيمة العملية الأصلية', reportMoney(t.originalTotal)),
                  pair('مساهمة صافي المبيعات', reportMoney(t.sale)),
                  pair('مساهمة صافي المشتريات', reportMoney(t.purchase)),
                  pair('المصروف', reportMoney(t.expense)),
                  pair('حركة النقد', reportMoney(t.cash)),
                  if (t.kind == 'opening_balances')
                    pair(
                      'الرصيد الافتتاحي المستبعد من الحركة',
                      reportMoney(t.openingCash),
                    ),
                  for (final m in t.methods.entries)
                    pair(reportMethod(m.key), reportMoney(m.value)),
                  for (final i in t.items) ...[
                    text(i.name.isEmpty ? 'ذهب' : i.name),
                    pair('العيار', i.karat.toString()),
                    pair('الوزن الأصلي بالجرام', reportGrams(i.milligrams)),
                    pair('مساهمة المباع بالجرام', reportGrams(i.sold)),
                    pair('مساهمة المشترى بالجرام', reportGrams(i.bought)),
                  ],
                  for (final g in t.inventory.entries) ...[
                    pair('عيار حركة المخزون', g.key.toString()),
                    pair('تغير المخزون بالجرام', reportGrams(g.value)),
                  ],
                ])
                  pw.TableRow(children: [part]),
              ],
            ),
          ],
        ],
      ],
    ),
  );
  return document.save();
}
