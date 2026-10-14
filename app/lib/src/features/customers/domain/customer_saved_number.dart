/// An owner declaration, never automatic WhatsApp or device evidence.
const savedNumberStates = {'unknown', 'saved', 'not_saved'};

String savedNumberLabel(String? state) => switch (state) {
  'saved' => 'أكد المالك حفظ الرقم',
  'not_saved' => 'حدد المالك أن الرقم غير محفوظ',
  'unknown' => 'لم يحدد المالك الحالة',
  _ => 'حالة حفظ الرقم غير متاحة',
};

class CustomerSavedNumber {
  const CustomerSavedNumber({
    required this.id,
    required this.state,
    this.actorId,
    this.actorName,
    this.declaredAt,
    this.declaredAtShop,
  });
  final String id, state;
  final String? actorId, actorName, declaredAt, declaredAtShop;
}
