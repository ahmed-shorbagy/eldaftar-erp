enum AppVersionPlatform { android, ios, windows }

class AppVersionPlatformPolicy {
  const AppVersionPlatformPolicy({
    required this.platform,
    this.minVersion,
    this.messageAr = '',
    this.updateUrl,
  });

  final AppVersionPlatform platform;
  final String? minVersion;
  final String messageAr;
  final String? updateUrl;
}

class AppVersionSnapshot {
  const AppVersionSnapshot({required this.platforms});

  final List<AppVersionPlatformPolicy> platforms;

  AppVersionPlatformPolicy? forPlatform(AppVersionPlatform platform) {
    for (final row in platforms) {
      if (row.platform == platform) return row;
    }
    return null;
  }
}

enum AppVersionFailure { unavailable, invalidResponse, unauthorized }

class AppVersionException implements Exception {
  const AppVersionException(this.failure);

  final AppVersionFailure failure;
}

/// Returns -1 if [left] < [right], 0 if equal, 1 if [left] > [right].
int compareAppVersions(String left, String right) {
  final leftParts = _parts(left);
  final rightParts = _parts(right);
  for (var i = 0; i < 3; i++) {
    if (leftParts[i] < rightParts[i]) return -1;
    if (leftParts[i] > rightParts[i]) return 1;
  }
  return 0;
}

bool isValidAppVersion(String value) =>
    RegExp(r'^\d+\.\d+\.\d+$').hasMatch(value);

List<int> _parts(String value) {
  if (!isValidAppVersion(value)) {
    throw const FormatException('invalid_version');
  }
  return value.split('.').map(int.parse).toList(growable: false);
}

AppVersionPlatform? appVersionPlatformFromName(String name) => switch (name) {
  'android' => AppVersionPlatform.android,
  'ios' => AppVersionPlatform.ios,
  'windows' => AppVersionPlatform.windows,
  _ => null,
};

String appVersionPlatformName(AppVersionPlatform platform) => switch (platform) {
  AppVersionPlatform.android => 'android',
  AppVersionPlatform.ios => 'ios',
  AppVersionPlatform.windows => 'windows',
};
