import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:eldafttar/src/features/reports/data/report_codec.dart';
import 'package:eldafttar/src/features/reports/presentation/report_pdf.dart';
import 'report_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Arabic financial-day PDF renders complete multi-page transactions and empty report',
    () async {
      for (final sample in ['complete', 'empty']) {
        final report = parseFinancialDayReport(
          reportFixture(empty: sample == 'empty', sales: 12),
        );
        final bytes = await buildFinancialDayPdf(report);
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        final pages = RegExp(
          r'/Type\s*/Page\b',
        ).allMatches(String.fromCharCodes(bytes)).length;
        expect(pages, sample == 'empty' ? equals(1) : greaterThan(1));
        if (const bool.fromEnvironment('REPORT_PDF')) {
          final file = File('build/reports/pdf/$sample.pdf');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes);
        }
      }
    },
  );
}
