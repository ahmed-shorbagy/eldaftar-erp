import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:integration_test/integration_test.dart';
import '../test/ledger_compensation_workflow_test.dart' as review;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });
  for (final brightness in Brightness.values) {
    for (final flow in ['partial', 'correction', 'exchange']) {
      testWidgets('native $flow ${brightness.name}', (tester) async {
        final gateway = review.CompensationReviewGateway();
        await tester.pumpWidget(
          review.reviewHost(
            flow == 'correction'
                ? review.correction(gateway)
                : review.partial(gateway),
            brightness: brightness,
          ),
        );
        await tester.pumpAndSettle();
        if (flow == 'correction') {
          await review.enter(tester, 'correction-reason', 'فرق العد');
          await review.tap(tester, 'correction-review');
        } else if (flow == 'exchange') {
          await review.prepareExchange(tester);
        } else {
          await review.preparePartial(tester);
        }
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('compensation-capture')),
        );
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        // ignore: avoid_print
        print(
          'COMPENSATION_REVIEW_BASE64 $flow-${brightness.name} ${base64Encode(bytes!.buffer.asUint8List())}',
        );
        await review.tap(
          tester,
          flow == 'correction'
              ? 'correction-confirm'
              : flow == 'exchange'
              ? 'trade-confirm'
              : 'partial-confirm',
        );
        expect(gateway.bodies, hasLength(1));
        expect(tester.takeException(), isNull);
      });
    }
  }
}
