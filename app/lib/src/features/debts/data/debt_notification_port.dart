import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import '../../daily_ledger/application/idempotency_key.dart';
import '../application/debt_reminder_device.dart';

final class SystemReminderClock implements ReminderClock {
  final _watch = Stopwatch()..start();
  @override
  DateTime nowUtc() => DateTime.now().toUtc();
  @override
  Duration get elapsed => _watch.elapsed;
}

/// One-shot, ordinary system notifications. Never requests exact alarm/DND access.
final class LocalDebtNotificationPort implements DebtNotificationPort {
  LocalDebtNotificationPort({
    FlutterLocalNotificationsPlugin? plugin,
    this.windowsChannel = const MethodChannel('eldafttar/debt_reminders'),
  }) : plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin plugin;
  final MethodChannel windowsChannel;
  bool _ready = false;
  bool get _supported =>
      !kIsWeb &&
      const {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.windows,
      }.contains(defaultTargetPlatform);
  @override
  Future<void> initialize(void Function(String token) onTap) async {
    if (!_supported) return;
    void tap(NotificationResponse response) {
      final token = response.payload;
      if (token != null && isUuid(token)) onTap(token);
    }

    final ok = await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_debt_reminder'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
        windows: WindowsInitializationSettings(
          appName: 'الدفتر',
          appUserModelId: 'ElDafttar.ERP.DebtReminders',
          guid: '251bb676-c8bd-4a8e-9f79-c1b6e7a646c2',
        ),
      ),
      onDidReceiveNotificationResponse: tap,
    );
    _ready = ok == true;
    if (!_ready) throw StateError('notification_setup');
    final launch = await plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse != null) {
      tap(launch!.notificationResponse!);
    }
  }

  @override
  Future<ReminderPermission> permission() async {
    if (!_supported || !_ready) return ReminderPermission.unsupported;
    final bool? allowed;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        allowed = await plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.areNotificationsEnabled();
      case TargetPlatform.iOS:
        allowed =
            (await plugin
                    .resolvePlatformSpecificImplementation<
                      IOSFlutterLocalNotificationsPlugin
                    >()
                    ?.checkPermissions())
                ?.isEnabled;
      case TargetPlatform.windows:
        allowed = await windowsChannel.invokeMethod<bool>('enabled');
      default:
        return ReminderPermission.unsupported;
    }
    return allowed == null
        ? ReminderPermission.unsupported
        : allowed
        ? ReminderPermission.allowed
        : ReminderPermission.denied;
  }

  @override
  Future<ReminderPermission> requestPermission() async {
    if (!_supported || !_ready) return ReminderPermission.unsupported;
    if (defaultTargetPlatform == TargetPlatform.android) {
      await plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      await plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, sound: true, badge: false);
    }
    // Windows has no runtime consent dialog; system settings determine enablement.
    return permission();
  }

  @override
  Future<bool> openSettings() async {
    if (!_supported || !_ready) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        await plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.openAppNotificationSettings() ??
            false,
      TargetPlatform.iOS =>
        await plugin
                .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin
                >()
                ?.openAppNotificationSettings() ??
            false,
      TargetPlatform.windows =>
        await windowsChannel.invokeMethod<bool>('settings') ?? false,
      _ => false,
    };
  }

  @override
  Future<Set<int>> pendingIds() async {
    if (!_supported || !_ready) throw UnsupportedError('notifications');
    return (await plugin.pendingNotificationRequests())
        .map((r) => r.id)
        .toSet();
  }

  @override
  Future<void> cancel(int id) async {
    if (!_supported || !_ready) throw UnsupportedError('notifications');
    await plugin.cancel(id: id);
  }

  @override
  Future<void> replace(DeviceReminderRequest request) async {
    if (await permission() != ReminderPermission.allowed) {
      throw StateError('permission_denied');
    }
    await plugin.zonedSchedule(
      id: request.id,
      title: 'الدفتر',
      body: 'لديك تذكير بموعد دين. افتح الدفتر للمراجعة.',
      payload: request.token,
      scheduledDate: tz.TZDateTime.from(request.at, tz.UTC),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'debt_reminders_v1',
          'مواعيد الديون',
          channelDescription: 'تذكير اختياري بمواعيد الديون',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: false,
        ),
        windows: WindowsNotificationDetails(),
      ),
    );
  }
}
