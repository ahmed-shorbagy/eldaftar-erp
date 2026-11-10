import 'package:eldafttar/src/features/invoice_message/domain/message_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Egyptian and Saudi numbers lose the leading + for WhatsApp', () {
    expect(messageWhatsappPhone('+201012345678'), '201012345678');
    expect(messageWhatsappPhone('+966501234567'), '966501234567');
    expect(messageWhatsappPhone('01012345678'), '201012345678');
  });

  test('wa.me URI uses digits without +', () {
    final uri = messageWhatsappUri('مرحبا', '+201012345678');
    expect(uri.host, 'wa.me');
    expect(uri.path, '/201012345678');
    expect(uri.queryParameters['text'], 'مرحبا');
  });
}
