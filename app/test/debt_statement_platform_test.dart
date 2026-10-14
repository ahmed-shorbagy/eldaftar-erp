import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:printing/printing.dart';
import 'package:eldafttar/src/features/debts/application/debt_statement_flow.dart';
import 'package:eldafttar/src/features/debts/data/debt_statement_platform.dart';
import 'package:eldafttar/src/features/daily_ledger/application/idempotency_key.dart';

void main() {
  for (final target in [TargetPlatform.android, TargetPlatform.iOS]) {
    test(
      'native $target unique owned files retired without touching other files',
      () async {
        final root = Directory(
          'build/debt-statement/native-${newIdempotencyKey()}',
        );
        await root.create(recursive: true);
        final folder = target == TargetPlatform.android
            ? Directory('${root.path}/share')
            : root;
        await folder.create(recursive: true);
        final unrelated = File('${folder.path}/other.pdf');
        await unrelated.writeAsBytes([1, 2, 3]);
        var authorized = true;
        final names = <String>[];
        final platform = NativeDebtStatementPlatform(
          target: target,
          temporaryDirectory: () async => root,
          info: () async => const PrintingInfo(canShare: true, canPrint: true),
          share: (bytes, name) async {
            names.add(name);
            await File('${folder.path}/$name').writeAsBytes(bytes);
            return false;
          },
        );
        final caps = await platform.capabilities();
        expect(caps.share, true);
        expect(caps.save, false);
        for (var i = 0; i < 2; i++) {
          expect(
            await platform.handoff(
              StatementAction.share,
              Uint8List.fromList([1, 2]),
              stillAuthorized: () => authorized,
            ),
            StatementOutcome.handedOff,
          );
        }
        expect(names.toSet().length, 2);
        await platform.discardTemporaryFiles();
        expect(
          names.every((n) => !File('${folder.path}/$n').existsSync()),
          true,
        );
        expect(unrelated.existsSync(), true);
        final previous = File(
          '${folder.path}/كشف-حساب-دين-${newIdempotencyKey()}.pdf',
        );
        await previous.writeAsBytes([1]);
        final restart = NativeDebtStatementPlatform(
          target: target,
          temporaryDirectory: () async => root,
        );
        await restart.discardTemporaryFiles();
        expect(previous.existsSync(), false);
        expect(unrelated.existsSync(), true);
        final late = NativeDebtStatementPlatform(
          target: target,
          temporaryDirectory: () async => root,
          share: (bytes, name) async {
            authorized = false;
            await File('${folder.path}/$name').writeAsBytes(bytes);
            return true;
          },
        );
        expect(
          await late.handoff(
            StatementAction.share,
            Uint8List(4),
            stillAuthorized: () => authorized,
          ),
          StatementOutcome.stale,
        );
        expect(folder.listSync().whereType<File>().length, 1);
      },
    );
  }
  test(
    'Windows viewer-open implementation is not offered as sharing',
    () async {
      final p = NativeDebtStatementPlatform(
        target: TargetPlatform.windows,
        info: () async => const PrintingInfo(canShare: true, canPrint: true),
      );
      final caps = await p.capabilities();
      expect(caps.share, false);
      expect(caps.save, true);
      expect(caps.print, true);
    },
  );
}
