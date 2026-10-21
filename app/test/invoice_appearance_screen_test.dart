import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/financial_operation_screen.dart';
import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/invoice_appearance_contract.dart';
import 'package:eldafttar/src/features/invoice_appearance/application/invoice_appearance_gateway.dart';
import 'package:eldafttar/src/features/invoice_appearance/data/logo_upload_store.dart';
import 'package:eldafttar/src/features/invoice_appearance/domain/appearance_rules.dart';
import 'package:eldafttar/src/features/invoice_appearance/presentation/invoice_appearance_screen.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_account.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_image.dart';
import 'package:eldafttar/src/shell/shop_workspace.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _user = 'a1111111-1111-4111-8111-111111111111';
const _shop = 'a1222222-2222-4222-8222-222222222222';
const _key = 'a1555555-5555-4555-8555-555555555555';
const _operation = 'a1333333-3333-4333-8333-333333333333';
const _logoAsset = 'a1666666-6666-4666-8666-666666666666';
const _tinyPngHex =
    '89504e470d0a1a0a0000000d494844520000000200000002080600000072b60d240000001a49444154789c63e1129163909393fbcf626363d3b07bd3ca930020e105b1e1ef98ad0000000049454e44ae426082';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final font = await File('assets/fonts/Cairo.ttf').readAsBytes();
    await (FontLoader(
      'Cairo',
    )..addFont(Future<ByteData>.value(ByteData.sublistView(font)))).load();
    final icons = await File(
      r'C:\flutter\bin\cache\artifacts\material_fonts\MaterialIcons-Regular.otf',
    ).readAsBytes();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(Future<ByteData>.value(ByteData.sublistView(icons)))).load();
  });

  testWidgets('settings route and appearance states stay in Arabic', (
    tester,
  ) async {
    final shop = ShopAccount(
      id: _shop,
      name: 'متجر المعاينة',
      role: 'owner',
      entitlement: ShopEntitlement.active,
    );
    await tester.pumpWidget(
      _host(
        ShopWorkspace(
          shop: shop,
          onSignOut: () async {},
          onToggleTheme: (_) async {},
        ),
        390,
        false,
        1,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workspace-nav-4')));
    await tester.pumpAndSettle();
    expect(find.text('مظهر الفاتورة غير متاح في هذا الاتصال.'), findsOneWidget);

    final gateway = AppearanceTestGateway();
    await tester.pumpWidget(
      _host(
        ShopWorkspace(
          shop: shop,
          userId: _user,
          onSignOut: () async {},
          onToggleTheme: (_) async {},
          appearanceBuilder: (_) => InvoiceAppearanceScreen(
            gateway: gateway,
            store: AppearanceTestLocker(),
            userId: _user,
            shopId: _shop,
            canRead: () => true,
            canWrite: () => true,
            logoStore: MemoryLogoUploadStore(),
          ),
        ),
        390,
        false,
        1,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workspace-nav-4')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workspace-invoice-appearance')));
    await tester.pumpAndSettle();
    expect(find.text('مظهر الفاتورة'), findsWidgets);
    expect(find.text('لم يُحفظ مظهر بعد'), findsWidgets);
  });

  testWidgets('branded editions load only after the owner asks', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final calls = <String>[];
    final gateway = HttpOpeningGateway(
      client: MockClient((request) async {
        calls.add(request.url.path);
        if (request.url.path.endsWith('/get_daily_ledger_operation')) {
          return _json(_operationJson());
        }
        if (request.url.path.endsWith('/get_invoice_dispatch_state')) {
          return _json({'operation_id': _operation, 'status': 'unconfirmed'});
        }
        if (request.url.path.endsWith('/get_invoice_presentations_v1')) {
          return _json({
            'version': 1,
            'shop_id': _shop,
            'operation_id': _operation,
            'can_write': true,
            'items': <Object?>[],
          });
        }
        fail('Unexpected RPC ${request.url.path}');
      }),
      supabaseUrl: 'https://example.test',
      publishableKey: 'test',
      accessToken: () => 'token',
      currentUserId: () => _user,
    );
    await tester.pumpWidget(
      _host(
        FinancialOperationScreen(
          gateway: gateway,
          userId: _user,
          shopId: _shop,
          canRead: () => true,
          canWrite: () => true,
          line: const LedgerFeedLine(
            kind: 'sale',
            labelAr: 'بيع',
            operationId: _operation,
            actorDisplayName: 'المالك',
            occurredAt: '2026-10-17T08:00:00+00:00',
            occurredAtCairo: '2026-10-17T10:00:00',
          ),
        ),
        390,
        false,
        1,
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('معاينة المستند الأصلي الثابت'),
      200,
    );
    expect(find.text('معاينة المستند الأصلي الثابت'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('مشاركة مستند PDF عبر واتساب'),
      200,
    );
    expect(find.text('مشاركة مستند PDF عبر واتساب'), findsOneWidget);
    expect(calls.any((path) => path.contains('presentation')), isFalse);
    await tester.scrollUntilVisible(
      find.byKey(const Key('invoice-branded-open')),
      200,
    );
    await tester.tap(find.byKey(const Key('invoice-branded-open')));
    await tester.pumpAndSettle();
    expect(
      calls.any((path) => path.endsWith('/get_invoice_presentations_v1')),
      isTrue,
    );
    expect(find.text('لا توجد نسخة موسومة بعد.'), findsOneWidget);
    expect(find.text('أكد المالك الإرسال عبر واتساب'), findsNothing);
  });

  testWidgets(
    'appearance states stay readable in both themes',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const visible = <String, String>{
        'loading': 'جارٍ التحميل',
        'default': 'لم يُحفظ مظهر بعد',
        'edited': 'ذهب أمين',
        'upload-pending': 'رفع الشعار لم يكتمل. لم يُحفظ.',
        'upload-failure': 'تعذر حفظ الشعار.',
        'review': 'راجع الحقول ثم احفظ. لن يُنشأ مستند مالي.',
        'stale': 'تغيّرت المراجعة المحفوظة. راجع الحقول ثم احفظ من جديد.',
        'unknown':
            'طلب مظهر فاتورة بانتظار التأكيد. أعد التحقق دون تغيير البيانات.',
        'confirmed': 'حُفظت المراجعة 1. لم تتغير العمليات أو الإرسال.',
        'expired': 'انتهى الاشتراك. يمكن قراءة المظهر دون حفظ جديد.',
        'access-loss': 'لم يعد هذا الحساب يصل إلى المتجر.',
        'preview': 'معاينة تجريبية لا تُنشئ عملية أو إرسالاً',
      };
      final cases = <String, Future<void> Function(WidgetTester)>{
        'loading': (tester) async {},
        'default': (tester) async {},
        'edited': (tester) async {
          await tester.ensureVisible(
            find.byKey(const Key('appearance-slogan')),
          );
          await tester.enterText(
            find.byKey(const Key('appearance-slogan')),
            'ذهب أمين',
          );
          await tester.pump();
        },
        'upload-pending': (tester) async {},
        'upload-failure': (tester) async {},
        'review': (tester) async {
          await tester.ensureVisible(
            find.byKey(const Key('appearance-review')),
          );
          await tester.tap(find.byKey(const Key('appearance-review')));
          await _pumpIdle(tester);
        },
        'stale': (tester) async {
          await tester.ensureVisible(
            find.byKey(const Key('appearance-review')),
          );
          await tester.tap(find.byKey(const Key('appearance-review')));
          await _pumpIdle(tester);
        },
        'unknown': (tester) async {},
        'confirmed': (tester) async {
          await tester.ensureVisible(
            find.byKey(const Key('appearance-review')),
          );
          await tester.tap(find.byKey(const Key('appearance-review')));
          await _pumpIdle(tester);
          await tester.ensureVisible(find.byKey(const Key('appearance-save')));
          await tester.tap(find.byKey(const Key('appearance-save')));
          await _pumpIdle(tester);
        },
        'expired': (tester) async {},
        'access-loss': (tester) async {},
        'preview': (tester) async {
          await tester.ensureVisible(
            find.byKey(const Key('appearance-synthetic')),
          );
        },
      };
      for (final entry in cases.entries) {
        for (final width in [320.0, 390.0, 1440.0]) {
          for (final dark in [false, true]) {
            for (final scale in [1.0, 1.7]) {
              final harness = _harness(entry.key);
              tester.view.physicalSize = Size(width, 2400);
              tester.view.devicePixelRatio = 1;
              await tester.pumpWidget(
                _host(harness.screen, width, dark, scale),
              );
              if (entry.key == 'loading') {
                await tester.pump();
              } else {
                await _pumpIdle(tester);
              }
              await entry.value(tester);
              if (entry.key != 'loading') await _pumpIdle(tester);
              expect(
                tester.takeException(),
                isNull,
                reason:
                    '${entry.key} ${dark ? 'dark' : 'light'} $width x$scale',
              );
              final status = tester.widget<Text>(
                find.byKey(const Key('appearance-status')),
              );
              final expectedStatus = switch (entry.key) {
                'edited' => 'لم يُحفظ مظهر بعد',
                'preview' => 'لم يُحفظ مظهر بعد',
                _ => visible[entry.key],
              };
              expect(
                status.data,
                expectedStatus,
                reason:
                    '${entry.key} ${dark ? 'dark' : 'light'} $width x$scale',
              );
              if (entry.key == 'edited' || entry.key == 'preview') {
                expect(find.text(visible[entry.key]!), findsWidgets);
              }
              harness.finish();
              await _pumpIdle(tester);
            }
          }
        }
      }
      expect(
        find.text('معاينة تجريبية لا تُنشئ عملية أو إرسالاً'),
        findsWidgets,
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets('synthetic preview opens a labeled dialog', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    final harness = _harness('default');
    await tester.pumpWidget(_host(harness.screen, 390, false, 1));
    await _pumpIdle(tester);
    final label = find.descendant(
      of: find.byKey(const Key('appearance-synthetic')),
      matching: find.byType(Text),
    );
    await tester.ensureVisible(label);
    await tester.tap(label);
    await _pumpIdle(tester);
    expect(
      find.byKey(const Key('appearance-synthetic-dialog')),
      findsOneWidget,
    );
    expect(
      find.text('هذه معاينة فقط. لم يُحفظ الملف ولم يُرسل.'),
      findsOneWidget,
    );
    expect(find.text('أكد المالك الإرسال عبر واتساب'), findsNothing);
  });

  testWidgets('shop image toggle uploads and clears the invoice logo', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    final gateway = AppearanceTestGateway()..acceptLogoUploads = true;
    final shopImages = FakeShopImageGateway(
      ShopImage(
        shopId: _shop,
        sha256: 'cd' * 32,
        mime: 'image/png',
        width: 2,
        height: 2,
        bytes: _hex(_tinyPngHex),
      ),
    );
    final screen = InvoiceAppearanceScreen(
      gateway: gateway,
      store: AppearanceTestLocker(),
      logoStore: MemoryLogoUploadStore(),
      shopImageGateway: shopImages,
      userId: _user,
      shopId: _shop,
      canRead: () => true,
      canWrite: () => true,
      newKey: () => _key,
    );
    await tester.pumpWidget(_host(screen, 390, false, 1));
    await _pumpIdle(tester);
    expect(
      find.byKey(const Key('appearance-shop-image-preview')),
      findsOneWidget,
    );
    expect(find.text('إظهار صورة المتجر على الفاتورة'), findsOneWidget);
    final toggle = find.byKey(const Key('appearance-shop-image-toggle'));
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await _pumpIdle(tester);
    expect(gateway.logoUploads, 1);
    expect(gateway.logoConfirms, 1);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(find.textContaining('تم ربط الصورة بالفاتورة'), findsOneWidget);
    await tester.tap(toggle);
    await _pumpIdle(tester);
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    expect(find.byKey(const Key('appearance-logo-clear')), findsNothing);
  });

  testWidgets('shop image toggle asks for a shop image when none is saved', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    tester.view.physicalSize = const Size(390, 1600);
    tester.view.devicePixelRatio = 1;
    final screen = InvoiceAppearanceScreen(
      gateway: AppearanceTestGateway(),
      store: AppearanceTestLocker(),
      logoStore: MemoryLogoUploadStore(),
      shopImageGateway: FakeShopImageGateway(null),
      userId: _user,
      shopId: _shop,
      canRead: () => true,
      canWrite: () => true,
      newKey: () => _key,
    );
    await tester.pumpWidget(_host(screen, 390, false, 1));
    await _pumpIdle(tester);
    expect(
      find.byKey(const Key('appearance-shop-image-missing')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('appearance-shop-image-toggle')));
    await _pumpIdle(tester);
    expect(find.textContaining('أضف صورة المتجر من المزيد'), findsOneWidget);
  });
}

Uint8List _hex(String value) {
  final out = Uint8List(value.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(value.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

_Harness _harness(String state) {
  final gateway = AppearanceTestGateway();
  final logos = MemoryLogoUploadStore();
  final locker = AppearanceTestLocker();
  var read = true;
  var write = true;
  if (state == 'loading') {
    gateway.pending = Completer<InvoiceAppearanceSnapshot>();
  }
  if (state == 'upload-pending' || state == 'upload-failure') {
    logos.record = LogoUploadRecord(
      phase: state == 'upload-pending'
          ? LogoUploadPhase.uploadPending
          : LogoUploadPhase.failed,
      sha256: 'ab' * 32,
      mime: 'image/png',
      objectName: '$_shop/${'ab' * 32}.png',
      message: 'تعذر حفظ الشعار.',
    );
  }
  if (state == 'stale') {
    gateway.review = const InvoiceAppearanceReview(
      status: 'stale',
      currentRevision: 4,
      canWrite: true,
    );
  }
  if (state == 'unknown') {
    locker.command = PendingFinancialCommand(
      key: _key,
      kind: invoiceAppearanceKind,
      body: {
        'p_idempotency_key': _key,
        'p_payload': appearanceCommandPayload(
          expectedRevision: 1,
          template: InvoiceTemplate.compact,
          accent: InvoiceAccent.gold,
          slogan: 'ذهب أمين',
        ),
      },
    );
  }
  if (state == 'expired') write = false;
  if (state == 'access-loss') read = false;
  final screen = InvoiceAppearanceScreen(
    key: UniqueKey(),
    gateway: gateway,
    store: locker,
    logoStore: logos,
    userId: _user,
    shopId: _shop,
    canRead: () => read,
    canWrite: () => write,
    newKey: () => _key,
  );
  return _Harness(screen, gateway);
}

class _Harness {
  _Harness(this.screen, this.gateway);
  final InvoiceAppearanceScreen screen;
  final AppearanceTestGateway gateway;
  void finish() {
    final pending = gateway.pending;
    if (pending != null && !pending.isCompleted) {
      pending.complete(AppearanceTestGateway.snapshot);
    }
  }
}

Future<void> _pumpIdle(WidgetTester tester) async {
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (!tester.binding.hasScheduledFrame) return;
  }
}

Widget _host(Widget child, double width, bool dark, double scale) =>
    RepaintBoundary(
      key: const Key('appearance-capture'),
      child: MaterialApp(
        key: UniqueKey(),
        locale: const Locale('ar'),
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, content) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            size: Size(width, 2400),
            textScaler: TextScaler.linear(scale),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: content!,
          ),
        ),
        home: child,
      ),
    );

http.Response _json(Object? body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, Object?> _operationJson() => {
  'operation_id': _operation,
  'shop_id': _shop,
  'kind': 'sale',
  'shop_sequence': '44',
  'shop_name': 'متجر المعاينة',
  'actor_display_name': 'المالك',
  'occurred_at_cairo': '2026-10-17T10:00:00',
  'payload': {
    'total_piastres': '100',
    'items': [
      {
        'item_name': 'صنف معاينة',
        'category': 'worked_jewelry',
        'karat': 21,
        'milligrams': '1000',
        'count': '1',
      },
    ],
    'tenders': [
      {'method': 'cash', 'piastres': '100'},
    ],
  },
};

final class AppearanceTestLocker implements FinancialCommandLocker {
  PendingFinancialCommand? command;
  @override
  Future<void> clear(String userId, String shopId, String key) async {
    if (command?.key == key) command = null;
  }

  @override
  Future<PendingFinancialCommand?> read(String userId, String shopId) async =>
      command;

  @override
  Future<void> save(
    String userId,
    String shopId,
    PendingFinancialCommand command,
  ) async {
    this.command = command;
  }
}

class FakeShopImageGateway implements ShopImageGateway {
  FakeShopImageGateway(this.current);
  ShopImage? current;

  @override
  Future<ShopImage?> readCurrent() async => current;

  @override
  Future<ShopImage> setImage(Uint8List preparedBytes) =>
      throw UnimplementedError();

  @override
  Future<void> clearImage() => throw UnimplementedError();
}

class AppearanceTestGateway implements InvoiceAppearanceGateway {
  static const snapshot = InvoiceAppearanceSnapshot(
    shopId: _shop,
    value: InvoiceAppearanceValue.defaults,
    canWrite: true,
    timeZone: 'Africa/Cairo',
  );
  Completer<InvoiceAppearanceSnapshot>? pending;
  InvoiceAppearanceReview review = const InvoiceAppearanceReview(
    status: 'ready',
    currentRevision: 0,
    canWrite: true,
  );
  Object? session = Object();
  var acceptLogoUploads = false;
  var logoUploads = 0;
  var logoConfirms = 0;

  @override
  Object? appearanceSession(String userId) => session;

  @override
  Future<InvoiceAppearanceSnapshot> readAppearance({
    required String userId,
    required String shopId,
  }) => pending?.future ?? Future.value(snapshot);

  @override
  Future<InvoiceAppearanceReview> reviewAppearance({
    required String userId,
    required String shopId,
    required Map<String, Object?> payload,
  }) async => review;

  @override
  Future<AppearanceTransport> sendAppearance({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  }) async => AppearanceTransport(
    receipt: AppearanceReceipt(
      shopId: shopId,
      key: key,
      kind: invoiceAppearanceKind,
      payload: Map<String, Object?>.from(body['p_payload'] as Map),
      actorId: userId,
      atUtc: '2026-10-17T08:00:00.000000Z',
      replayed: false,
      revision: 1,
    ),
  );

  @override
  Future<AppearanceTransport> appearanceStatus({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  }) async => const AppearanceTransport(absent: true);

  @override
  Future<LogoUploadResult> uploadInvoiceLogo({
    required String userId,
    required String shopId,
    required String objectName,
    required String mimeType,
    required List<int> bytes,
  }) async {
    if (!acceptLogoUploads) throw UnimplementedError();
    logoUploads++;
    return const LogoUploadResult(LogoUploadDisposition.stored);
  }

  @override
  Future<LogoConfirmation> confirmInvoiceLogo({
    required String userId,
    required String shopId,
    required String base64Bytes,
    required String sha256,
  }) async {
    if (!acceptLogoUploads) throw UnimplementedError();
    logoConfirms++;
    return LogoConfirmation(
      shopId: shopId,
      assetId: _logoAsset,
      sha256: sha256,
      mime: 'image/png',
      width: 2,
      height: 2,
    );
  }

  @override
  Future<InvoiceBrandSource> readBrandSource({
    required String userId,
    required String shopId,
    required String operationId,
  }) => throw UnimplementedError();

  @override
  Future<AppearanceTransport> sendPresentation({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  }) => throw UnimplementedError();

  @override
  Future<AppearanceTransport> presentationStatus({
    required String userId,
    required String shopId,
    required String key,
    required Map<String, Object?> body,
  }) => throw UnimplementedError();

  @override
  Future<InvoicePresentationList> listPresentations({
    required String userId,
    required String shopId,
    required String operationId,
  }) => throw UnimplementedError();

  @override
  Future<InvoicePresentationCopy> readPresentation({
    required String userId,
    required String shopId,
    required String operationId,
    required int edition,
  }) => throw UnimplementedError();
}
