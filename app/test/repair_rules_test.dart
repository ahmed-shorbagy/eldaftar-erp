import 'package:eldafttar/src/features/repairs/domain/repair_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'intake keeps milligrams, optional estimate, and zero stock or cash',
    () {
      final reviewed = RepairRules.reviewIntake(
        customerName: '  عميل الإصلاح  ',
        customerPhone: '01001234567',
        itemDescription: 'خاتم',
        gramsText: '1.255',
        karat: 21,
        issue: 'مفصص',
        intakeNotes: 'ملاحظة',
        estimatedPounds: '150',
      );
      final command = (reviewed as RepairAccepted<RepairIntakeCommand>).value;
      expect(command.measuredMilligrams, BigInt.from(1255));
      expect(command.estimatedFeePiastres, BigInt.from(15000));
      expect(command.stockMilligrams, BigInt.zero);
      expect(command.cashPiastres, BigInt.zero);
      expect(command.payload()['estimated_fee_piastres'], '15000');
      expect(repairRoundingHidesMilligrams(command.measuredMilligrams), isTrue);
      expect(repairRoundingHidesMilligrams(BigInt.from(1260)), isFalse);

      final omitted = RepairRules.reviewIntake(
        customerName: 'عميل',
        customerPhone: '',
        itemDescription: 'سلسلة',
        gramsText: '1.000',
        karat: 18,
        issue: 'لحام',
        intakeNotes: '',
        estimatedPounds: '',
      );
      expect(
        (omitted as RepairAccepted<RepairIntakeCommand>)
            .value
            .estimatedFeePiastres,
        isNull,
      );
      expect(
        (RepairRules.reviewIntake(
                  customerName: 'عميل',
                  customerPhone: 'abc',
                  itemDescription: 'سلسلة',
                  gramsText: '1.000',
                  karat: 18,
                  issue: 'لحام',
                  intakeNotes: '',
                  estimatedPounds: '',
                )
                as RepairRejected<RepairIntakeCommand>)
            .issue,
        RepairIssue.invalidInput,
      );
      expect(
        (RepairRules.reviewIntake(
                  customerName: 'عميل',
                  customerPhone: '',
                  itemDescription: 'سلسلة',
                  gramsText: '1.000',
                  karat: 12,
                  issue: 'لحام',
                  intakeNotes: '',
                  estimatedPounds: '',
                )
                as RepairRejected<RepairIntakeCommand>)
            .issue,
        RepairIssue.unsupportedKarat,
      );
      expect(
        (RepairRules.reviewIntake(
                  customerName: 'عميل',
                  customerPhone: '',
                  itemDescription: 'سلسلة',
                  gramsText: '0',
                  karat: 21,
                  issue: 'لحام',
                  intakeNotes: '',
                  estimatedPounds: '',
                )
                as RepairRejected<RepairIntakeCommand>)
            .issue,
        RepairIssue.weightRequired,
      );
    },
  );

  test('handover bounds all, part, none, and over-collection', () {
    RepairHandoverCommand handover({
      required RepairCollectionMode mode,
      String finalPounds = '200',
      String collected = '',
      List<RepairTender> tenders = const [],
      String? dayId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
      BigInt? dayVersion,
    }) =>
        (RepairRules.reviewHandover(
                  repairId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
                  expectedVersion: BigInt.one,
                  custodyMilligrams: BigInt.from(1255),
                  finalPounds: finalPounds,
                  mode: mode,
                  collectedPounds: collected,
                  tenders: tenders,
                  expectedDayId: mode == RepairCollectionMode.none
                      ? null
                      : dayId,
                  expectedDayVersion: mode == RepairCollectionMode.none
                      ? null
                      : (dayVersion ?? BigInt.from(3)),
                )
                as RepairAccepted<RepairHandoverCommand>)
            .value;

    final part = handover(
      mode: RepairCollectionMode.part,
      collected: '80',
      tenders: [RepairTender(method: 'cash', piastres: BigInt.from(8000))],
    );
    expect(part.collectedPiastres, BigInt.from(8000));
    expect(part.outstandingPiastres, BigInt.from(12000));
    expect(part.stockMilligrams, BigInt.zero);
    expect(part.payload().containsKey('expected_day_id'), isTrue);

    final none = handover(mode: RepairCollectionMode.none);
    expect(none.collectedPiastres, BigInt.zero);
    expect(none.outstandingPiastres, BigInt.from(20000));
    expect(none.payload().containsKey('expected_day_id'), isFalse);
    expect(none.tenders, isEmpty);

    final all = handover(
      mode: RepairCollectionMode.all,
      tenders: [
        RepairTender(method: 'cash', piastres: BigInt.from(12000)),
        RepairTender(method: 'wallet', piastres: BigInt.from(8000)),
      ],
    );
    expect(all.collectedPiastres, BigInt.from(20000));
    expect(all.outstandingPiastres, BigInt.zero);

    RepairIssue reject({
      required RepairCollectionMode mode,
      String finalPounds = '200',
      String collected = '',
      List<RepairTender> tenders = const [],
      String? dayId,
      BigInt? dayVersion,
    }) =>
        (RepairRules.reviewHandover(
                  repairId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
                  expectedVersion: BigInt.one,
                  custodyMilligrams: BigInt.from(1255),
                  finalPounds: finalPounds,
                  mode: mode,
                  collectedPounds: collected,
                  tenders: tenders,
                  expectedDayId: dayId,
                  expectedDayVersion: dayVersion,
                )
                as RepairRejected<RepairHandoverCommand>)
            .issue;

    expect(
      reject(
        mode: RepairCollectionMode.part,
        collected: '250',
        tenders: [RepairTender(method: 'cash', piastres: BigInt.from(25000))],
        dayId: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
        dayVersion: BigInt.one,
      ),
      RepairIssue.collectionMismatch,
    );
    expect(
      reject(mode: RepairCollectionMode.all, finalPounds: '0'),
      RepairIssue.collectionMismatch,
    );
    expect(
      reject(mode: RepairCollectionMode.none, collected: '1'),
      RepairIssue.collectionMismatch,
    );
    expect(
      reject(mode: RepairCollectionMode.part, finalPounds: ''),
      RepairIssue.feeRequired,
    );
  });

  test('cancel releases custody with no fee and archive keeps outstanding', () {
    final cancel = RepairRules.reviewCancel(
      repairId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      expectedVersion: BigInt.two,
      reason: '  العميل استرد القطعة  ',
      custodyMilligrams: BigInt.from(1255),
      confirmReturn: true,
    );
    final command = (cancel as RepairAccepted<RepairCancelCommand>).value;
    expect(command.cashPiastres, BigInt.zero);
    expect(command.stockMilligrams, BigInt.zero);
    expect(command.payload()['confirm_return'], isTrue);
    expect(command.reason, 'العميل استرد القطعة');
    expect(
      (RepairRules.reviewCancel(
                repairId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
                expectedVersion: BigInt.one,
                reason: '',
                custodyMilligrams: BigInt.from(1255),
                confirmReturn: true,
              )
              as RepairRejected<RepairCancelCommand>)
          .issue,
      RepairIssue.invalidInput,
    );

    final archive = RepairRules.reviewArchive(
      repairId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
      expectedVersion: BigInt.from(4),
      outstandingPiastres: BigInt.from(12000),
      terminal: true,
      confirmArchive: true,
    );
    final archived = (archive as RepairAccepted<RepairArchiveCommand>).value;
    expect(archived.outstandingPiastres, BigInt.from(12000));
    expect(archived.cashPiastres, BigInt.zero);
    expect(
      (RepairRules.reviewArchive(
                repairId: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
                expectedVersion: BigInt.one,
                outstandingPiastres: BigInt.zero,
                terminal: false,
                confirmArchive: true,
              )
              as RepairRejected<RepairArchiveCommand>)
          .issue,
      RepairIssue.invalidInput,
    );
    expect(RepairRules.canAdvanceStatus('received', 'in_progress'), isTrue);
    expect(RepairRules.canAdvanceStatus('ready', 'received'), isFalse);
  });
}
