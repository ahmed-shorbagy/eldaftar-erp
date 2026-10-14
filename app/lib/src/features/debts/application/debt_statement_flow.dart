import 'dart:async';
import 'dart:typed_data';
import '../domain/debt_rules.dart';
import '../domain/debt_statement.dart';
import 'debt_statement_gateway.dart';

enum StatementAction { save, share, print }

enum StatementOutcome {
  prepared,
  saved,
  handedOff,
  cancelled,
  unavailable,
  failed,
  stale,
  busy,
}

final class StatementCapabilities {
  const StatementCapabilities({
    this.save = false,
    this.share = false,
    this.print = false,
  });
  final bool save, share, print;
  bool supports(StatementAction action) => switch (action) {
    StatementAction.save => save,
    StatementAction.share => share,
    StatementAction.print => print,
  };
}

abstract interface class DebtStatementPlatform {
  Future<StatementCapabilities> capabilities();
  Future<StatementOutcome> handoff(
    StatementAction action,
    Uint8List bytes, {
    required bool Function() stillAuthorized,
  });
}

typedef StatementRenderer = Future<Uint8List> Function(DebtStatement);

abstract interface class DebtStatementTemporaryFiles {
  Future<void> discardTemporaryFiles();
}

/// Never touches a command locker or posts a financial/export status command.
final class DebtStatementFlow {
  DebtStatementFlow({
    required this.gateway,
    required this.platform,
    required this.render,
    required this.userId,
    required this.shopId,
    required this.sourceKind,
    required this.sourceId,
    required this.canRead,
  });
  final DebtStatementGateway gateway;
  final DebtStatementPlatform platform;
  final StatementRenderer render;
  final String userId, shopId, sourceId;
  final DebtSourceKind sourceKind;
  final bool Function() canRead;
  int _epoch = 0;
  bool busy = false;
  Object? _session;
  Future<void> _retiring = Future.value();
  DebtStatement? statement;
  Uint8List? bytes;
  bool get authorized => canRead() && gateway.statementSession(userId) != null;
  bool get current =>
      authorized &&
      _session != null &&
      gateway.statementSession(userId) == _session;
  void invalidate() {
    _epoch++;
    bytes?.fillRange(0, bytes!.length, 0);
    bytes = null;
    statement = null;
    _session = null;
    if (platform is DebtStatementTemporaryFiles) {
      _retiring = (platform as DebtStatementTemporaryFiles)
          .discardTemporaryFiles();
      unawaited(_retiring.catchError((Object _) {}));
    }
  }

  Future<StatementOutcome> prepare() async {
    if (busy) return StatementOutcome.busy;
    invalidate();
    if (!authorized) return StatementOutcome.stale;
    busy = true;
    final epoch = _epoch;
    _session = gateway.statementSession(userId);
    try {
      await _retiring;
      final s = await _read();
      if (epoch != _epoch || !current) return StatementOutcome.stale;
      final b = await render(s);
      if (epoch != _epoch || !current) {
        b.fillRange(0, b.length, 0);
        return StatementOutcome.stale;
      }
      if (b.length < 4 || String.fromCharCodes(b.take(4)) != '%PDF') {
        b.fillRange(0, b.length, 0);
        return StatementOutcome.failed;
      }
      statement = s;
      bytes = b;
      return StatementOutcome.prepared;
    } catch (_) {
      invalidate();
      return authorized ? StatementOutcome.failed : StatementOutcome.stale;
    } finally {
      busy = false;
      if (!current) invalidate();
    }
  }

  Future<DebtStatement> _read() async {
    final s = await gateway.readStatement(
      callerUserId: userId,
      shopId: shopId,
      sourceKind: sourceKind,
      sourceId: sourceId,
    );
    if (s.shopId != shopId ||
        s.sourceKind != sourceKind ||
        s.sourceId != sourceId) {
      throw const FormatException('statement_identity');
    }
    return s;
  }

  Future<StatementOutcome> handoff(StatementAction action) async {
    if (busy) return StatementOutcome.busy;
    if (!current || statement == null || bytes == null) {
      invalidate();
      return StatementOutcome.stale;
    }
    busy = true;
    final epoch = _epoch;
    final reviewed = statement!;
    bool guard() =>
        epoch == _epoch && current && statement == reviewed && bytes != null;
    try {
      final fresh = await _read();
      if (!guard()) {
        invalidate();
        return StatementOutcome.stale;
      }
      if (fresh.freshness != reviewed.freshness) {
        invalidate();
        return StatementOutcome.stale;
      }
      final caps = await platform.capabilities();
      if (!guard()) {
        invalidate();
        return StatementOutcome.stale;
      }
      if (!caps.supports(action)) return StatementOutcome.unavailable;
      final result = await platform.handoff(
        action,
        bytes!,
        stillAuthorized: guard,
      );
      if (!guard()) {
        invalidate();
        return StatementOutcome.stale;
      }
      return result;
    } catch (_) {
      invalidate();
      return authorized ? StatementOutcome.failed : StatementOutcome.stale;
    } finally {
      busy = false;
    }
  }
}
