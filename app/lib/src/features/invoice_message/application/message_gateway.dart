abstract class InvoiceMessageGateway {
  Object? messageSession(String userId);
  Future<MessageProfile> readMessage(String user, String shop);
  Future<MessageReview> reviewMessage(
    String user,
    String shop,
    Map<String, Object?> payload,
  );
  Future<MessageTransport> sendMessage(
    String user,
    String shop,
    Map<String, Object?> body,
  );
  Future<MessageTransport> messageStatus(
    String user,
    String shop,
    Map<String, Object?> body,
  );
  Future<MessageSource> readMessageSource(
    String user,
    String shop,
    String operation,
  );
}

final class MessageGatewayException implements Exception {
  const MessageGatewayException([this.code]);
  final String? code;
}

final class MessageProfile {
  const MessageProfile({
    required this.shop,
    required this.revision,
    required this.template,
    required this.canWrite,
    required this.zone,
    this.atUtc,
    this.atShop,
  });
  final String shop;
  final int revision;
  final String? template;
  final bool canWrite;
  final String zone;
  final String? atUtc;
  final String? atShop;
}

final class MessageReview {
  const MessageReview(this.status, this.revision, this.canWrite);
  final String status;
  final int revision;
  final bool canWrite;
}

final class MessageReceipt {
  const MessageReceipt({
    required this.shop,
    required this.key,
    required this.actor,
    required this.payload,
    required this.revision,
    required this.at,
  });
  final String shop, key, actor, at;
  final int revision;
  final Map<String, Object?> payload;
}

final class MessageTransport {
  const MessageTransport({this.receipt, this.error, this.absent = false});
  final MessageReceipt? receipt;
  final String? error;
  final bool absent;
}

final class MessageSource {
  const MessageSource(this.profile, this.operation);
  final MessageProfile profile;
  final Map<String, Object?> operation;
}

enum MessageLaunch { opened, unavailable, failure, unknown }

abstract class MessageLauncher {
  Future<MessageLaunch> launch(Uri uri);
}
