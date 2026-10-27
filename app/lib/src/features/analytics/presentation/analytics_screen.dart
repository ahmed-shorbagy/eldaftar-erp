import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../../reports/application/report_export.dart';
import '../../reports/application/report_gateway.dart';
import '../../reports/data/report_output.dart';
import '../../reports/domain/financial_day_report.dart';
import '../application/analytics_export.dart';
import '../application/analytics_gateway.dart';
import '../domain/period_analytics.dart';
import 'analytics_pdf.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({
    super.key,
    required this.sessions,
    required this.gateway,
    required this.userId,
    required this.shopId,
    required this.canRead,
    required this.isOwner,
    this.syncTicks,
    this.render = buildPeriodAnalyticsPdf,
    this.output = outputReportPdf,
  });

  final ReportGateway sessions;
  final AnalyticsGateway gateway;
  final String userId, shopId;
  final bool Function() canRead;
  final bool isOwner;
  final Listenable? syncTicks;
  final AnalyticsRenderer render;
  final ReportOutput output;

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen>
    with WidgetsBindingObserver {
  PeriodAnalytics? _report;
  AnalyticsPeriod _period = AnalyticsPeriod.month;
  String? _anchor, _error, _message;
  bool _loading = true, _exporting = false, _refreshQueued = false;
  int _generation = 0;
  Timer? _sessionWatch;
  late AnalyticsExport _export;

  bool get _allowed =>
      mounted &&
      widget.canRead() &&
      widget.sessions.reportSession(widget.userId) != null;

  AnalyticsExport _newExport() {
    final user = widget.userId,
        shop = widget.shopId,
        sessions = widget.sessions,
        gateway = widget.gateway;
    return AnalyticsExport(
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
    widget.syncTicks?.addListener(_queueRefresh);
    _export = _newExport();
    _sessionWatch = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_allowed && _report != null) _deny();
    });
    _load();
  }

  @override
  void didUpdateWidget(AnalyticsScreen old) {
    super.didUpdateWidget(old);
    if (old.syncTicks != widget.syncTicks) {
      old.syncTicks?.removeListener(_queueRefresh);
      widget.syncTicks?.addListener(_queueRefresh);
    }
    if (old.userId != widget.userId ||
        old.shopId != widget.shopId ||
        old.gateway != widget.gateway ||
        old.sessions != widget.sessions) {
      _report = null;
      _anchor = null;
      _message = null;
      _exporting = false;
      _refreshQueued = false;
      _export = _newExport();
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.syncTicks?.removeListener(_queueRefresh);
    _sessionWatch?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _queueRefresh();
  }

  void _queueRefresh() {
    if (_loading) {
      _refreshQueued = true;
      return;
    }
    _load();
  }

  void _deny() {
    setState(() {
      _report = null;
      _error = 'انتهت صلاحية الجلسة. أعد الدخول للمتجر.';
      _message = null;
      _loading = false;
    });
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (!_allowed) {
        if (!mounted || generation != _generation) return;
        _deny();
        return;
      }
      final report = await widget.gateway.periodAnalytics(
        widget.userId,
        widget.shopId,
        period: _period,
        anchorDate: _anchor,
      );
      if (!mounted || generation != _generation) return;
      if (!_allowed) {
        _deny();
        return;
      }
      setState(() {
        _report = report;
        _anchor = report.anchorDate;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل التحليلات. أعد المحاولة.';
        _report = null;
      });
    } finally {
      if (_refreshQueued && mounted && generation == _generation) {
        _refreshQueued = false;
        unawaited(_load());
      }
    }
  }

  Future<void> _exportPdf() async {
    final report = _report;
    if (report == null || _exporting) return;
    setState(() {
      _exporting = true;
      _message = null;
    });
    final code = await _export.run(report, widget.render, widget.output);
    if (!mounted) return;
    setState(() {
      _exporting = false;
      _message = switch (code) {
        'opened' || 'shared' || 'saved' => 'أُعد ملف التحليلات من الأرقام المؤكدة.',
        'busy' => 'التصدير جارٍ بالفعل.',
        'stale' => 'تغيّرت الأرقام. حدّث ثم صدّر مجددًا.',
        'denied' => 'انتهت صلاحية الجلسة. لم يُصدَّر الملف.',
        'cancelled' => 'أُلغي التصدير.',
        _ => 'تعذر تصدير التحليلات.',
      };
    });
    if (code == 'stale') await _load();
  }

  Future<void> _pickAnchor() async {
    final report = _report;
    if (report == null) return;
    final initial = DateTime.tryParse(report.anchorDate) ?? DateTime.now();
    final first = DateTime.tryParse(report.firstBusinessDate ?? report.serverDate);
    final last = DateTime.tryParse(report.lastSelectableDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first ?? DateTime(2020),
      lastDate: last ?? DateTime.now().add(const Duration(days: 366)),
      helpText: switch (_period) {
        AnalyticsPeriod.week => 'آخر يوم في الأسبوع',
        AnalyticsPeriod.month => 'أي يوم في الشهر',
        AnalyticsPeriod.year => 'أي يوم في السنة',
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _anchor =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('التحليلات')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTokens.contentMaxWidth,
            ),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                if (_loading) const LinearProgressIndicator(),
                Text(analyticsScope, style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 12),
                SegmentedButton<AnalyticsPeriod>(
                  key: const Key('analytics-period'),
                  segments: [
                    for (final period in AnalyticsPeriod.values)
                      ButtonSegment(
                        value: period,
                        label: Text(analyticsPeriodLabel(period)),
                      ),
                  ],
                  selected: {_period},
                  onSelectionChanged: _loading
                      ? null
                      : (next) {
                          setState(() => _period = next.first);
                          _load();
                        },
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const Key('analytics-pick-anchor'),
                  onPressed: _loading || report == null ? null : _pickAnchor,
                  child: Text(
                    report == null
                        ? 'اختيار التاريخ'
                        : 'الفترة ${report.startDate} / ${report.endDate}',
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  key: const Key('analytics-refresh'),
                  onPressed: _loading ? null : _load,
                  child: const Text('تحديث'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    key: const Key('analytics-error'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  Text(_message!, key: const Key('analytics-status')),
                ],
                if (report != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    report.containsOpenDay
                        ? 'تشمل الفترة يومًا ماليًا مفتوحًا.'
                        : 'لا يوجد يوم مالي مفتوح داخل الفترة المعروضة.',
                  ),
                  Text('أيام مالية ${report.dayCount}'),
                  const SizedBox(height: 12),
                  Text(
                    'النقد والعمليات',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final entry in reportSummaryLabels.entries)
                    ListTile(
                      title: Text(entry.value),
                      trailing: Text(reportMoney(report.value(entry.key))),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'الأوزان حسب العيار',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final g in report.gold)
                    ListTile(
                      key: Key('analytics-gold-${g.karat}'),
                      title: Text('عيار ${g.karat}'),
                      subtitle: Text(
                        'مبيع ${reportGrams(g.sold)} جرام — مشترى ${reportGrams(g.bought)} جرام',
                      ),
                    ),
                  if (widget.isOwner && report.isOwner) ...[
                    const SizedBox(height: 8),
                    Text(
                      'أوزان الموظفين والمستخدمين',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (report.actors.isEmpty)
                      const Text(
                        'لا توجد أوزان بيع أو شراء مربوطة بمستخدم في هذه الفترة.',
                      )
                    else
                      for (final actor in report.actors)
                        Card(
                          key: Key('analytics-actor-${actor.actorUserId}'),
                          child: ListTile(
                            title: Text(actor.displayName),
                            subtitle: Text(
                              'مبيع ${reportGrams(actor.soldTotal)} — مشترى ${reportGrams(actor.boughtTotal)}',
                            ),
                          ),
                        ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    key: const Key('analytics-export'),
                    onPressed: _exporting || !_allowed ? null : _exportPdf,
                    child: Text(
                      _exporting ? 'جارٍ إعداد الملف' : 'PDF للطباعة أو المشاركة',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
