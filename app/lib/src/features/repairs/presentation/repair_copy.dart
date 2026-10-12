import '../../daily_ledger/domain/opening_issue.dart';
import '../../daily_ledger/domain/quantities.dart';
import '../../../theme/amount_format.dart';
import '../domain/repair_rules.dart';

const repairStatusLabels = <String, String>{
  'received': 'مستلم',
  'in_progress': 'قيد الإصلاح',
  'ready': 'جاهز للتسليم',
  'delivered': 'تم التسليم',
  'cancelled': 'ملغى',
  'archived': 'مؤرشف',
};

const repairFilterLabels = <String, String>{
  'open': 'المفتوحة',
  'delivered': 'تم التسليم',
  'cancelled': 'الملغاة',
  'archived': 'المؤرشفة',
  'outstanding': 'المتبقي',
};

const repairMethodLabels = <String, String>{
  'cash': 'نقدي',
  'instant_transfer': 'تحويل فوري',
  'wallet': 'محفظة',
  'card': 'بطاقة',
};

const repairCollectionLabels = <RepairCollectionMode, String>{
  RepairCollectionMode.all: 'تحصيل الكل',
  RepairCollectionMode.part: 'تحصيل جزء',
  RepairCollectionMode.none: 'بدون تحصيل',
};

String repairStatusLabel(String status) =>
    repairStatusLabels[status] ?? 'حالة غير متاحة';

String repairEventLabel(String kind) => switch (kind) {
  'repair_intake' => 'استلام القطعة',
  'repair_status' => 'تحديث الحالة',
  'repair_handover' => 'تسليم القطعة',
  'repair_cancel' => 'إلغاء وإعادة القطعة',
  'repair_archive' => 'أرشفة السجل',
  _ => 'تحديث السجل',
};

String repairIssueText(RepairIssue issue) => switch (issue) {
  RepairIssue.invalidInput => 'راجع الحقول المطلوبة.',
  RepairIssue.unsupportedKarat =>
    'العيار يجب أن يكون 14 أو 18 أو 21 أو 22 أو 24.',
  RepairIssue.weightRequired => 'أدخل وزنًا أكبر من صفر بثلاث خانات عشرية.',
  RepairIssue.feeRequired => 'أدخل أجرة التسليم.',
  RepairIssue.collectedExceedsFee => 'المحصّل لا يتجاوز الأجرة النهائية.',
  RepairIssue.collectionMismatch => 'طريقة التحصيل لا تطابق المبلغ.',
  RepairIssue.overflow => 'القيمة أكبر من الحد المسموح.',
};

String repairFailureText(String code) => switch (code) {
  'stale_repair' => 'تغيّر السجل. أعد التحميل ثم أعد المحاولة.',
  'repair_not_ready' => 'التسليم متاح فقط من حالة جاهز للتسليم.',
  'repair_not_active' => 'الإلغاء متاح للسجلات النشطة فقط.',
  'repair_not_terminal' => 'الأرشفة للسجلات المسلّمة أو الملغاة فقط.',
  'shop_not_active' => 'الاشتراك منتهٍ. العرض للقراءة فقط.',
  'rpc_unavailable' => 'الصيانة غير متاحة في هذا الاتصال حاليًا.',
  'shop_unavailable' => 'الإصلاحات غير متاحة قبل تفعيل الاشتراك.',
  'day_closed' => 'اليوم مغلق. لا يمكن تحصيل الأجرة.',
  'stale_day' => 'تغيّر اليوم. أعد التحميل ثم أعد المحاولة.',
  'payload_mismatch' => 'الطلب المحفوظ لا يطابق الخادم.',
  'other_pending' => 'يوجد طلب معلّق. أعد المحاولة بنفس الطلب.',
  'storage' => 'تعذّر حفظ الطلب على الجهاز. لم يُرسل.',
  'invalid_input' => 'البيانات غير مقبولة.',
  'tender_mismatch' => 'طرق الدفع لا تساوي المبلغ المحصّل.',
  'unauthenticated' || 'session_expired' => 'انتهت الجلسة. سجّل الدخول مجددًا.',
  'forbidden' => 'لا يمكن تنفيذ هذا الطلب.',
  'not_found' => 'السجل غير موجود.',
  'negative_owned_balance' => 'رصيد الطريقة لا يكفي.',
  _ => 'تعذّر إكمال الطلب. تحقق من الاتصال وأعد المحاولة.',
};

String repairMoney(BigInt? piastres) {
  if (piastres == null) return 'بدون تقدير';
  final parsed = Piastres.parseWire(piastres.toString());
  if (parsed is! Accepted<Piastres>) return piastres.toString();
  return '\u2066${displayPounds(parsed.value.poundsText)}\u2069';
}

String repairGramsExact(BigInt milligrams) {
  final parsed = Milligrams.parseWire(milligrams.toString());
  if (parsed is! Accepted<Milligrams>) return milligrams.toString();
  return '${parsed.value.gramsText} جرام';
}

/// Two decimals in lists. Confirmation adds exact milligrams when rounding hides them.
String repairWeight(BigInt milligrams, {required bool exact}) {
  if (exact) return displayGoldEffect(milligrams);
  return '${displayGrams(milligrams.toString())} جرام';
}
