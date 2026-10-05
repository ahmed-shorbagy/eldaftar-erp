import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../daily_ledger/application/financial_gateway.dart';
import '../../daily_ledger/application/opening_gateway.dart';
import '../../daily_ledger/application/pending_financial_command.dart';
import '../../daily_ledger/data/pending_financial_command.dart';
import '../../daily_ledger/domain/opening_issue.dart';
import '../../daily_ledger/domain/quantities.dart';
import '../../daily_ledger/presentation/ledger_form_fields.dart';
import '../../daily_ledger/presentation/purchase_cash_settlement_screen.dart';
import '../../onboarding/application/onboarding_store.dart';
import '../application/inventory_command_flow.dart';
import '../application/inventory_gateway.dart';
import '../domain/inventory_models.dart';
import 'inventory_copy.dart';
import 'inventory_forms.dart';
import 'inventory_widgets.dart';
import 'trader_statement_pdf.dart';

typedef TraderPdfShare = Future<void> Function(Uint8List bytes);

class TraderScreen extends StatefulWidget {
  const TraderScreen({
    super.key,
    required this.gateway,
    required this.statusGateway,
    required this.userId,
    required this.shopId,
    required this.shopName,
    required this.readOnly,
    this.dayGateway,
    this.settlementGateway,
    this.onboardingStore,
    this.store = const PendingFinancialCommands(),
    this.sharePdf,
  });

  final InventoryGateway gateway;
  final OpeningGateway statusGateway;
  final FinancialGateway? dayGateway;
  final PurchaseSettlementGateway? settlementGateway;
  final String userId;
  final String shopId;
  final String shopName;
  final bool readOnly;
  final OnboardingStore? onboardingStore;
  final FinancialCommandLocker store;
  final TraderPdfShare? sharePdf;

  @override
  State<TraderScreen> createState() => _TraderScreenState();
}

class _TraderScreenState extends State<TraderScreen> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _listFocus = FocusNode();
  final _statementFocus = FocusNode();
  final _nameFocus = FocusNode();
  late final InventoryCommandFlow _flow = InventoryCommandFlow(
    gateway: widget.gateway,
    statusGateway: widget.statusGateway,
    store: widget.store,
  );
  int _generation = 0;
  bool _loading = true;
  String? _message;
  bool _messageError = false;
  DayAnchor? _day;
  List<TraderSummary> _traders = const [];
  String? _nextCursor;
  TraderDetail? _detail;
  List<TraderActivity> _activity = const [];
  String? _activityCursor;
  List<TraderObligation> _obligations = const [];
  String? _obligationCursor;
  bool _obligationsMissing = false;
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TraderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.shopId != widget.shopId) {
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _listFocus.dispose();
    _statementFocus.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<DayAnchor?> _readDay() async {
    final gateway = widget.dayGateway;
    if (gateway == null) return null;
    final state = await gateway.dayState(callerUserId: widget.userId);
    final id = state.dayId;
    final version = state.dayVersion;
    if (!state.isOpen || id == null || version == null || version < 1) {
      return null;
    }
    final parsed = DayAnchor.tryCreate(id, '$version');
    return parsed is InventoryAccepted<DayAnchor> ? parsed.value : null;
  }

  bool _same(int generation, String userId, String shopId) =>
      mounted &&
      generation == _generation &&
      widget.userId == userId &&
      widget.shopId == shopId;

  Future<void> _load() async {
    final generation = ++_generation;
    final userId = widget.userId;
    final shopId = widget.shopId;
    setState(() => _loading = true);
    DayAnchor? day;
    List<TraderSummary> traders = const [];
    String? cursor;
    String? message;
    var error = false;
    try {
      day = await _readDay();
    } catch (_) {
      message = 'تعذر قراءة يوم العمل. لم يُرسل أمر.';
      error = true;
    }
    try {
      final query = _search.text.trim();
      final page = await widget.gateway.traders(
        callerUserId: userId,
        query: query.isEmpty ? null : query,
      );
      if (!_same(generation, userId, shopId)) return;
      traders = page.items;
      cursor = page.nextCursor;
    } on InventoryReadException catch (failure) {
      if (!_same(generation, userId, shopId)) return;
      if (failure.code == 'discarded') {
        setState(() {
          _loading = false;
          _message = inventoryFailureCopy('discarded');
          _messageError = true;
        });
        return;
      }
      message = inventoryFailureCopy(failure.code ?? 'unavailable');
      error = true;
    } catch (_) {
      if (!_same(generation, userId, shopId)) return;
      message = 'تعذر تحميل التجار.';
      error = true;
    }
    if (!_same(generation, userId, shopId)) return;
    setState(() {
      _loading = false;
      _day = day;
      _traders = traders;
      _nextCursor = cursor;
      _message =
          message ??
          (widget.readOnly ? 'الاشتراك منتهٍ. بيانات التجار للقراءة.' : null);
      _messageError = error || widget.readOnly;
      if (_detail != null && traders.every((item) => item.id != _detail!.id)) {
        _detail = null;
        _activity = const [];
        _activityCursor = null;
        _obligations = const [];
        _obligationCursor = null;
      }
    });
    final selected = _detail?.id;
    if (selected != null) await _openTrader(selected, quiet: true);
  }

  Future<void> _openTrader(String id, {bool quiet = false}) async {
    final generation = _generation;
    final userId = widget.userId;
    final shopId = widget.shopId;
    try {
      final detail = await widget.gateway.trader(
        callerUserId: userId,
        traderId: id,
      );
      if (!_same(generation, userId, shopId)) return;
      final activity = await widget.gateway.traderActivity(
        callerUserId: userId,
        traderId: id,
      );
      if (!_same(generation, userId, shopId)) return;
      final obligations = await widget.gateway.traderObligations(
        callerUserId: userId,
        traderId: id,
      );
      if (!_same(generation, userId, shopId)) return;
      setState(() {
        _detail = detail;
        _activity = activity.items;
        _activityCursor = activity.nextCursor;
        _obligationsMissing = !obligations.available;
        _obligations = obligations.items ?? const [];
        _obligationCursor = obligations.nextCursor;
        if (!quiet) {
          _message = null;
          _messageError = false;
        }
      });
    } on InventoryReadException catch (error) {
      if (!_same(generation, userId, shopId)) return;
      if (error.code == 'discarded') {
        setState(() {
          _message = inventoryFailureCopy('discarded');
          _messageError = true;
        });
        return;
      }
      setState(() {
        _message = inventoryFailureCopy(error.code ?? 'unavailable');
        _messageError = true;
      });
    }
  }

  Future<void> _share() async {
    final detail = _detail;
    if (detail == null || _sharing) return;
    setState(() => _sharing = true);
    try {
      final bytes = await buildTraderStatementPdf(
        shopName: widget.shopName,
        trader: detail,
        activity: _activity,
        activityHasOlder: _activityCursor != null,
      );
      final share = widget.sharePdf;
      if (share != null) {
        await share(bytes);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: 'amanah-statement.pdf');
      }
      if (!mounted) return;
      setState(() {
        _sharing = false;
        _message = 'أُعد كشف الأمانة من الأرقام المؤكدة.';
        _messageError = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sharing = false;
        _message = 'تعذر بناء كشف الأمانة.';
        _messageError = true;
      });
    }
  }

  Future<void> _olderActivity(String traderId) async {
    final cursor = _activityCursor;
    if (cursor == null) return;
    final userId = widget.userId;
    final generation = _generation;
    try {
      final page = await widget.gateway.traderActivity(
        callerUserId: userId,
        traderId: traderId,
        cursor: cursor,
      );
      if (!_same(generation, userId, widget.shopId)) return;
      setState(() {
        _activity = [..._activity, ...page.items];
        _activityCursor = page.nextCursor;
      });
    } on InventoryReadException catch (error) {
      if (!_same(generation, userId, widget.shopId) ||
          error.code != 'discarded') {
        return;
      }
      setState(() {
        _message = inventoryFailureCopy('discarded');
        _messageError = true;
      });
    }
  }

  Future<void> _olderObligations(String traderId) async {
    final cursor = _obligationCursor;
    if (cursor == null) return;
    final userId = widget.userId;
    final generation = _generation;
    try {
      final page = await widget.gateway.traderObligations(
        callerUserId: userId,
        traderId: traderId,
        cursor: cursor,
      );
      if (!_same(generation, userId, widget.shopId) || !page.available) return;
      setState(() {
        _obligations = [..._obligations, ...?page.items];
        _obligationCursor = page.nextCursor;
      });
    } on InventoryReadException catch (error) {
      if (!_same(generation, userId, widget.shopId) ||
          error.code != 'discarded') {
        return;
      }
      setState(() {
        _message = inventoryFailureCopy('discarded');
        _messageError = true;
      });
    }
  }

  Future<void> _openCashSettlement(TraderObligation item) async {
    final gateway = widget.settlementGateway;
    final parsed = Piastres.parseWire(item.remaining.toString());
    if (gateway == null || parsed is! Accepted<Piastres>) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PurchaseCashSettlementScreen(
          gateway: gateway,
          statusGateway: widget.statusGateway,
          userId: widget.userId,
          shopId: widget.shopId,
          purchaseOperationId: item.operationId,
          remaining: parsed.value,
        ),
      ),
    );
  }

  InventoryFormScope get _scope => InventoryFormScope(
    flow: _flow,
    userId: widget.userId,
    shopId: widget.shopId,
    readOnly: widget.readOnly,
    day: _day,
    reloadDay: _readDay,
  );

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return InventoryPage(
      title: 'التجار والأمانات',
      actions: [
        IconButton(
          tooltip: 'تحديث التجار',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_message != null) ...[
          InventoryNotice(
            message: _message!,
            error: _messageError,
            messageKey: const Key('trader-status'),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          key: const Key('trader-search'),
          controller: _search,
          focusNode: _searchFocus,
          maxLength: 120,
          textInputAction: TextInputAction.search,
          decoration: ledgerFieldDecoration(context, label: 'بحث عن تاجر'),
          onSubmitted: (_) => _load(),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('trader-search-go'),
          onPressed: _load,
          child: const Text('بحث'),
        ),
        const SizedBox(height: 12),
        Focus(
          focusNode: _listFocus,
          child: Column(
            key: const Key('trader-list'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_traders.isEmpty && !_loading)
                const Text('لا يوجد تاجر مطابق.'),
              for (final trader in _traders)
                Card(
                  child: ListTile(
                    key: Key('trader-row-${trader.id}'),
                    minVerticalPadding: 12,
                    title: Text(trader.displayName),
                    subtitle: Text(
                      '${trader.active ? 'نشط' : 'موقوف'}'
                      '${trader.phone.isEmpty ? '' : ' — ${trader.phone}'}',
                    ),
                    onTap: () => _openTrader(trader.id),
                  ),
                ),
            ],
          ),
        ),
        if (_nextCursor != null)
          OutlinedButton(
            onPressed: () async {
              final page = await widget.gateway.traders(
                callerUserId: widget.userId,
                query: _search.text.trim().isEmpty ? null : _search.text.trim(),
                cursor: _nextCursor,
              );
              if (!mounted) return;
              setState(() {
                _traders = [..._traders, ...page.items];
                _nextCursor = page.nextCursor;
              });
            },
            child: const Text('المزيد من التجار'),
          ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('trader-statement'),
          focusNode: _statementFocus,
          onPressed: detail == null || _sharing ? null : _share,
          child: Text(_sharing ? 'جارٍ إعداد الكشف' : 'كشف أمانة محاسبي'),
        ),
        if (detail != null) ...[
          const SizedBox(height: 16),
          Text(
            detail.displayName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'ما استُلم أصلاً ${gramsOf(detail.originalHeldMilligrams)} جرام. '
            'ما زال في الحيازة ${gramsOf(detail.currentHeldMilligrams)} جرام. '
            'استلامات معلّقة ${detail.pendingReceiptCount}.',
            key: const Key('trader-holding'),
          ),
          Text(
            'المبلغ المستحق المتبقي ${poundsOf(detail.cashPayableRemainingPiastres)} '
            '(${detail.cashPayableRemainingPiastres} قرشاً).',
            key: const Key('trader-cash-remaining'),
          ),
          if (detail.goldRemaining.isEmpty)
            const Text('لا يوجد متبقي ذهب مربوط بهذا التاجر.')
          else
            for (final gold in detail.goldRemaining)
              Text(
                'ذهب عيار ${gold.karat}: المتبقي ${gramsOf(gold.remainingMilligrams)} جرام '
                'من أصل ${gramsOf(gold.initialMilligrams)} جرام.',
                key: Key('trader-gold-${gold.karat}'),
              ),
          for (final bucket in detail.buckets)
            ListTile(
              title: Text(
                '${inventoryCategoryLabel(bucket.category)} عيار ${bucket.karat}',
              ),
              subtitle: Text(
                'الأصل ${gramsOf(bucket.originalMilligrams)} — الحالي ${gramsOf(bucket.currentMilligrams)}',
              ),
            ),
          Text(
            _activityCursor == null
                ? 'النشاط المحمّل ${_activity.length} حركة. لا يوجد مؤشر لصفحة أقدم، وهذا ليس ادّعاءً بأن السجلات التاريخية خارج الصفحة صُفّرت.'
                : 'النشاط المعروض أحدث ${_activity.length} حركة فقط. توجد حركات أقدم ولم يكتمل الكشف.',
            key: const Key('trader-activity-range'),
          ),
          for (final line in _activity)
            ListTile(
              key: Key('trader-activity-${line.operationId}'),
              title: Text('${line.kind} — ${line.shopSequence}'),
              subtitle: Text(line.createdAt),
            ),
          if (_activity.isEmpty) const Text('لا يوجد نشاط مؤكد في هذه الصفحة.'),
          if (_activityCursor != null)
            OutlinedButton(
              key: const Key('trader-activity-older'),
              onPressed: () => _olderActivity(detail.id),
              child: const Text('حركات أقدم'),
            ),
          const Text('التزامات مربوطة بمعرّف التاجر'),
          if (_obligationsMissing)
            const Text('قائمة الالتزامات غير متاحة في هذا الاتصال.')
          else ...[
            Text(
              _obligationCursor == null
                  ? 'الالتزامات المعروضة ${_obligations.length}. لا يوجد مؤشر لصف أقدم.'
                  : 'الالتزامات المعروضة ${_obligations.length}. توجد صفوف أقدم.',
            ),
            for (final item in _obligations)
              ListTile(
                key: Key('trader-obligation-${item.operationId}'),
                title: Text(
                  item.unit == 'egp_piastres'
                      ? 'مستحق نقدي'
                      : 'ذهب عيار ${item.karat} ${item.operationId}',
                ),
                subtitle: Text(
                  'المتبقي ${item.unit == 'egp_piastres' ? poundsOf(item.remaining) : '${gramsOf(item.remaining)} جرام'}',
                ),
                onTap:
                    item.unit == 'egp_piastres' &&
                        item.remaining > BigInt.zero &&
                        widget.settlementGateway != null
                    ? () => _openCashSettlement(item)
                    : null,
              ),
            if (_obligationCursor != null)
              OutlinedButton(
                key: const Key('trader-obligations-older'),
                onPressed: () => _olderObligations(detail.id),
                child: const Text('التزامات أقدم'),
              ),
          ],
        ],
        const SizedBox(height: 24),
        TraderSaveForm(
          scope: _scope,
          nameFocus: _nameFocus,
          embedded: true,
          onFinished: _load,
        ),
      ],
    );
  }
}
