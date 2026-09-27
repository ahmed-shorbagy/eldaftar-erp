import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/config/supabase_public_config.dart';
import 'src/config/supabase_startup.dart';
import 'src/features/auth/data/supabase_auth_gateway.dart';
import 'src/features/daily_ledger/data/http_opening_gateway.dart';
import 'src/features/daily_ledger/data/shared_preferences_pending_store.dart';
import 'src/features/shop_accounts/data/supabase_shop_account_gateway.dart';
import 'src/theme/theme_controller.dart';
import 'src/theme/theme_preference_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = SupabasePublicConfig.fromEnvironment;
  final supabaseStatus = await prepareSupabase(config, _startSupabase);
  final preferences = await SharedPreferences.getInstance();
  final themeController = ThemeController(
    store: SharedPreferencesThemeStore(preferences),
  );
  await themeController.load();
  runApp(
    ElDafttarApp(
      supabaseStatus: supabaseStatus,
      authGateway: supabaseStatus == SupabaseStartupStatus.ready
          ? SupabaseAuthGateway(Supabase.instance.client)
          : null,
      themeController: themeController,
      shopAccountGateway: supabaseStatus == SupabaseStartupStatus.ready
          ? SupabaseShopAccountGateway(Supabase.instance.client)
          : null,
      openingGateway: supabaseStatus == SupabaseStartupStatus.ready
          ? HttpOpeningGateway(
              client: http.Client(),
              supabaseUrl: config.trimmedUrl,
              publishableKey: config.trimmedPublishableKey,
              accessToken: () =>
                  Supabase.instance.client.auth.currentSession?.accessToken ??
                  '',
              currentUserId: () =>
                  Supabase.instance.client.auth.currentUser?.id,
            )
          : null,
      pendingOpeningStore: supabaseStatus == SupabaseStartupStatus.ready
          ? SharedPreferencesPendingOpeningStore(preferences)
          : null,
      currentUserId: supabaseStatus == SupabaseStartupStatus.ready
          ? () => Supabase.instance.client.auth.currentUser?.id
          : null,
    ),
  );
}

Future<void> _startSupabase(String url, String publishableKey) async {
  await Supabase.initialize(url: url, publishableKey: publishableKey);
}
