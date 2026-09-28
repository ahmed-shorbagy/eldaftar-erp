import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../application/daily_ledger_view.dart';
import 'opening_copy.dart';

/// Displays only figures returned by the confirmed server read model.
class ConfirmedLedgerDashboard extends StatefulWidget {
  const ConfirmedLedgerDashboard({
    super.key,
    required this.ledger,
    required this.shopId,
  });

  final DailyLedgerView? ledger;
  final String shopId;

  @override
  State<ConfirmedLedgerDashboard> createState() =>
      _ConfirmedLedgerDashboardState();
}

class _ConfirmedLedgerDashboardState extends State<ConfirmedLedgerDashboard> {
  static const _sections = ['cash', 'gold', 'activity'];
  final _visible = <String, bool>{
    for (final section in _sections) section: true,
  };
  final _order = List<String>.of(_sections);
  bool _customizing = false;
  bool _layoutEdited = false;
  Future<void> _saveTail = Future<void>.value();

  String get _preferenceKey => 'ledger_layout_${widget.shopId}';

  @override
  void initState() {
    super.initState();
    _loadLayout();
  }

  @override
  void didUpdateWidget(covariant ConfirmedLedgerDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shopId != widget.shopId) {
      _order.setAll(0, _sections);
      _visible.updateAll((_, _) => true);
      _layoutEdited = false;
      _loadLayout();
    }
  }

  Future<void> _loadLayout() async {
    final key = _preferenceKey;
    List<String>? saved;
    try {
      final preferences = await SharedPreferences.getInstance();
      saved = preferences.getStringList(key);
    } catch (_) {
      // The confirmed ledger remains readable if local preferences fail.
      return;
    }
    if (!mounted || key != _preferenceKey || _layoutEdited || saved == null) {
      return;
    }
    final savedLayout = saved;
    final ordered = savedLayout.where(_sections.contains).toSet().toList();
    ordered.addAll(_sections.where((section) => !ordered.contains(section)));
    setState(() {
      _order.setAll(0, ordered);
      for (final section in _sections) {
        _visible[section] = !savedLayout.contains('hidden:$section');
      }
    });
  }

  void _saveLayout() {
    _layoutEdited = true;
    final key = _preferenceKey;
    final snapshot = [
      ..._order,
      for (final section in _sections)
        if (!_visible[section]!) 'hidden:$section',
    ];
    _saveTail = _saveTail.then((_) => _writeLayout(key, snapshot));
  }

  Future<void> _writeLayout(String key, List<String> snapshot) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList(key, snapshot);
    } catch (_) {
      // The visible choice still applies for the current session.
    }
  }

  void _move(String section, int direction) {
    final index = _order.indexOf(section);
    final next = index + direction;
    if (next < 0 || next >= _order.length) return;
    setState(() {
      _order.removeAt(index);
      _order.insert(next, section);
    });
    _saveLayout();
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.ledger;
    if (view == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final stockWeight = _sum(view.stock.map((line) => line.milligrams));
    final scrapWeight = _sum(view.scrap.map((line) => line.milligrams));
    final goldWeight = stockWeight + scrapWeight;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('نظرة على الدفتر', style: theme.textTheme.headlineSmall),
                if (view.businessDay != null)
                  Text(
                    'يوم العمل ${formatServerDate(view.businessDay!.businessDate)}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const Chip(
              avatar: Icon(Icons.verified_outlined, size: 18),
              label: Text('تم تأكيد الأرصدة الافتتاحية'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'تعرض هذه الصفحة الأرصدة التي أكدها الخادم. تتوفر حركة البيع والشراء عند تفعيلها في النظام.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final tileWidth = width >= 480 ? (width - 12) / 2 : width;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: tileWidth,
                  child: _SummaryCard(
                    key: const Key('ledger-total-gold'),
                    icon: Icons.scale_outlined,
                    title: 'إجمالي الذهب',
                    value: _grams(goldWeight),
                    unit: 'جرام',
                    detail: 'المخزون والكسر · وزن مؤكد',
                    featured: true,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: _SummaryCard(
                    key: const Key('ledger-total-cash'),
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'إجمالي النقدية',
                    value: view.totalCashPounds ?? '—',
                    unit: 'جنيه',
                    detail: 'جميع طرق الدفع · رصيد مؤكد',
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          key: const Key('ledger-customize'),
          onPressed: () => setState(() => _customizing = !_customizing),
          icon: const Icon(Icons.tune),
          label: Text(_customizing ? 'إغلاق تخصيص العرض' : 'تخصيص العرض'),
        ),
        if (_customizing) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('الأقسام وترتيبها', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  const Text(
                    'اختر ما يظهر أولاً. يُحفظ هذا الترتيب لهذا المتجر على الجهاز.',
                  ),
                  for (final section in _order)
                    _SectionControl(
                      section: section,
                      visible: _visible[section]!,
                      first: _order.first == section,
                      last: _order.last == section,
                      onChanged: (value) {
                        setState(() => _visible[section] = value);
                        _saveLayout();
                      },
                      onUp: () => _move(section, -1),
                      onDown: () => _move(section, 1),
                    ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        for (final section in _order)
          if (_visible[section]!) ...[
            switch (section) {
              'cash' => _CashSection(view: view),
              'gold' => _GoldSection(view: view),
              _ => _ActivitySection(view: view),
            },
            const SizedBox(height: 16),
          ],
      ],
    );
  }
}

String _label(String section) => switch (section) {
  'cash' => 'النقدية',
  'gold' => 'الذهب',
  _ => 'حركة الدفتر',
};

class _SectionControl extends StatelessWidget {
  const _SectionControl({
    required this.section,
    required this.visible,
    required this.first,
    required this.last,
    required this.onChanged,
    required this.onUp,
    required this.onDown,
  });

  final String section;
  final bool visible;
  final bool first;
  final bool last;
  final ValueChanged<bool> onChanged;
  final VoidCallback onUp;
  final VoidCallback onDown;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: SwitchListTile.adaptive(
          key: Key('ledger-show-$section'),
          contentPadding: EdgeInsets.zero,
          title: Text(_label(section)),
          value: visible,
          onChanged: onChanged,
        ),
      ),
      IconButton(
        tooltip: 'نقل ${_label(section)} إلى الأعلى',
        onPressed: first ? null : onUp,
        icon: const Icon(Icons.arrow_upward),
      ),
      IconButton(
        tooltip: 'نقل ${_label(section)} إلى الأسفل',
        onPressed: last ? null : onDown,
        icon: const Icon(Icons.arrow_downward),
      ),
    ],
  );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.unit,
    required this.detail,
    this.featured = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final String unit;
  final String detail;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: featured ? scheme.primaryContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: featured ? scheme.onPrimaryContainer : scheme.primary,
            ),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.end,
              spacing: 6,
              children: [
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    value,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Text(unit, style: theme.textTheme.bodyMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(detail, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _CashSection extends StatelessWidget {
  const _CashSection({required this.view});
  final DailyLedgerView view;

  @override
  Widget build(BuildContext context) {
    final values = [
      for (final line in view.cash)
        BigInt.tryParse(line.piastres) ?? BigInt.zero,
    ];
    final max = values.fold<BigInt>(BigInt.zero, (a, b) => a > b ? a : b);
    return _SectionCard(
      title: 'مقارنة طرق النقدية',
      subtitle: 'الأرصدة المؤكدة بالجنيه · طول الشريط نسبة إلى أعلى رصيد',
      icon: Icons.payments_outlined,
      child: view.cash.isEmpty
          ? const Text('لا توجد أرصدة نقدية معروضة.')
          : Column(
              children: [
                for (var index = 0; index < view.cash.length; index++) ...[
                  _BarLine(
                    label: view.cash[index].labelAr,
                    value: '${view.cash[index].pounds} جنيه',
                    fraction: _fraction(values[index], max),
                    colorIndex: index,
                  ),
                  if (index < view.cash.length - 1) const SizedBox(height: 16),
                ],
              ],
            ),
    );
  }
}

class _GoldSection extends StatelessWidget {
  const _GoldSection({required this.view});
  final DailyLedgerView view;

  @override
  Widget build(BuildContext context) {
    final byKarat = <int, BigInt>{};
    for (final line in view.stock) {
      byKarat.update(
        line.karat,
        (value) => value + (BigInt.tryParse(line.milligrams) ?? BigInt.zero),
        ifAbsent: () => BigInt.tryParse(line.milligrams) ?? BigInt.zero,
      );
    }
    for (final line in view.scrap) {
      byKarat.update(
        line.karat,
        (value) => value + (BigInt.tryParse(line.milligrams) ?? BigInt.zero),
        ifAbsent: () => BigInt.tryParse(line.milligrams) ?? BigInt.zero,
      );
    }
    final karats = byKarat.keys.toList()..sort((a, b) => b.compareTo(a));
    final max = byKarat.values.fold<BigInt>(
      BigInt.zero,
      (a, b) => a > b ? a : b,
    );
    return _SectionCard(
      title: 'الذهب حسب العيار',
      subtitle: 'المخزون والكسر · الوزن بالجرام · طول الشريط نسبة إلى أعلى وزن',
      icon: Icons.scale_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (karats.isEmpty)
            const Text('لا يوجد وزن ذهب مسجل في الأرصدة المؤكدة.'),
          for (final karat in karats) ...[
            _BarLine(
              label: 'عيار $karat',
              value: '${_grams(byKarat[karat]!)} جرام',
              fraction: _fraction(byKarat[karat]!, max),
              colorIndex: karats.indexOf(karat),
            ),
            const SizedBox(height: 16),
          ],
          if (view.stock.isNotEmpty) ...[
            const Divider(),
            Text('المخزون', style: Theme.of(context).textTheme.titleSmall),
            for (final line in view.stock)
              _DetailLine(
                label:
                    '${line.labelAr} · عيار ${line.karat} · ${line.count} قطعة',
                value: '${line.grams} جرام',
              ),
          ],
          if (view.scrap.isNotEmpty) ...[
            const Divider(),
            Text('الكسر', style: Theme.of(context).textTheme.titleSmall),
            for (final line in view.scrap)
              _DetailLine(
                label: '${line.labelAr} · عيار ${line.karat}',
                value: '${line.grams} جرام',
              ),
          ],
        ],
      ),
    );
  }
}

class _ActivitySection extends StatelessWidget {
  const _ActivitySection({required this.view});
  final DailyLedgerView view;

  @override
  Widget build(BuildContext context) => _SectionCard(
    title: 'حركة الدفتر',
    subtitle: 'عمليات أكدها الخادم',
    icon: Icons.receipt_long_outlined,
    child: view.feed.isEmpty
        ? const Text('لا توجد عمليات معروضة حتى الآن.')
        : Column(
            children: [
              for (final line in view.feed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(child: Icon(Icons.check)),
                  title: Text(line.labelAr),
                  subtitle: Text(
                    '${line.actorDisplayName} · ${formatServerCairoTimestamp(line.occurredAtCairo)}',
                  ),
                ),
            ],
          ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _BarLine extends StatelessWidget {
  const _BarLine({
    required this.label,
    required this.value,
    required this.fraction,
    required this.colorIndex,
  });
  final String label;
  final String value;
  final double fraction;
  final int colorIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = [
      theme.colorScheme.primary,
      theme.colorScheme.tertiary,
      theme.colorScheme.secondary,
      theme.colorScheme.onSurfaceVariant,
      theme.colorScheme.primaryContainer,
    ];
    return Semantics(
      label: '$label، $value',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
                const SizedBox(width: 8),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 7),
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 10,
                color: colors[colorIndex % colors.length],
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 10),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 8,
      runSpacing: 4,
      children: [
        Text(label),
        Directionality(textDirection: TextDirection.ltr, child: Text(value)),
      ],
    ),
  );
}

BigInt _sum(Iterable<String> values) => values.fold(
  BigInt.zero,
  (sum, value) => sum + (BigInt.tryParse(value) ?? BigInt.zero),
);

String _grams(BigInt milligrams) {
  final whole = milligrams ~/ BigInt.from(1000);
  final fraction = (milligrams % BigInt.from(1000)).toString().padLeft(3, '0');
  return '$whole.$fraction';
}

double _fraction(BigInt value, BigInt max) => max == BigInt.zero
    ? 0
    : ((value * BigInt.from(1000)) ~/ max).toDouble() / 1000;
