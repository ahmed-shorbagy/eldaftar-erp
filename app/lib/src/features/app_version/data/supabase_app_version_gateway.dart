import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/app_version_gateway.dart';
import '../domain/app_version_policy.dart';

class SupabaseAppVersionGateway implements AppVersionGateway {
  const SupabaseAppVersionGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<AppVersionSnapshot> getPolicy() async {
    try {
      final response = await _client
          .rpc('get_app_version_policy_v1')
          .timeout(const Duration(seconds: 15));
      return _parse(response);
    } on AppVersionException {
      rethrow;
    } on PostgrestException catch (error) {
      if (error.code == '42501' || error.code == 'PGRST301') {
        throw const AppVersionException(AppVersionFailure.unauthorized);
      }
      throw const AppVersionException(AppVersionFailure.unavailable);
    } catch (_) {
      throw const AppVersionException(AppVersionFailure.unavailable);
    }
  }

  static AppVersionSnapshot _parse(Object? value) {
    if (value is! List) {
      throw const AppVersionException(AppVersionFailure.invalidResponse);
    }
    final platforms = <AppVersionPlatformPolicy>[];
    for (final row in value) {
      if (row is! Map) {
        throw const AppVersionException(AppVersionFailure.invalidResponse);
      }
      final map = Map<String, dynamic>.from(row);
      final platformName = map['platform'];
      final platform = platformName is String
          ? appVersionPlatformFromName(platformName)
          : null;
      final minVersion = map['min_version'];
      final message = map['message_ar'];
      final url = map['update_url'];
      if (platform == null ||
          message is! String ||
          (minVersion != null &&
              (minVersion is! String || !isValidAppVersion(minVersion))) ||
          (url != null && url is! String)) {
        throw const AppVersionException(AppVersionFailure.invalidResponse);
      }
      platforms.add(
        AppVersionPlatformPolicy(
          platform: platform,
          minVersion: minVersion as String?,
          messageAr: message,
          updateUrl: url as String?,
        ),
      );
    }
    return AppVersionSnapshot(platforms: platforms);
  }
}
