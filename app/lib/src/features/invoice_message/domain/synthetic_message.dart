/// Synthetic preview only; never submitted to any operation/dispatch port.
Map<String, Object?> syntheticMessageOperation() => {
  'operation_id': '11111111-1111-4111-8111-111111111111',
  'kind': 'sale',
  'shop_sequence': '73',
  'shop_name': 'متجر تجريبي',
  'time_zone': 'Africa/Cairo',
  'occurred_at': '2026-10-18T07:30:00Z',
  'occurred_at_shop': '2026-10-18T10:30:00',
  'payload': <String, Object?>{
    'version': 1,
    'kind': 'sale',
    'total_piastres': '123450',
    'customer_name': 'عميل تجريبي',
    'customer_phone': '01011111111',
    'items': [
      {'karat': 18, 'milligrams': '1255'},
      {'karat': 18, 'milligrams': '2450'},
    ],
    'tenders': [
      {'method': 'cash', 'piastres': '123450'},
    ],
  },
};
