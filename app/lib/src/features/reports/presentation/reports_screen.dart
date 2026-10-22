import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_tokens.dart';
import '../application/report_gateway.dart';
import '../application/weekly_report_gateway.dart';
import '../application/report_export.dart';
import '../data/report_output.dart';
import '../domain/financial_day_report.dart';
import 'report_pdf.dart';
import 'report_transaction_card.dart';
import 'weekly_reports_screen.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({
    super.key,
    required this.gateway,
    required this.userId,
    required this.shopId,
    required this.canRead,
    this.syncTicks,
    this.render = buildFinancialDayPdf,
    this.output = outputReportPdf,
  });
  final ReportGateway gateway;
  final String userId, shopId;
  final bool Function() canRead;
  final Listenable? syncTicks;
  final ReportRenderer render;
  final ReportOutput output;
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with WidgetsBindingObserver {
  List<ReportDay>? _days;
  FinancialDayReport? _report;
  String? _dayId;
  String? _error;
  String? _message;
  bool _loading = true, _exporting = false;
  int _generation = 0;
  Timer? _watch;
  late ReportExport _export;
  Route<void>? _weeklyRoute;
  void _closeWeekly() {
    final route = _weeklyRoute;
    _weeklyRoute = null;
    final navigator = route?.navigator;
    if (route == null || navigator == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (navigator.mounted && route.isActive) navigator.removeRoute(route);
    });
  }

  Future<void> _openWeekly() async {
    final gateway = widget.gateway;
    if (gateway is! WeeklyReportGateway ||
        _weeklyRoute != null ||
        _exporting ||
        !_allowed) {
      return;
    }
    final user = widget.userId, shop = widget.shopId;
    final route = MaterialPageRoute<void>(
      builder: (_) => WeeklyReportsScreen(
        sessions: gateway,
        gateway: gateway as WeeklyReportGateway,
        userId: user,
        shopId: shop,
        canRead: () =>
            _allowed &&
            widget.userId == user &&
            widget.shopId == shop &&
            identical(widget.gateway, gateway),
        syncTicks: widget.syncTicks,
      ),
    );
    _weeklyRoute = route;
    try {
      await Navigator.of(context).push<void>(route);
    } finally {
      if (identical(_weeklyRoute, route)) _weeklyRoute = null;
    }
  }

  bool get _allowed =>
      mounted &&
      widget.canRead() &&
      widget.gateway.reportSession(widget.userId) != null;
  ReportExport _newExport() {
    final user = widget.userId, shop = widget.shopId;
    final gateway = widget.gateway;
    return ReportExport(
      gateway,
      user,
      shop,
      () =>
          _allowed &&
          widget.userId == user &&
          widget.shopId == shop &&
          identical(widget.gateway, gateway),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.syncTicks?.addListener(_reload);
    _export = _newExport();
    _watch = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_allowed && (_report != null || _days != null)) _deny();
    });
    _load();
  }

  @override
  void didUpdateWidget(ReportsScreen old) {
    super.didUpdateWidget(old);
    if (old.syncTicks != widget.syncTicks) {
      old.syncTicks?.removeListener(_reload);
      widget.syncTicks?.addListener(_reload);
    }
    if (old.gateway != widget.gateway ||
        old.userId != widget.userId ||
        old.shopId != widget.shopId) {
      _closeWeekly();
      _days = null;
      _report = null;
      _dayId = null;
      _exporting = false;
      _message = null;
      _export = _newExport();
      _load();
    }
  }

  @override
  void dispose() {
    _closeWeekly();
    _generation++;
    _watch?.cancel();
    widget.syncTicks?.removeListener(_reload);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_exporting) _reload();
  }

  void _deny() {
    if (!mounted) return;
    _closeWeekly();
    _generation++;
    setState(() {
      _report = null;
      _days = null;
      _loading = false;
      _error = 'انتهت صلاحية الوصول إلى التقرير.';
    });
  }

  void _reload() {
    if (!_exporting) unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final session = widget.gateway.reportSession(widget.userId);
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
      final days = await widget.gateway.reportDays(
        widget.userId,
        widget.shopId,
      );
      if (!mounted || generation != _generation) return;
      if (!_allowed || widget.gateway.reportSession(widget.userId) != session) {
        _deny();
        return;
      }
      final selected =
          days.where((d) => d.id == _dayId).firstOrNull ??
          days.where((d) => d.status == 'open').firstOrNull ??
          days.firstOrNull;
      final report = selected == null
          ? null
          : await widget.gateway.financialDayReport(
              widget.userId,
              widget.shopId,
              selected.id,
            );
      if (!mounted || generation != _generation) return;
      if (!_allowed || widget.gateway.reportSession(widget.userId) != session) {
        _deny();
        return;
      }
      setState(() {
        _days = days;
        _dayId = selected?.id;
        _report = report;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      if (!_allowed) {
        _deny();
        return;
      }
      setState(() {
        _loading = false;
        _report = null;
        _days = null;
        _error = 'تعذر تحميل التقرير من الخادم. تحقق من الاتصال وأعد المحاولة.';
      });
    }
  }

  Future<void> _save() async {
    final report = _report;
    if (report == null || _exporting || _loading) return;
    setState(() {
      _exporting = true;
      _message = 'جارٍ إنشاء الملف ورفعه والتحقق منه…';
    });
    final export = _export;
    final result = await export.run(report, widget.render, widget.output);
    if (!mounted || !identical(export, _export)) return;
    setState(() {
      _exporting = false;
      _message = switch (result) {
        'saved' => 'تم حفظ ملف التقرير.',
        'opened' => 'فُتحت المشاركة. اختر الجهة لإكمال الإرسال.',
        'cancelled' => 'أُلغي حفظ أو مشاركة الملف.',
        'unavailable' => 'المشاركة غير متاحة على هذا الجهاز. أعد المحاولة.',
        'stale' =>
          'تغيّرت بيانات التقرير. راجع التقرير المحدّث ثم صدّره مجددًا.',
        'denied' => 'انتهت صلاحية الوصول إلى التقرير.',
        _ => 'تعذر تصدير الملف. أعد المحاولة؛ لن تتكرر أي عملية مالية.',
      };
    });
    if (result == 'denied') {
      _deny();
      return;
    }
    if (result == 'stale') await _load();
    // Reconcile updates received while the export was being prepared.
    if (result == 'saved' || result == 'opened') await _load();
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
  Widget _transaction(ReportTransaction t) => ReportTransactionCard(
    transaction: t,
    scopeKey: 'report-${widget.shopId}-$_dayId-${t.id}',
  );
  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('التقارير')),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTokens.contentMaxWidth,
              ),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'تقرير يوم مالي',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                  ),
                  if (widget.gateway is WeeklyReportGateway)
                    OutlinedButton.icon(
                      key: const Key('reports-open-weekly'),
                      onPressed: _exporting || !_allowed ? null : _openWeekly,
                      icon: const Icon(Icons.date_range_outlined),
                      label: const Text('فتح التقرير الأسبوعي'),
                    ),
                  if (_loading) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                    const Text('جارٍ تحميل التقرير المؤكد…'),
                  ] else if (_error != null) ...[
                    Text(_error!),
                    FilledButton(
                      onPressed: _load,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ] else if (_days?.isEmpty ?? true)
                    const Text('لا توجد أيام مالية مسجلة بعد.')
                  else ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      key: ValueKey(_dayId),
                      initialValue: _dayId,
                      isExpanded: true,
                      itemHeight: null,
                      selectedItemBuilder: (context) => [
                        for (final d in _days!)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Text(
                              d.date,
                              textDirection: TextDirection.ltr,
                            ),
                          ),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'اليوم المالي',
                      ),
                      items: [
                        for (final d in _days!)
                          DropdownMenuItem(value: d.id, child: Text(d.label)),
                      ],
                      onChanged: _exporting
                          ? null
                          : (id) {
                              if (id != null) {
                                _dayId = id;
                                _message = null;
                                _load();
                              }
                            },
                    ),
                    if (report != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        report.day.status == 'open'
                            ? 'اليوم مفتوح'
                            : 'اليوم مغلق',
                      ),
                      Text(
                        'فتح اليوم حسب توقيت المتجر: \u2066${report.day.openedAtShop}\u2069',
                      ),
                      Text(
                        report.shopName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text(
                        'وقت اللقطة حسب توقيت المتجر: \u2066${report.generatedAtShop}\u2069',
                      ),
                      Text(reportScope),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const Key('report-export'),
                        onPressed: _exporting ? null : _save,
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: Text(
                          _exporting ? 'جارٍ تصدير الملف…' : 'تصدير PDF عربي',
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
                      _section('الإجماليات بالجنيه', [
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
                        const Text('صافٍ بعد المرتجعات؛ كل عيار مستقل.'),
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
                        'السجل الكامل الداعم للإجماليات',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (report.transactions.isEmpty)
                        const Text('لا توجد عمليات لهذا اليوم المالي.'),
                      for (final t in report.transactions) _transaction(t),
                    ],
                  ],
                  if (_message != null && report == null)
                    Semantics(
                      liveRegion: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(_message!),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
