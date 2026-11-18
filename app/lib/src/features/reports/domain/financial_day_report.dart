import '../../../theme/shop_clock.dart';
import '../../daily_ledger/domain/quantities.dart' show twoDecimalGrams;

/// Exact server report values. No Flutter, transport or storage dependencies.
class ReportDay {
  const ReportDay(
    this.id,
    this.date,
    this.status,
    this.openedAtShop, {
    this.closedAtShop,
  });
  final String id, date, status, openedAtShop;

  /// Server close time in the shop zone; null while open or from older
  /// servers (U18).
  final String? closedAtShop;
  String get label =>
      '$date • ${status == 'open' ? 'مفتوح' : 'مغلق'} • ${shopClockOf(openedAtShop) ?? openedAtShop.substring(11)}';
}

class ReportGold {
  const ReportGold(this.karat, this.sold, this.bought);
  final int karat;
  final BigInt sold, bought;
}

class ReportItem {
  const ReportItem(
    this.name,
    this.category,
    this.karat,
    this.milligrams,
    this.sold,
    this.bought,
  );
  final String name, category;
  final int karat;
  final BigInt milligrams, sold, bought;
}

class ReportTransaction {
  const ReportTransaction({
    required this.id,
    required this.sequence,
    required this.kind,
    required this.label,
    required this.state,
    required this.atShop,
    required this.description,
    required this.originalTotal,
    required this.sale,
    required this.purchase,
    required this.expense,
    required this.cash,
    required this.openingCash,
    required this.items,
    required this.methods,
    required this.inventory,
    this.sourceId,
  });
  final String id, sequence, kind, state, atShop, description;

  /// The server's Arabic name for the operation, or null for kinds it does
  /// not name (stock moves, trader receipts, reversals). Such a row still
  /// counts in every total and check, but is not listed (see [listed]).
  final String? label;

  /// Whether the row appears in the report's list and PDF, as in the daily
  /// ledger: only operations the server names are listed.
  bool get listed => label != null;
  final String? sourceId;
  final BigInt originalTotal, sale, purchase, expense, cash, openingCash;
  final List<ReportItem> items;
  final Map<String, BigInt> methods;
  final Map<int, BigInt> inventory;
  String get stateLabel => switch (state) {
    'edit' => 'أصل عُدّل — مستبعد من إجمالي التجارة',
    'delete' => 'أصل حُذف — مستبعد من إجمالي التجارة',
    'internal_reversal' => 'عكس تعديل أو حذف — نقده ضمن الحركة',
    _ => 'مؤكدة',
  };
}

class FinancialDayReport {
  const FinancialDayReport({
    required this.shopId,
    required this.shopName,
    required this.day,
    required this.timeZone,
    required this.fingerprint,
    required this.generatedAtShop,
    required this.summary,
    required this.gold,
    required this.transactions,
  });
  final String shopId, shopName, timeZone, fingerprint, generatedAtShop;
  final ReportDay day;
  final Map<String, BigInt> summary;
  final List<ReportGold> gold;

  /// Every operation of the day, for totals and integrity checks.
  final List<ReportTransaction> transactions;

  /// The operations the report lists and prints.
  List<ReportTransaction> get listedTransactions =>
      transactions.where((t) => t.listed).toList(growable: false);
  BigInt value(String key) => summary[key]!;
}

String reportExact(BigInt amount, int decimals) {
  final scale = BigInt.from(10).pow(decimals);
  final whole = (amount.abs() ~/ scale).toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '${amount.isNegative ? '-' : ''}$whole.${(amount.abs() % scale).toString().padLeft(decimals, '0')}';
}

String reportMoney(BigInt n) => reportExact(n, 2);
String reportGrams(BigInt n) => twoDecimalGrams(n, grouped: true);
String reportMethod(String method) => switch (method) {
  'cash' => 'كاش',
  'instant_transfer' => 'إنستا باي',
  'wallet' => 'محفظة',
  'card' => 'فيزا',
  _ => 'طريقة دفع',
};

const reportScope =
    'التجارة الحالية بعد التعديل والحذف؛ المرتجعات في يوم ترحيلها. حركة النقد تشمل التسويات والتعويضات وتستبعد الرصيد الافتتاحي؛ وليست ربحًا.';
const reportSummaryLabels = <String, String>{
  'sales': 'المبيعات المؤكدة',
  'sale_returns': 'مرتجعات البيع',
  'net_sales': 'صافي المبيعات بعد المرتجعات',
  'purchases': 'المشتريات المؤكدة',
  'purchase_returns': 'مرتجعات الشراء',
  'net_purchases': 'صافي المشتريات بعد المرتجعات',
  'expenses': 'المصروفات',
  'net_cash': 'صافي حركة النقد',
  'opening_cash': 'نقد الرصيد الافتتاحي',
  'sale_count': 'عدد عمليات البيع',
  'purchase_count': 'عدد عمليات الشراء',
  'expense_count': 'عدد المصروفات',
  'return_count': 'عدد المرتجعات',
  'operation_count': 'عدد العمليات الحالية',
  'audit_row_count': 'عدد صفوف السجل الكامل',
};
