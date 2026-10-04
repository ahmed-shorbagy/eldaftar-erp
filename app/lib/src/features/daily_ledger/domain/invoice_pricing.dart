import 'opening_issue.dart';
import 'quantities.dart';

/// The owner's explicit agreed price; no tax or legal rule is inferred.
final class InvoicePricing {
  const InvoicePricing._({
    required this.base,
    required this.workmanship,
    required this.otherCharges,
    required this.otherChargesLabel,
    required this.discount,
    required this.total,
  });

  final Piastres base;
  final Piastres workmanship;
  final Piastres otherCharges;
  final String otherChargesLabel;
  final Piastres discount;
  final Piastres total;

  static DomainResult<InvoicePricing> compose({
    required String basePounds,
    String workmanshipPounds = '0',
    String otherChargesPounds = '0',
    String otherChargesLabel = '',
    String discountPounds = '0',
  }) {
    final parsed = [
      basePounds,
      workmanshipPounds,
      otherChargesPounds,
      discountPounds,
    ].map(Piastres.parsePounds).toList();
    for (final amount in parsed) {
      if (amount is Rejected<Piastres>) return Rejected(amount.code);
    }
    final amounts = parsed
        .map((amount) => (amount as Accepted<Piastres>).value)
        .toList();
    final label = otherChargesLabel.trim();
    if (label.length > 120 ||
        (amounts[2].value > BigInt.zero && label.isEmpty)) {
      return const Rejected(OpeningIssueCode.invalidInput);
    }
    // Exact intermediate arithmetic permits a discount before the final bound.
    final totalValue =
        amounts[0].value +
        amounts[1].value +
        amounts[2].value -
        amounts[3].value;
    if (totalValue <= BigInt.zero) {
      return const Rejected(OpeningIssueCode.invalidInput);
    }
    final total = Piastres.parseWire(totalValue.toString());
    if (total is Rejected<Piastres>) return Rejected(total.code);
    return Accepted(
      InvoicePricing._(
        base: amounts[0],
        workmanship: amounts[1],
        otherCharges: amounts[2],
        otherChargesLabel: label,
        discount: amounts[3],
        total: (total as Accepted<Piastres>).value,
      ),
    );
  }

  Map<String, Object?> toJson() => {
    'base_piastres': base.wire,
    'workmanship_piastres': workmanship.wire,
    'other_charges_piastres': otherCharges.wire,
    'other_charges_label': otherChargesLabel,
    'discount_piastres': discount.wire,
  };
}
