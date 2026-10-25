import 'package:flutter/foundation.dart';

import '../domain/app_version_policy.dart';

class AppVersionBlock {
  const AppVersionBlock({
    required this.platform,
    required this.currentVersion,
    required this.requiredVersion,
    required this.messageAr,
    this.updateUrl,
  });

  final AppVersionPlatform platform;
  final String currentVersion;
  final String requiredVersion;
  final String messageAr;
  final String? updateUrl;
}

AppVersionPlatform detectAppVersionPlatform() {
  if (kIsWeb) return AppVersionPlatform.android;
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => AppVersionPlatform.ios,
    TargetPlatform.windows => AppVersionPlatform.windows,
    _ => AppVersionPlatform.android,
  };
}

/// Returns a block when [currentVersion] is strictly below the platform minimum.
AppVersionBlock? evaluateAppVersionBlock({
  required AppVersionSnapshot snapshot,
  required String currentVersion,
  AppVersionPlatform? platform,
}) {
  final resolved = platform ?? detectAppVersionPlatform();
  if (!isValidAppVersion(currentVersion)) return null;
  final policy = snapshot.forPlatform(resolved);
  final min = policy?.minVersion;
  if (min == null || !isValidAppVersion(min)) return null;
  if (compareAppVersions(currentVersion, min) >= 0) return null;
  final message = policy!.messageAr.trim();
  if (message.isEmpty) return null;
  return AppVersionBlock(
    platform: resolved,
    currentVersion: currentVersion,
    requiredVersion: min,
    messageAr: message,
    updateUrl: policy.updateUrl,
  );
}
