import 'dart:io';

import 'package:eldafttar/src/theme/app_banner.dart';
import 'package:eldafttar/src/theme/app_messages.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:eldafttar/src/theme/message_tone.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({
  required void Function(BuildContext) onPressed,
  ThemeData? theme,
  double textScale = 1,
  bool accessibleNavigation = false,
  Widget? bottomBar,
}) {
  return MaterialApp(
    theme: theme ?? AppTheme.light(),
    builder: (context, child) => Directionality(
      textDirection: TextDirection.rtl,
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          accessibleNavigation: accessibleNavigation,
        ),
        child: child!,
      ),
    ),
    home: Builder(
      builder: (context) => Scaffold(
        bottomNavigationBar: bottomBar,
        body: Center(
          child: Builder(
            builder: (inner) => FilledButton(
              key: const Key('raise'),
              onPressed: () => onPressed(inner),
              child: const Text('raise'),
            ),
          ),
        ),
      ),
    ),
  );
}

Finder get _toast => find.byKey(const Key('app-toast'));

void main() {
  test('only AppMessages builds snack bars in lib/', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (path.endsWith('lib/src/theme/app_messages.dart')) continue;
      final source = entity.readAsStringSync();
      if (RegExp(
        r'showSnackBar\(|\bSnackBar\(|SnackBarAction\(',
      ).hasMatch(source)) {
        offenders.add(path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Use AppMessages (toast) or AppBanner instead of raw snack bars.',
    );
  });

  test('toast duration follows tone, length and action', () {
    expect(
      AppMessages.durationFor(MessageTone.success, 'تم', null),
      const Duration(seconds: 4),
    );
    expect(
      AppMessages.durationFor(MessageTone.info, 'تنبيه', null),
      const Duration(seconds: 5),
    );
    expect(
      AppMessages.durationFor(MessageTone.error, 'خطأ', null),
      const Duration(seconds: 6),
    );
    expect(
      AppMessages.durationFor(MessageTone.success, 'تم', null, hasAction: true),
      const Duration(seconds: 8),
    );
    final long = 'ن' * 80;
    expect(
      AppMessages.durationFor(MessageTone.success, long, null),
      const Duration(milliseconds: 5000),
    );
    expect(
      AppMessages.durationFor(MessageTone.error, 'ن' * 400, null),
      const Duration(seconds: 10),
    );
  });

  testWidgets('a success toast shows, then dismisses itself after 4 s', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(onPressed: (c) => AppMessages.success(c, 'تم حفظ البيع')),
    );
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pumpAndSettle();
    expect(_toast, findsOneWidget);
    expect(find.text('تم حفظ البيع'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 3900));
    expect(_toast, findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(_toast, findsNothing);
  });

  testWidgets('pressing the toast pauses its timer', (tester) async {
    await tester.pumpWidget(
      _host(onPressed: (c) => AppMessages.success(c, 'تم حفظ البيع')),
    );
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('app-toast-title'))),
    );
    await tester.pump(const Duration(seconds: 10));
    expect(_toast, findsOneWidget);
    await gesture.up();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(_toast, findsNothing);
  });

  testWidgets('the close button dismisses the toast', (tester) async {
    await tester.pumpWidget(
      _host(onPressed: (c) => AppMessages.info(c, 'تنبيه')),
    );
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pumpAndSettle();
    expect(find.byTooltip('إغلاق الرسالة'), findsOneWidget);
    await tester.tap(find.byKey(const Key('app-toast-close')));
    await tester.pumpAndSettle();
    expect(_toast, findsNothing);
  });

  testWidgets('the action runs once and closes the toast', (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      _host(
        onPressed: (c) => AppMessages.error(
          c,
          'لم يصل رد الخادم',
          actionLabel: 'إعادة المحاولة',
          onAction: () => retries += 1,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('إعادة المحاولة'));
    await tester.pumpAndSettle();
    expect(retries, 1);
    expect(_toast, findsNothing);
  });

  testWidgets('toasts do not auto-dismiss under a screen reader', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        accessibleNavigation: true,
        onPressed: (c) => AppMessages.success(c, 'تم حفظ البيع'),
      ),
    );
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 30));
    expect(_toast, findsOneWidget);
    await tester.tap(find.byKey(const Key('app-toast-close')));
    await tester.pumpAndSettle();
    expect(_toast, findsNothing);
  });

  testWidgets('identical toasts within 3 s merge into one', (tester) async {
    await tester.pumpWidget(
      _host(onPressed: (c) => AppMessages.success(c, 'تم مسح الملاحظة')),
    );
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pumpAndSettle();
    expect(find.text('تم مسح الملاحظة'), findsOneWidget);
    await tester.tap(find.byKey(const Key('app-toast-close')));
    await tester.pumpAndSettle();
    expect(_toast, findsNothing, reason: 'nothing was queued behind it');
  });

  testWidgets('a newer toast with the same id replaces the visible one', (
    tester,
  ) async {
    var count = 0;
    await tester.pumpWidget(
      _host(
        onPressed: (c) {
          count += 1;
          AppMessages.warning(c, 'محاولة $count', id: 'same-event');
        },
      ),
    );
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pumpAndSettle();
    expect(find.text('محاولة 1'), findsNothing);
    expect(find.text('محاولة 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('app-toast-close')));
    await tester.pumpAndSettle();
    expect(_toast, findsNothing);
  });

  testWidgets('different toasts queue and show one at a time', (tester) async {
    var count = 0;
    await tester.pumpWidget(
      _host(
        onPressed: (c) {
          count += 1;
          AppMessages.info(c, 'رسالة $count');
        },
      ),
    );
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pumpAndSettle();
    expect(_toast, findsOneWidget);
    expect(find.text('رسالة 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('app-toast-close')));
    await tester.pumpAndSettle();
    expect(find.text('رسالة 2'), findsOneWidget);
  });

  testWidgets('clear removes the visible and queued toasts', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      _host(
        onPressed: (c) {
          captured = c;
          AppMessages.info(c, 'أولى');
          AppMessages.info(c, 'ثانية');
        },
      ),
    );
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pumpAndSettle();
    expect(_toast, findsOneWidget);
    AppMessages.clear(captured);
    await tester.pumpAndSettle();
    expect(_toast, findsNothing);
    await tester.pump(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(_toast, findsNothing);
  });

  testWidgets('a toast raised before a route pops shows on the destination', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        onPressed: (c) => Navigator.of(c).push(
          MaterialPageRoute<void>(
            builder: (route) => Scaffold(
              body: Center(
                child: TextButton(
                  key: const Key('save-and-pop'),
                  onPressed: () {
                    AppMessages.success(route, 'تم إقفال يوم العمل');
                    Navigator.of(route).pop();
                  },
                  child: const Text('save'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-and-pop')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('save-and-pop')), findsNothing);
    expect(find.text('تم إقفال يوم العمل'), findsOneWidget);
  });

  testWidgets('the toast floats above the bottom navigation bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        bottomBar: const SizedBox(key: Key('nav'), height: 80),
        onPressed: (c) => AppMessages.success(c, 'تم حفظ البيع'),
      ),
    );
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pumpAndSettle();
    final toast = tester.getRect(_toast);
    final nav = tester.getRect(find.byKey(const Key('nav')));
    expect(toast.bottom, lessThanOrEqualTo(nav.top));
  });

  for (final dark in [false, true]) {
    testWidgets(
      'every tone renders at 200 % text in ${dark ? 'dark' : 'light'}',
      (tester) async {
        tester.view.physicalSize = const Size(375 * 3, 812 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        for (final tone in MessageTone.values) {
          await tester.pumpWidget(
            _host(
              theme: dark ? AppTheme.dark() : AppTheme.light(),
              textScale: 2,
              onPressed: (c) => AppMessages.show(
                c,
                tone: tone,
                title: 'تعذر حفظ تخصيص الدفتر على هذا الجهاز',
                body: 'يسري اختيارك في هذه الجلسة فقط.',
                actionLabel: 'إعادة المحاولة',
                onAction: () {},
              ),
            ),
          );
          await tester.tap(find.byKey(const Key('raise')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$tone overflowed');
          expect(_toast, findsOneWidget);
          AppMessages.clear(tester.element(find.byKey(const Key('raise'))));
          await tester.pumpAndSettle();
        }
      },
    );
  }

  testWidgets('on wide layouts the toast sits in the start (right) corner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(onPressed: (c) => AppMessages.success(c, 'تم حفظ البيع')),
    );
    await tester.tap(find.byKey(const Key('raise')));
    await tester.pumpAndSettle();
    final rect = tester.getRect(_toast);
    expect(rect.width, closeTo(480, 1));
    expect(rect.right, closeTo(1280 - 24, 1));
  });

  testWidgets('AppBanner shows its tone, title key and single action', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Column(
              children: [
                AppBanner(
                  tone: MessageTone.error,
                  title: 'تعذر حفظ الشراء',
                  message: 'لم يُسجَّل شيء.',
                  titleKey: const Key('banner-title'),
                  actionLabel: 'إعادة المحاولة',
                  onAction: () => taps += 1,
                ),
                const AppBanner(
                  tone: MessageTone.pending,
                  title: 'بانتظار تأكيد الحفظ',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('banner-title')), findsOneWidget);
    expect(find.text('لم يُسجَّل شيء.'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('إعادة المحاولة'));
    expect(taps, 1);
  });

  test('message colours come from the theme scheme for every tone', () {
    for (final theme in [AppTheme.light(), AppTheme.dark()]) {
      final scheme = theme.colorScheme;
      expect(
        MessageColors.of(scheme, MessageTone.success).accent,
        scheme.tertiary,
      );
      expect(MessageColors.of(scheme, MessageTone.error).accent, scheme.error);
      expect(
        MessageColors.of(scheme, MessageTone.info).container,
        scheme.surfaceContainerHigh,
      );
      for (final tone in MessageTone.values) {
        final colors = MessageColors.of(scheme, tone);
        expect(
          _contrast(colors.onContainer, colors.container),
          greaterThanOrEqualTo(4.5),
          reason: '$tone text contrast in ${scheme.brightness}',
        );
      }
    }
  });
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}
