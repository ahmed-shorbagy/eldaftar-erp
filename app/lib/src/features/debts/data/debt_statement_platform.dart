import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../daily_ledger/application/idempotency_key.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import '../application/debt_statement_flow.dart';

/// Existing native adapters; no cloud storage, provider or financial command.
class NativeDebtStatementPlatform
    implements DebtStatementPlatform, DebtStatementTemporaryFiles {
  NativeDebtStatementPlatform({
    this.temporaryDirectory,
    this.share,
    this.info,
    this.target,
  });
  final Future<Directory> Function()? temporaryDirectory;
  final Future<bool> Function(Uint8List, String)? share;
  final Future<PrintingInfo> Function()? info;
  final TargetPlatform? target;
  TargetPlatform get _target => target ?? defaultTargetPlatform;
  Future<Directory> _directory() =>
      temporaryDirectory?.call() ??
      (_target == TargetPlatform.iOS
          ? Future.value(Directory.systemTemp)
          : getTemporaryDirectory());
  final _temporaryFiles = <String>{};
  Future<void> _cleanup = Future.value();
  @override
  Future<void> discardTemporaryFiles() {
    _cleanup = _cleanup.catchError((Object _) {}).then((_) => _discard());
    return _cleanup;
  }

  Future<void> _discard() async {
    if (!kIsWeb &&
        const {TargetPlatform.android, TargetPlatform.iOS}.contains(_target)) {
      final root = await _directory();
      final folder = Directory(
        _target == TargetPlatform.android
            ? '${root.path}${Platform.pathSeparator}share'
            : root.path,
      );
      if (await folder.exists()) {
        await for (final entry in folder.list(followLinks: false)) {
          if (entry is File &&
              RegExp(
                r'^كشف-حساب-دين-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}\.pdf$',
              ).hasMatch(entry.uri.pathSegments.last)) {
            _temporaryFiles.add(entry.path);
          }
        }
      }
    }
    for (final path in _temporaryFiles.toList()) {
      final file = File(path);
      if (await file.exists()) await file.delete();
      _temporaryFiles.remove(path);
    }
  }

  @override
  Future<StatementCapabilities> capabilities() async {
    final capability = await (info?.call() ?? Printing.info());
    return StatementCapabilities(
      save:
          !kIsWeb &&
          const {
            TargetPlatform.windows,
            TargetPlatform.linux,
            TargetPlatform.macOS,
          }.contains(_target),
      share:
          !kIsWeb &&
          const {
            TargetPlatform.android,
            TargetPlatform.iOS,
          }.contains(_target) &&
          capability.canShare,
      print: capability.canPrint,
    );
  }

  @override
  Future<StatementOutcome> handoff(
    StatementAction action,
    Uint8List bytes, {
    required bool Function() stillAuthorized,
  }) async {
    if (!stillAuthorized()) return StatementOutcome.stale;
    switch (action) {
      case StatementAction.save:
        final destination = await getSaveLocation(
          suggestedName: 'كشف حساب دين.pdf',
          acceptedTypeGroups: const [
            XTypeGroup(label: 'PDF', extensions: ['pdf']),
          ],
        );
        if (!stillAuthorized()) return StatementOutcome.stale;
        if (destination == null) return StatementOutcome.cancelled;
        final copy = Uint8List.fromList(bytes);
        try {
          await XFile.fromData(
            copy,
            mimeType: 'application/pdf',
            name: 'كشف حساب دين.pdf',
          ).saveTo(destination.path);
          return stillAuthorized()
              ? StatementOutcome.saved
              : StatementOutcome.stale;
        } finally {
          copy.fillRange(0, copy.length, 0);
        }
      case StatementAction.share:
        final directory = await _directory();
        if (!stillAuthorized()) return StatementOutcome.stale;
        final filename = 'كشف-حساب-دين-${newIdempotencyKey()}.pdf';
        final path =
            '${directory.path}${Platform.pathSeparator}${_target == TargetPlatform.android ? 'share${Platform.pathSeparator}' : ''}$filename';
        _temporaryFiles.add(path);
        try {
          await (share?.call(bytes, filename) ??
              Printing.sharePdf(bytes: bytes, filename: filename));
          // Native boolean cannot prove dialog/delivery or distinguish cancellation.
          return stillAuthorized()
              ? StatementOutcome.handedOff
              : StatementOutcome.stale;
        } finally {
          if (!stillAuthorized()) {
            final file = File(path);
            if (await file.exists()) await file.delete();
            _temporaryFiles.remove(path);
          }
        }
      case StatementAction.print:
        final completed = await Printing.layoutPdf(
          name: 'كشف حساب دين',
          dynamicLayout: false,
          onLayout: (_) async {
            if (!stillAuthorized()) throw StateError('statement_access_lost');
            return bytes;
          },
        );
        return completed
            ? StatementOutcome.handedOff
            : StatementOutcome.cancelled;
    }
  }
}
