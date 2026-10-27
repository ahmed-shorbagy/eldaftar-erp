import 'package:eldafttar/src/features/help/domain/help_models.dart';
import 'package:eldafttar/src/features/help/presentation/announcement_banner.dart';
import 'package:eldafttar/src/features/help/presentation/help_screen.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeHelpGateway implements HelpGateway {
  FakeHelpGateway({
    this.topics = const [],
    this.announcement,
    this.fail = false,
  });

  List<HelpTopic> topics;
  PlatformAnnouncement? announcement;
  bool fail;

  @override
  Future<List<HelpTopic>> listCatalog() async {
    if (fail) throw const HelpException(HelpFailure.unavailable);
    return topics;
  }

  @override
  Future<PlatformAnnouncement?> getAnnouncement() async {
    if (fail) throw const HelpException(HelpFailure.unavailable);
    return announcement;
  }
}

void main() {
  testWidgets('lists topics and opens article body', (tester) async {
    final gateway = FakeHelpGateway(
      topics: const [
        HelpTopic(
          id: 't1',
          titleAr: 'المبيعات',
          sortOrder: 1,
          articles: [
            HelpArticle(
              id: 'a1',
              titleAr: 'كيف أسجّل بيعًا',
              bodyAr: 'افتح الدفتر ثم اختر بيع.',
              sortOrder: 1,
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        supportedLocales: const [Locale('ar')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(),
        home: HelpScreen(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('المبيعات'), findsOneWidget);
    await tester.tap(find.text('المبيعات'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('كيف أسجّل بيعًا'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('help-article-body')), findsOneWidget);
    expect(find.text('افتح الدفتر ثم اختر بيع.'), findsOneWidget);
  });

  testWidgets('filters articles by search query', (tester) async {
    final gateway = FakeHelpGateway(
      topics: const [
        HelpTopic(
          id: 't1',
          titleAr: 'عام',
          sortOrder: 1,
          articles: [
            HelpArticle(
              id: 'a1',
              titleAr: 'البيع',
              bodyAr: 'تفاصيل البيع',
              sortOrder: 1,
            ),
            HelpArticle(
              id: 'a2',
              titleAr: 'الشراء',
              bodyAr: 'تفاصيل الشراء',
              sortOrder: 2,
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: HelpScreen(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('help-search')), 'شراء');
    await tester.pumpAndSettle();
    await tester.tap(find.text('عام'));
    await tester.pumpAndSettle();
    expect(find.text('الشراء'), findsOneWidget);
    expect(find.text('البيع'), findsNothing);
  });

  testWidgets('always shows the support entry and emphasizes it when search '
      'has no match', (tester) async {
    final gateway = FakeHelpGateway(
      topics: const [
        HelpTopic(
          id: 't1',
          titleAr: 'عام',
          sortOrder: 1,
          articles: [
            HelpArticle(
              id: 'a1',
              titleAr: 'البيع',
              bodyAr: 'تفاصيل البيع',
              sortOrder: 1,
            ),
          ],
        ),
      ],
    );
    Widget buildHelp() => MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
      home: HelpScreen(
        gateway: gateway,
        supportBuilder: (_) =>
            const Scaffold(key: Key('support-probe'), body: Text('شاشة الدعم')),
      ),
    );
    await tester.pumpWidget(buildHelp());
    await tester.pumpAndSettle();
    // The action is persistent: visible before any search.
    expect(find.byKey(const Key('help-support-entry')), findsOneWidget);
    expect(
      find.text('لم تجد ما تبحث عنه؟ أرسل استفسارك إلى فريق الدعم.'),
      findsNothing,
    );

    // Emphasized when the current search yields no match.
    await tester.enterText(
      find.byKey(const Key('help-search')),
      'كلمة غير موجودة',
    );
    await tester.pumpAndSettle();
    expect(find.text('لا نتائج مطابقة للبحث.'), findsOneWidget);
    expect(
      find.text('لم تجد ما تبحث عنه؟ أرسل استفسارك إلى فريق الدعم.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('help-support-entry')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('support-probe')), findsOneWidget);
  });

  testWidgets('hides the support entry when no support builder is provided', (
    tester,
  ) async {
    final gateway = FakeHelpGateway();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        home: HelpScreen(gateway: gateway),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('help-support-entry')), findsNothing);
  });

  testWidgets('announcement banner dismisses for the session', (tester) async {
    var dismissed = false;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        home: Scaffold(
          body: AnnouncementBanner(
            announcement: const PlatformAnnouncement(
              titleAr: 'تنبيه',
              bodyAr: 'نص',
            ),
            onDismiss: () => dismissed = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('platform-announcement-dismiss')));
    expect(dismissed, isTrue);
  });
}
