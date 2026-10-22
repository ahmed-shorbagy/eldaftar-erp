import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_tokens.dart';
import '../application/report_export.dart';
import '../application/report_gateway.dart';
import '../application/weekly_report_export.dart';
import '../application/weekly_report_gateway.dart';
import '../data/report_output.dart';
import '../domain/financial_day_report.dart';
import '../domain/financial_week_report.dart';
import 'report_pdf.dart';
import 'report_transaction_card.dart';

class WeeklyReportsScreen extends StatefulWidget {
  const WeeklyReportsScreen({
    super.key,
    required this.sessions,
    required this.gateway,
    required this.userId,
    required this.shopId,
    required this.canRead,
    this.syncTicks,
    this.render = buildFinancialWeekPdf,
    this.output = outputReportPdf,
  });
  final ReportGateway sessions;
  final WeeklyReportGateway gateway;
  final String userId, shopId;
  final bool Function() canRead;
  final Listenable? syncTicks;
  final WeeklyReportRenderer render;
  final ReportOutput output;
  @override
  State<WeeklyReportsScreen> createState() => _WeeklyReportsScreenState();
}

class _WeeklyReportsScreenState extends State<WeeklyReportsScreen>
    with WidgetsBindingObserver {
  FinancialWeekReport? _report;
  String? _endDate, _error, _message;
  bool _loading = true, _exporting = false, _refreshQueued = false;
  int _generation = 0;
  Timer? _sessionWatch;
  late WeeklyReportExport _export;
  bool get _allowed =>
      mounted &&
      widget.canRead() &&
      widget.sessions.reportSession(widget.userId) != null;
  WeeklyReportExport _newExport() {
    final user = widget.userId,
        shop = widget.shopId,
        sessions = widget.sessions,
        gateway = widget.gateway;
    return WeeklyReportExport(
      sessions,
      gateway,
      user,
      shop,
      () =>
          _allowed &&
          widget.userId == user &&
          widget.shopId == shop &&
          identical(widget.sessions, sessions) &&
          identical(widget.gateway, gateway),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.syncTicks?.addListener(_refresh);
    _export = _newExport();
    _sessionWatch = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_allowed && _report != null) _deny();
    });
    _load();
  }

  @override
  void didUpdateWidget(WeeklyReportsScreen old) {
    super.didUpdateWidget(old);
    if (old.syncTicks != widget.syncTicks) {
      old.syncTicks?.removeListener(_refresh);
      widget.syncTicks?.addListener(_refresh);
    }
    if (old.userId != widget.userId ||
        old.shopId != widget.shopId ||
        old.gateway != widget.gateway ||
        old.sessions != widget.sessions) {
      _report = null;
      _endDate = null;
      _message = null;
      _exporting = false;
      _refreshQueued = false;
      _export = _newExport();
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _generation++;
    _sessionWatch?.cancel();
    widget.syncTicks?.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _deny() {
    if (!mounted) return;
    _generation++;
    setState(() {
      _report = null;
      _loading = false;
      _error = 'انتهت صلاحية الوصول إلى التقرير الأسبوعي.';
    });
  }

  void _refresh() {
    if (!_allowed) {
      _deny();
      return;
    }
    if (_exporting) {
      _refreshQueued = true;
      return;
    }
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final session = widget.sessions.reportSession(widget.userId);
    if (!_allowed) {
      _deny();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _report = null;
    });
    try {
      final report = await widget.gateway.financialWeekReport(
        widget.userId,
        widget.shopId,
        endDate: _endDate,
      );
      if (!mounted || generation != _generation) return;
      if (!_allowed ||
          widget.sessions.reportSession(widget.userId) != session) {
        _deny();
        return;
      }
      setState(() {
        _report = report;
        _endDate = report.endDate;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      if (!_allowed) {
        _deny();
        return;
      }
      setState(() {
        _report = null;
        _loading = false;
        _error = 'تعذر تحميل التقرير الأسبوعي. تحقق من الاتصال وأعد المحاولة.';
      });
    }
  }

  Future<void> _chooseEndDate() async {
    final report = _report;
    if (report == null ||
        _loading ||
        _exporting ||
        report.firstBusinessDate == null) {
      return;
    }
    final generation = _generation;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(report.endDate),
      firstDate: DateTime.parse(report.firstBusinessDate!),
      lastDate: DateTime.parse(report.lastSelectableDate),
      locale: const Locale('ar'),
      helpText: 'آخر يوم في الأسبوع',
      confirmText: 'اختيار',
      cancelText: 'إلغاء',
    );
    if (!mounted || picked == null || generation != _generation || !_allowed) {
      return;
    }
    final date =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    if (date == _endDate) return;
    _endDate = date;
    _message = null;
    await _load();
  }

  Future<void> _save() async {
    final report = _report;
    if (report == null || _exporting || _loading) return;
    setState(() {
      _exporting = true;
      _message = 'جارٍ إنشاء الملف الأسبوعي ورفعه والتحقق منه…';
    });
    final export = _export;
    final result = await export.run(report, widget.render, widget.output);
    if (!mounted || !identical(export, _export)) return;
    setState(() {
      _exporting = false;
      _message = switch (result) {
        'saved' => 'تم حفظ التقرير الأسبوعي.',
        'opened' => 'فُتحت المشاركة. اختر الجهة لإكمال الإرسال.',
        'cancelled' => 'أُلغي حفظ أو مشاركة التقرير الأسبوعي.',
        'unavailable' => 'المشاركة غير متاحة على هذا الجهاز. أعد المحاولة.',
        'stale' =>
          'تغيّرت بيانات الأسبوع. راجع التقرير المحدّث ثم صدّره مجددًا.',
        'denied' => 'انتهت صلاحية الوصول إلى التقرير الأسبوعي.',
        _ =>
          'تعذر تصدير التقرير الأسبوعي. أعد المحاولة؛ لن تتكرر أي عملية مالية.',
      };
    });
    if (result == 'denied') {
      _deny();
      return;
    }
    if (_refreshQueued ||
        result == 'stale' ||
        result == 'saved' ||
        result == 'opened') {
      _refreshQueued = false;
      await _load();
    }
  }

  Widget _value(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Wrap(
      spacing: 12,
      runSpacing: 4,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Text(label),
        Text(
          value,
          textDirection: TextDirection.ltr,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    ),
  );
  Widget _section(String title, List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    ),
  );
  Widget _group(FinancialWeekReport report, WeeklyReportGroup group) => Card(
    child: ExpansionTile(
      key: PageStorageKey(
        'week-${report.endDate}-${group.category}-${group.karat}',
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${reportCategory(group.category)} • عيار ${group.karat}'),
          _value('المباع بالجرام', reportGrams(group.sold)),
          _value('المشترى بالجرام', reportGrams(group.bought)),
        ],
      ),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      childrenPadding: const EdgeInsets.all(16),
      children: [
        _value('حركات البيع، شاملة المرتجعات', group.saleMovements.toString()),
        _value(
          'حركات الشراء، شاملة المرتجعات',
          group.purchaseMovements.toString(),
        ),
        for (final day in report.days)
          for (final t in day.transactions)
            for (final item in t.items.where(
              (i) =>
                  i.category == group.category &&
                  i.karat == group.karat &&
                  (i.sold != BigInt.zero || i.bought != BigInt.zero),
            )) ...[
              const Divider(),
              Text('${t.label} • \u2066${t.sequence}\u2069'),
              Text('اليوم المالي: \u2066${day.day.date}\u2069'),
              if (item.name.isNotEmpty) Text(item.name),
              _value('مساهمة المباع بالجرام', reportGrams(item.sold)),
              _value('مساهمة المشترى بالجرام', reportGrams(item.bought)),
            ],
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final report = _report;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('التقرير الأسبوعي')),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTokens.contentMaxWidth,
              ),
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + keyboard),
                children: [
                  const Text(
                    'تقرير أسبوعي',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  if (_loading) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                    const Text('جارٍ تحميل الأسبوع من الخادم…'),
                  ] else if (_error != null) ...[
                    Text(_error!),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('إعادة المحاولة'),
                    ),
                    if (_allowed)
                      OutlinedButton(
                        onPressed: () {
                          _endDate = null;
                          _message = null;
                          _load();
                        },
                        child: const Text('فتح أحدث أسبوع'),
                      ),
                  ] else if (report != null) ...[
                    Text(
                      report.shopName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    _value('من', report.startDate),
                    _value('إلى، شاملًا', report.endDate),
                    OutlinedButton.icon(
                      key: const Key('weekly-report-select-end'),
                      onPressed: _exporting || report.firstBusinessDate == null
                          ? null
                          : _chooseEndDate,
                      icon: const Icon(Icons.date_range_outlined),
                      label: const Text('اختيار آخر يوم في الأسبوع'),
                    ),
                    const Text(weeklyReportScope),
                    Text(
                      'وقت اللقطة حسب توقيت المتجر: \u2066${report.generatedAtShop}\u2069',
                    ),
                    if (report.containsOpenDay)
                      const Text(
                        'الفترة تتضمن يومًا ماليًا مفتوحًا؛ الأرقام حتى وقت اللقطة.',
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      key: const Key('weekly-report-export'),
                      onPressed: _exporting ? null : _save,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(
                        _exporting ? 'جارٍ تصدير الأسبوع…' : 'تصدير PDF أسبوعي',
                      ),
                    ),
                    if (_message != null)
                      Semantics(
                        liveRegion: true,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(_message!),
                        ),
                      ),
                    if (report.days.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('لا توجد أيام مالية مسجّلة في هذه الفترة.'),
                      ),
                    _section('إجماليات الأسبوع بالجنيه', [
                      for (final e in reportSummaryLabels.entries.where(
                        (e) => !e.key.endsWith('count'),
                      ))
                        _value(e.value, reportMoney(report.value(e.key))),
                    ]),
                    _section('أعداد العمليات', [
                      for (final e in reportSummaryLabels.entries.where(
                        (e) => e.key.endsWith('count'),
                      ))
                        _value(e.value, report.value(e.key).toString()),
                    ]),
                    _section('الذهب بالجرام حسب العيار', [
                      const Text('أوزان صافية بعد المرتجعات؛ كل عيار مستقل.'),
                      for (final g in report.gold) ...[
                        const Divider(),
                        Text(
                          'عيار ${g.karat}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        _value('المباع', reportGrams(g.sold)),
                        _value('المشترى', reportGrams(g.bought)),
                      ],
                    ]),
                    const SizedBox(height: 12),
                    Text(
                      'التجميع حسب الصنف والعيار',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(weeklyCategoryScope),
                    if (report.groups.isEmpty)
                      const Text('لا توجد حركة بيع أو شراء ذهب في هذه الفترة.'),
                    for (final group in report.groups) _group(report, group),
                    const SizedBox(height: 12),
                    Text(
                      'الأيام المالية والسجل الكامل',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final day in report.days)
                      Card(
                        child: ExpansionTile(
                          key: PageStorageKey(
                            'week-day-${report.endDate}-${day.day.id}',
                          ),
                          title: Text(
                            'اليوم المالي: \u2066${day.day.date}\u2069',
                          ),
                          subtitle: Text(
                            '${day.day.status == 'open' ? 'مفتوح' : 'مغلق'} • \u2066${day.day.openedAtShop}\u2069',
                          ),
                          expandedCrossAxisAlignment:
                              CrossAxisAlignment.stretch,
                          childrenPadding: const EdgeInsets.all(12),
                          children: [
                            _value(
                              'صافي المبيعات',
                              reportMoney(day.value('net_sales')),
                            ),
                            _value(
                              'صافي المشتريات',
                              reportMoney(day.value('net_purchases')),
                            ),
                            _value(
                              'المصروفات',
                              reportMoney(day.value('expenses')),
                            ),
                            _value(
                              'صافي حركة النقد',
                              reportMoney(day.value('net_cash')),
                            ),
                            if (day.transactions.isEmpty)
                              const Text('لا توجد عمليات لهذا اليوم المالي.'),
                            for (final t in day.transactions)
                              ReportTransactionCard(
                                transaction: t,
                                scopeKey:
                                    'week-${report.endDate}-${day.day.id}-${t.id}',
                              ),
                          ],
                        ),
                      ),
                  ],
                  if (_message != null && report == null)
                    Semantics(liveRegion: true, child: Text(_message!)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
