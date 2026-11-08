import 'dart:typed_data';

import 'package:eldafttar/src/features/daily_ledger/application/financial_gateway.dart';
import 'package:eldafttar/src/features/daily_ledger/application/invoice_whatsapp_share.dart';
import 'package:eldafttar/src/features/daily_ledger/presentation/invoice_pdf_share_dialog.dart';
import 'package:eldafttar/src/features/invoice_message/application/message_gateway.dart';
import 'package:eldafttar/src/features/invoice_message/data/url_message_launcher.dart';
import 'package:eldafttar/src/features/invoice_message/domain/synthetic_message.dart';
import 'package:eldafttar/src/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart';

import 'financial_trade_screen_test.dart' show FakeFinancialGateway;
import 'meeting_ui_completion_test.dart' show completionUser, completionShop;

const _operationId = 'a1333333-3333-4333-8333-333333333333';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the launcher tries WhatsApp directly before the web link', () async {
    final seen = <Uri>[];
    final launcher = UrlMessageLauncher(
      open: (uri, {required LaunchMode mode}) async {
        seen.add(uri);
        return seen.length == 2;
      },
    );
    expect(
      await launcher.launch(Uri.parse('https://wa.me/201012345678?text=مرحبا')),
      MessageLaunch.opened,
    );
    expect(seen.first.scheme, 'whatsapp');
    expect(seen.first.queryParameters['phone'], '201012345678');
    expect(seen.last.scheme, 'https');
  });

  testWidgets('WhatsApp receives the PDF, message, and customer number', (
    t,
  ) async {
    final gateway = _MessageShareGateway();
    final calls = <_ShareCall>[];
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: InvoicePdfShareDialog(
            gateway: gateway,
            userId: completionUser,
            shopId: completionShop,
            operationId: _operationId,
            canRead: () => true,
            canWrite: () => true,
            whatsapp: _FakeWhatsapp(calls),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.byKey(const Key('invoice-image-share')), findsNothing);
    expect(find.byKey(const Key('invoice-pdf-share')), findsOneWidget);
    await t.tap(find.byKey(const Key('invoice-whatsapp-pdf')));
    await t.pumpAndSettle();
    expect(String.fromCharCodes(calls.single.pdf.take(4)), '%PDF');
    expect(calls.single.filename, endsWith('.pdf'));
    expect(calls.single.phone, '201012345678');
    expect(calls.single.text, contains('متجر تجريبي'));
    expect(calls.single.text, contains('73'));
    expect(calls.single.text, contains('1,234.50'));
    expect(
      find.text(
        'فُتحت محادثة العميل في واتساب ومعها الفاتورة والرسالة. أرسلها ثم أكّد هنا.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('a missing WhatsApp app falls back to the share sheet', (
    t,
  ) async {
    final gateway = _DispatchMessageGateway();
    final calls = <_ShareCall>[];
    final fallback = <String>[];
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: InvoicePdfShareDialog(
            gateway: gateway,
            userId: completionUser,
            shopId: completionShop,
            operationId: _operationId,
            canRead: () => true,
            canWrite: () => true,
            whatsapp: _FakeWhatsapp(
              calls,
              result: WhatsappShareResult.notInstalled,
            ),
            share: (bytes, name) async {
              fallback.add(name);
              return true;
            },
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('invoice-whatsapp-pdf')));
    await t.pumpAndSettle();
    expect(fallback.single, endsWith('.pdf'));
    expect(
      find.text('واتساب غير مثبت. اختر تطبيقاً للمشاركة.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('invoice-pdf-confirm')), findsOneWidget);
    expect(gateway.confirms, 0);
  });
}

final class _ShareCall {
  const _ShareCall(this.pdf, this.filename, this.phone, this.text);
  final Uint8List pdf;
  final String filename;
  final String? phone;
  final String text;
}

final class _FakeWhatsapp implements InvoiceWhatsappShare {
  _FakeWhatsapp(this.calls, {this.result = WhatsappShareResult.opened});
  final List<_ShareCall> calls;
  final WhatsappShareResult result;

  @override
  Future<WhatsappShareResult> sharePdf({
    required Uint8List pdf,
    required String filename,
    required String? phoneDigits,
    required String text,
    Rect? origin,
  }) async {
    calls.add(_ShareCall(pdf, filename, phoneDigits, text));
    return result;
  }
}

final class _MessageShareGateway extends FakeFinancialGateway
    implements InvoiceMessageGateway {
  Map<String, Object?> get _sale {
    final base = syntheticMessageOperation();
    final payload = Map<String, Object?>.from(base['payload']! as Map);
    payload['customer_phone'] = '01012345678';
    return {
      ...base,
      'operation_id': _operationId,
      'shop_id': completionShop,
      'payload': payload,
    };
  }

  MessageProfile get _profile => const MessageProfile(
    shop: completionShop,
    revision: 0,
    template: null,
    canWrite: true,
    zone: 'Africa/Cairo',
  );

  @override
  Object? messageSession(String userId) => 'session';

  @override
  Future<Map<String, Object?>> operation({
    required String callerUserId,
    required String operationId,
  }) async => _sale;

  @override
  Future<MessageProfile> readMessage(String user, String shop) async =>
      _profile;

  @override
  Future<MessageReview> reviewMessage(
    String user,
    String shop,
    Map<String, Object?> payload,
  ) async => const MessageReview('ready', 0, true);

  @override
  Future<MessageTransport> sendMessage(
    String user,
    String shop,
    Map<String, Object?> body,
  ) async => const MessageTransport();

  @override
  Future<MessageTransport> messageStatus(
    String user,
    String shop,
    Map<String, Object?> body,
  ) async => const MessageTransport(absent: true);

  @override
  Future<MessageSource> readMessageSource(
    String user,
    String shop,
    String operation,
  ) async => MessageSource(_profile, _sale);
}

final class _DispatchMessageGateway extends _MessageShareGateway
    implements InvoiceDispatchGateway {
  var confirms = 0;

  @override
  Future<PendingInvoicePage> pendingInvoiceSends({
    required String callerUserId,
    int? beforeSequence,
  }) async => const PendingInvoicePage(<PendingInvoice>[], null);

  @override
  Future<InvoiceDispatchState> dispatchState({
    required String callerUserId,
    required String operationId,
  }) async => const InvoiceDispatchState(ownerConfirmed: false);

  @override
  Future<FinancialCommandResult> confirmWhatsappSend({
    required String callerUserId,
    required String operationId,
    required String idempotencyKey,
  }) async {
    confirms++;
    return const FinancialCommitted('sent', replayed: false);
  }
}
