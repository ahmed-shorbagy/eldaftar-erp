import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:eldafttar/src/features/reports/data/report_codec.dart';
import 'package:eldafttar/src/features/reports/data/weekly_report_codec.dart';
import 'package:eldafttar/src/features/reports/presentation/report_pdf.dart';
import 'report_fixtures.dart';
import 'weekly_report_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Arabic weekly and daily PDFs render every representative page',
    () async {
      final samples = <String, Future<List<int>> Function()>{
        'weekly-empty': () => buildFinancialWeekPdf(
          parseFinancialWeekReport(
            consistentWeek(const [], endDate: '2026-10-22'),
          ),
        ),
        'weekly-categories': () =>
            buildFinancialWeekPdf(parseFinancialWeekReport(richWeek())),
        'weekly-long': () => buildFinancialWeekPdf(
          parseFinancialWeekReport(richWeek(extraExpenses: 40)),
        ),
        'weekly-same-date': () => buildFinancialWeekPdf(
          parseFinancialWeekReport(richWeek(duplicateDate: true)),
        ),
        'daily-complete': () => buildFinancialDayPdf(
          parseFinancialDayReport(reportFixture(sales: 12)),
        ),
        'daily-empty': () => buildFinancialDayPdf(
          parseFinancialDayReport(reportFixture(empty: true)),
        ),
      };
      for (final sample in samples.entries) {
        final bytes = await sample.value();
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        final pages = RegExp(
          r'/Type\s*/Page\b',
        ).allMatches(String.fromCharCodes(bytes)).length;
        expect(bytes.length, greaterThan(1000));
        expect(
          pages,
          sample.key == 'daily-empty'
              ? 1
              : sample.key == 'weekly-long' || sample.key == 'daily-complete'
              ? greaterThan(1)
              : greaterThan(0),
          reason: sample.key,
        );
        if (const bool.fromEnvironment('WEEKLY_REPORT_PDF')) {
          final file = File(
            '../docs/reviews/weekly-reports-2026-10-22/pdf/${sample.key}.pdf',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes);
          final python = await Process.run('python', [
            '-c',
            '''
import sys
import pypdfium2 as pdfium
document = pdfium.PdfDocument(sys.argv[1])
count = 0
for index, page in enumerate(document, start=1):
    image = page.render(scale=1.5).to_pil()
    image.save(f"{sys.argv[2]}-page-{index}.png")
    count += 1
if count < 1:
    raise SystemExit("no_pages")
print(count)
''',
            file.path,
            file.path.substring(0, file.path.length - 4),
          ]);
          expect(
            python.exitCode,
            0,
            reason: '${python.stdout}\n${python.stderr}',
          );
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
