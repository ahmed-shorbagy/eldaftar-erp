import '../domain/message_template.dart';
import 'message_contract.dart';
import 'message_gateway.dart';

final class MessagePreview {
  const MessagePreview(
    this.source,
    this.body,
    this.uri,
    this.binding,
    this.session,
  );
  final MessageSource source;
  final String body, binding;
  final Uri uri;
  final Object session;
}

final class MessageHandoffResult {
  const MessageHandoffResult({
    this.launch,
    this.updated,
    this.error,
    this.validationMessage,
  });
  final MessageLaunch? launch;
  final MessagePreview? updated;
  final String? error;
  final String? validationMessage;
}

/// All authorization/freshness inputs are reread before the sole launcher port.
final class MessageHandoff {
  const MessageHandoff(this.gateway, this.launcher, {this.canRead});
  final InvoiceMessageGateway gateway;
  final MessageLauncher launcher;
  final bool Function()? canRead;
  Future<MessagePreview> prepare(
    String user,
    String shop,
    String operation,
  ) async {
    final session = gateway.messageSession(user);
    if (session == null || canRead?.call() == false) {
      throw const MessageGatewayException('session_expired');
    }
    final source = await gateway.readMessageSource(user, shop, operation);
    if (canRead?.call() == false ||
        gateway.messageSession(user) != session ||
        source.profile.shop != shop ||
        source.operation['operation_id'] != operation) {
      throw const MessageGatewayException('discarded');
    }
    final body = MessageTemplate.parse(
      source.profile.template,
    ).render(source.operation);
    final payload = source.operation['payload'] as Map;
    final uri = messageWhatsappUri(body, payload['customer_phone']);
    final binding = canonicalMessageJson({
      'owner': user,
      'shop': shop,
      'operation': source.operation,
      'revision': '${source.profile.revision}',
      'template': source.profile.template,
      'zone': source.profile.zone,
      'renderer': messageRendererVersion,
      'body': body,
      'uri': '$uri',
    });
    return MessagePreview(source, body, uri, binding, session);
  }

  Future<MessageHandoffResult> open(
    String user,
    String shop,
    String operation,
    MessagePreview preview,
  ) async {
    if (canRead?.call() == false ||
        gateway.messageSession(user) != preview.session) {
      return const MessageHandoffResult(error: 'discarded');
    }
    try {
      final fresh = await prepare(user, shop, operation);
      if (fresh.session != preview.session) {
        return const MessageHandoffResult(error: 'discarded');
      }
      if (fresh.binding != preview.binding) {
        return MessageHandoffResult(updated: fresh, error: 'stale');
      }
      // No await between this final identity check and invoking the adapter.
      if (canRead?.call() == false ||
          gateway.messageSession(user) != preview.session) {
        return const MessageHandoffResult(error: 'discarded');
      }
      final result = await launcher.launch(fresh.uri);
      if (canRead?.call() == false ||
          gateway.messageSession(user) != preview.session) {
        return const MessageHandoffResult(error: 'discarded');
      }
      return MessageHandoffResult(launch: result);
    } on MessageGatewayException catch (e) {
      return MessageHandoffResult(error: e.code ?? 'unavailable');
    } on MessageValidation catch (e) {
      return MessageHandoffResult(
        error: 'validation',
        validationMessage: e.message,
      );
    } catch (_) {
      return const MessageHandoffResult(error: 'unavailable');
    }
  }
}
