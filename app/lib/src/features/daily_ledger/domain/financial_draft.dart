import 'opening_catalog.dart';
import 'opening_issue.dart';
import 'quantities.dart';
import 'invoice_pricing.dart';

enum FinancialKind { sale, purchase, expense, scrapSale }

enum FinancialIssue {
  invalidTotal,
  invalidTender,
  tenderMismatch,
  invalidItem,
  linePriceMismatch,
  missingDescription,
  invalidCustomer,
  missingSeller,
  pricingMismatch,
}

final class FinancialItemInput {
  const FinancialItemInput({
    required this.category,
    required this.karat,
    required this.grams,
    required this.count,
    required this.name,
    this.linePricePounds,
  });

  final String category;
  final int karat;
  final String grams;
  final String count;
  final String name;
  final String? linePricePounds;
}

final class FinancialTenderInput {
  const FinancialTenderInput({required this.method, required this.pounds});

  final CashMethod method;
  final String pounds;
}

final class FinancialDraftResult {
  const FinancialDraftResult._(this.draft, this.issue);
  final FinancialDraft? draft;
  final FinancialIssue? issue;

  bool get isValid => draft != null;
}

/// Exact, canonical command data. This layer never depends on Flutter or HTTP.
final class FinancialDraft {
  const FinancialDraft._({
    required this.kind,
    required this.total,
    required this.items,
    required this.tenders,
    required this.description,
    required this.customerName,
    required this.customerPhone,
    required this.note,
    required this.cashPaid,
    required this.purchasePayable,
    this.pricing,
  });

  final FinancialKind kind;
  final Piastres total;
  final List<Map<String, Object?>> items;
  final List<Map<String, Object?>> tenders;
  final String description;
  final String customerName;
  final String customerPhone;
  final String note;
  final Piastres cashPaid;
  final Piastres? purchasePayable;
  final InvoicePricing? pricing;

  static FinancialDraftResult compose({
    required FinancialKind kind,
    required String totalPounds,
    required List<FinancialItemInput> items,
    required List<FinancialTenderInput> tenders,
    String description = '',
    String customerName = '',
    String customerPhone = '',
    String note = '',
    InvoicePricing? pricing,
  }) {
    final parsedTotal = Piastres.parsePounds(totalPounds.trim());
    if (parsedTotal is! Accepted<Piastres> ||
        parsedTotal.value.value == BigInt.zero) {
      return const FinancialDraftResult._(null, FinancialIssue.invalidTotal);
    }
    if (pricing != null &&
        (pricing.total != parsedTotal.value ||
            (kind != FinancialKind.sale && kind != FinancialKind.purchase))) {
      return const FinancialDraftResult._(null, FinancialIssue.pricingMismatch);
    }
    if (description.length > 300 ||
        (kind == FinancialKind.expense && description.trim().isEmpty)) {
      return const FinancialDraftResult._(
        null,
        FinancialIssue.missingDescription,
      );
    }
    if (customerName.length > 200 ||
        customerPhone.length > 20 ||
        note.length > 1000 ||
        (customerPhone.isNotEmpty &&
            !RegExp(r'^\+?[0-9]{7,15}$').hasMatch(customerPhone))) {
      return const FinancialDraftResult._(null, FinancialIssue.invalidCustomer);
    }
    if ((tenders.isEmpty && kind != FinancialKind.purchase) ||
        tenders.length > 4) {
      return const FinancialDraftResult._(null, FinancialIssue.invalidTender);
    }
    final tenderRows = <Map<String, Object?>>[];
    final seen = <CashMethod>{};
    var tenderSum = BigInt.zero;
    for (final tender in tenders) {
      final amount = Piastres.parsePounds(tender.pounds.trim());
      if (!seen.add(tender.method) ||
          amount is! Accepted<Piastres> ||
          amount.value.value == BigInt.zero) {
        return const FinancialDraftResult._(null, FinancialIssue.invalidTender);
      }
      tenderSum += amount.value.value;
      tenderRows.add({
        'method': tender.method.code,
        'piastres': amount.value.wire,
      });
    }
    if (tenderSum > parsedTotal.value.value ||
        (kind != FinancialKind.purchase &&
            tenderSum != parsedTotal.value.value)) {
      return const FinancialDraftResult._(null, FinancialIssue.tenderMismatch);
    }
    final payableValue = parsedTotal.value.value - tenderSum;
    if (kind == FinancialKind.purchase &&
        payableValue > BigInt.zero &&
        customerName.trim().isEmpty) {
      return const FinancialDraftResult._(null, FinancialIssue.missingSeller);
    }
    final parsedCashPaid = Piastres.parseWire(tenderSum.toString());
    final parsedPayable = payableValue == BigInt.zero
        ? null
        : Piastres.parseWire(payableValue.toString());
    if (parsedCashPaid is! Accepted<Piastres> ||
        (parsedPayable != null && parsedPayable is! Accepted<Piastres>)) {
      return const FinancialDraftResult._(null, FinancialIssue.invalidTender);
    }
    if ((kind == FinancialKind.expense && items.isNotEmpty) ||
        (kind != FinancialKind.expense &&
            (items.isEmpty || items.length > 50))) {
      return const FinancialDraftResult._(null, FinancialIssue.invalidItem);
    }
    final itemRows = <Map<String, Object?>>[];
    var linePriceSum = BigInt.zero;
    var pricedLines = 0;
    for (final item in items) {
      final isScrap = item.category == 'scrap';
      final category = StockCategory.byCode(item.category);
      if ((isScrap && kind == FinancialKind.sale) ||
          (kind == FinancialKind.scrapSale && !isScrap) ||
          (!isScrap &&
              (category == null || !category.allowsKarat(item.karat))) ||
          (isScrap && !ScrapKarats.allowed.contains(item.karat)) ||
          item.name.trim().isEmpty ||
          item.name.length > 120) {
        return const FinancialDraftResult._(null, FinancialIssue.invalidItem);
      }
      final weight = Milligrams.parseGrams(item.grams.trim());
      final pieces = isScrap ? null : PieceCount.parseWire(item.count.trim());
      if (weight is! Accepted<Milligrams> ||
          weight.value.value == BigInt.zero ||
          (!isScrap &&
              (pieces is! Accepted<PieceCount> ||
                  pieces.value.value == BigInt.zero))) {
        return const FinancialDraftResult._(null, FinancialIssue.invalidItem);
      }
      String? linePrice;
      if (item.linePricePounds != null &&
          item.linePricePounds!.trim().isNotEmpty) {
        final parsed = Piastres.parsePounds(item.linePricePounds!.trim());
        if (parsed is! Accepted<Piastres> ||
            parsed.value.value == BigInt.zero) {
          return const FinancialDraftResult._(null, FinancialIssue.invalidItem);
        }
        linePrice = parsed.value.wire;
        linePriceSum += parsed.value.value;
        pricedLines++;
      }
      itemRows.add({
        'category': item.category,
        'karat': item.karat,
        'milligrams': weight.value.wire,
        'count': isScrap ? null : (pieces as Accepted<PieceCount>).value.wire,
        'item_name': item.name.trim(),
        'line_price_piastres': linePrice,
      });
    }
    if (pricedLines != 0 &&
        (pricedLines != items.length ||
            linePriceSum != (pricing?.base.value ?? parsedTotal.value.value))) {
      return const FinancialDraftResult._(
        null,
        FinancialIssue.linePriceMismatch,
      );
    }
    return FinancialDraftResult._(
      FinancialDraft._(
        kind: kind,
        total: parsedTotal.value,
        items: List.unmodifiable(itemRows),
        tenders: List.unmodifiable(tenderRows),
        description: description.trim(),
        customerName: customerName.trim(),
        customerPhone: customerPhone.trim(),
        note: note.trim(),
        cashPaid: parsedCashPaid.value,
        purchasePayable: parsedPayable == null
            ? null
            : (parsedPayable as Accepted<Piastres>).value,
        pricing: pricing,
      ),
      null,
    );
  }

  Map<String, Object?> toJson() => {
    'version': pricing == null ? 1 : 2,
    'kind': kind == FinancialKind.scrapSale ? 'scrap_sale' : kind.name,
    'total_piastres': total.wire,
    'tenders': tenders,
    'items': items,
    'description': description,
    'customer_name': customerName,
    'customer_phone': customerPhone,
    'note': note,
    if (pricing != null) 'pricing': pricing!.toJson(),
    if (purchasePayable != null)
      'purchase_obligation_piastres': purchasePayable!.wire,
  };
}
