import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'src/app.dart';
import 'src/config/supabase_public_config.dart';
import 'src/config/supabase_startup.dart';
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
      themeController: themeController,
    ),
  );
}

Future<void> _startSupabase(String url, String publishableKey) async {
  await Supabase.initialize(url: url, publishableKey: publishableKey);
}
