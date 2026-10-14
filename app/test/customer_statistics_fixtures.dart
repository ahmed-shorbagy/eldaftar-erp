import 'customer_fixtures.dart';

Map<String, Object?> statisticsJson({
  bool empty = false,
  String utc = '2026-10-13T21:30:00.000000Z',
  String local = '2026-10-14T00:30:00',
}) => {
  'version': 1,
  'policy': 'net_explicit_links_v1',
  'weights': [
    for (final k in [14, 18, 21, 22, 24])
      {
        'karat': k,
        'bought_milligrams': empty
            ? '0'
            : switch (k) {
                14 => '1111',
                18 => '3001',
                21 => '6000',
                24 => '1',
                _ => '0',
              },
        'sold_milligrams': !empty && k == 21 ? '1255' : '0',
      },
  ],
  'bought_count': empty ? '0' : '1',
  'sold_count': empty ? '0' : '1',
  'last_operation': empty
      ? null
      : {
          ...candidateJson(),
          'operation_id': commandKey,
          'operation_kind': 'sale_return',
          'shop_sequence': '9',
          'operation_created_at': utc,
          'operation_created_at_shop': local,
        },
};

Map<String, Object?> statisticsCustomerJson({bool empty = false}) => {
  ...customerJson(),
  'saved_number_policy': 'owner_number_v1',
  'statistics': statisticsJson(empty: empty),
  'last_operation_at': empty ? null : '2026-10-13T21:30:00.000000Z',
  'last_operation_at_shop': empty ? null : '2026-10-14T00:30:00',
};
