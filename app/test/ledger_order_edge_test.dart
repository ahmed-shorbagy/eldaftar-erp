import 'package:eldafttar/src/features/daily_ledger/application/daily_ledger_view.dart';
import 'package:eldafttar/src/features/daily_ledger/application/ledger_activity.dart';
import 'package:flutter_test/flutter_test.dart';

LedgerFeedLine operation(String id, String utc, {String? sequence}) =>
    LedgerFeedLine(
      kind: 'sale',
      labelAr: 'بيع',
      operationId: id,
      actorDisplayName: 'مالك اختبار',
      occurredAt: utc,
      occurredAtCairo: '2026-10-12T12:00:00',
      shopSequence: sequence,
    );

void main() {
  test('history orders fractional UTC instants rather than timestamp text', () {
    final rows = [
      operation('second', '2026-10-12T09:00:00.100Z'),
      operation('first', '2026-10-12T09:00:00Z'),
      operation('third', '2026-10-12T09:00:00.200Z'),
    ];
    expect(
      sortLedgerHistory(rows, newestFirst: false).map((row) => row.operationId),
      ['first', 'second', 'third'],
    );
    expect(
      sortLedgerHistory(rows, newestFirst: true).map((row) => row.operationId),
      ['third', 'second', 'first'],
    );
  });

  test('server sequence controls order even across clock adjustments', () {
    final rows = [
      operation('later', '2026-10-12T08:59:59Z', sequence: '9007199254740993'),
      operation(
        'earlier',
        '2026-10-12T09:00:00Z',
        sequence: '9007199254740992',
      ),
    ];
    expect(
      sortLedgerHistory(rows, newestFirst: false).map((row) => row.operationId),
      ['earlier', 'later'],
    );
  });

  test(
    'historical rows without sequences retain recorded chronological order',
    () {
      final rows = [
        operation('new', '2026-10-12T09:00:00Z', sequence: '2'),
        operation('old', '2026-10-11T23:59:59Z'),
      ];
      expect(
        sortLedgerHistory(
          rows,
          newestFirst: false,
        ).map((row) => row.operationId),
        ['old', 'new'],
      );
    },
  );
}
