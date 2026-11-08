import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../application/message_gateway.dart';

typedef UrlLaunch = Future<bool> Function(Uri uri, {required LaunchMode mode});

Future<bool> _launchExternal(Uri uri, {required LaunchMode mode}) =>
    launchUrl(uri, mode: mode);

final class UrlMessageLauncher implements MessageLauncher {
  const UrlMessageLauncher({this.open = _launchExternal});
  final UrlLaunch open;

  @override
  Future<MessageLaunch> launch(Uri uri) async {
    final phone = uri.pathSegments.isEmpty ? '' : uri.pathSegments.first;
    final text = uri.queryParameters['text'] ?? '';
    final direct = Uri.parse(
      'whatsapp://send?phone=$phone&text=${Uri.encodeComponent(text)}',
    );
    try {
      if (await open(direct, mode: LaunchMode.externalNonBrowserApplication)) {
        return MessageLaunch.opened;
      }
    } on PlatformException {
      // The https link is the fallback when WhatsApp is not registered.
    }
    try {
      return await open(uri, mode: LaunchMode.externalApplication)
          ? MessageLaunch.opened
          : MessageLaunch.unavailable;
    } on MissingPluginException {
      return MessageLaunch.unavailable;
    } on PlatformException {
      return MessageLaunch.failure;
    } catch (_) {
      return MessageLaunch.unknown;
    }
  }
}
