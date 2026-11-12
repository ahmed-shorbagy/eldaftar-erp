import 'package:eldafttar/src/features/daily_ledger/presentation/ledger_form_fields.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// U15 (device pass 2026-11-11): on day close the number pad's ✓ moved focus
// into the next cell, and tapping outside a cell kept the keyboard open.
void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Column(
              children: [
                ClosingCountCell(
                  fieldKey: const Key('cell-a'),
                  controller: TextEditingController(),
                  semanticsLabel: 'عدد خواتم عيار 21',
                ),
                ClosingCountCell(
                  fieldKey: const Key('cell-b'),
                  controller: TextEditingController(),
                  semanticsLabel: 'عدد سلاسل عيار 21',
                ),
                const SizedBox(key: Key('outside'), height: 200),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool focused(WidgetTester tester, String key) => tester
      .widget<EditableText>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(EditableText),
        ),
      )
      .focusNode
      .hasFocus;

  testWidgets('✓ closes the keyboard and does not focus the next cell', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('cell-a')));
    await tester.enterText(find.byKey(const Key('cell-a')), '3');
    expect(
      tester.widget<TextField>(find.byKey(const Key('cell-a'))).textInputAction,
      TextInputAction.done,
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(focused(tester, 'cell-a'), isFalse);
    expect(focused(tester, 'cell-b'), isFalse);
  });

  testWidgets('tapping outside a cell closes the keyboard', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('cell-a')));
    await tester.pump();
    expect(focused(tester, 'cell-a'), isTrue);
    await tester.tapAt(tester.getCenter(find.byKey(const Key('outside'))));
    await tester.pumpAndSettle();
    expect(focused(tester, 'cell-a'), isFalse);
  });
}
