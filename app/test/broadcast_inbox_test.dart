import 'dart:io';
import 'dart:ui' as ui;

import 'package:eldafttar/src/features/broadcasts/data/supabase_broadcast_gateway.dart';
import 'package:eldafttar/src/features/broadcasts/domain/broadcast_models.dart';
import 'package:eldafttar/src/features/broadcasts/presentation/broadcast_inbox_screen.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'financial_trade_screen_test.dart' show FakeFinancialGateway;

const _shop = 'b1100000-0000-4000-8000-000000000001';
const _idA = 'b1000000-0000-4000-8000-00000000000a';
const _idB = 'b1000000-0000-4000-8000-00000000000b';

Map<String, Object?> _row(String id, {String? readAt, String? link}) => {
  'id': id,
  'title_ar': id == _idA ? 'تجديد الاشتراك' : 'تحديث جديد',
  'body_ar': 'اشتراكك ينتهي خلال ثلاثة أيام.\nجدّد من صفحة الاشتراك.',
  'link_url': link,
  'starts_at': '2026-11-13T08:00:00+00:00',
  'ends_at': '2026-12-13T08:00:00+00:00',
  'read_at': readAt,
};

Map<String, Object?> _inbox({String unread = '1', List<Object?>? rows}) => {
  'shop_id': _shop,
  'time_zone': 'Africa/Cairo',
  'unread_count': unread,
  'rows':
      rows ??
      [
        _row(_idA, link: 'https://example.test/renew'),
        _row(_idB, readAt: '2026-11-13T09:00:00+00:00'),
      ],
};

class FakeBroadcastGateway implements BroadcastGateway {
  FakeBroadcastGateway({this.listFailure, this.readFailure});

  BroadcastFailure? listFailure;
  BroadcastFailure? readFailure;
  BroadcastInbox inbox = parseBroadcastInbox(_inbox());
  final reads = <String>[];
  int lists = 0;

  @override
  Future<BroadcastInbox> listMine() async {
    lists++;
    final failure = listFailure;
    if (failure != null) throw BroadcastException(failure);
    return inbox;
  }

  @override
  Future<BroadcastReadResult> markRead(String broadcastId) async {
    reads.add(broadcastId);
    final failure = readFailure;
    if (failure != null) throw BroadcastException(failure);
    final at = DateTime.utc(2026, 11, 13, 10);
    inbox = inbox.withRead(broadcastId, at);
    return BroadcastReadResult(readAt: at, alreadyRead: false);
  }
}

Widget _host(Widget child, Brightness brightness, {GlobalKey? capture}) =>
    MaterialApp(
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: brightness == Brightness.light
          ? AppTheme.light()
          : AppTheme.dark(),
      home: child,
      builder: (context, page) => RepaintBoundary(key: capture, child: page!),
    );

Future<void> _capture(WidgetTester tester, GlobalKey key, String name) async {
  await tester.pumpAndSettle();
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final picture = await boundary.toImage();
    final png = await picture.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/broadcast-review/$name.png');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
    picture.dispose();
  });
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = await File('assets/fonts/Cairo.ttf').readAsBytes();
    await (FontLoader(
      'Cairo',
    )..addFont(Future.value(ByteData.sublistView(font)))).load();
    final sdkRoot = Platform.resolvedExecutable
        .split(RegExp(r'[/\\]bin[/\\]cache[/\\]'))
        .first;
    final icons = await File(
      '$sdkRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future.value(ByteData.sublistView(icons)))).load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  group('decoding', () {
    test('parses the inbox and the newest unread message', () {
      final inbox = parseBroadcastInbox(_inbox());
      expect(inbox.shopId, _shop);
      expect(inbox.unreadCount, 1);
      expect(inbox.items, hasLength(2));
      expect(inbox.newestUnread?.id, _idA);
      expect(inbox.items.first.linkUrl, 'https://example.test/renew');
      expect(inbox.items.last.isUnread, isFalse);
    });

    test('rejects malformed payloads', () {
      final bad = <Object?>[
        null,
        {..._inbox(), 'unread_count': 1},
        {..._inbox(), 'unread_count': '0'},
        {..._inbox(), 'shop_id': 'shop'},
        _inbox(rows: [_row(_idA), _row(_idA)]),
        _inbox(rows: [_row('x')]),
        _inbox(rows: [_row(_idA, link: 'http://example.test')]),
        _inbox(
          rows: [
            {..._row(_idA), 'title_ar': ' '},
          ],
        ),
        _inbox(
          rows: [
            {..._row(_idA), 'ends_at': '2026-11-13T08:00:00+00:00'},
          ],
        ),
      ];
      for (final raw in bad) {
        expect(
          () => parseBroadcastInbox(raw),
          throwsA(isA<BroadcastException>()),
          reason: '$raw',
        );
      }
    });

    test('read results are bound to the requested message', () {
      final result = parseReadResult({
        'status': 'already_read',
        'broadcast_id': _idA,
        'read_at': '2026-11-13T09:00:00+00:00',
      }, _idA);
      expect(result.alreadyRead, isTrue);
      expect(
        () => parseReadResult({
          'status': 'read',
          'broadcast_id': _idB,
          'read_at': '2026-11-13T09:00:00+00:00',
        }, _idA),
        throwsA(isA<BroadcastException>()),
      );
      expect(mapBroadcastError('unauthorized'), BroadcastFailure.unauthorized);
      expect(mapBroadcastError('not_found'), BroadcastFailure.notFound);
      expect(mapBroadcastError('boom'), BroadcastFailure.unavailable);
    });

    test('marking read updates the count once', () {
      final inbox = parseBroadcastInbox(_inbox());
      final at = DateTime.utc(2026, 11, 13, 10);
      final once = inbox.withRead(_idA, at);
      expect(once.unreadCount, 0);
      expect(once.newestUnread, isNull);
      expect(identical(once.withRead(_idA, at), once), isTrue);
    });
  });

  testWidgets('opening a message marks it read and updates the inbox', (
    tester,
  ) async {
    final gateway = FakeBroadcastGateway();
    final changes = <BroadcastInbox>[];
    await tester.pumpWidget(
      _host(
        BroadcastInboxScreen(gateway: gateway, onChanged: changes.add),
        Brightness.light,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('broadcast-unread-count')), findsOneWidget);
    expect(find.text(BroadcastCopy.unreadCount(1)), findsOneWidget);
    expect(find.byKey(const Key('broadcast-unread-$_idA')), findsOneWidget);
    expect(find.byKey(const Key('broadcast-unread-$_idB')), findsNothing);

    await tester.tap(find.byKey(const Key('broadcast-$_idA')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('broadcast-detail-title')), findsOneWidget);
    expect(find.byKey(const Key('broadcast-detail-link')), findsOneWidget);
    expect(find.byKey(const Key('broadcast-read-failed')), findsNothing);
    expect(gateway.reads, [_idA]);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('broadcast-unread-$_idA')), findsNothing);
    expect(find.byKey(const Key('broadcast-unread-count')), findsNothing);
    expect(changes.last.unreadCount, 0);

    await tester.tap(find.byKey(const Key('broadcast-$_idB')));
    await tester.pumpAndSettle();
    expect(gateway.reads, [_idA], reason: 'read messages are not re-marked');
  });

  testWidgets('a failed read mark is reported and stays unread', (
    tester,
  ) async {
    final gateway = FakeBroadcastGateway(
      readFailure: BroadcastFailure.unavailable,
    );
    await tester.pumpWidget(
      _host(BroadcastInboxScreen(gateway: gateway), Brightness.light),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('broadcast-$_idA')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('broadcast-read-failed')), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('broadcast-unread-$_idA')), findsOneWidget);
  });

  testWidgets('load failure offers retry; lost access does not', (
    tester,
  ) async {
    final gateway = FakeBroadcastGateway(
      listFailure: BroadcastFailure.unavailable,
    );
    await tester.pumpWidget(
      _host(BroadcastInboxScreen(gateway: gateway), Brightness.light),
    );
    await tester.pumpAndSettle();
    expect(find.text(BroadcastCopy.loadError), findsOneWidget);
    gateway.listFailure = null;
    await tester.tap(find.text(BroadcastCopy.retry));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('broadcast-$_idA')), findsOneWidget);

    final denied = FakeBroadcastGateway(
      listFailure: BroadcastFailure.unauthorized,
    );
    await tester.pumpWidget(
      _host(
        BroadcastInboxScreen(key: const Key('denied'), gateway: denied),
        Brightness.light,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(BroadcastCopy.accessLost), findsOneWidget);
    expect(find.text(BroadcastCopy.retry), findsNothing);
  });

  testWidgets('an empty inbox says so', (tester) async {
    final gateway = FakeBroadcastGateway()
      ..inbox = parseBroadcastInbox(_inbox(unread: '0', rows: const []));
    await tester.pumpWidget(
      _host(BroadcastInboxScreen(gateway: gateway), Brightness.dark),
    );
    await tester.pumpAndSettle();
    expect(find.text(BroadcastCopy.empty), findsOneWidget);
  });

  Widget workspace({
    required String role,
    BroadcastInbox? inbox,
    VoidCallback? onDismiss,
    BroadcastGateway? gateway,
  }) => ShopWorkspace(
    shop: ShopAccount(
      id: _shop,
      name: 'متجر تجريبي',
      role: role,
      entitlement: ShopEntitlement.active,
    ),
    gateway: FakeFinancialGateway(),
    userId: 'owner-1',
    onSignOut: () async {},
    onToggleTheme: (_) async {},
    broadcastGateway: gateway,
    broadcastInbox: inbox,
    broadcastBanner: inbox?.newestUnread,
    onDismissBroadcast: onDismiss,
  );

  testWidgets('owners see the newest unread message as a banner', (
    tester,
  ) async {
    var dismissed = 0;
    final inbox = parseBroadcastInbox(_inbox());
    await tester.pumpWidget(
      _host(
        workspace(
          role: 'owner',
          inbox: inbox,
          gateway: FakeBroadcastGateway(),
          onDismiss: () => dismissed++,
        ),
        Brightness.light,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('broadcast-banner')), findsOneWidget);
    expect(find.text('تجديد الاشتراك'), findsOneWidget);
    await tester.tap(find.byKey(const Key('platform-announcement-dismiss')));
    expect(dismissed, 1);
  });

  testWidgets('partners get no banner and no messages link', (tester) async {
    final inbox = parseBroadcastInbox(_inbox());
    await tester.pumpWidget(
      _host(
        workspace(
          role: 'partner',
          inbox: inbox,
          gateway: FakeBroadcastGateway(),
          onDismiss: () {},
        ),
        Brightness.light,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('broadcast-banner')), findsNothing);
    await tester.tap(find.text('المزيد').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workspace-broadcasts')), findsNothing);
  });

  for (final width in [320.0, 390.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('Arabic messages ${width.toInt()} ${brightness.name}', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final capture = GlobalKey();
        final gateway = FakeBroadcastGateway();
        await tester.pumpWidget(
          _host(
            workspace(
              role: 'owner',
              inbox: parseBroadcastInbox(_inbox()),
              gateway: gateway,
              onDismiss: () {},
            ),
            brightness,
            capture: capture,
          ),
        );
        await tester.pumpAndSettle();
        final name = '${width.toInt()}-${brightness.name}';
        await _capture(tester, capture, 'banner-$name');
        await tester.tap(find.text('المزيد').last);
        await tester.pumpAndSettle();
        final link = find.byKey(const Key('workspace-broadcasts'));
        await tester.ensureVisible(link);
        await tester.pumpAndSettle();
        expect(
          find.text('${BroadcastCopy.title} (${BroadcastCopy.unreadCount(1)})'),
          findsOneWidget,
        );
        await tester.tap(link);
        await tester.pumpAndSettle();
        expect(
          Directionality.of(
            tester.element(find.byKey(const Key('broadcast-inbox-list'))),
          ),
          TextDirection.rtl,
        );
        await _capture(tester, capture, 'inbox-$name');
        await tester.tap(find.byKey(const Key('broadcast-$_idA')));
        await tester.pumpAndSettle();
        await _capture(tester, capture, 'detail-$name');
        expect(tester.takeException(), isNull);
      });
    }
  }
}
