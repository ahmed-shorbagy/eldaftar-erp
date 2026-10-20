import '../../daily_ledger/domain/opening_issue.dart';
import '../../daily_ledger/domain/quantities.dart';
import 'appearance_rules.dart';

/// A frozen customer copy of one confirmed sale or purchase.
///
/// Field rules live here. This file does not import widgets, HTTP, files, or PDF.
final class BrandedInvoiceDocument {
  const BrandedInvoiceDocument({
    required this.operationId,
    required this.kind,
    required this.shopName,
    required this.shopSequence,
    required this.occurredAtUtc,
    required this.occurredAtShop,
    required this.copyCreatedAtUtc,
    required this.copyCreatedAtShop,
    required this.timeZone,
    required this.edition,
    required this.contentSha256,
    required this.appearanceRevision,
    required this.template,
    required this.accent,
    required this.renderVersion,
    required this.lines,
    required this.tenders,
    required this.logoRequired,
    this.slogan,
    this.address,
    this.logoAssetId,
    this.logoSha256,
    this.totalPiastres,
    this.pricing,
    this.customerName,
    this.customerPhone,
    this.description,
    this.note,
    this.purchasePaidPiastres,
    this.obligationPiastres,
    this.synthetic = false,
  });

  final String operationId;
  final String kind;
  final String shopName;
  final String shopSequence;
  final String occurredAtUtc;
  final String occurredAtShop;
  final String copyCreatedAtUtc;
  final String copyCreatedAtShop;
  final String timeZone;
  final int edition;
  final String contentSha256;
  final int appearanceRevision;
  final InvoiceTemplate template;
  final InvoiceAccent accent;
  final int renderVersion;
  final List<BrandedInvoiceLine> lines;
  final List<BrandedTender> tenders;
  final bool logoRequired;
  final String? slogan;
  final String? address;
  final String? logoAssetId;
  final String? logoSha256;
  final String? totalPiastres;
  final BrandedInvoicePricing? pricing;
  final String? customerName;
  final String? customerPhone;
  final String? description;
  final String? note;
  final String? purchasePaidPiastres;
  final String? obligationPiastres;
  final bool synthetic;

  String get kindLabel => kind == 'sale' ? 'مستند بيع مؤكد' : 'مستند شراء مؤكد';

  /// Builds from a fresh authorized operation read plus one frozen edition.
  /// Malformed lines throw. Live remaining balance is ignored.
  factory BrandedInvoiceDocument.fromConfirmed({
    required Map<String, Object?> source,
    required int edition,
    required String contentSha256,
    required int appearanceRevision,
    required InvoiceTemplate template,
    required InvoiceAccent accent,
    required int renderVersion,
    required String copyCreatedAtUtc,
    required String copyCreatedAtShop,
    String? slogan,
    String? address,
    String? logoAssetId,
    String? logoSha256,
    bool logoRequired = false,
  }) {
    final kind = source['kind'];
    final payload = source['payload'];
    if ((kind != 'sale' && kind != 'purchase') ||
        payload is! Map ||
        source['shop_sequence'] is! String ||
        source['shop_name'] is! String ||
        (source['shop_name'] as String).trim().isEmpty ||
        source['operation_id'] is! String ||
        source['occurred_at'] is! String ||
        source['occurred_at_shop'] is! String ||
        source['time_zone'] is! String ||
        edition < 1 ||
        appearanceRevision < 0 ||
        !const [1, 2].contains(renderVersion) ||
        (renderVersion == 1 && template == InvoiceTemplate.dark) ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(contentSha256)) {
      throw const FormatException('branded_invoice');
    }
    final body = Map<String, Object?>.from(payload);
    final items = body['items'];
    final tenderRaw = body['tenders'];
    if (items is! List || tenderRaw is! List) {
      throw const FormatException('branded_invoice');
    }
    final lines = <BrandedInvoiceLine>[];
    for (final raw in items) {
      if (raw is! Map) throw const FormatException('branded_invoice');
      lines.add(BrandedInvoiceLine._parse(Map<String, Object?>.from(raw)));
    }
    final tenders = <BrandedTender>[];
    for (final raw in tenderRaw) {
      if (raw is! Map) throw const FormatException('branded_invoice');
      tenders.add(BrandedTender._parse(Map<String, Object?>.from(raw)));
    }
    if (kind == 'sale' && tenders.isEmpty) {
      throw const FormatException('branded_invoice');
    }
    var paid = BigInt.zero;
    for (final tender in tenders) {
      final parsed = Piastres.parseWire(tender.piastres);
      if (parsed is! Accepted<Piastres>) {
        throw const FormatException('branded_invoice');
      }
      final sum = paid + parsed.value.value;
      if (sum < paid) throw const FormatException('branded_invoice');
      paid = sum;
    }
    final total = _optionalMoney(body['total_piastres'], required: true);
    BrandedInvoicePricing? pricing;
    if (body.containsKey('pricing') && body['pricing'] != null) {
      final rawPricing = body['pricing'];
      if (rawPricing is! Map) throw const FormatException('branded_invoice');
      pricing = BrandedInvoicePricing._parse(
        Map<String, Object?>.from(rawPricing),
      );
    }
    String? obligation;
    if (kind == 'purchase' &&
        body.containsKey('purchase_obligation_piastres')) {
      obligation = _optionalMoney(
        body['purchase_obligation_piastres'],
        required: true,
      );
    }
    return BrandedInvoiceDocument(
      operationId: source['operation_id'] as String,
      kind: kind as String,
      shopName: source['shop_name'] as String,
      shopSequence: source['shop_sequence'] as String,
      occurredAtUtc: source['occurred_at'] as String,
      occurredAtShop: source['occurred_at_shop'] as String,
      copyCreatedAtUtc: copyCreatedAtUtc,
      copyCreatedAtShop: copyCreatedAtShop,
      timeZone: source['time_zone'] as String,
      edition: edition,
      contentSha256: contentSha256,
      appearanceRevision: appearanceRevision,
      template: template,
      accent: accent,
      renderVersion: renderVersion,
      lines: lines,
      tenders: tenders,
      logoRequired: logoRequired,
      slogan: slogan,
      address: address,
      logoAssetId: logoAssetId,
      logoSha256: logoSha256,
      totalPiastres: total,
      pricing: pricing,
      customerName: _optionalText(body['customer_name']),
      customerPhone: _optionalText(body['customer_phone']),
      description: _optionalText(body['description']),
      note: _optionalText(body['note']),
      purchasePaidPiastres: kind == 'purchase' ? paid.toString() : null,
      obligationPiastres: obligation,
    );
  }
}

final class BrandedInvoiceLine {
  const BrandedInvoiceLine({
    required this.category,
    required this.categoryLabel,
    required this.karat,
    required this.milligrams,
    required this.gramsText,
    required this.itemName,
    this.count,
    this.linePricePiastres,
  });

  final String category;
  final String categoryLabel;
  final int karat;
  final String milligrams;
  final String gramsText;
  final String itemName;
  final String? count;
  final String? linePricePiastres;

  factory BrandedInvoiceLine._parse(Map<String, Object?> raw) {
    const labels = {
      'worked_jewelry': 'مشغولات',
      'bullion': 'سبائك',
      'coin': 'عملات',
      'scrap': 'كسر',
    };
    final category = raw['category'];
    final karat = raw['karat'];
    final name = raw['item_name'];
    if (category is! String ||
        !labels.containsKey(category) ||
        karat is! int ||
        !const {14, 18, 21, 22, 24}.contains(karat) ||
        name is! String) {
      throw const FormatException('branded_invoice');
    }
    final weight = raw['milligrams'];
    if (weight is! String) throw const FormatException('branded_invoice');
    final parsed = Milligrams.parseWire(weight);
    if (parsed is! Accepted<Milligrams>) {
      throw const FormatException('branded_invoice');
    }
    String? count;
    if (category == 'scrap') {
      if (raw['count'] != null) {
        count = _count(raw['count']);
      }
    } else {
      count = _count(raw['count']);
    }
    String? price;
    if (raw.containsKey('line_price_piastres') &&
        raw['line_price_piastres'] != null) {
      price = _optionalMoney(raw['line_price_piastres'], required: true);
    }
    return BrandedInvoiceLine(
      category: category,
      categoryLabel: labels[category]!,
      karat: karat,
      milligrams: weight,
      gramsText: parsed.value.gramsText,
      itemName: name,
      count: count,
      linePricePiastres: price,
    );
  }
}

final class BrandedTender {
  const BrandedTender({
    required this.method,
    required this.methodLabel,
    required this.piastres,
  });

  final String method;
  final String methodLabel;
  final String piastres;

  factory BrandedTender._parse(Map<String, Object?> raw) {
    const labels = {
      'cash': 'نقدي',
      'instant_transfer': 'تحويل فوري',
      'wallet': 'محفظة',
      'card': 'بطاقة',
    };
    final method = raw['method'];
    if (method is! String || !labels.containsKey(method)) {
      throw const FormatException('branded_invoice');
    }
    return BrandedTender(
      method: method,
      methodLabel: labels[method]!,
      piastres: _optionalMoney(raw['piastres'], required: true)!,
    );
  }
}

final class BrandedInvoicePricing {
  const BrandedInvoicePricing({
    required this.basePiastres,
    required this.workmanshipPiastres,
    required this.otherChargesPiastres,
    required this.otherChargesLabel,
    required this.discountPiastres,
  });

  final String basePiastres;
  final String workmanshipPiastres;
  final String otherChargesPiastres;
  final String otherChargesLabel;
  final String discountPiastres;

  factory BrandedInvoicePricing._parse(Map<String, Object?> raw) {
    const keys = [
      'base_piastres',
      'workmanship_piastres',
      'other_charges_piastres',
      'discount_piastres',
    ];
    if (raw['other_charges_label'] is! String) {
      throw const FormatException('branded_invoice');
    }
    for (final key in keys) {
      if (!raw.containsKey(key)) throw const FormatException('branded_invoice');
    }
    return BrandedInvoicePricing(
      basePiastres: _optionalMoney(raw['base_piastres'], required: true)!,
      workmanshipPiastres: _optionalMoney(
        raw['workmanship_piastres'],
        required: true,
      )!,
      otherChargesPiastres: _optionalMoney(
        raw['other_charges_piastres'],
        required: true,
      )!,
      otherChargesLabel: raw['other_charges_label'] as String,
      discountPiastres: _optionalMoney(
        raw['discount_piastres'],
        required: true,
      )!,
    );
  }
}

String? _optionalText(Object? value) {
  if (value == null) return null;
  if (value is! String) throw const FormatException('branded_invoice');
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : value;
}

String? _optionalMoney(Object? value, {required bool required}) {
  if (value == null) {
    if (required) throw const FormatException('branded_invoice');
    return null;
  }
  if (value is! String) throw const FormatException('branded_invoice');
  final parsed = Piastres.parseWire(value);
  if (parsed is! Accepted<Piastres>) {
    throw const FormatException('branded_invoice');
  }
  return value;
}

String _count(Object? value) {
  if (value is! String) throw const FormatException('branded_invoice');
  final parsed = PieceCount.parseWire(value);
  if (parsed is! Accepted<PieceCount>) {
    throw const FormatException('branded_invoice');
  }
  return value;
}
