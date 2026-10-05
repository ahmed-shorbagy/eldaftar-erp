import '../../../theme/amount_format.dart';
import '../../daily_ledger/domain/opening_catalog.dart';
import '../../daily_ledger/domain/opening_issue.dart';
import '../../daily_ledger/domain/quantities.dart';
import '../../daily_ledger/presentation/opening_copy.dart';
import '../domain/inventory_models.dart';

String inventoryCategoryLabel(String category) => switch (category) {
  'worked_jewelry' => 'مشغولات',
  'bullion' => 'سبائك',
  'coin' => 'عملات',
  'scrap' => 'كسر',
  _ => category,
};

String stockClassLabel(StockClass value) => switch (value) {
  StockClass.ownedAvailable => 'متاح للبيع',
  StockClass.ownedPending => 'مملوك بانتظار الاعتراف',
  StockClass.traderCustody => 'أمانة تاجر',
};

String inventoryIssueCopy(InventoryIssueCode code) => switch (code) {
  InventoryIssueCode.invalidInput => 'البيانات المدخلة غير صالحة.',
  InventoryIssueCode.overflow => 'القيمة تتجاوز حد الأرقام الصحيح.',
  InventoryIssueCode.unsupportedCategoryKarat => 'الفئة أو العيار غير مسموح.',
  InventoryIssueCode.exceedsRemaining => 'الكمية أكبر من المتبقي.',
  InventoryIssueCode.stockPairMismatch =>
    'الوزن والعدد يجب أن ينتهيا معاً أو يبقيا معاً.',
  InventoryIssueCode.mixedObligation => 'لا يجتمع التزام  والتزام بالذهب.',
  InventoryIssueCode.karatMismatch =>
    'التزام الذهب يجب أن يكون من عيار القطعة نفسه.',
  InventoryIssueCode.tenderMismatch => 'المدفوع أكبر من السعر المتفق عليه.',
  InventoryIssueCode.emptyCommand => 'أدخل أثراً واحداً على الأقل.',
  InventoryIssueCode.duplicateLine => 'تكرر السطر أو وسيلة الدفع.',
  InventoryIssueCode.negativeBalance => 'التصحيح يجعل الرصيد سالباً.',
  InventoryIssueCode.custodyRequiresTransfer =>
    'أمانة التاجر لا تُعترف ولا تُربط. انقل الملكية بأمر صريح.',
};

String inventoryFailureCopy(String code) {
  if (code == 'stale_day') {
    return 'تغيّر يوم العمل أو إصداره. راجع الأثر من جديد قبل الإرسال.';
  }
  if (code == 'shop_not_active') {
    return 'الاشتراك غير نشط. العرض للقراءة فقط ولم يُرسل الأمر.';
  }
  if (code == 'not_found') return 'السجل المطلوب غير موجود على الخادم.';
  if (code == 'already_allocated') return 'هذه الكمية خُصصت من قبل.';
  if (code == 'custody_requires_transfer') {
    return inventoryIssueCopy(InventoryIssueCode.custodyRequiresTransfer);
  }
  if (code == 'insufficient_lot' || code == 'insufficient_stock') {
    return 'الرصيد المؤكد لا يكفي.';
  }
  if (code == 'negative_owned_balance' || code == 'negative_balance') {
    return 'العملية تجعل رصيداً مملوكاً سالباً.';
  }
  if (code == 'other_pending') {
    return 'توجد عملية مالية معلّقة. أكمل التحقق قبل أمر جديد.';
  }
  if (code == 'storage') {
    return 'تعذر حفظ الطلب على هذا الجهاز. لم يُرسل شيء.';
  }
  if (code == 'discarded') {
    return 'تغيّرت الجلسة أو المتجر. أُهملت القراءة المتأخرة.';
  }
  return openingFailureCopy(code);
}

String inventoryNoteCopy(String note) => switch (note) {
  'nominal_not_stock' =>
    'الوزن الاسمي هوية في الكتالوج فقط. المخزون يُسجل بالوزن الفعلي.',
  'pending_not_saleable' =>
    'الكمية مملوكة وبانتظار الاعتراف، وليست ضمن المتاح للبيع.',
  'custody_not_owned' =>
    'الكمية أمانة لدى المحل. لا تدخل المخزون المملوك ولا تحرك النقد ولا تفتح مستحقاً.',
  'owned_now' => 'تنتقل الملكية الآن إلى المتاح للبيع.',
  'no_second_stock_posting' =>
    'الربط يطابق استلاماً بإضافة مؤكدة ولا يضيف مخزوناً مرة ثانية.',
  'egp_obligation_only' => 'الالتزام  فقط، دون التزام ذهبي للثمن نفسه.',
  'gold_obligation_only' => 'الالتزام بذهب من عيار واحد فقط، دون التزام .',
  'partial_quantity' => 'حركة جزئية من الكمية المتبقية.',
  'full_quantity' => 'كامل الكمية المتبقية.',
  'partial_settlement' => 'تسوية جزئية للمستحق.',
  'full_settlement' => 'تسوية كاملة للمستحق.',
  'same_karat' =>
    'التحويل يبقي العيار نفسه ولا يحوّل بين العيارات أو بين الذهب والنقد.',
  'adjustment_clearing' => 'فرق الجرد يبقى ظاهراً ويُقابل حساب التسوية.',
  'catalog_only' => 'حفظ في الكتالوج بلا أثر على النقد أو الذهب.',
  'explicit_obligation_karat' =>
    'عيار المستحق مكتوب صراحة وليس تحويلاً لوزن القطعة.',
  'linked_trader' => 'المستحق مربوط بتاجر محدد، لا باسم معروض.',
  'named_lot' => 'البيع يخص الدفعة المختارة، وليس صرفًا بأسبقية الدخول.',
  _ => note,
};

String effectCopy(InventoryEffect effect) {
  final direction = effect.delta.isNegative ? 'ينقص' : 'يزيد';
  final amount = effect.delta.abs();
  final where = _bucketLabel(effect.bucket);
  if (effect.unit == EffectUnit.piastres) {
    final parsed = Piastres.parseWire(amount.toString());
    final pounds = parsed is Accepted<Piastres>
        ? displayPounds(parsed.value.poundsText)
        : amount.toString();
    if (effect.bucket == 'cash') {
      final method = CashMethod.byCode(effect.method ?? '');
      final label = method == null
          ? effect.method ?? ''
          : cashMethodLabel(method);
      return '$direction النقد ($label): $pounds.';
    }
    if (effect.bucket == 'egp_payable') {
      return effect.delta.isNegative
          ? 'ينقص المستحق : $pounds، دون حركة ذهب.'
          : 'يفتح مستحقاً : $pounds، دون مستحق ذهبي.';
    }
  }
  if (effect.unit == EffectUnit.count) {
    final category = inventoryCategoryLabel(effect.category ?? '');
    return '$direction عدد $where ($category عيار ${effect.karat}): $amount.';
  }
  final parsed = Milligrams.parseWire(amount.toString());
  final grams = parsed is Accepted<Milligrams>
      ? parsed.value.gramsText
      : amount.toString();
  if (effect.bucket == 'gold_payable') {
    return effect.delta.isNegative
        ? 'ينقص المستحق بالذهب عيار ${effect.karat}: $grams جرام، دون حركة نقد.'
        : 'يفتح مستحقاً بالذهب عيار ${effect.karat}: $grams جرام، دون مستحق .';
  }
  final category = inventoryCategoryLabel(effect.category ?? '');
  return '$direction $where: $grams جرام $category عيار ${effect.karat}.';
}

String _bucketLabel(String bucket) => switch (bucket) {
  'owned_available' => 'المتاح للبيع',
  'owned_pending' => 'المملوك بانتظار الاعتراف',
  'trader_custody' => 'أمانة التاجر',
  'cash' => 'النقد',
  'egp_payable' => 'المستحق ',
  'gold_payable' => 'المستحق بالذهب',
  _ => bucket,
};

String gramsOf(BigInt milligrams) {
  final parsed = Milligrams.parseWire(
    milligrams.isNegative ? milligrams.abs().toString() : milligrams.toString(),
  );
  if (parsed is! Accepted<Milligrams>) return milligrams.toString();
  final text = parsed.value.gramsText;
  return milligrams.isNegative ? '-$text' : text;
}

String poundsOf(BigInt piastres) {
  final parsed = Piastres.parseWire(piastres.toString());
  return parsed is Accepted<Piastres>
      ? displayPounds(parsed.value.poundsText)
      : piastres.toString();
}

String receiptOptionLabel(ReceiptSnapshot item) {
  final name = item.productName.isEmpty
      ? item.counterpartyName
      : item.productName;
  final count = item.remainingCount == null
      ? ''
      : ' — ${item.remainingCount} قطعة';
  return '${item.id} — $name — المتبقي ${gramsOf(item.remainingMilligrams)} جرام$count';
}

String lotIdentityCopy(LotSnapshot lot) {
  final lines = <String>[
    if (lot.denominationId != null) 'هوية السبيكة ${lot.denominationId}',
    if (lot.coinTypeId != null) 'هوية العملة ${lot.coinTypeId}',
    if (lot.nominalMilligrams != null)
      'الاسمي ${gramsOf(lot.nominalMilligrams!)} جرام ليس وزن المخزون',
    if (lot.nominalMilligrams == null && lot.coinNominalMilligrams != null)
      'الاسمي ${gramsOf(lot.coinNominalMilligrams!)} جرام ليس وزن المخزون',
  ];
  return lines.join('\n');
}

const inventoryGuideSteps = <({String title, String description, String action})>[
  (
    title: 'ابحث في المخزون الفعلي',
    description: 'حقل البحث أدناه يصفّي الأسماء المعروضة من الخادم.',
    action: 'الانتقال إلى البحث',
  ),
  (
    title: 'ثلاث كميات منفصلة',
    description:
        'المتاح للبيع غير المملوك بانتظار الاعتراف وغير أمانة التاجر. لا تُجمع في رصيد واحد.',
    action: 'إظهار الإجماليات',
  ),
  (
    title: 'صفِّ حسب الحيازة',
    description:
        'اختر المتاح أو الانتظار أو الأمانة من قائمة التصفية الحقيقية.',
    action: 'الانتقال إلى التصفية',
  ),
  (
    title: 'الأمر يراجع قبل الحفظ',
    description:
        'زر الإضافة يفتح النموذج الحقيقي. الإرشاد لا يرسل أمراً ولا يكتب رصيداً معلقاً.',
    action: 'الانتقال إلى الإضافة',
  ),
];

const traderGuideSteps = <({String title, String description, String action})>[
  (
    title: 'ابحث عن تاجر',
    description: 'البحث يستخدم الاسم الظاهر في قائمة التجار.',
    action: 'الانتقال إلى البحث',
  ),
  (
    title: 'الأمانة ليست مخزوناً مملوكاً',
    description: 'تفاصيل التاجر تفصل ما استُلم أصلاً عما هو ما زال في الحيازة.',
    action: 'إظهار القائمة',
  ),
  (
    title: 'كشف عربي',
    description: 'زر الكشف يبني بياناً من الأرقام المؤكدة بعد فتح التاجر.',
    action: 'الانتقال إلى الكشف',
  ),
  (
    title: 'بيانات التاجر',
    description:
        'اكتب الاسم في الحقل الحقيقي. الحفظ يتم بعد المراجعة ولا يتم من الإرشاد.',
    action: 'الانتقال إلى الاسم',
  ),
];
