import 'dart:convert';

import 'package:eldafttar/src/features/daily_ledger/application/pending_financial_command.dart';
import 'package:eldafttar/src/features/daily_ledger/data/http_opening_gateway.dart';
import 'package:eldafttar/src/features/repairs/application/repair_gateway.dart';
import 'package:eldafttar/src/features/repairs/data/repair_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Response jsonResponse(Object? body, int status) => http.Response(
  jsonEncode(body),
  status,
  headers: const {'content-type': 'application/json; charset=utf-8'},
);

const repairId = '66666666-6666-4666-8666-666666666666';
const dayId = '33333333-3333-4333-8333-333333333333';
const key = '55555555-5555-4555-8555-555555555555';

HttpOpeningGateway gateway(http.Client client) => HttpOpeningGateway(
  client: client,
  supabaseUrl: 'https://example.test/',
  publishableKey: 'publishable-key',
  accessToken: () => 'access-token',
  currentUserId: () => 'owner-a',
);

Map<String, Object?> summaryJson() => {
  'repair_id': repairId,
  'status': 'received',
  'record_version': '1',
  'customer_name': 'عميل',
  'customer_phone': '',
  'item_description': 'خاتم',
  'measured_milligrams': '1255',
  'karat': 21,
  'issue': 'مفصص',
  'custody_held': true,
  'estimated_fee_piastres': '15000',
  'final_fee_piastres': null,
  'collected_piastres': '0',
  'outstanding_piastres': '0',
  'intake_at': '2026-10-12T08:00:00+00:00',
  'intake_at_shop': '2026-10-12T10:00:00',
};

void main() {
  test('codec keeps fee strings and shop-local intake time', () {
    final command = parseRepairCommand({
      'ok': true,
      'replayed': false,
      'repair_id': repairId,
      'operation_id': null,
      'collected_piastres': '0',
      'stock_milligrams': '0',
    });
    expect(command.repairId, repairId);
    expect(command.result['operation_id'], isNull);
    expect(
      () => parseRepairCommand({
        'ok': true,
        'replayed': false,
        'repair_id': 'not-a-uuid',
      }),
      throwsFormatException,
    );
    expect(
      parseRepairCommandStatus({'status': 'absent'}),
      isA<RepairRemoteAbsent>(),
    );
    final completed = parseRepairCommandStatus({
      'status': 'completed',
      'repair_id': repairId,
      'command_kind': 'repair_handover',
      'result': {'ok': true},
    });
    expect((completed as RepairRemoteCompleted).kind, 'repair_handover');
    final page = parseRepairPage({
      'items': [summaryJson()],
      'next_cursor': repairId,
    });
    expect(page.items.single.measuredMilligrams, BigInt.from(1255));
    expect(page.items.single.estimatedFeePiastres, BigInt.from(15000));
    expect(page.items.single.intakeAtShop, '2026-10-12T10:00:00');
    expect(page.nextCursor, repairId);
    final detail = parseRepairDetail({
      ...summaryJson(),
      'intake_notes': 'ملاحظة',
      'financial_operation_id': null,
      'cancellation_reason': null,
      'archived_from_status': null,
      'intake_actor_user_id': '11111111-1111-4111-8111-111111111111',
      'time_zone': 'Africa/Cairo',
      'events': [
        {
          'id': '77777777-7777-4777-8777-777777777777',
          'event_type': 'repair_intake',
          'actor_user_id': '11111111-1111-4111-8111-111111111111',
          'actor_display_name': 'مالك',
          'created_at': '2026-10-12T08:00:00+00:00',
          'created_at_shop': '2026-10-12T10:00:00',
        },
      ],
      'custody_events': [
        {
          'id': '88888888-8888-4888-8888-888888888888',
          'direction': 'intake',
          'measured_milligrams': '1255',
          'karat': 21,
          'created_at_shop': '2026-10-12T10:00:00',
        },
      ],
    });
    expect(detail.events.single.actorDisplayName, 'مالك');
    expect(detail.custodyEvents.single.measuredMilligrams, BigInt.from(1255));
    final context = parseRepairContext({
      'time_zone': 'Africa/Cairo',
      'day': {
        'state': 'open',
        'business_day_id': dayId,
        'business_date': '2026-10-12',
        'day_version': '4',
      },
      'cash_methods': [
        {'method': 'cash', 'balance_piastres': '500000'},
      ],
    });
    expect(context.day.isOpen, isTrue);
    expect(context.cashMethods.single.balancePiastres, BigInt.from(500000));
  });

  test(
    'http adapter posts custody commands and refuses unknown errors',
    () async {
      final calls = <String>[];
      final client = MockClient((request) async {
        calls.add(request.url.path);
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path.endsWith('post_repair_intake_v1')) {
          expect(body['p_idempotency_key'], key);
          return jsonResponse({
            'ok': true,
            'replayed': false,
            'repair_id': repairId,
            'stock_milligrams': '0',
            'cash_piastres': '0',
          }, 200);
        }
        if (request.url.path.endsWith('post_repair_handover_v1')) {
          return jsonResponse({
            'message': 'stale_repair',
            'code': 'P0001',
          }, 400);
        }
        if (request.url.path.endsWith('get_repair_command_status')) {
          return jsonResponse({'status': 'absent'}, 200);
        }
        if (request.url.path.endsWith('list_repairs_v1')) {
          return jsonResponse({
            'items': [summaryJson()],
            'next_cursor': null,
          }, 200);
        }
        return jsonResponse({'message': 'surprise'}, 400);
      });
      final remote = gateway(client);
      final saved = await remote.post(
        callerUserId: 'owner-a',
        command: PendingFinancialCommand(
          key: key,
          kind: 'repair_intake',
          body: {
            'p_idempotency_key': key,
            'p_payload': {
              'version': 1,
              'kind': 'repair_intake',
              'customer_name': 'عميل',
              'customer_phone': '',
              'item_description': 'خاتم',
              'measured_milligrams': '1255',
              'karat': 21,
              'issue': 'مفصص',
              'intake_notes': '',
              'estimated_fee_piastres': '15000',
            },
          },
        ),
      );
      expect(saved, isA<RepairRpcCommitted>());
      final rejected = await remote.post(
        callerUserId: 'owner-a',
        command: PendingFinancialCommand(
          key: key,
          kind: 'repair_handover',
          body: {
            'p_idempotency_key': key,
            'p_payload': {
              'version': 1,
              'kind': 'repair_handover',
              'repair_id': repairId,
              'expected_version': '2',
              'final_fee_piastres': '0',
              'collection': 'none',
              'collected_piastres': '0',
              'tenders': <Object?>[],
            },
          },
        ),
      );
      expect((rejected as RepairRpcRejected).code, 'stale_repair');
      expect(
        await remote.commandStatus(
          callerUserId: 'owner-a',
          idempotencyKey: key,
        ),
        isA<RepairRemoteAbsent>(),
      );
      final page = await remote.list(
        callerUserId: 'owner-a',
        query: 'عميل',
        filter: 'open',
        limit: 20,
        cursor: null,
      );
      expect(page.items.single.customerName, 'عميل');
      final unknown = await remote.post(
        callerUserId: 'owner-a',
        command: PendingFinancialCommand(
          key: key,
          kind: 'repair_status',
          body: {
            'p_idempotency_key': key,
            'p_payload': {
              'version': 1,
              'kind': 'repair_status',
              'repair_id': repairId,
              'expected_version': '1',
              'status': 'in_progress',
            },
          },
        ),
      );
      expect(unknown, isA<RepairRpcUnknown>());
      expect(calls, contains('/rest/v1/rpc/post_repair_intake_v1'));
    },
  );

  test('server failure stays unknown and does not decode as saved', () async {
    final remote = gateway(
      MockClient((request) async => http.Response('unavailable', 500)),
    );
    final result = await remote.post(
      callerUserId: 'owner-a',
      command: PendingFinancialCommand(
        key: key,
        kind: 'repair_cancel',
        body: {
          'p_idempotency_key': key,
          'p_payload': {
            'version': 1,
            'kind': 'repair_cancel',
            'repair_id': repairId,
            'expected_version': '2',
            'reason': 'إرجاع',
            'confirm_return': true,
          },
        },
      ),
    );
    expect(result, isA<RepairRpcUnknown>());
    expect(
      () => remote.detail(callerUserId: 'owner-a', repairId: repairId),
      throwsA(isA<RepairReadException>()),
    );
  });
}
