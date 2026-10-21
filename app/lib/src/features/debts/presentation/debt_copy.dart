import '../../../theme/amount_format.dart';
import '../domain/debt_rules.dart';

const debtDirectionLabels = <DebtDirection, String>{
  DebtDirection.shopOwes: 'على المحل',
  DebtDirection.owedToShop: 'للمحل',
};

const debtUnitLabels = <DebtUnit, String>{
  DebtUnit.money: 'نقد',
  DebtUnit.gold: 'ذهب',
};

const debtFilterLabels = <String, String>{
  'open': 'المفتوحة',
  'settled': 'المسددة',
  'remaining': 'المتبقية',
  'cancelled': 'الملغاة',
  'archived': 'المؤرشفة',
  'all': 'الكل',
};

const debtStatusLabels = <String, String>{
  'open': 'مفتوح',
  'settled': 'مسدد',
  'cancelled': 'ملغى',
  'archived': 'مؤرشف',
};

const debtMethodLabels = <String, String>{
  'cash': 'نقدي',
  'instant_transfer': 'انستا',
  'wallet': 'محفظة',
  'card': 'فيزا',
};

const debtCategoryLabels = <String, String>{
  'worked_jewelry': 'مشغولات',
  'bullion': 'سبائك',
  'coin': 'عملات',
  'scrap': 'كسر',
};

String debtIssueText(DebtIssue issue) => switch (issue) {
  DebtIssue.invalidInput => 'راجع الحقول المطلوبة قبل المتابعة.',
  DebtIssue.unsupportedCategoryKarat => 'هذا العيار غير مسموح لهذه الفئة.',
  DebtIssue.negativeAmount => 'المبلغ لا يمكن أن يكون سالبًا.',
  DebtIssue.overflow => 'القيمة أكبر من الحد المسموح.',
  DebtIssue.exceedsRemaining => 'السداد أكبر من المتبقي.',
  DebtIssue.ledgerEffectRequired =>
    'سداد الرصيد المرتبط يجب أن يحرك النقد أو الذهب لأن القيد الأصلي سجّل الأثر.',
  DebtIssue.tenderMismatch => 'مجموع طرق الدفع يجب أن يساوي مبلغ السداد.',
  DebtIssue.deliveryMismatch =>
    'وزن الذهب وعدد القطع يجب أن يطابقا مبلغ السداد.',
};

String debtFailureText(String code) => switch (code) {
  'shop_not_active' => 'الحساب منتهٍ. يمكن قراءة الديون فقط.',
  'stale_debt' => 'تغيّر الرصيد. أعد فتح الدين قبل التأكيد.',
  'stale_day' => 'تغيّر يوم العمل. أعد المراجعة قبل التأكيد.',
  'day_closed' => 'يوم العمل مغلق. افتح اليوم قبل سداد يحرك النقد أو الذهب.',
  'settlement_exceeds_obligation' => 'السداد أكبر من المتبقي.',
  'duplicate_debt' => 'يوجد دين مطابق. افتح السجل القائم من قائمة الديون.',
  'duplicate_reference' => 'هذا المرجع مستخدم من قبل.',
  'payload_mismatch' => 'طلب الحفظ لا يطابق المحاولة السابقة.',
  'ledger_effect_required' => debtIssueText(DebtIssue.ledgerEffectRequired),
  'partly_settled' => 'لا يمكن إلغاء دين تم سداد جزء منه.',
  'source_cancel_forbidden' => 'لا يمكن إلغاء دين مصدره شراء أو التزام ذهب.',
  'cancel_not_allowed' => 'لا يمكن إلغاء هذا الدين.',
  'archive_not_allowed' => 'هذا الدين مؤرشف بالفعل.',
  'duplicate_archive' => 'هذا الرصيد مؤرشف بالفعل.',
  'settlement_not_allowed' => 'لا يمكن سداد دين ملغى.',
  'negative_owned_balance' => 'الرصيد المملوك لا يكفي لهذا السداد.',
  'other_pending' => 'يوجد طلب آخر بانتظار التأكيد.',
  'storage' => 'تعذر حفظ الطلب على هذا الجهاز.',
  'not_found' => 'الدين غير موجود.',
  'forbidden' => 'لا يمكن تنفيذ هذا الطلب.',
  'session_expired' => 'انتهت الجلسة. سجّل الدخول مرة أخرى.',
  _ => 'تعذر إتمام الطلب. تحقق من الاتصال وأعد المحاولة.',
};

String debtMoney(BigInt piastres, {bool exact = false}) {
  final negative = piastres < BigInt.zero;
  final abs = piastres.abs();
  final whole = abs ~/ BigInt.from(100);
  final fraction = (abs % BigInt.from(100)).toInt();
  final shown = displayPounds(
    '${negative ? '-' : ''}$whole.${fraction.toString().padLeft(2, '0')}',
  );
  if (!exact) return '\u2066$shown\u2069';
  return '\u2066$shown\u2069';
}

String debtGold(BigInt milligrams, {bool exact = false}) {
  if (exact) return '\u2066${displayGoldEffect(milligrams)}\u2069';
  final shown = displayGrams(milligrams.toString());
  return '\u2066$shown\u2069 جرام';
}

String debtSignedCount(BigInt count) => count.toString();
