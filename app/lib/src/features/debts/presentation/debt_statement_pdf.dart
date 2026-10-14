import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../../theme/app_tokens.dart';
import '../domain/debt_rules.dart';
import '../domain/debt_statement.dart';
import 'debt_copy.dart';

const statementScope =
    'لقطة محاسبية مؤكدة لدين واحد مع سجله الكامل؛ ليست فاتورة أو إيصال سداد أو إقرارًا قانونيًا.';
String statementGold(BigInt n) {
  final a = n.abs();
  final whole = (a ~/ BigInt.from(1000)).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${n.isNegative ? '-' : ''}$whole.${(a % BigInt.from(1000)).toString().padLeft(3, '0')}';
}

String statementAmount(DebtStatement s, BigInt n) => s.unit == DebtUnit.money
    ? debtMoney(n)
    : '\u2066${statementGold(n)}\u2069 جرام';
String statementSource(DebtSourceKind kind) => switch (kind) {
  DebtSourceKind.standalone => 'دين مستقل',
  DebtSourceKind.purchaseCashPayable => 'رصيد شراء آجل',
  DebtSourceKind.goldObligation => 'التزام ذهب',
};

Future<Uint8List> buildDebtStatementPdf(DebtStatement s) async {
  s.validate();
  final font = pw.Font.ttf(await rootBundle.load('assets/fonts/Cairo.ttf'));
  PdfColor color(Color c) => PdfColor(c.r, c.g, c.b);
  final ink = color(AppTokens.lightOnSurface),
      accent = color(AppTokens.seed),
      paper = color(AppTokens.lightSurface);
  final document = pw.Document(title: 'كشف حساب دين', author: s.shopName);
  pw.Widget text(String value, {bool ltr = false, double size = 10}) => pw.Text(
    value.replaceAll(RegExp('[\u2066-\u2069]'), ''),
    textDirection: ltr ? pw.TextDirection.ltr : pw.TextDirection.rtl,
    style: pw.TextStyle(fontSize: size, color: ink),
  );
  pw.Widget line(String label, String value, {bool ltr = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(width: 100, child: text(label)),
        pw.Expanded(child: text(value, ltr: ltr)),
      ],
    ),
  );
  pw.Widget cell(String value, {bool ltr = false}) => pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: text(value, ltr: ltr),
  );
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      maxPages: s.history.length + 10,
      textDirection: pw.TextDirection.rtl,
      theme: pw.ThemeData.withFont(base: font, bold: font),
      header: (_) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            text('كشف حساب دين', size: 16),
            text(s.shopName, size: 14),
          ],
        ),
      ),
      footer: (c) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            text('دين واحد • سجل كامل', size: 9),
            text('${c.pageNumber} / ${c.pagesCount}', ltr: true, size: 9),
          ],
        ),
      ),
      build: (_) => [
        text(statementScope),
        pw.SizedBox(height: 10),
        if (s.shopPhone != null) line('هاتف المحل', s.shopPhone!, ltr: true),
        line('الطرف', s.partyName),
        if (s.contactPhone != null)
          line('الهاتف المسجل', s.contactPhone!, ltr: true),
        line('المصدر', statementSource(s.sourceKind)),
        line(
          s.sourceSequence == null ? 'هوية الدين' : 'رقم عملية المصدر',
          s.sourceSequence ?? s.sourceId,
          ltr: true,
        ),
        line('الاتجاه', debtDirectionLabels[s.direction]!),
        line(
          'الوحدة',
          s.unit == DebtUnit.money ? 'نقد' : 'ذهب • عيار ${s.karat}',
        ),
        line('الحالة', debtStatusLabels[s.status]!),
        line('السبب', s.reason),
        if (s.reference != null) line('المرجع المسجل', s.reference!),
        line(
          'وقت اللقطة بالمحل',
          s.snapshotAtShop.replaceFirst('T', ' '),
          ltr: true,
        ),
        line('المنطقة الزمنية', s.timeZone, ltr: true),
        line('وقت الخادم UTC', s.snapshotAt.toIso8601String(), ltr: true),
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          color: paper,
          child: pw.Column(
            children: [
              line(
                s.sourceKind == DebtSourceKind.purchaseCashPayable
                    ? 'أصل الدين الآجل'
                    : 'الأصل',
                statementAmount(s, s.original),
              ),
              line('المسدد فعليًا', statementAmount(s, s.settled)),
              line('الملغى', statementAmount(s, s.cancelled)),
              line('المتبقي', statementAmount(s, s.remaining)),
            ],
          ),
        ),
        if (s.sourceKind == DebtSourceKind.purchaseCashPayable)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6),
            child: text(
              'أصل الدين هو المتبقي عند الشراء؛ لا يشمل كامل ثمن الشراء أو النقد المدفوع وقتها. إلغاء المرتجع منفصل عن السداد.',
            ),
          ),
        pw.SizedBox(height: 12),
        text('السجل الكامل', size: 14),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: accent, width: .5),
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FlexColumnWidth(4),
            2: const pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              repeat: true,
              decoration: pw.BoxDecoration(color: paper),
              children: [
                cell('وقت المحل'),
                cell('الحدث والمالك'),
                cell('المبلغ أو الوزن'),
              ],
            ),
            for (final e in s.history)
              pw.TableRow(
                children: [
                  cell(e.atShop.replaceFirst('T', ' '), ltr: true),
                  cell(
                    '${e.label}\n${e.actorName}${e.actorNameCurrent ? ' (الاسم الحالي)' : ''}'
                    '${e.reason == null ? '' : '\n${e.reason}'}'
                    '${e.type == DebtStatementEventType.settled && !e.movesLedger ? '\nسداد بلا حركة في دفتر المحل' : ''}',
                  ),
                  cell(
                    '${e.type == DebtStatementEventType.archived
                        ? 'أرشفة؛ الرصيد محفوظ'
                        : e.cancelled > BigInt.zero
                        ? 'إلغاء: ${statementAmount(s, e.cancelled)}'
                        : statementAmount(s, e.amount)}'
                    '${e.cash == BigInt.zero ? '' : '\nالنقد: ${debtMoney(e.cash)}'}'
                    '${e.gold == BigInt.zero ? '' : '\nالذهب: \u2066${statementGold(e.gold)}\u2069 جرام'}',
                  ),
                ],
              ),
          ],
        ),
      ],
    ),
  );
  return document.save();
}
