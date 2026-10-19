import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'opening_copy.dart';
import '../../../theme/app_tokens.dart';
import '../application/daily_ledger_view.dart';
import '../application/ledger_date_gateway.dart';
import '../application/ledger_home_metrics.dart';
import '../application/ledger_line_items.dart';
import 'ledger_balance_sections.dart';
import 'ledger_journal_table.dart';
import 'ledger_metric_specs.dart';

class LedgerDateScreen extends StatefulWidget {
  const LedgerDateScreen({
    super.key,
    required this.gateway,
    required this.userId,
    required this.shopId,
    required this.canRead,
    required this.onOperation,
    this.syncTicks,
    this.loadItems,
  });
  final LedgerDateGateway gateway;
  final String userId, shopId;
  final bool Function() canRead;
  final Future<void> Function(LedgerFeedLine) onOperation;
  final Future<List<LedgerLineItem>?> Function(String)? loadItems;
  final Listenable? syncTicks;
  @override
  State<LedgerDateScreen> createState() => _LedgerDateScreenState();
}

class _LedgerDateScreenState extends State<LedgerDateScreen> {
  LedgerDateSnapshot? _snapshot;
  List<LedgerFeedLine> _lines = const [];
  LedgerMetricLayout _layout = migrateLedgerMetricLayout(null);
  bool _busy = false;
  String? _error, _selectedDate;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    widget.syncTicks?.addListener(_sync);
    unawaited(_preferences());
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    widget.syncTicks?.removeListener(_sync);
    super.dispose();
  }

  void _sync() => unawaited(_load());
  Future<void> _preferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final layout = migrateLedgerMetricLayout(
        prefs.getStringList('ledger_layout_${widget.shopId}'),
      );
      if (mounted) setState(() => _layout = layout);
    } catch (_) {
      /* A local preference failure must not block authorized reads. */
    }
  }

  Future<void> _load({bool older = false}) async {
    if (older && (_busy || _snapshot?.page.hasMore != true)) return;
    final generation = ++_generation;
    if (!widget.canRead()) {
      setState(() {
        _snapshot = null;
        _lines = const [];
        _busy = false;
        _error = 'لم تعد بيانات الدفتر متاحة لهذا الحساب.';
      });
      return;
    }
    final previous = _snapshot;
    setState(() {
      _busy = true;
      _error = null;
      if (!older) {
        _snapshot = null;
        _lines = const [];
      }
    });
    try {
      final value = await widget.gateway.readLedgerDate(
        userId: widget.userId,
        shopId: widget.shopId,
        businessDate: _selectedDate,
        beforeSequence: older ? previous?.page.nextBeforeSequence : null,
      );
      if (!mounted || generation != _generation) return;
      if (!widget.canRead()) {
        _sync();
        return;
      }
      if (older &&
          previous?.page.snapshotSequence != value.page.snapshotSequence) {
        // Re-read the full head if the server changed during pagination.
        unawaited(_load());
        return;
      }
      setState(() {
        _snapshot = value;
        _selectedDate = value.businessDate;
        _lines = older
            ? {
                ...{for (final line in _lines) line.operationId: line},
                ...{
                  for (final line in value.page.items) line.operationId: line,
                },
              }.values.toList()
            : value.page.items;
      });
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = 'تعذر تحميل دفتر التاريخ المحدد. أعد المحاولة.',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _chooseDate() async {
    final snapshot = _snapshot;
    if (snapshot == null || _busy) return;
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(snapshot.businessDate),
      firstDate: DateTime(1900),
      lastDate: DateTime.parse(snapshot.serverDate),
      helpText: 'اختر تاريخ الدفتر',
      cancelText: 'إلغاء',
      confirmText: 'عرض الدفتر',
    );
    if (!mounted || selected == null) return;
    _selectedDate =
        '${selected.year.toString().padLeft(4, '0')}-${selected.month.toString().padLeft(2, '0')}-${selected.day.toString().padLeft(2, '0')}';
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.canRead() ? _snapshot : null;
    final view = snapshot == null
        ? null
        : DailyLedgerView(
            state: 'confirmed',
            entitlementStatus: 'read',
            canConfirm: false,
            businessDay: null,
            cash: const [],
            stock: const [],
            scrap: const [],
            feed: _lines,
            daySummary: snapshot.summary,
          );
    final specs = view == null
        ? null
        : ledgerMetricValues(view, _layout.normalizationKarat);
    Widget tile(String id) {
      final spec = specs![id]!;
      return LedgerMetricTile(
        key: Key('date-metric-$id'),
        label: spec.label,
        value: spec.value,
        unit: spec.unit,
        icon: spec.icon,
        tone: spec.tone,
        compact: true,
      );
    }

    Widget strip(Iterable<String> ids) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final id in ids.where((id) => id != 'total_cash'))
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: SizedBox(
                width: MediaQuery.textScalerOf(context).scale(190),
                child: tile(id),
              ),
            ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('دفتر حسب التاريخ')),
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
                OutlinedButton.icon(
                  key: const Key('ledger-select-date'),
                  onPressed: snapshot == null || _busy ? null : _chooseDate,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(
                    snapshot == null
                        ? 'اختيار التاريخ بعد تحميل الدفتر'
                        : formatServerDate(snapshot.businessDate),
                  ),
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null) ...[
                  Text(_error!),
                  TextButton(
                    onPressed: _busy ? null : _load,
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
                if (snapshot != null) ...[
                  const SizedBox(height: 12),
                  LedgerNormalizationControl(
                    value: _layout.normalizationKarat,
                    onChanged: (karat) => setState(
                      () =>
                          _layout = _layout.copyWith(normalizationKarat: karat),
                    ),
                  ),
                  const SizedBox(height: 12),
                  strip(_layout.homeIds),
                  ExpansionTile(
                    title: const Text('المزيد من الملخص'),
                    children: [strip(_layout.moreIds)],
                  ),
                  const Text(
                    'أرصدة النقد والمخزون الحالية تظهر في الدفتر الرئيسي.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'عمليات اليوم',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (_lines.isEmpty)
                    const Text(
                      'لا توجد عمليات في هذا التاريخ.',
                      key: Key('ledger-date-empty'),
                    ),
                  for (final (index, line) in _lines.indexed)
                    LedgerOperationTable(
                      key: ValueKey('dated-${line.operationId}'),
                      line: line,
                      position: index + 1,
                      showDetails: false,
                      loadItems: widget.loadItems,
                      onOpen: () async {
                        await widget.onOperation(line);
                        if (mounted) await _load();
                      },
                    ),
                  if (snapshot.page.hasMore)
                    OutlinedButton(
                      key: const Key('ledger-date-older'),
                      onPressed: _busy ? null : () => _load(older: true),
                      child: const Text('عرض العمليات الأقدم'),
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
