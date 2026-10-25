import 'dart:async';
import 'src/features/debts/application/debt_reminder_coordinator.dart';
import 'src/features/debts/data/debt_notification_port.dart';
import 'src/features/debts/data/debt_reminder_device_store.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/config/supabase_public_config.dart';
import 'src/config/supabase_startup.dart';
import 'src/features/app_version/data/supabase_app_version_gateway.dart';
import 'src/features/auth/data/recovery_session_storage.dart';
import 'src/features/auth/data/supabase_auth_gateway.dart';
import 'src/features/auth/domain/password_recovery.dart';
import 'src/features/daily_ledger/data/http_opening_gateway.dart';
import 'src/features/daily_ledger/data/shared_preferences_pending_store.dart';
import 'src/features/onboarding/data/shared_preferences_onboarding_store.dart';
import 'src/features/media/data/r2_media_client.dart';
import 'src/features/shop_accounts/data/supabase_shop_account_gateway.dart';
import 'src/features/shop_accounts/data/supabase_shop_image_gateway.dart';
import 'src/features/shop_accounts/data/supabase_shop_sync_gateway.dart';
import 'src/theme/theme_controller.dart';
import 'src/theme/theme_preference_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = SupabasePublicConfig.fromEnvironment;
  final supabaseStatus = await prepareSupabase(config, _startSupabase);
  final packageInfo = await PackageInfo.fromPlatform();
  final preferences = await SharedPreferences.getInstance();
  final themeController = ThemeController(
    store: SharedPreferencesThemeStore(preferences),
  );
  await themeController.load();
  final authGateway = supabaseStatus == SupabaseStartupStatus.ready
      ? SupabaseAuthGateway(Supabase.instance.client)
      : null;
  final openingGateway = supabaseStatus == SupabaseStartupStatus.ready
      ? HttpOpeningGateway(
          client: http.Client(),
          supabaseUrl: config.trimmedUrl,
          publishableKey: config.trimmedPublishableKey,
          accessToken: () =>
              Supabase.instance.client.auth.currentSession?.accessToken ?? '',
          currentUserId: () => Supabase.instance.client.auth.currentUser?.id,
        )
      : null;
  final r2Media = supabaseStatus == SupabaseStartupStatus.ready
      ? R2MediaClient(
          client: http.Client(),
          supabaseUrl: config.trimmedUrl,
          publishableKey: config.trimmedPublishableKey,
          accessToken: () =>
              Supabase.instance.client.auth.currentSession?.accessToken ?? '',
        )
      : null;
  final reminders = openingGateway == null
      ? null
      : DebtReminderCoordinator(
          gateway: openingGateway,
          store: const SecureDeviceReminderStore(),
          port: LocalDebtNotificationPort(),
          clock: SystemReminderClock(),
        );
  if (reminders != null && Supabase.instance.client.auth.currentUser == null) {
    await reminders.bind(null, null);
  }
  if (reminders != null) {
    Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      if (event.session == null) unawaited(reminders.bind(null, null));
    });
  }
  runApp(
    ElDafttarApp(
      supabaseStatus: supabaseStatus,
      authGateway: authGateway,
      recoveryGateway: authGateway,
      themeController: themeController,
      appVersion: packageInfo.version,
      appVersionGateway: supabaseStatus == SupabaseStartupStatus.ready
          ? SupabaseAppVersionGateway(Supabase.instance.client)
          : null,
      shopAccountGateway: supabaseStatus == SupabaseStartupStatus.ready
          ? SupabaseShopAccountGateway(Supabase.instance.client)
          : null,
      shopImageGateway:
          supabaseStatus == SupabaseStartupStatus.ready && r2Media != null
          ? SupabaseShopImageGateway(Supabase.instance.client, r2Media)
          : null,
      syncGateway: supabaseStatus == SupabaseStartupStatus.ready
          ? SupabaseShopSyncGateway(Supabase.instance.client)
          : null,
      openingGateway: openingGateway,
      reminders: reminders,
      pendingOpeningStore: supabaseStatus == SupabaseStartupStatus.ready
          ? SharedPreferencesPendingOpeningStore(preferences)
          : null,
      onboardingStore: SharedPreferencesOnboardingStore(preferences),
      currentUserId: supabaseStatus == SupabaseStartupStatus.ready
          ? () => Supabase.instance.client.auth.currentUser?.id
          : null,
    ),
  );
}

Future<void> _startSupabase(String url, String publishableKey) async {
  final projectHost = Uri.parse(url).host.split('.').first;
  await Supabase.initialize(
    url: url,
    publishableKey: publishableKey,
    authOptions: FlutterAuthClientOptions(
      localStorage: RecoverySessionStorage(
        SharedPreferencesLocalStorage(
          persistSessionKey: 'sb-$projectHost-auth-token',
        ),
      ),
      // Only the fixed recovery callback may be exchanged for a session.
      detectSessionInUriPredicate: RecoveryCallback.allows,
    ),
  );
}
