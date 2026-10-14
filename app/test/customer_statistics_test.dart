import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:eldafttar/src/features/customers/data/customer_codec.dart';
import 'package:eldafttar/src/features/customers/domain/customer_statistics.dart';
import 'package:eldafttar/src/features/customers/application/customer_gateway.dart';
import 'package:eldafttar/src/features/shop_accounts/application/shop_sync_ticks.dart';
import 'package:eldafttar/src/features/shop_accounts/domain/shop_sync.dart';
import 'customer_fixtures.dart';
import 'customer_http_test.dart' show gateway, response;
import 'customer_statistics_fixtures.dart';

void main() {
  test('milligrams retain three decimals beyond binary integer precision', () {
    expect(customerGrams(BigInt.from(1)), '0.001');
    expect(customerGrams(BigInt.from(1000)), '1.000');
    expect(
      customerGrams(BigInt.parse('9007199254740993')),
      '9,007,199,254,740.993',
    );
    expect(() => customerGrams(BigInt.from(-1)), throwsArgumentError);
  });
  test(
    'decodes independent directions, counts and shop-local return activity',
    () {
      final c = parseCustomer(
        statisticsCustomerJson(),
        requireStatistics: true,
      );
      expect(c.statistics!.at(21).boughtMilligrams, BigInt.from(6000));
      expect(c.statistics!.at(21).soldMilligrams, BigInt.from(1255));
      expect(c.statistics!.boughtCount, BigInt.one);
      expect(c.statistics!.lastOperation!.kind, 'sale_return');
      expect(c.statistics!.lastOperation!.createdAtShop, '2026-10-14T00:30:00');
      expect(c.updatedAtShop, isNot(c.lastAtShop));
    },
  );
  test('zero linked history differs from fully returned activity', () {
    final empty = parseCustomer(
      statisticsCustomerJson(empty: true),
    ).statistics!;
    expect(empty.hasActivity, false);
    final json = statisticsJson();
    for (final w in json['weights'] as List) {
      (w as Map)['bought_milligrams'] = '0';
      w['sold_milligrams'] = '0';
    }
    final full = parseCustomerStatistics(json);
    expect(full.hasActivity, true);
    expect(full.boughtCount, BigInt.one);
    expect(full.lastOperation, isNotNull);
  });
  test(
    'rejects incomplete, duplicate, floating, negative and inconsistent summaries',
    () {
      final cases = <Map<String, Object?>>[];
      var s = statisticsJson();
      s['policy'] = 'gross';
      cases.add(s);
      s = statisticsJson();
      (s['weights'] as List).removeLast();
      cases.add(s);
      s = statisticsJson();
      ((s['weights'] as List)[1] as Map)['karat'] = 14;
      cases.add(s);
      for (final v in ['-1', '1.001', '01', 1.0]) {
        s = statisticsJson();
        ((s['weights'] as List)[0] as Map)['bought_milligrams'] = v;
        cases.add(s);
      }
      s = statisticsJson();
      s['last_operation'] = null;
      cases.add(s);
      s = statisticsJson();
      s['bought_count'] = '0';
      cases.add(s);
      for (final value in cases) {
        expect(() => parseCustomerStatistics(value), throwsFormatException);
      }
      expect(
        () => parseCustomer(customerJson(), requireStatistics: true),
        throwsFormatException,
      );
      expect(
        () => parseCustomer({
          ...statisticsCustomerJson(),
          'last_operation_at': null,
        }),
        throwsFormatException,
      );
    },
  );
  test(
    'one v2 list request carries all summaries without per-card fan-out',
    () async {
      var calls = 0;
      final g = gateway(
        MockClient((request) async {
          calls++;
          expect(request.url.path.endsWith('get_customer_list_v2'), true);
          final body = jsonDecode(request.body) as Map;
          expect(body['p_limit'], 20);
          expect(body['p_sort'], 'last_operation');
          return response({
            'items': [statisticsCustomerJson()],
            'next_cursor': null,
          }, 200);
        }),
      );
      final page = await g.customers(
        callerUserId: 'owner',
        query: '',
        sort: 'last_operation',
        filter: 'active',
        cursor: null,
      );
      expect(page.items.single.statistics!.boughtCount, BigInt.one);
      expect(calls, 1);
    },
  );
  test('v2 detail requires a summary and retains archived reads', () async {
    final json = {
      ...statisticsCustomerJson(),
      'status': 'archived',
      for (final key in ['notes', 'history', 'links'])
        key: {'items': [], 'next_cursor': null},
    };
    final g = gateway(
      MockClient((request) async {
        expect(request.url.path.endsWith('get_customer_v2'), true);
        return response(json, 200);
      }),
    );
    expect(
      (await g.customer(
        callerUserId: 'owner',
        id: customerId,
      )).customer.archived,
      true,
    );
    json.remove('statistics');
    expect(
      () => g.customer(callerUserId: 'owner', id: customerId),
      throwsA(isA<CustomerReadException>()),
    );
  });
  test('financial revision alone refreshes customer statistics', () {
    final ticks = ShopSyncTicks();
    addTearDown(ticks.dispose);
    const before = ShopSyncSnapshot(
      shopId: 'shop',
      revision: 5,
      customerRevision: 2,
      ledgerRevision: 1,
    );
    const after = ShopSyncSnapshot(
      shopId: 'shop',
      revision: 6,
      customerRevision: 2,
      ledgerRevision: 2,
    );
    ticks.apply(after.changedFrom(before));
    expect(ticks.customer, 1);
    ticks.apply({ShopSyncScope.customer});
    expect(ticks.customer, 2);
    ticks.apply(ShopSyncScope.values.toSet());
    expect(ticks.customer, 3);
  });
}
