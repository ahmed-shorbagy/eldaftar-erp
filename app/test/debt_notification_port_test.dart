import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:eldafttar/src/features/debts/application/debt_reminder_device.dart';
import 'package:eldafttar/src/features/debts/data/debt_notification_port.dart';
import 'debt_due_fixtures.dart';

class MemoryNotificationFacade implements FlutterLocalNotificationsPlugin {
  final ids = <int>{};
  InitializationSettings? settings;
  String? body, payload;
  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    this.settings = settings;
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async =>
      const NotificationAppLaunchDetails(false);
  @override
  Future<List<PendingNotificationRequest>>
  pendingNotificationRequests() async => [
    for (final id in ids) PendingNotificationRequest(id, null, null, null),
  ];
  @override
  Future<void> cancel({required int id, String? tag}) async {
    ids.remove(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #zonedSchedule) {
      ids.add(invocation.namedArguments[#id] as int);
      body = invocation.namedArguments[#body] as String?;
      payload = invocation.namedArguments[#payload] as String?;
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });
  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      'native $platform method-channel setup/permission/payload/cancel is synthetic',
      () async {
        debugDefaultTargetPlatformOverride = platform;
        FlutterLocalNotificationsPlatform.instance =
            platform == TargetPlatform.android
            ? AndroidFlutterLocalNotificationsPlugin()
            : IOSFlutterLocalNotificationsPlugin();
        final calls = <MethodCall>[], ids = <int>{};
        messenger.setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'initialize':
              return true;
            case 'getNotificationAppLaunchDetails':
              return {'notificationLaunchedApp': false};
            case 'areNotificationsEnabled':
              return true;
            case 'checkPermissions':
              return {
                'isEnabled': true,
                'isAlertEnabled': true,
                'isSoundEnabled': true,
              };
            case 'requestNotificationsPermission':
              return true;
            case 'requestPermissions':
              return true;
            case 'openAppNotificationSettings':
              return true;
            case 'pendingNotificationRequests':
              return [
                for (final id in ids)
                  {'id': id, 'title': null, 'body': null, 'payload': null},
              ];
            case 'zonedSchedule':
              ids.add((call.arguments as Map)['id'] as int);
              return null;
            case 'cancel':
              ids.remove(
                call.arguments is int
                    ? call.arguments as int
                    : (call.arguments as Map)['id'] as int,
              );
              return null;
            default:
              throw StateError('unexpected native call ${call.method}');
          }
        });
        final port = LocalDebtNotificationPort();
        await port.initialize((_) {});
        expect(calls.where((c) => c.method.startsWith('request')), isEmpty);
        if (platform == TargetPlatform.iOS) {
          final settings =
              calls.firstWhere((c) => c.method == 'initialize').arguments
                  as Map;
          expect(settings['requestAlertPermission'], isFalse);
          expect(settings['requestSoundPermission'], isFalse);
          expect(settings['requestBadgePermission'], isFalse);
        }
        expect(await port.requestPermission(), ReminderPermission.allowed);
        await port.replace(
          DeviceReminderRequest(
            id: 0x40000001,
            token: dueKey,
            sourceKind: 'standalone',
            sourceId: dueSourceId,
            fingerprint: dueHash,
            at: DateTime.utc(2099, 1, 1),
          ),
        );
        final scheduled =
            calls.firstWhere((c) => c.method == 'zonedSchedule').arguments
                as Map;
        expect(scheduled['payload'], dueKey);
        expect(
          scheduled['body'],
          'لديك تذكير بموعد دين. افتح الدفتر للمراجعة.',
        );
        expect(scheduled.toString(), isNot(contains(dueSourceId)));
        expect(scheduled.toString(), isNot(contains('عميل اختبار')));
        expect(await port.pendingIds(), {0x40000001});
        await port.cancel(0x40000001);
        expect(await port.pendingIds(), isEmpty);
        expect(await port.openSettings(), isTrue);
        expect(
          calls.any(
            (c) =>
                c.method.toLowerCase().contains('exact') ||
                c.method.contains('PolicyAccess'),
          ),
          isFalse,
        );
      },
    );
  }
  test(
    'Windows facade + settings channel confirms permission separately, generic payload, verified removal',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      const windows = MethodChannel('eldafttar/debt_reminders');
      var allowed = false;
      messenger.setMockMethodCallHandler(
        windows,
        (call) async => call.method == 'enabled' ? allowed : true,
      );
      addTearDown(() => messenger.setMockMethodCallHandler(windows, null));
      final fake = MemoryNotificationFacade(),
          port = LocalDebtNotificationPort(plugin: fake);
      await port.initialize((_) {});
      expect(
        fake.settings!.windows!.appUserModelId,
        'ElDafttar.ERP.DebtReminders',
      );
      expect(await port.permission(), ReminderPermission.denied);
      allowed = true;
      expect(await port.requestPermission(), ReminderPermission.allowed);
      await port.replace(
        DeviceReminderRequest(
          id: 0x40000001,
          token: dueKey,
          sourceKind: 'standalone',
          sourceId: dueSourceId,
          fingerprint: dueHash,
          at: DateTime.utc(2099),
        ),
      );
      expect(await port.pendingIds(), {0x40000001});
      expect(fake.payload, dueKey);
      expect(fake.body, isNot(contains('10005')));
      await port.cancel(0x40000001);
      expect(await port.pendingIds(), isEmpty);
      expect(await port.openSettings(), isTrue);
    },
  );
}
