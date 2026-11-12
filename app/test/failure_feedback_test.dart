import 'package:eldafttar/src/theme/app_confirm.dart';
import 'package:eldafttar/src/theme/app_outcome.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:eldafttar/src/theme/failure_feedback.dart';
import 'package:eldafttar/src/theme/message_tone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('gateway codes map to one failure kind each', () {
    expect(failureKindFor(null), FailureKind.unexpected);
    expect(failureKindFor('session_expired'), FailureKind.accessLost);
    expect(failureKindFor('unauthenticated'), FailureKind.accessLost);
    expect(failureKindFor('forbidden'), FailureKind.accessLost);
    expect(failureKindFor('shop_not_active'), FailureKind.readOnly);
    expect(failureKindFor('entitlement_status'), FailureKind.readOnly);
    expect(failureKindFor('stale_day'), FailureKind.stale);
    expect(failureKindFor('stale_repair'), FailureKind.stale);
    expect(failureKindFor('unavailable'), FailureKind.offline);
    expect(failureKindFor('rpc_unavailable'), FailureKind.offline);
    expect(failureKindFor('storage'), FailureKind.deviceStorage);
    expect(failureKindFor('day_closed'), FailureKind.rejected);
    expect(failureKindFor('insufficient_lot'), FailureKind.rejected);
  });

  test('each kind has a tone, Arabic copy and the right next action', () {
    for (final kind in FailureKind.values) {
      final feedback = failureFeedback(kind);
      expect(feedback.title, isNotEmpty, reason: '$kind');
      expect(
        RegExp('[A-Za-z!]').hasMatch(
          '${feedback.title}${feedback.body ?? ''}${feedback.actionLabel ?? ''}',
        ),
        isFalse,
        reason: '$kind copy must be Arabic without exclamation marks',
      );
    }
    expect(failureFeedback(FailureKind.offline).actionLabel, 'إعادة المحاولة');
    expect(
      failureFeedback(FailureKind.unknownOutcome).actionLabel,
      'إعادة المحاولة',
    );
    expect(failureFeedback(FailureKind.rejected).actionLabel, isNull);
    expect(failureFeedback(FailureKind.rejected).body, 'لم يُحفظ شيء.');
    expect(failureTone('stale_day'), MessageTone.warning);
    expect(failureTone('day_closed'), MessageTone.error);
    expect(failureTone('storage'), MessageTone.info);
  });

  test('a feature reason replaces the generic title', () {
    final feedback = failureFeedback(
      FailureKind.rejected,
      reason: 'يوم العمل مغلق',
    );
    expect(feedback.title, 'يوم العمل مغلق');
    expect(feedback.tone, MessageTone.error);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'confirm dialog: safe default, Back is cancel (${dark ? 'dark' : 'light'})',
      (tester) async {
        bool? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    key: const Key('ask'),
                    onPressed: () async => result = await showAppConfirm(
                      context,
                      title: 'مسح الملاحظة؟',
                      message: 'ستختفي الملاحظة من الدفتر.',
                      confirmLabel: 'مسح الملاحظة',
                      destructive: true,
                    ),
                    child: const Text('ask'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('ask')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('app-confirm')), findsOneWidget);
        final cancel = tester.widget<OutlinedButton>(
          find.byType(OutlinedButton),
        );
        expect(cancel.autofocus, isTrue);
        final confirm = tester.widget<FilledButton>(find.byType(FilledButton));
        final scheme = (dark ? AppTheme.dark() : AppTheme.light()).colorScheme;
        expect(
          confirm.style!.backgroundColor!.resolve(<WidgetState>{}),
          scheme.error,
        );
        await tester.binding.handlePopRoute();
        await tester.pumpAndSettle();
        expect(result, isFalse);

        await tester.tap(find.byKey(const Key('ask')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('مسح الملاحظة'));
        await tester.pumpAndSettle();
        expect(result, isTrue);
      },
    );
  }

  testWidgets('outcome screen names the result and lists confirmed figures', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320 * 3, 700 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 700),
              textScaler: TextScaler.linear(1.7),
            ),
            child: Scaffold(
              body: ListView(
                children: const [
                  AppOutcome(
                    title: 'تم حفظ البيع',
                    titleKey: Key('outcome-title'),
                    subtitle: 'أكد الخادم الحفظ وتحدّثت الأرصدة.',
                    figures: [
                      OutcomeFigure('الإجمالي', '1,250,000'),
                      OutcomeFigure(
                        'خواتم 18 · عيار 18',
                        '10.50 جرام (10,503 ملليجرام)',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('outcome-title')), findsOneWidget);
    expect(find.text('1,250,000'), findsOneWidget);
    expect(find.text('الإجمالي'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
