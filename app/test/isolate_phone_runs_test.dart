import 'package:eldafttar/src/theme/amount_format.dart';
import 'package:flutter_test/flutter_test.dart';

// Regression (2026-11-11 device pass): the automatic customer name
// «عميل +201001234567» rendered as «عميل 201001234567+» in an RTL line.
void main() {
  test('a phone run inside an Arabic name stays left to right', () {
    expect(
      isolatePhoneRuns('عميل +201001234567'),
      'عميل \u2066+201001234567\u2069',
    );
  });

  test('names without digits are unchanged', () {
    expect(isolatePhoneRuns('أحمد محمود'), 'أحمد محمود');
    expect(isolatePhoneRuns('Test Buyer'), 'Test Buyer');
  });

  test('Arabic-Indic digits and grouped numbers are one run', () {
    expect(isolatePhoneRuns('عميل ٠١٠١٢٣'), 'عميل \u2066٠١٠١٢٣\u2069');
    expect(
      isolatePhoneRuns('عميل +20 100 123'),
      'عميل \u2066+20 100 123\u2069',
    );
  });
}
