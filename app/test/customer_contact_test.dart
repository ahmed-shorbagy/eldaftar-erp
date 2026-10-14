import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:eldafttar/src/features/customers/domain/customer_contact.dart';
import 'package:eldafttar/src/features/customers/domain/customer_rules.dart';
import 'package:eldafttar/src/features/customers/application/customer_contact_flow.dart';
import 'package:eldafttar/src/features/customers/application/customer_gateway.dart';
import 'package:eldafttar/src/features/customers/data/customer_codec.dart';
import 'package:eldafttar/src/features/customers/data/url_customer_contact_launcher.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'customer_fixtures.dart';
import 'customer_http_test.dart' show response;
import 'customer_statistics_fixtures.dart';

class ContactFake extends FakeCustomers implements CustomerContactSession {
  String? token = 'session';
  Future<void>? readHold;
  void Function()? afterRead;
  @override
  Object? contactSession(String callerUserId) => token;
  @override
  Future<CustomerDetail> customer({
    required String callerUserId,
    required String id,
    String? notesCursor,
    String? historyCursor,
    String? linksCursor,
  }) async {
    if (readHold != null) await readHold;
    if (readError != null) throw CustomerReadException(readError);
    final result = await super.customer(callerUserId: callerUserId, id: id);
    afterRead?.call();
    return result;
  }
}

class ContactLauncherFake implements CustomerContactLauncher {
  final destinations = <Uri>[];
  Future<void>? hold;
  Future<void>? resultHold;
  ContactHandoff outcome = ContactHandoff.opened;
  bool throws = false;
  @override
  Future<ContactHandoff> open(
    CustomerContactAction action,
    Uri destination, {
    required bool Function() stillAuthorized,
  }) async {
    if (hold != null) await hold;
    if (!stillAuthorized()) return ContactHandoff.stale;
    destinations.add(destination);
    if (resultHold != null) await resultHold;
    if (throws) throw StateError('synthetic');
    return outcome;
  }
}

List<Object?> contactPhones() => [
  {'raw': '٠١٠١١١١١١١١', 'normalized': '+201011111111', 'is_primary': true},
  {'raw': '+33123456789', 'normalized': '+33123456789', 'is_primary': false},
];

void main() {
  test(
    'Android method channel queries then opens only the allowlisted dialer destination',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('eldafttar/customer_contact');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      expect(
        await const UrlCustomerContactLauncher(
          platform: TargetPlatform.android,
        ).open(
          CustomerContactAction.dialer,
          Uri.parse('tel:+33123456789'),
          stillAuthorized: () => true,
        ),
        ContactHandoff.opened,
      );
      expect(calls.map((c) => c.method), ['canOpenDialer', 'openDialer']);
      expect(calls.every((c) => c.arguments == 'tel:+33123456789'), isTrue);
    },
  );
  test(
    'canonical destinations preserve international digits and exclude private content',
    () {
      for (final raw in [
        '٠١٠١١١١١١١١',
        '۰۱۰۱۱۱۱۱۱۱۱',
        '00 33 1 23 45 67 89',
        '+966500000000',
      ]) {
        final number = normalizeCustomerPhone(raw)!;
        for (final action in CustomerContactAction.values) {
          final uri = customerContactUri(action, number)!;
          expect(isCustomerContactUri(action, uri), isTrue);
          expect(uri.queryParameters.containsKey('text'), isFalse);
          expect(uri.fragment, isEmpty);
        }
      }
      expect(
        customerContactUri(
          CustomerContactAction.dialer,
          '+201011111111',
        ).toString(),
        'tel:+201011111111',
      );
      expect(
        customerContactUri(
          CustomerContactAction.whatsapp,
          '+33123456789',
        ).toString(),
        'whatsapp://send?phone=33123456789',
      );
      expect(
        customerContactUri(
          CustomerContactAction.whatsappLink,
          '+33123456789',
        ).toString(),
        'https://wa.me/33123456789',
      );
      for (final invalid in [
        '',
        '01011111111',
        '+٢٠١٠١١١١١١١١',
        '+201011111111?text=secret',
        '+201011111111#fragment',
        '+201011111111;123',
        '+0000000',
        '+201011111111\n',
      ]) {
        for (final action in CustomerContactAction.values) {
          expect(customerContactUri(action, invalid), isNull);
        }
      }
      expect(
        isCustomerContactUri(
          CustomerContactAction.whatsappLink,
          Uri.parse('https://evil.test/33123456789'),
        ),
        isFalse,
      );
      expect(
        isCustomerContactUri(
          CustomerContactAction.whatsapp,
          Uri.parse('whatsapp://send?phone=33123456789&text=private'),
        ),
        isFalse,
      );
    },
  );
  test(
    'read authority permits expired and archived handoffs but denies lost authority',
    () {
      for (final status in ['active', 'archived']) {
        expect(
          mayContactCustomer(authorizedReader: true, status: status),
          isTrue,
        );
        expect(
          mayContactCustomer(authorizedReader: false, status: status),
          isFalse,
        );
      }
      expect(
        mayContactCustomer(authorizedReader: true, status: 'deleted'),
        isFalse,
      );
    },
  );
  for (final outcome in [
    ContactHandoff.opened,
    ContactHandoff.cancelled,
    ContactHandoff.denied,
    ContactHandoff.permanentlyDenied,
    ContactHandoff.unavailable,
    ContactHandoff.failed,
  ]) {
    test(
      'injected $outcome is only a handoff and posts no CRM command',
      () async {
        final g = ContactFake()
          ..row = customerJson(phones: contactPhones(), status: 'archived');
        final before = jsonEncode(g.row);
        final launcher = ContactLauncherFake()..outcome = outcome;
        final result = await CustomerContactFlow(g, launcher).launch(
          userId: 'owner',
          reviewed: parseCustomer(g.row),
          number: '+33123456789',
          action: CustomerContactAction.whatsapp,
          stillAuthorized: () => true,
        );
        expect(result, outcome);
        expect(
          launcher.destinations.single.queryParameters['phone'],
          '33123456789',
        );
        expect(g.sent, isEmpty);
        expect(jsonEncode(g.row), before);
      },
    );
  }
  test(
    'duplicate requests, number edits and stale caller cannot launch',
    () async {
      final g = ContactFake()..row = customerJson(phones: contactPhones());
      final launcher = ContactLauncherFake();
      final flow = CustomerContactFlow(g, launcher);
      final reviewed = parseCustomer(g.row);
      final read = Completer<void>();
      g.readHold = read.future;
      var current = true;
      Future<ContactHandoff> run() => flow.launch(
        userId: 'owner',
        reviewed: reviewed,
        number: '+33123456789',
        action: CustomerContactAction.dialer,
        stillAuthorized: () => current,
      );
      final first = run();
      expect(await run(), ContactHandoff.busy);
      current = false;
      read.complete();
      expect(await first, ContactHandoff.stale);
      expect(launcher.destinations, isEmpty);
      current = true;
      g.readHold = null;
      g.row['record_version'] = '2';
      expect(await run(), ContactHandoff.changed);
      expect(launcher.destinations, isEmpty);
      g.row['record_version'] = '1';
      g.row['phones'] = <Object?>[];
      expect(await run(), ContactHandoff.changed);
    },
  );
  test(
    'a phone outside the freshly authorized directory is rejected',
    () async {
      final g = ContactFake()..row = customerJson(phones: contactPhones());
      final l = ContactLauncherFake();
      expect(
        await CustomerContactFlow(g, l).launch(
          userId: 'owner',
          reviewed: parseCustomer(g.row),
          number: '+966500000000',
          action: CustomerContactAction.whatsapp,
          stillAuthorized: () => true,
        ),
        ContactHandoff.unavailable,
      );
      expect(l.destinations, isEmpty);
    },
  );
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
  ]) {
    test(
      '$platform capability and final caller check precede external launch',
      () async {
        final opened = <Uri>[];
        var authorized = true;
        final adapter = UrlCustomerContactLauncher(
          platform: platform,
          canOpen: (uri) async {
            authorized = false;
            return true;
          },
          launch: (uri) async {
            opened.add(uri);
            return true;
          },
        );
        expect(
          await adapter.open(
            CustomerContactAction.whatsapp,
            customerContactUri(CustomerContactAction.whatsapp, '+33123456789')!,
            stillAuthorized: () => authorized,
          ),
          ContactHandoff.stale,
        );
        expect(opened, isEmpty);
        authorized = true;
        final available = UrlCustomerContactLauncher(
          platform: platform,
          canOpen: (_) async => true,
          launch: (u) async {
            opened.add(u);
            return true;
          },
        );
        expect(
          await available.open(
            CustomerContactAction.dialer,
            customerContactUri(CustomerContactAction.dialer, '+33123456789')!,
            stillAuthorized: () => true,
          ),
          platform == TargetPlatform.windows
              ? ContactHandoff.unavailable
              : ContactHandoff.opened,
        );
      },
    );
  }
  test(
    'missing handler false return exceptions and denied permission remain honest',
    () async {
      final uri = customerContactUri(
        CustomerContactAction.whatsapp,
        '+33123456789',
      )!;
      Future<ContactHandoff> run(UrlCustomerContactLauncher adapter) =>
          adapter.open(
            CustomerContactAction.whatsapp,
            uri,
            stillAuthorized: () => true,
          );
      expect(
        await run(
          UrlCustomerContactLauncher(
            canOpen: (_) async => false,
            launch: (_) async => throw StateError('must not launch'),
          ),
        ),
        ContactHandoff.unavailable,
      );
      expect(
        await run(
          UrlCustomerContactLauncher(
            canOpen: (_) async => true,
            launch: (_) async => false,
          ),
        ),
        ContactHandoff.unavailable,
      );
      expect(
        await run(
          UrlCustomerContactLauncher(
            canOpen: (_) async => throw StateError('synthetic'),
          ),
        ),
        ContactHandoff.failed,
      );
      for (final entry in {
        'PERMISSION_DENIED': ContactHandoff.denied,
        'PERMISSION_PERMANENTLY_DENIED': ContactHandoff.permanentlyDenied,
        'synthetic': ContactHandoff.failed,
      }.entries) {
        expect(
          await run(
            UrlCustomerContactLauncher(
              canOpen: (_) async => true,
              launch: (_) async => throw PlatformException(code: entry.key),
            ),
          ),
          entry.value,
        );
      }
    },
  );
  test(
    'production HTTP rechecks session token and performs only the existing detail read',
    () async {
      var token = 'first';
      final requests = <String>[];
      final g = HttpOpeningGateway(
        client: MockClient((r) async {
          requests.add(r.url.path);
          token = 'second';
          return response({
            ...statisticsCustomerJson(),
            'notes': {'items': [], 'next_cursor': null},
            'history': {'items': [], 'next_cursor': null},
            'links': {'items': [], 'next_cursor': null},
          }, 200);
        }),
        supabaseUrl: 'https://example.test',
        publishableKey: 'test-public',
        accessToken: () => token,
        currentUserId: () => 'owner',
      );
      final initial = g.contactSession('owner');
      expect(
        await g
            .customer(callerUserId: 'owner', id: customerId)
            .then(
              (_) => false,
              onError: (e) =>
                  e is CustomerReadException && e.code == 'session_expired',
            ),
        isTrue,
      );
      expect(initial, isNot(g.contactSession('owner')));
      expect(g.contactSession('another'), isNull);
      expect(requests, ['/rest/v1/rpc/get_customer_v3']);
    },
  );
}
