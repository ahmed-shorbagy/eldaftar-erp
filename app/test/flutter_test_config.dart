// Layout sweep for the whole widget suite.
//
// A normal `flutter test` is unchanged. With
// `--dart-define=LAYOUT_SWEEP=1.3` every test runs with the shop's Cairo font
// and the phone font enlarged to that scale, so a row or column that does not
// fit is reported by Flutter as an overflow, naming its file and line. Run it
// after a layout change and read the overflow reports, not the pass count:
// functional tests may fail at a larger font for unrelated reasons.

import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _sweep = String.fromEnvironment('LAYOUT_SWEEP');

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  if (_sweep.isEmpty) return testMain();
  final scale = double.parse(_sweep);
  TestWidgetsFlutterBinding.ensureInitialized();
  final font = File('assets/fonts/Cairo.ttf').readAsBytesSync();
  await (FontLoader(
    'Cairo',
  )..addFont(Future.value(ByteData.sublistView(font)))).load();
  setUp(() {
    TestWidgetsFlutterBinding
            .instance
            .platformDispatcher
            .textScaleFactorTestValue =
        scale;
  });
  await testMain();
}
