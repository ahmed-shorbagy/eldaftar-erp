import 'dart:async';

import 'package:eldafttar/src/features/support/domain/support_models.dart';
import 'package:eldafttar/src/features/support/presentation/support_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSupportGateway implements SupportGateway {
  FakeSupportGateway({List<SupportInquiry>? initial, List<SupportInquiry>? older})
    : inquiries = initial ?? <SupportInquiry>[],
      older = older ?? const <SupportInquiry>[];

  List<SupportInquiry> inquiries;
  List<SupportInquiry> older;
  SupportFailure? createFailure;
  SupportFailure? listFailure;

  final List<String> createKeys = [];
  final List<SupportCategory?> createCategories = [];
  final List<String> createBodies = [];
  int listCalls = 0;
  bool moreAvailable = false;
  bool replayNext = false;
  Future<SupportSaveResult> Function(String key)? gatedCreate;

  @override
  Future<SupportSaveResult> createInquiry({
    required String key,
    required SupportCategory? category,
    required String bodyAr,
  }) async {
    createKeys.add(key);
    createCategories.add(category);
    createBodies.add(bodyAr);
    final gated = gatedCreate;
    if (gated != null) return gated(key);
    if (createFailure != null) throw SupportException(createFailure!);
    final inquiry = SupportInquiry(
      id: 'inq-${createKeys.length}',
      category: category,
      bodyAr: bodyAr,
      status: SupportInquiryStatus.fresh,
      replyAr: null,
      createdAt: DateTime.utc(2026, 10, 27, 12),
      updatedAt: DateTime.utc(2026, 10, 27, 12),
      answeredAt: null,
      closedAt: null,
    );
    inquiries = [inquiry, ...inquiries];
    final replayed = replayNext;
    replayNext = false;
    return SupportSaveResult(inquiry: inquiry, replayed: replayed);
  }

  @override
  Future<SupportInquiryPage> listInquiries({
    DateTime? cursorAt,
    String? cursorId,
    int pageSize = 20,
  }) async {
    listCalls++;
    if (listFailure != null) throw SupportException(listFailure!);
    if (cursorId != null) {
      return SupportInquiryPage(
        inquiries: List.of(older),
        nextCursorAt: null,
        nextCursorId: null,
        openCount: inquiries.length,
        openLimit: 10,
        timeZone: 'Africa/Cairo',
        snapshotAt: DateTime.utc(2026, 10, 27, 12, 30),
      );
    }
    return SupportInquiryPage(
      inquiries: List.of(inquiries),
      nextCursorAt: moreAvailable ? DateTime.utc(2026, 10, 26, 12) : null,
      nextCursorId: moreAvailable ? 'cursor-older' : null,
      openCount: inquiries.length,
      openLimit: 10,
      timeZone: 'Africa/Cairo',
      snapshotAt: DateTime.utc(2026, 10, 27, 12, 30),
    );
  }
}

SupportInquiry inquiryOf(
  String id, {
  SupportCategory? category,
  SupportInquiryStatus status = SupportInquiryStatus.fresh,
  String? replyAr,
}) => SupportInquiry(
  id: id,
  category: category,
  bodyAr: 'نص الاستفسار رقم $id مع تفاصيل كافية',
  status: status,
  replyAr: replyAr,
  createdAt: DateTime.utc(2026, 10, 27, 12),
  updatedAt: DateTime.utc(2026, 10, 27, 12),
  answeredAt: status == SupportInquiryStatus.answered || replyAr != null
      ? DateTime.utc(2026, 10, 27, 13)
      : null,
  closedAt: status == SupportInquiryStatus.closed
      ? DateTime.utc(2026, 10, 27, 14)
      : null,
);

Widget harness(FakeSupportGateway gateway) => MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar')],
  localizationsDelegates: const [
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  theme: AppTheme.light(),
  home: SupportScreen(gateway: gateway),
);

const validBody = 'سؤال عن فاتورة سابقة';

/// Taps a widget by key name, scrolling it into view first and pumping so
/// the latest frame (enabled/disabled state) is current.
Future<void> tapKey(WidgetTester tester, String keyName) async {
  final finder = find.byKey(Key(keyName));
  if (finder.evaluate().isNotEmpty) {
    await tester.ensureVisible(finder);
  }
  await tester.pump();
  await tester.tap(finder, warnIfMissed: false);
  await tester.pump();
}

/// The submit button is only enabled when the draft is valid and the form
/// is not blocked.
bool submitEnabled(WidgetTester tester) =>
    tester
        .widget<FilledButton>(find.byKey(const Key('support-submit')))
        .onPressed !=
    null;

void main() {
  group('normalizeSupportBody', () {
    test('accepts a valid Arabic body after trimming spaces', () {
      expect(
        normalizeSupportBody('  سؤال عن فاتورة سابقة  '),
        'سؤال عن فاتورة سابقة',
      );
    });

    test('accepts the newline control character', () {
      expect(
        normalizeSupportBody('سطر أول للسؤال\nوسطر ثانٍ للمتابعة'),
        isNotNull,
      );
    });

    test('rejects short bodies', () {
      expect(normalizeSupportBody('قصير'), isNull);
      expect(normalizeSupportBody('         '), isNull);
      expect(normalizeSupportBody(''), isNull);
    });

    test('accepts exactly 1000 characters and rejects more', () {
      expect(normalizeSupportBody('ط' * 1000), isNotNull);
      expect(normalizeSupportBody('ط' * 1001), isNull);
    });

    test('rejects CR, tab and other control characters', () {
      expect(normalizeSupportBody('سؤال يحتوي\r\nعلى سطر'), isNull);
      expect(normalizeSupportBody('سؤال يحتوي\tعلى تباعد'), isNull);
      expect(
        normalizeSupportBody('سؤال يحتوي على محرف${String.fromCharCode(1)}'),
        isNull,
      );
      expect(
        normalizeSupportBody('سؤال يحتوي على محرف${String.fromCharCode(127)}'),
        isNull,
      );
    });
  });

  testWidgets('saves a valid inquiry and refreshes the list', (tester) async {
    final gateway = FakeSupportGateway();
    await tester.pumpWidget(harness(gateway));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-list-empty')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('support-body')), validBody);
    await tester.pump();
    await tapKey(tester, 'support-category-technical');
    await tapKey(tester, 'support-submit');
    await tester.pumpAndSettle();

    expect(find.text(SupportCopy.saved), findsOneWidget);
    expect(find.byKey(const Key('support-item-status-fresh')), findsOneWidget);
    expect(gateway.createKeys, hasLength(1));
    expect(gateway.createCategories.single, SupportCategory.technical);
    expect(gateway.createBodies.single, validBody);
    expect(gateway.listCalls, 2);
  });

  testWidgets('shows the exact remaining count and blocks invalid drafts', (
    tester,
  ) async {
    final gateway = FakeSupportGateway();
    await tester.pumpWidget(harness(gateway));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('support-body')), 'قصير');
    await tester.pump();
    expect(find.text(SupportCopy.remaining(996)), findsOneWidget);
    expect(submitEnabled(tester), isFalse);
    expect(gateway.createKeys, isEmpty);

    await tester.enterText(find.byKey(const Key('support-body')), 'ط' * 1005);
    await tester.pump();
    expect(find.text(SupportCopy.overLimit(5)), findsOneWidget);
    expect(submitEnabled(tester), isFalse);
    expect(gateway.createKeys, isEmpty);
  });

  testWidgets('keeps the draft and replays the same key after a retryable '
      'failure', (tester) async {
    final gateway = FakeSupportGateway()
      ..createFailure = SupportFailure.unavailable;
    await tester.pumpWidget(harness(gateway));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('support-body')), validBody);
    await tester.pump();
    await tapKey(tester, 'support-submit');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('support-state-failed')), findsOneWidget);
    expect(find.text(SupportCopy.saveFailed), findsOneWidget);
    // The draft survives a retryable failure.
    expect(find.text(validBody), findsOneWidget);

    gateway.createFailure = null;
    await tapKey(tester, 'support-submit');
    await tester.pumpAndSettle();
    expect(gateway.createKeys, hasLength(2));
    expect(gateway.createKeys[0], gateway.createKeys[1]);
    expect(find.text(SupportCopy.saved), findsOneWidget);
  });

  testWidgets('drops the key after a definitive server failure and a draft '
      'edit', (tester) async {
    final gateway = FakeSupportGateway()
      ..createFailure = SupportFailure.invalidInput;
    await tester.pumpWidget(harness(gateway));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('support-body')), validBody);
    await tester.pump();
    await tapKey(tester, 'support-submit');
    await tester.pumpAndSettle();
    expect(find.text(SupportCopy.invalidBody), findsOneWidget);

    gateway.createFailure = null;
    await tapKey(tester, 'support-submit');
    await tester.pumpAndSettle();
    expect(gateway.createKeys, hasLength(2));
    expect(gateway.createKeys[0], isNot(gateway.createKeys[1]));

    // Editing the draft after a retryable failure also drops the key.
    gateway.createFailure = SupportFailure.unavailable;
    await tester.enterText(find.byKey(const Key('support-body')), validBody);
    await tester.pump();
    await tapKey(tester, 'support-submit');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-state-failed')), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('support-body')),
      'نص معدل بعد الفشل المؤقت ليصبح صالحًا',
    );
    gateway.createFailure = null;
    await tapKey(tester, 'support-submit');
    await tester.pumpAndSettle();
    expect(gateway.createKeys, hasLength(4));
    expect(gateway.createKeys[3], isNot(gateway.createKeys[2]));
  });

  testWidgets('ignores a duplicate tap while the create is in flight', (
    tester,
  ) async {
    final gateway = FakeSupportGateway();
    await tester.pumpWidget(harness(gateway));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('support-body')), validBody);
    await tester.pump();

    final first = Completer<SupportSaveResult>();
    gateway.gatedCreate = (_) => first.future;
    await tester.tap(find.byKey(const Key('support-submit')));
    await tester.pump();
    expect(find.byKey(const Key('support-state-pending')), findsOneWidget);
    expect(submitEnabled(tester), isFalse);

    // A second tap while in flight must not create a second command.
    await tester.tap(
      find.byKey(const Key('support-submit')),
      warnIfMissed: false,
    );
    await tester.pump();
    first.complete(
      SupportSaveResult(inquiry: inquiryOf('inq-x'), replayed: false),
    );
    await tester.pumpAndSettle();
    expect(gateway.createKeys, hasLength(1));
    expect(find.text(SupportCopy.saved), findsOneWidget);
  });

  testWidgets('shows the rate-limit state and blocks further submits', (
    tester,
  ) async {
    final gateway = FakeSupportGateway()
      ..createFailure = SupportFailure.inquiryLimit;
    await tester.pumpWidget(harness(gateway));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('support-body')), validBody);
    await tester.pump();
    await tapKey(tester, 'support-submit');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('support-state-limit')), findsOneWidget);
    expect(submitEnabled(tester), isFalse);
    expect(find.text(SupportCopy.openCount(10, 10)), findsOneWidget);
  });

  testWidgets('shows the access-loss state and blocks the form', (tester) async {
    final gateway = FakeSupportGateway()
      ..createFailure = SupportFailure.unauthorized;
    await tester.pumpWidget(harness(gateway));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('support-body')), validBody);
    await tester.pump();
    await tapKey(tester, 'support-submit');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('support-state-unauthorized')), findsOneWidget);
    expect(submitEnabled(tester), isFalse);
  });

  testWidgets('confirms an idempotent replay', (tester) async {
    final gateway = FakeSupportGateway()..replayNext = true;
    await tester.pumpWidget(harness(gateway));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('support-body')), validBody);
    await tester.pump();
    await tapKey(tester, 'support-submit');
    await tester.pumpAndSettle();
    expect(find.text(SupportCopy.savedReplayed), findsOneWidget);
  });

  testWidgets('pages the list with keyset retry and keeps content on failure', (
    tester,
  ) async {
    final gateway = FakeSupportGateway(
      initial: [inquiryOf('inq-1')],
      older: [inquiryOf('inq-2')],
    )..moreAvailable = true;
    await tester.pumpWidget(harness(gateway));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-item-inq-1')), findsOneWidget);
    expect(find.byKey(const Key('support-more')), findsOneWidget);

    // A failed page load keeps the cursor and offers a retry.
    gateway.moreAvailable = false;
    gateway.listFailure = SupportFailure.unavailable;
    await tapKey(tester, 'support-more');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-item-inq-1')), findsOneWidget);
    expect(find.byKey(const Key('support-list-retry')), findsOneWidget);

    gateway.listFailure = null;
    await tapKey(tester, 'support-list-retry');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-item-inq-2')), findsOneWidget);
    expect(find.byKey(const Key('support-more')), findsNothing);
  });

  testWidgets('shows statuses, saved reply and shop-local dates with LTR '
      'digits', (tester) async {
    final gateway = FakeSupportGateway(
      initial: [
        inquiryOf(
          'inq-1',
          category: SupportCategory.subscription,
          status: SupportInquiryStatus.closed,
          replyAr: 'تم حل المشكلة وتجديد الاشتراك.',
        ),
      ],
    );
    await tester.pumpWidget(harness(gateway));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-item-status-closed')), findsOneWidget);
    expect(find.byKey(const Key('support-item-reply')), findsOneWidget);
    expect(find.textContaining('تم حل المشكلة'), findsOneWidget);
    expect(find.textContaining('2026-10-27'), findsWidgets);
    expect(find.byKey(const Key('support-freshness')), findsOneWidget);
    expect(find.text(SupportCopy.openCount(1, 10)), findsOneWidget);
  });

  testWidgets('shows a list load error with retry', (tester) async {
    final gateway = FakeSupportGateway()
      ..listFailure = SupportFailure.unavailable;
    await tester.pumpWidget(harness(gateway));
    await tester.pumpAndSettle();
    expect(find.text(SupportCopy.listError), findsOneWidget);
    expect(find.byKey(const Key('support-list-retry')), findsOneWidget);

    gateway.listFailure = null;
    gateway.inquiries = [inquiryOf('inq-1')];
    await tapKey(tester, 'support-list-retry');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-item-inq-1')), findsOneWidget);
  });
}
