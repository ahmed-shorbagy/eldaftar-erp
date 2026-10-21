import 'package:flutter/material.dart';
import '../domain/financial_day_report.dart';

/// Shared complete operation detail for daily and weekly reports.
class ReportTransactionCard extends StatelessWidget {
  const ReportTransactionCard({
    super.key,
    required this.transaction,
    required this.scopeKey,
  });
  final ReportTransaction transaction;
  final String scopeKey;
  @override
  Widget build(BuildContext context) {
    final t = transaction;
    Widget value(String label, String amount) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Wrap(
        spacing: 12,
        runSpacing: 4,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            amount,
            textDirection: TextDirection.ltr,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ],
      ),
    );
    return Card(
      child: ExpansionTile(
        key: PageStorageKey(scopeKey),
        title: Text('${t.label} • \u2066${t.sequence}\u2069'),
        subtitle: Text('${t.stateLabel}\n\u2066${t.atShop}\u2069'),
        childrenPadding: const EdgeInsets.all(16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (t.description.isNotEmpty) Text(t.description),
          if (t.sourceId != null) ...[
            const Text('مرجع العملية الأصلية'),
            SelectableText(t.sourceId!, textDirection: TextDirection.ltr),
          ],
          value('قيمة العملية الأصلية', reportMoney(t.originalTotal)),
          value('مساهمة صافي المبيعات', reportMoney(t.sale)),
          value('مساهمة صافي المشتريات', reportMoney(t.purchase)),
          value('المصروف', reportMoney(t.expense)),
          value('حركة النقد', reportMoney(t.cash)),
          if (t.kind == 'opening_balances')
            value(
              'الرصيد الافتتاحي المستبعد من الحركة',
              reportMoney(t.openingCash),
            ),
          for (final m in t.methods.entries)
            value(reportMethod(m.key), reportMoney(m.value)),
          for (final i in t.items) ...[
            const Divider(),
            Text(i.name.isEmpty ? 'ذهب' : i.name),
            value('العيار', i.karat.toString()),
            value('الوزن الأصلي بالجرام', reportGrams(i.milligrams)),
            value('مساهمة المباع بالجرام', reportGrams(i.sold)),
            value('مساهمة المشترى بالجرام', reportGrams(i.bought)),
          ],
          for (final g in t.inventory.entries)
            value('تغير المخزون بالجرام • عيار ${g.key}', reportGrams(g.value)),
        ],
      ),
    );
  }
}
