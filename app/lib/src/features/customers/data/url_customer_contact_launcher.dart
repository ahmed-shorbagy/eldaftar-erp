import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/customer_contact.dart';

class UrlCustomerContactLauncher implements CustomerContactLauncher {
  const UrlCustomerContactLauncher({this.platform, this.canOpen, this.launch});
  final TargetPlatform? platform;
  final Future<bool> Function(Uri)? canOpen;
  final Future<bool> Function(Uri)? launch;
  static const _dialer = MethodChannel('eldafttar/customer_contact');

  @override
  Future<ContactHandoff> open(
    CustomerContactAction action,
    Uri destination, {
    required bool Function() stillAuthorized,
  }) async {
    if (!isCustomerContactUri(action, destination)) {
      return ContactHandoff.unavailable;
    }
    // Generic desktop/web tel handlers cannot guarantee dialer-only behavior.
    if (action == CustomerContactAction.dialer &&
        (kIsWeb ||
            ![
              TargetPlatform.android,
              TargetPlatform.iOS,
            ].contains(platform ?? defaultTargetPlatform))) {
      return ContactHandoff.unavailable;
    }
    try {
      final androidDialer =
          action == CustomerContactAction.dialer &&
          (platform ?? defaultTargetPlatform) == TargetPlatform.android;
      final available = canOpen != null
          ? await canOpen!(destination)
          : androidDialer
          ? await _dialer.invokeMethod<bool>(
                  'canOpenDialer',
                  destination.toString(),
                ) ??
                false
          : await canLaunchUrl(destination);
      if (!available) return ContactHandoff.unavailable;
      if (!stillAuthorized()) return ContactHandoff.stale;
      final opened = launch != null
          ? await launch!(destination)
          : androidDialer
          ? await _dialer.invokeMethod<bool>(
                  'openDialer',
                  destination.toString(),
                ) ??
                false
          : await launchUrl(destination, mode: LaunchMode.externalApplication);
      return opened ? ContactHandoff.opened : ContactHandoff.unavailable;
    } on PlatformException catch (e) {
      return switch (e.code) {
        'PERMISSION_DENIED' || 'permission_denied' => ContactHandoff.denied,
        'PERMISSION_PERMANENTLY_DENIED' => ContactHandoff.permanentlyDenied,
        _ => ContactHandoff.failed,
      };
    } catch (_) {
      return ContactHandoff.failed;
    }
  }
}
