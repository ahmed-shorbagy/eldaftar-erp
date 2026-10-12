import '../../daily_ledger/domain/opening_issue.dart';
import '../../daily_ledger/domain/postgres_integer.dart';
import '../../daily_ledger/domain/quantities.dart';

/// Repair validation codes. Arabic copy stays in presentation.
enum RepairIssue {
  invalidInput,
  unsupportedKarat,
  weightRequired,
  feeRequired,
  collectedExceedsFee,
  collectionMismatch,
  overflow,
}

sealed class RepairRulesResult<T> {
  const RepairRulesResult();
}

final class RepairAccepted<T> extends RepairRulesResult<T> {
  const RepairAccepted(this.value);
  final T value;
}

final class RepairRejected<T> extends RepairRulesResult<T> {
  const RepairRejected(this.issue);
  final RepairIssue issue;
}

const repairKarats = <int>[14, 18, 21, 22, 24];

const repairCashMethods = <String>[
  'cash',
  'instant_transfer',
  'wallet',
  'card',
];

/// True when two-decimal gram display would hide a stored milligram.
bool repairRoundingHidesMilligrams(BigInt milligrams) =>
    milligrams.abs() % BigInt.from(10) != BigInt.zero;

enum RepairCollectionMode { all, part, none }

final class RepairTender {
  const RepairTender({required this.method, required this.piastres});

  final String method;
  final BigInt piastres;

  Map<String, Object?> toJson() => {
    'method': method,
    'piastres': piastres.toString(),
  };
}

/// Intake never changes saleable stock or cash. Custody increases once.
final class RepairIntakeCommand {
  const RepairIntakeCommand({
    required this.customerName,
    required this.customerPhone,
    required this.itemDescription,
    required this.measuredMilligrams,
    required this.karat,
    required this.issue,
    required this.intakeNotes,
    required this.estimatedFeePiastres,
  });

  final String customerName;
  final String customerPhone;
  final String itemDescription;
  final BigInt measuredMilligrams;
  final int karat;
  final String issue;
  final String intakeNotes;
  final BigInt? estimatedFeePiastres;

  BigInt get stockMilligrams => BigInt.zero;
  BigInt get cashPiastres => BigInt.zero;

  Map<String, Object?> payload() => {
    'version': 1,
    'kind': 'repair_intake',
    'customer_name': customerName,
    'customer_phone': customerPhone,
    'item_description': itemDescription,
    'measured_milligrams': measuredMilligrams.toString(),
    'karat': karat,
    'issue': issue,
    'intake_notes': intakeNotes,
    'estimated_fee_piastres': estimatedFeePiastres?.toString(),
  };
}

final class RepairHandoverCommand {
  const RepairHandoverCommand({
    required this.repairId,
    required this.expectedVersion,
    required this.finalFeePiastres,
    required this.mode,
    required this.collectedPiastres,
    required this.tenders,
    required this.custodyMilligrams,
    this.expectedDayId,
    this.expectedDayVersion,
  });

  final String repairId;
  final BigInt expectedVersion;
  final BigInt finalFeePiastres;
  final RepairCollectionMode mode;
  final BigInt collectedPiastres;
  final List<RepairTender> tenders;
  final BigInt custodyMilligrams;
  final String? expectedDayId;
  final BigInt? expectedDayVersion;

  BigInt get outstandingPiastres => finalFeePiastres - collectedPiastres;
  BigInt get stockMilligrams => BigInt.zero;

  Map<String, Object?> payload() => {
    'version': 1,
    'kind': 'repair_handover',
    'repair_id': repairId,
    'expected_version': expectedVersion.toString(),
    'final_fee_piastres': finalFeePiastres.toString(),
    'collection': mode.name,
    'collected_piastres': collectedPiastres.toString(),
    'tenders': [for (final tender in tenders) tender.toJson()],
    if (collectedPiastres > BigInt.zero) ...{
      'expected_day_id': expectedDayId,
      'expected_day_version': expectedDayVersion.toString(),
    },
  };
}

final class RepairStatusCommand {
  const RepairStatusCommand({
    required this.repairId,
    required this.expectedVersion,
    required this.status,
  });

  final String repairId;
  final BigInt expectedVersion;
  final String status;

  Map<String, Object?> payload() => {
    'version': 1,
    'kind': 'repair_status',
    'repair_id': repairId,
    'expected_version': expectedVersion.toString(),
    'status': status,
  };
}

final class RepairCancelCommand {
  const RepairCancelCommand({
    required this.repairId,
    required this.expectedVersion,
    required this.reason,
    required this.custodyMilligrams,
  });

  final String repairId;
  final BigInt expectedVersion;
  final String reason;
  final BigInt custodyMilligrams;

  BigInt get cashPiastres => BigInt.zero;
  BigInt get stockMilligrams => BigInt.zero;

  Map<String, Object?> payload() => {
    'version': 1,
    'kind': 'repair_cancel',
    'repair_id': repairId,
    'expected_version': expectedVersion.toString(),
    'reason': reason,
    'confirm_return': true,
  };
}

final class RepairArchiveCommand {
  const RepairArchiveCommand({
    required this.repairId,
    required this.expectedVersion,
    required this.outstandingPiastres,
  });

  final String repairId;
  final BigInt expectedVersion;
  final BigInt outstandingPiastres;

  BigInt get cashPiastres => BigInt.zero;

  Map<String, Object?> payload() => {
    'version': 1,
    'kind': 'repair_archive',
    'repair_id': repairId,
    'expected_version': expectedVersion.toString(),
    'confirm_archive': true,
  };
}

abstract final class RepairRules {
  static RepairRulesResult<RepairIntakeCommand> reviewIntake({
    required String customerName,
    required String customerPhone,
    required String itemDescription,
    required String gramsText,
    required int? karat,
    required String issue,
    required String intakeNotes,
    required String estimatedPounds,
  }) {
    final name = customerName.trim();
    final phone = customerPhone.trim();
    final item = itemDescription.trim();
    final problem = issue.trim();
    final notes = intakeNotes.trim();
    if (name.isEmpty ||
        name.length > 200 ||
        item.isEmpty ||
        item.length > 300 ||
        problem.isEmpty ||
        problem.length > 500 ||
        notes.length > 1000) {
      return const RepairRejected(RepairIssue.invalidInput);
    }
    if (phone.isNotEmpty && !RegExp(r'^\+?[0-9]{7,15}$').hasMatch(phone)) {
      return const RepairRejected(RepairIssue.invalidInput);
    }
    if (karat == null || !repairKarats.contains(karat)) {
      return const RepairRejected(RepairIssue.unsupportedKarat);
    }
    final weight = Milligrams.parseGrams(gramsText.trim());
    if (weight is Rejected<Milligrams>) {
      return RepairRejected(
        weight.code.name == 'overflow'
            ? RepairIssue.overflow
            : RepairIssue.invalidInput,
      );
    }
    final milligrams = (weight as Accepted<Milligrams>).value.value;
    if (milligrams == BigInt.zero) {
      return const RepairRejected(RepairIssue.weightRequired);
    }
    BigInt? estimate;
    final feeText = estimatedPounds.trim();
    if (feeText.isNotEmpty) {
      final parsed = Piastres.parsePounds(feeText);
      if (parsed is Rejected<Piastres>) {
        return RepairRejected(
          parsed.code.name == 'overflow'
              ? RepairIssue.overflow
              : RepairIssue.invalidInput,
        );
      }
      estimate = (parsed as Accepted<Piastres>).value.value;
    }
    return RepairAccepted(
      RepairIntakeCommand(
        customerName: name,
        customerPhone: phone,
        itemDescription: item,
        measuredMilligrams: milligrams,
        karat: karat,
        issue: problem,
        intakeNotes: notes,
        estimatedFeePiastres: estimate,
      ),
    );
  }

  static RepairRulesResult<RepairHandoverCommand> reviewHandover({
    required String repairId,
    required BigInt expectedVersion,
    required BigInt custodyMilligrams,
    required String finalPounds,
    required RepairCollectionMode mode,
    required String collectedPounds,
    required List<RepairTender> tenders,
    required String? expectedDayId,
    required BigInt? expectedDayVersion,
  }) {
    if (expectedVersion < BigInt.one || custodyMilligrams <= BigInt.zero) {
      return const RepairRejected(RepairIssue.invalidInput);
    }
    final finalFee = _pounds(finalPounds.trim());
    if (finalFee is RepairRejected<BigInt>) {
      return finalFee.issue == RepairIssue.invalidInput &&
              finalPounds.trim().isEmpty
          ? const RepairRejected(RepairIssue.feeRequired)
          : RepairRejected(finalFee.issue);
    }
    final fee = (finalFee as RepairAccepted<BigInt>).value;
    final BigInt collected;
    if (mode == RepairCollectionMode.none) {
      if (fee == BigInt.zero) {
        collected = BigInt.zero;
      } else if (collectedPounds.trim().isNotEmpty) {
        return const RepairRejected(RepairIssue.collectionMismatch);
      } else {
        collected = BigInt.zero;
      }
    } else if (mode == RepairCollectionMode.all) {
      collected = fee;
    } else {
      final parsed = _pounds(collectedPounds.trim());
      if (parsed is RepairRejected<BigInt>) return RepairRejected(parsed.issue);
      collected = (parsed as RepairAccepted<BigInt>).value;
    }
    if (mode == RepairCollectionMode.none && collected != BigInt.zero) {
      return const RepairRejected(RepairIssue.collectionMismatch);
    }
    if (mode == RepairCollectionMode.all &&
        (collected != fee || collected == BigInt.zero)) {
      return const RepairRejected(RepairIssue.collectionMismatch);
    }
    if (mode == RepairCollectionMode.part &&
        (collected <= BigInt.zero || collected >= fee)) {
      return const RepairRejected(RepairIssue.collectionMismatch);
    }
    if (collected > fee) {
      return const RepairRejected(RepairIssue.collectedExceedsFee);
    }
    if (!_tendersMatch(tenders, collected)) {
      return const RepairRejected(RepairIssue.collectionMismatch);
    }
    if (collected == BigInt.zero) {
      if (expectedDayId != null || expectedDayVersion != null) {
        return const RepairRejected(RepairIssue.invalidInput);
      }
    } else if (expectedDayId == null ||
        expectedDayVersion == null ||
        expectedDayVersion < BigInt.one) {
      return const RepairRejected(RepairIssue.invalidInput);
    }
    return RepairAccepted(
      RepairHandoverCommand(
        repairId: repairId,
        expectedVersion: expectedVersion,
        finalFeePiastres: fee,
        mode: mode,
        collectedPiastres: collected,
        tenders: collected == BigInt.zero
            ? const []
            : List.unmodifiable(tenders),
        custodyMilligrams: custodyMilligrams,
        expectedDayId: collected == BigInt.zero ? null : expectedDayId,
        expectedDayVersion: collected == BigInt.zero
            ? null
            : expectedDayVersion,
      ),
    );
  }

  static RepairRulesResult<RepairCancelCommand> reviewCancel({
    required String repairId,
    required BigInt expectedVersion,
    required String reason,
    required BigInt custodyMilligrams,
    required bool confirmReturn,
  }) {
    final text = reason.trim();
    if (!confirmReturn ||
        text.isEmpty ||
        text.length > 500 ||
        expectedVersion < BigInt.one ||
        custodyMilligrams <= BigInt.zero) {
      return const RepairRejected(RepairIssue.invalidInput);
    }
    return RepairAccepted(
      RepairCancelCommand(
        repairId: repairId,
        expectedVersion: expectedVersion,
        reason: text,
        custodyMilligrams: custodyMilligrams,
      ),
    );
  }

  static RepairRulesResult<RepairArchiveCommand> reviewArchive({
    required String repairId,
    required BigInt expectedVersion,
    required BigInt outstandingPiastres,
    required bool terminal,
    required bool confirmArchive,
  }) {
    if (!confirmArchive ||
        !terminal ||
        expectedVersion < BigInt.one ||
        outstandingPiastres < BigInt.zero) {
      return const RepairRejected(RepairIssue.invalidInput);
    }
    return RepairAccepted(
      RepairArchiveCommand(
        repairId: repairId,
        expectedVersion: expectedVersion,
        outstandingPiastres: outstandingPiastres,
      ),
    );
  }

  static bool canAdvanceStatus(String from, String to) =>
      (from == 'received' && to == 'in_progress') ||
      (from == 'in_progress' && to == 'ready');

  static RepairRulesResult<BigInt> _pounds(String text) {
    if (text.isEmpty) return const RepairRejected(RepairIssue.feeRequired);
    final parsed = Piastres.parsePounds(text);
    if (parsed is Rejected<Piastres>) {
      return RepairRejected(
        parsed.code.name == 'overflow'
            ? RepairIssue.overflow
            : RepairIssue.invalidInput,
      );
    }
    final value = (parsed as Accepted<Piastres>).value.value;
    if (!PostgresInteger.fits(value)) {
      return const RepairRejected(RepairIssue.overflow);
    }
    return RepairAccepted(value);
  }

  static bool _tendersMatch(List<RepairTender> tenders, BigInt collected) {
    if (collected == BigInt.zero) return tenders.isEmpty;
    if (tenders.isEmpty || tenders.length > 4) return false;
    final seen = <String>{};
    var sum = BigInt.zero;
    for (final tender in tenders) {
      if (!repairCashMethods.contains(tender.method) ||
          !seen.add(tender.method) ||
          tender.piastres <= BigInt.zero ||
          !PostgresInteger.fits(tender.piastres)) {
        return false;
      }
      final next = PostgresInteger.checkedAdd(sum, tender.piastres);
      if (next == null) return false;
      sum = next;
    }
    return sum == collected;
  }
}
