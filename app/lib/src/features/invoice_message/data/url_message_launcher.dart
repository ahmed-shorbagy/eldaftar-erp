import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../application/message_gateway.dart';

final class UrlMessageLauncher implements MessageLauncher {
  const UrlMessageLauncher();
  @override
  Future<MessageLaunch> launch(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication)
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
