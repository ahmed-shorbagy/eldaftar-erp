import '../domain/postgres_integer.dart';
import 'daily_ledger_view.dart';

final class LedgerActivityState {
  const LedgerActivityState({
    required this.userId,
    required this.shopId,
    required this.dayId,
    required this.lines,
    required this.serverSequence,
    required this.hasOlder,
    this.olderCursor,
    this.catchUpAnchor,
  });

  static const empty = LedgerActivityState(
    userId: '',
    shopId: '',
    dayId: '',
    lines: [],
    serverSequence: '0',
    hasOlder: false,
  );

  final String userId;
  final String shopId;
  final String dayId;
  final List<LedgerFeedLine> lines;
  final String serverSequence;
  final bool hasOlder;
  final String? olderCursor;

  /// Highest sequence already merged without skipping a gap.
  /// A newer summary head must not move this past rows that were not fetched.
  final String? catchUpAnchor;

  String? get highestSequence {
    String? highest;
    BigInt? highestValue;
    for (final line in lines) {
      final sequence = line.shopSequence;
      if (sequence == null) continue;
      final parsed = PostgresInteger.parseCanonical(sequence);
      if (parsed == null) continue;
      if (highestValue == null || parsed > highestValue) {
        highestValue = parsed;
        highest = sequence;
      }
    }
    return highest;
  }
}

/// Merges one bounded feed page. Repeated and stale pages do not duplicate
/// or erase rows. A head page does not reopen a finished older walk.
/// A different owner or shop replaces the previous page.
LedgerActivityState mergeLedgerPage({
  required LedgerActivityState current,
  required String userId,
  required String shopId,
  required String dayId,
  required List<LedgerFeedLine> incoming,
  required String serverSequence,
  required String direction,
  required bool hasMore,
  String? nextCursor,
  bool fromSummary = false,
}) {
  final server = PostgresInteger.parseCanonical(
    serverSequence,
    allowZero: true,
  );
  if (server == null || (direction != 'desc' && direction != 'asc')) {
    return current.userId.isEmpty ? current : current;
  }
  final sameIdentity =
      current.userId == userId &&
      current.shopId == shopId &&
      current.dayId == dayId &&
      current.userId.isNotEmpty;
  if (!sameIdentity) {
    return LedgerActivityState(
      userId: userId,
      shopId: shopId,
      dayId: dayId,
      lines: _sorted(incoming),
      serverSequence: serverSequence,
      hasOlder: direction == 'desc' && hasMore,
      olderCursor: direction == 'desc' && hasMore ? nextCursor : null,
      catchUpAnchor: _maxSequenceText(incoming),
    );
  }
  final known = current.serverSequence == '0'
      ? BigInt.zero
      : PostgresInteger.parseCanonical(current.serverSequence, allowZero: true);
  final incomingIds = incoming.map((line) => line.operationId).toSet();
  final knownIds = current.lines.map((line) => line.operationId).toSet();
  final staleSnapshot =
      known != null && server < known && incomingIds.every(knownIds.contains);
  if (staleSnapshot) return current;
  final merged = <String, LedgerFeedLine>{
    for (final line in current.lines) line.operationId: line,
    for (final line in incoming) line.operationId: line,
  };
  final nextServer = known != null && known > server
      ? current.serverSequence
      : serverSequence;
  final incomingMin = _minSequence(incoming);
  final heldMin = _minSequence(current.lines);
  // The page is entirely above rows already held, including a restarted
  // summary of the newest lines. Keep the older cursor where the walk left it.
  final keepOlderWalk =
      (direction == 'desc' || fromSummary) &&
      incomingMin != null &&
      heldMin != null &&
      incomingMin > heldMin;
  return LedgerActivityState(
    userId: userId,
    shopId: shopId,
    dayId: dayId,
    lines: _sorted(merged.values),
    serverSequence: nextServer,
    hasOlder: keepOlderWalk
        ? current.hasOlder
        : direction == 'desc'
        ? hasMore
        : current.hasOlder,
    olderCursor: keepOlderWalk
        ? current.olderCursor
        : direction == 'desc'
        ? (hasMore ? nextCursor : null)
        : current.olderCursor,
    catchUpAnchor: _nextCatchUpAnchor(
      current: current.catchUpAnchor,
      incoming: incoming,
      direction: direction,
      fromSummary: fromSummary,
    ),
  );
}

String? _maxSequenceText(Iterable<LedgerFeedLine> lines) {
  String? highest;
  BigInt? highestValue;
  for (final line in lines) {
    final sequence = line.shopSequence;
    if (sequence == null) continue;
    final parsed = PostgresInteger.parseCanonical(sequence);
    if (parsed == null) continue;
    if (highestValue == null || parsed > highestValue) {
      highestValue = parsed;
      highest = sequence;
    }
  }
  return highest;
}

/// A descending summary whose lowest row is still above [current] leaves the
/// anchor where the client last caught up. An ascending page may move it.
String? _nextCatchUpAnchor({
  required String? current,
  required List<LedgerFeedLine> incoming,
  required String direction,
  required bool fromSummary,
}) {
  final incomingMaxText = _maxSequenceText(incoming);
  final incomingMax = incomingMaxText == null
      ? null
      : PostgresInteger.parseCanonical(incomingMaxText);
  if (incomingMax == null || incomingMaxText == null) return current;
  final incomingMin = _minSequence(incoming);
  final anchor = current == null
      ? null
      : PostgresInteger.parseCanonical(current);
  if (direction == 'asc' && !fromSummary) {
    if (anchor == null || incomingMax > anchor) return incomingMaxText;
    return current;
  }
  if (anchor != null && incomingMin != null && incomingMin > anchor) {
    return current;
  }
  if (anchor == null || incomingMax > anchor) return incomingMaxText;
  return current;
}

BigInt? _minSequence(Iterable<LedgerFeedLine> lines) {
  BigInt? min;
  for (final line in lines) {
    final sequence = line.shopSequence;
    if (sequence == null) continue;
    final parsed = PostgresInteger.parseCanonical(sequence);
    if (parsed == null) continue;
    if (min == null || parsed < min) min = parsed;
  }
  return min;
}

List<LedgerFeedLine> _sorted(Iterable<LedgerFeedLine> lines) {
  final copy = [...lines];
  copy.sort((left, right) {
    final a = left.shopSequence == null
        ? null
        : PostgresInteger.parseCanonical(left.shopSequence!);
    final b = right.shopSequence == null
        ? null
        : PostgresInteger.parseCanonical(right.shopSequence!);
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  });
  return copy;
}

bool feedIdsDisjoint(
  Iterable<LedgerFeedLine> left,
  Iterable<LedgerFeedLine> right,
) {
  final ids = left.map((line) => line.operationId).toSet();
  return right.every((line) => !ids.contains(line.operationId));
}

/// Shop-local wall time supplied by the server. The device clock is not used.
String displayedShopTime({
  required String occurredAtUtc,
  required String occurredAtShop,
}) {
  if (!occurredAtUtc.contains('T') || !occurredAtShop.contains('T')) {
    throw const FormatException('time');
  }
  return occurredAtShop;
}

abstract class LedgerFeedGateway {
  Future<LedgerOperationPage> operationPage({
    required String callerUserId,
    required String shopId,
    required String? dayId,
    required String? beforeSequence,
    required String? afterSequence,
    required int limit,
  });
}

final class LedgerOperationPage {
  const LedgerOperationPage({
    required this.shopId,
    required this.dayId,
    required this.direction,
    required this.limit,
    required this.hasMore,
    required this.serverSequence,
    required this.snapshotSequence,
    required this.items,
    this.nextBeforeSequence,
    this.nextAfterSequence,
  });

  final String shopId;
  final String? dayId;
  final String direction;
  final int limit;
  final bool hasMore;
  final String serverSequence;
  final String snapshotSequence;
  final String? nextBeforeSequence;
  final String? nextAfterSequence;
  final List<LedgerFeedLine> items;
}

class LedgerActivityController {
  LedgerActivityState state = LedgerActivityState.empty;
  int _generation = 0;
  int? _busyGeneration;

  bool get busy => _busyGeneration == _generation;

  void reset() {
    _generation += 1;
    state = LedgerActivityState.empty;
  }

  bool _still(int generation, String userId, String shopId, String dayId) =>
      generation == _generation &&
      state.userId == userId &&
      state.shopId == shopId &&
      state.dayId == dayId;

  void adoptSummary({
    required String userId,
    required String shopId,
    required DailyLedgerView? ledger,
  }) {
    final day = ledger?.businessDay;
    if (ledger == null || !ledger.isConfirmed || day == null) return;
    final cursor = ledger.feedCursor;
    state = mergeLedgerPage(
      current: state,
      userId: userId,
      shopId: shopId,
      dayId: day.id,
      incoming: ledger.feed,
      serverSequence: cursor?.serverSequence ?? state.highestSequence ?? '0',
      direction: cursor?.direction ?? 'desc',
      hasMore: cursor?.hasMore ?? false,
      nextCursor: cursor?.nextBeforeSequence,
      fromSummary: true,
    );
  }

  Future<void> loadOlder({
    required LedgerFeedGateway gateway,
    required String userId,
  }) async {
    if (busy || !state.hasOlder || state.olderCursor == null) return;
    final generation = _generation;
    final capturedUser = state.userId;
    final capturedShop = state.shopId;
    final capturedDay = state.dayId;
    final cursor = state.olderCursor;
    _busyGeneration = generation;
    try {
      final page = await gateway.operationPage(
        callerUserId: userId,
        shopId: capturedShop,
        dayId: capturedDay,
        beforeSequence: cursor,
        afterSequence: null,
        limit: 100,
      );
      if (!_still(generation, capturedUser, capturedShop, capturedDay)) {
        return;
      }
      if (page.shopId != capturedShop ||
          (page.dayId != null && page.dayId != capturedDay)) {
        return;
      }
      state = mergeLedgerPage(
        current: state,
        userId: capturedUser,
        shopId: capturedShop,
        dayId: capturedDay,
        incoming: page.items,
        serverSequence: page.serverSequence,
        direction: page.direction,
        hasMore: page.hasMore,
        nextCursor: page.nextBeforeSequence,
      );
    } catch (error, stack) {
      if (!_still(generation, capturedUser, capturedShop, capturedDay)) {
        return;
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      if (_busyGeneration == generation) _busyGeneration = null;
    }
  }

  /// Walks ascending pages until the snapshot is caught up or [maxPages] is hit.
  Future<int> catchUp({
    required LedgerFeedGateway gateway,
    required String userId,
    int maxPages = 20,
  }) async {
    if (busy || state.userId.isEmpty || state.dayId.isEmpty) return 0;
    final generation = _generation;
    final capturedUser = state.userId;
    final capturedShop = state.shopId;
    final capturedDay = state.dayId;
    final before = state.lines.length;
    _busyGeneration = generation;
    try {
      var pages = 0;
      while (pages < maxPages) {
        if (!_still(generation, capturedUser, capturedShop, capturedDay)) {
          return 0;
        }
        final after = state.catchUpAnchor ?? state.highestSequence;
        if (after == null) break;
        final page = await gateway.operationPage(
          callerUserId: userId,
          shopId: capturedShop,
          dayId: capturedDay,
          beforeSequence: null,
          afterSequence: after,
          limit: 100,
        );
        if (!_still(generation, capturedUser, capturedShop, capturedDay)) {
          return 0;
        }
        if (page.shopId != capturedShop ||
            (page.dayId != null && page.dayId != capturedDay)) {
          return 0;
        }
        final next = mergeLedgerPage(
          current: state,
          userId: capturedUser,
          shopId: capturedShop,
          dayId: capturedDay,
          incoming: page.items,
          serverSequence: page.serverSequence,
          direction: page.direction,
          hasMore: page.hasMore,
          nextCursor: page.nextAfterSequence,
        );
        final grew =
            next.lines.length != state.lines.length ||
            next.serverSequence != state.serverSequence;
        state = next;
        pages += 1;
        if (!grew || !page.hasMore || page.direction != 'asc') break;
      }
    } catch (error, stack) {
      if (!_still(generation, capturedUser, capturedShop, capturedDay)) {
        return 0;
      }
      Error.throwWithStackTrace(error, stack);
    } finally {
      if (_busyGeneration == generation) _busyGeneration = null;
    }
    if (!_still(generation, capturedUser, capturedShop, capturedDay)) return 0;
    final added = state.lines.length - before;
    return added < 0 ? 0 : added;
  }
}
