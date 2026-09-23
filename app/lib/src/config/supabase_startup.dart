import 'supabase_public_config.dart';

enum SupabaseStartupStatus { missingConfiguration, ready, failed }

typedef SupabaseStarter =
    Future<void> Function(String url, String publishableKey);

/// Initializes Supabase only when both public values are present.
Future<SupabaseStartupStatus> prepareSupabase(
  SupabasePublicConfig config,
  SupabaseStarter start,
) async {
  if (!config.isComplete) {
    return SupabaseStartupStatus.missingConfiguration;
  }
  try {
    await start(config.trimmedUrl, config.trimmedPublishableKey);
    return SupabaseStartupStatus.ready;
  } on Object {
    return SupabaseStartupStatus.failed;
  }
}
