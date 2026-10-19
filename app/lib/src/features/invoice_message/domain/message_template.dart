import '../../../theme/amount_format.dart';
import '../../daily_ledger/domain/opening_issue.dart';
import '../../daily_ledger/domain/postgres_integer.dart';
import '../../daily_ledger/domain/quantities.dart';

const defaultInvoiceMessage =
    'ملخص العملية رقم {sequence}\n'
    '{kind}\nالإجمالي: {total}\nيرجى مراجعة تفاصيل العملية قبل الإرسال.';
const messageRendererVersion = 1;
const messageTokens = <String, String>{
  'sequence': 'رقم العملية',
  'kind': 'نوع العملية',
  'shop_name': 'اسم المتجر',
  'operation_time': 'وقت العملية',
  'total': 'الإجمالي',
  'customer_name': 'اسم العميل',
  'item_count': 'عدد أسطر الأصناف',
  'grams_14': 'جرامات عيار ١٤',
  'grams_18': 'جرامات عيار ١٨',
  'grams_21': 'جرامات عيار ٢١',
  'grams_22': 'جرامات عيار ٢٢',
  'grams_24': 'جرامات عيار ٢٤',
  'paid': 'المدفوع عند الشراء',
  'obligation': 'المستحق عند تأكيد الشراء',
};

/// Domain failure messages never contain snapshot data or customer text.
final class MessageValidation implements Exception {
  const MessageValidation(this.message);
  final String message;
  @override
  String toString() => message;
}

void validateMessageUnicode(String text) {
  // Dart runes replaces lone surrogates; inspect UTF-16 first instead.
  final units = text.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final c = units[i];
    if (c >= 0xd800 && c <= 0xdbff) {
      if (++i >= units.length || units[i] < 0xdc00 || units[i] > 0xdfff) {
        throw const MessageValidation('يحتوي النص على محرف غير صالح.');
      }
    } else if (c >= 0xdc00 && c <= 0xdfff) {
      throw const MessageValidation('يحتوي النص على محرف غير صالح.');
    }
  }
  for (final c in text.runes) {
    if ((c < 32 && c != 10) ||
        (c >= 127 && c <= 159) ||
        (c >= 0xd800 && c <= 0xdfff) ||
        (c >= 0xfdd0 && c <= 0xfdef) ||
        c % 65536 == 65534 ||
        c % 65536 == 65535 ||
        const {
          173,
          1564,
          1757,
          1807,
          2274,
          6158,
          8203,
          8204,
          8206,
          8207,
          65279,
          69821,
          69837,
          917505,
        }.contains(c) ||
        (c >= 1536 && c <= 1541) ||
        (c >= 2192 && c <= 2193) ||
        (c >= 8234 && c <= 8238) ||
        (c >= 8288 && c <= 8303) ||
        (c >= 65529 && c <= 65531) ||
        (c >= 78896 && c <= 78911) ||
        (c >= 113824 && c <= 113827) ||
        (c >= 119155 && c <= 119162) ||
        (c >= 917536 && c <= 917631)) {
      throw const MessageValidation(
        'احذف محارف التحكم من النص؛ يُسمح بسطر جديد فقط.',
      );
    }
  }
}

final class MessageTemplate {
  MessageTemplate._(this.custom, this._parts);
  final String? custom;
  final List<({String text, bool token})> _parts;
  String get text => custom ?? defaultInvoiceMessage;

  factory MessageTemplate.parse(String? input) {
    // Reject remaining CR; trim Unicode whitespace before scalar validation.
    final normalized = (input ?? '').replaceAll('\r\n', '\n');
    if (normalized.contains('\r')) {
      throw const MessageValidation('احذف محرف الرجوع؛ استخدم سطراً جديداً.');
    }
    final trimmed = normalized.trim();
    validateMessageUnicode(trimmed);
    if (trimmed.runes.length > 400 || '\n'.allMatches(trimmed).length > 8) {
      throw const MessageValidation('الحد الأقصى للنص ٤٠٠ محرف و٨ فواصل أسطر.');
    }
    final custom = trimmed.isEmpty ? null : trimmed;
    final text = custom ?? defaultInvoiceMessage;
    final parts = <({String text, bool token})>[];
    final literal = StringBuffer();
    void flush() {
      if (literal.isNotEmpty) {
        parts.add((text: literal.toString(), token: false));
        literal.clear();
      }
    }

    for (var i = 0; i < text.length;) {
      final c = text[i];
      if (c == '{' || c == '}') {
        if (i + 1 < text.length && text[i + 1] == c) {
          literal.write(c);
          i += 2;
          continue;
        }
        if (c == '}') throw const MessageValidation('قوس إغلاق غير مكتمل.');
        final end = text.indexOf('}', i + 1);
        if (end < 0) throw const MessageValidation('أكمل قوس الحقل المتغير.');
        final name = text.substring(i + 1, end);
        if (!messageTokens.containsKey(name)) {
          throw const MessageValidation(
            'حقل متغير غير مسموح أو أقواس غير صالحة.',
          );
        }
        flush();
        parts.add((text: name, token: true));
        i = end + 1;
      } else {
        literal.write(c);
        i++;
      }
    }
    flush();
    return MessageTemplate._(custom, List.unmodifiable(parts));
  }

  String render(Map<String, Object?> source) {
    final values = messageValues(source);
    final out = StringBuffer();
    for (final part in _parts) {
      out.write(part.token ? values[part.text]! : part.text);
    }
    final body = out.toString();
    validateMessageUnicode(body);
    if (body.runes.length > 500) {
      throw const MessageValidation(
        'الرسالة الناتجة تتجاوز ٥٠٠ محرف. اختصر النص ثم راجعه.',
      );
    }
    return body;
  }
}

String _requiredText(Object? raw) {
  if (raw is! String || raw.trim().isEmpty) {
    throw const MessageValidation('تعذر التحقق من بيانات العملية المؤكدة.');
  }
  validateMessageUnicode(raw);
  return raw.trim();
}

Piastres _money(Object? raw) {
  final result = Piastres.parseWire(_requiredText(raw));
  if (result is! Accepted<Piastres>) {
    throw const MessageValidation('قيمة مالية غير صالحة في العملية المؤكدة.');
  }
  return result.value;
}

String _sumMoney(BigInt value) => displayPounds(_money('$value').poundsText);

Map<String, String> messageValues(Map<String, Object?> source) {
  final kind = source['kind'];
  final raw = source['payload'];
  final seq = _requiredText(source['shop_sequence']);
  if ((kind != 'sale' && kind != 'purchase') ||
      raw is! Map ||
      !RegExp(r'^[1-9][0-9]*$').hasMatch(seq) ||
      !PostgresInteger.fits(BigInt.parse(seq))) {
    throw const MessageValidation('تعذر التحقق من بيانات العملية المؤكدة.');
  }
  final payload = Map<String, Object?>.from(raw);
  if ((payload['version'] != 1 && payload['version'] != 2) ||
      payload['kind'] != kind) {
    throw const MessageValidation('إصدار العملية غير مدعوم.');
  }
  final items = payload['items'];
  final tenders = payload['tenders'];
  if (items is! List || tenders is! List) {
    throw const MessageValidation('بيانات الأصناف أو المدفوعات غير مكتملة.');
  }
  final sums = {
    for (final k in [14, 18, 21, 22, 24]) k: BigInt.zero,
  };
  for (final item in items) {
    if (item is! Map ||
        !sums.containsKey(item['karat']) ||
        item['milligrams'] is! String) {
      throw const MessageValidation('وزن أو عيار غير صالح.');
    }
    final weight = Milligrams.parseWire(item['milligrams'] as String);
    if (weight is! Accepted<Milligrams>) {
      throw const MessageValidation('وزن غير صالح.');
    }
    final k = item['karat'] as int;
    final sum = sums[k]! + weight.value.value;
    if (!PostgresInteger.fits(sum)) {
      throw const MessageValidation('مجموع الأوزان أكبر من المسموح.');
    }
    sums[k] = sum;
  }
  var paid = BigInt.zero;
  for (final tender in tenders) {
    if (tender is! Map) throw const MessageValidation('مدفوعات غير صالحة.');
    paid += _money(tender['piastres']).value;
    if (!PostgresInteger.fits(paid)) {
      throw const MessageValidation('مجموع المدفوعات أكبر من المسموح.');
    }
  }
  final name = payload['customer_name'];
  if (name != null && name is! String) {
    throw const MessageValidation('اسم العميل غير صالح.');
  }
  if (name is String) validateMessageUnicode(name);
  return {
    'sequence': seq,
    'kind': kind == 'sale' ? 'بيع' : 'شراء',
    'shop_name': _requiredText(source['shop_name']),
    'operation_time': messageOperationTime(source),
    'total': displayPounds(_money(payload['total_piastres']).poundsText),
    'customer_name': (name as String? ?? '').trim(),
    'item_count': '${items.length}',
    for (final entry in sums.entries)
      'grams_${entry.key}': entry.value == BigInt.zero
          ? ''
          : (Milligrams.parseWire('${entry.value}') as Accepted<Milligrams>)
                .value
                .gramsText,
    'paid': kind == 'purchase' && tenders.isNotEmpty ? _sumMoney(paid) : '',
    'obligation':
        kind == 'purchase' && payload['purchase_obligation_piastres'] != null
        ? displayPounds(
            _money(payload['purchase_obligation_piastres']).poundsText,
          )
        : '',
  };
}

/// Local timestamp is authoritative only when supplied with its server zone.
String messageOperationTime(Map<String, Object?> source) {
  _requiredText(source['time_zone']);
  final utc = _requiredText(source['occurred_at']);
  final local = _requiredText(source['occurred_at_shop']);
  if (!RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?Z$').hasMatch(utc) ||
      !RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$').hasMatch(local) ||
      DateTime.tryParse(utc)?.isUtc != true ||
      DateTime.parse(utc).toIso8601String().substring(0, 19) !=
          utc.substring(0, 19)) {
    throw const MessageValidation(
      'تعذر التحقق من وقت العملية والمنطقة الزمنية.',
    );
  }
  final date = DateTime.tryParse('${local}Z');
  if (date == null || date.toIso8601String().substring(0, 19) != local) {
    throw const MessageValidation('وقت العملية غير صالح.');
  }
  const months = [
    'يناير',
    'فبراير',
    'مارس',
    'أبريل',
    'مايو',
    'يونيو',
    'يوليو',
    'أغسطس',
    'سبتمبر',
    'أكتوبر',
    'نوفمبر',
    'ديسمبر',
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}، ${local.substring(11, 16)}';
}

String? messageEgyptianPhone(Object? raw) {
  if (raw is! String) return null;
  final phone = raw.trim().replaceAll(RegExp(r'[\s()-]'), '');
  if (RegExp(r'^01[0-9]{9}$').hasMatch(phone)) return '2$phone';
  if (RegExp(r'^\+201[0-9]{9}$').hasMatch(phone)) return phone.substring(1);
  return RegExp(r'^201[0-9]{9}$').hasMatch(phone) ? phone : null;
}

Uri messageWhatsappUri(String body, Object? snapshotPhone) {
  final phone = messageEgyptianPhone(snapshotPhone);
  if (phone == null) {
    throw const MessageValidation(
      'لا يحتوي المستند المؤكد على رقم مصري صالح لواتساب.',
    );
  }
  validateMessageUnicode(body);
  if (body.runes.length > 500) {
    throw const MessageValidation('الرسالة الناتجة تتجاوز ٥٠٠ محرف.');
  }
  final uri = Uri.https('wa.me', '/$phone', {'text': body});
  if (uri.toString().length > 1800) {
    throw const MessageValidation(
      'الرابط المشفّر يتجاوز ١٨٠٠ محرف. اختصر النص ثم راجعه.',
    );
  }
  return uri;
}
