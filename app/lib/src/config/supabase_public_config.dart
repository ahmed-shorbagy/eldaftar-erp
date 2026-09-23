/// Public Supabase client settings from `--dart-define`.
///
/// Both [url] and [publishableKey] must be non-empty. A secret or
/// service-role key must never be supplied here.
class SupabasePublicConfig {
  const SupabasePublicConfig({required this.url, required this.publishableKey});

  static const fromEnvironment = SupabasePublicConfig(
    url: String.fromEnvironment('SUPABASE_URL'),
    publishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );

  final String url;
  final String publishableKey;

  String get trimmedUrl => url.trim();

  String get trimmedPublishableKey => publishableKey.trim();

  bool get isComplete =>
      trimmedUrl.isNotEmpty && trimmedPublishableKey.isNotEmpty;
}
