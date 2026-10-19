import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../theme/amount_format.dart';
import '../../../theme/detail_surface.dart';
import '../../shop_accounts/domain/shop_account.dart';
import '../application/daily_ledger_view.dart';
import '../application/ledger_home_metrics.dart';
import '../application/opening_gateway.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';
import 'ledger_balance_sections.dart';
import 'opening_copy.dart';

/// Live remaining metric plus inventory/scrap, sourced from the confirmed ledger.
class LedgerMoreBalances extends StatefulWidget {
  const LedgerMoreBalances({
    super.key,
    required this.shop,
    this.gateway,
    this.userId,
    this.refreshGeneration = 0,
    this.syncTicks,
  });

  final ShopAccount shop;
  final OpeningGateway? gateway;
  final String? userId;
  final int refreshGeneration;
  final Listenable? syncTicks;

  @override
  State<LedgerMoreBalances> createState() => _LedgerMoreBalancesState();
}

class _LedgerMoreBalancesState extends State<LedgerMoreBalances> {
  DailyLedgerView? _ledger;
  LedgerMetricLayout _metrics = migrateLedgerMetricLayout(null);
  String? _error;
  bool _loading = true;
  int _generation = 0;
  final _detailRevision = ValueNotifier<int>(0);
  BuildContext? _detailContext;

  String get _preferenceKey => 'ledger_layout_${widget.shop.id}';

  @override
  void initState() {
    super.initState();
    widget.syncTicks?.addListener(_onSync);
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant LedgerMoreBalances oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncTicks != widget.syncTicks) {
      oldWidget.syncTicks?.removeListener(_onSync);
      widget.syncTicks?.addListener(_onSync);
    }
    if (oldWidget.shop.id != widget.shop.id ||
        oldWidget.userId != widget.userId ||
        oldWidget.gateway != widget.gateway ||
        oldWidget.refreshGeneration != widget.refreshGeneration) {
      _dismissDetails();
      _ledger = null;
      _error = null;
      _metrics = migrateLedgerMetricLayout(null);
      unawaited(_reload());
    }
  }

  @override
  void dispose() {
    widget.syncTicks?.removeListener(_onSync);
    _dismissDetails();
    _detailRevision.dispose();
    super.dispose();
  }

  void _notifyDetails() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _detailRevision.value++;
    });
  }

  void _dismissDetails() {
    final surface = _detailContext;
    _detailContext = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (surface != null &&
          surface.mounted &&
          ModalRoute.of(surface)?.isCurrent == true) {
        Navigator.of(surface).pop();
      }
    });
  }

  Future<void> _showDetails({required bool cash}) async {
    if (_detailContext != null) return;
    await showDetailSurface(
      context,
      title: cash ? 'وسائل الدفع' : 'المخزون والكسر',
      builder: (surface) {
        _detailContext = surface;
        return ValueListenableBuilder<int>(
          valueListenable: _detailRevision,
          builder: (_, _, _) {
            final view = _ledger;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loading) const LinearProgressIndicator(),
                if (_error != null) ...[
                  Text(_error!),
                  TextButton(
                    onPressed: _loading ? null : _reload,
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
                if (view == null || !view.isConfirmed)
                  const Text('بيانات الدفتر غير متاحة.')
                else if (cash)
                  LedgerCashBreakdown(view: view)
                else
                  LedgerGoldBreakdown(view: view),
              ],
            );
          },
        );
      },
    );
    _detailContext = null;
  }

  void _onSync() {
    if (mounted) unawaited(_reload());
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    final gateway = widget.gateway;
    final userId = widget.userId;
    final shopId = widget.shop.id;
    setState(() {
      _loading = true;
      _error = null;
    });
    _notifyDetails();
    if (gateway == null || userId == null || userId.isEmpty) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _ledger = null;
        _loading = false;
        _error = 'بيانات المحل غير متاحة';
      });
      _dismissDetails();
      return;
    }
    // Local layout storage must never block a confirmed balance read.
    unawaited(_loadMetrics());
    try {
      final view = await gateway.ledger(callerUserId: userId);
      if (!mounted || generation != _generation || widget.shop.id != shopId) {
        return;
      }
      setState(() {
        _ledger = view;
        _loading = false;
        _error = null;
      });
      _notifyDetails();
    } catch (error) {
      if (!mounted || generation != _generation || widget.shop.id != shopId) {
        return;
      }
      final code = error is LedgerReadException ? error.code : null;
      final denied = openingAccessDenied(code);
      setState(() {
        if (denied) _ledger = null;
        _loading = false;
        _error = denied
            ? openingFailureCopy(code ?? 'forbidden')
            : _ledger == null
            ? 'تعذر تحميل أرصدة الدفتر.'
            : 'تعذر تحديث أرصدة الدفتر. الأرقام المعروضة قديمة.';
      });
      if (denied) _dismissDetails();
      _notifyDetails();
    }
  }

  Future<void> _loadMetrics() async {
    final key = _preferenceKey;
    List<String>? saved;
    try {
      saved = (await SharedPreferences.getInstance()).getStringList(key);
    } catch (_) {
      saved = null;
    }
    if (!mounted || key != _preferenceKey) return;
    setState(() => _metrics = migrateLedgerMetricLayout(saved));
  }

  Map<String, _MoreMetric> _values(DailyLedgerView view) {
    final summary = view.daySummary;
    String money(String? wire) => wire == null
        ? '—'
        : displayPounds(
            (Piastres.parseWire(wire) as Accepted<Piastres>).value.poundsText,
          );
    BigInt weight(String kind) =>
        summary?.goldByBucket
            .where((row) => row.kind == kind)
            .fold<BigInt>(
              BigInt.zero,
              (sum, row) => sum + BigInt.parse(row.milligrams),
            ) ??
        BigInt.zero;
    final gold =
        view.stock.fold<BigInt>(
          BigInt.zero,
          (sum, line) =>
              sum + (BigInt.tryParse(line.milligrams) ?? BigInt.zero),
        ) +
        view.scrap.fold<BigInt>(
          BigInt.zero,
          (sum, line) =>
              sum + (BigInt.tryParse(line.milligrams) ?? BigInt.zero),
        );
    return {
      'total_cash': _MoreMetric(
        ledgerMetricLabel('total_cash'),
        displayPounds(view.totalCashPounds ?? '—'),
        '',
        Icons.account_balance_wallet_outlined,
        LedgerMetricTone.primary,
      ),
      'total_gold': _MoreMetric(
        ledgerMetricLabel('total_gold'),
        displayGrams(gold.toString()),
        'جرام',
        Icons.diamond_outlined,
        LedgerMetricTone.primary,
      ),
      'sale': _MoreMetric(
        ledgerMetricLabel('sale'),
        money(summary?.salePiastres),
        '',
        Icons.trending_up,
        LedgerMetricTone.positive,
      ),
      'purchase': _MoreMetric(
        ledgerMetricLabel('purchase'),
        money(summary?.purchasePiastres),
        '',
        Icons.trending_down,
        LedgerMetricTone.negative,
      ),
      'sale_gold': _MoreMetric(
        ledgerMetricLabel('sale_gold'),
        displayGrams(weight('sale').toString()),
        'جرام',
        Icons.south_west,
        LedgerMetricTone.positive,
      ),
      'purchase_gold': _MoreMetric(
        ledgerMetricLabel('purchase_gold'),
        displayGrams(weight('purchase').toString()),
        'جرام',
        Icons.south_east,
        LedgerMetricTone.negative,
      ),
      'expense': _MoreMetric(
        ledgerMetricLabel('expense'),
        money(summary?.expensePiastres),
        '',
        Icons.receipt_long_outlined,
        LedgerMetricTone.neutral,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final view = _ledger;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading)
          const LinearProgressIndicator(key: Key('more-balances-loading')),
        if (_error != null) ...[
          Text(_error!, key: const Key('more-balances-error')),
          TextButton.icon(
            key: const Key('more-balances-retry'),
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
        if (view == null && !_loading && _error == null)
          const Text(
            'لا توجد أرصدة مؤكدة لهذا المحل.',
            key: Key('more-balances-empty'),
          ),
        if (view != null && !view.isConfirmed)
          const Text(
            'لا توجد أرصدة مؤكدة لهذا المحل.',
            key: Key('more-balances-unconfirmed'),
          ),
        if (view != null && view.isConfirmed) ...[
          Text('باقي أرقام الدفتر', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          _remainingTile(view),
          const SizedBox(height: 20),
          TextButton.icon(
            key: const Key('more-inventory-scrap'),
            onPressed: () => _showDetails(cash: false),
            icon: const Icon(Icons.diamond_outlined),
            label: const Text('المخزون والكسر'),
          ),
        ],
      ],
    );
  }

  Widget _remainingTile(DailyLedgerView view) {
    final spec = _values(view)[_metrics.remainingId]!;
    final cash = _metrics.remainingId == 'total_cash';
    return LedgerMetricTile(
      key: Key('more-metric-${_metrics.remainingId}'),
      label: spec.label,
      value: spec.value,
      unit: spec.unit,
      icon: spec.icon,
      tone: spec.tone,
      trailing: cash
          ? IconButton(
              key: const Key('more-cash-methods'),
              tooltip: 'وسائل الدفع',
              onPressed: () => _showDetails(cash: true),
              icon: const Icon(Icons.keyboard_arrow_left),
            )
          : null,
    );
  }
}

class _MoreMetric {
  const _MoreMetric(this.label, this.value, this.unit, this.icon, this.tone);
  final String label;
  final String value;
  final String unit;
  final IconData icon;
  final LedgerMetricTone tone;
}
