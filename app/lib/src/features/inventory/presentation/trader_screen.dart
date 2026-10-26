import 'dart:async';

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
    this.refreshGeneration = 0,
    this.syncTicks,
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
  final int refreshGeneration;
  final Listenable? syncTicks;

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
  bool _reloadInFlight = false;
  bool _reloadPending = false;
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
  List<ReceiptSnapshot> _receipts = const [];
  String? _receiptCursor;
  bool _receiptsMissing = false;
  List<LotSnapshot> _lots = const [];
  List<GoldObligationView> _gold = const [];
  bool _sharing = false;

  BigInt get _pendingOnPage {
    var total = BigInt.zero;
    for (final trader in _traders) {
      total += trader.pendingReceiptCount;
    }
    return total;
  }

  @override
  void initState() {
    super.initState();
    widget.syncTicks?.addListener(_onSync);
    _load();
  }

  @override
  void didUpdateWidget(covariant TraderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncTicks != widget.syncTicks) {
      oldWidget.syncTicks?.removeListener(_onSync);
      widget.syncTicks?.addListener(_onSync);
    }
    if (oldWidget.userId != widget.userId ||
        oldWidget.shopId != widget.shopId ||
        (widget.syncTicks == null &&
            oldWidget.refreshGeneration != widget.refreshGeneration)) {
      _load();
    }
  }

  void _onSync() {
    if (mounted) _load();
  }

  @override
  void dispose() {
    widget.syncTicks?.removeListener(_onSync);
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
    if (_reloadInFlight) {
      _reloadPending = true;
      return;
    }
    _reloadInFlight = true;
    try {
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
        if (_detail != null &&
            traders.every((item) => item.id != _detail!.id)) {
          _detail = null;
          _activity = const [];
          _activityCursor = null;
          _obligations = const [];
          _obligationCursor = null;
          _receipts = const [];
          _receiptCursor = null;
          _lots = const [];
          _gold = const [];
        }
      });
      final selected = _detail?.id;
      if (selected != null) await _openTrader(selected, quiet: true);
    } finally {
      _reloadInFlight = false;
      final reload = _reloadPending;
      _reloadPending = false;
      if (reload && mounted) unawaited(_load());
    }
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
      var receipts = const ReceiptPage.missing();
      try {
        receipts = await widget.gateway.receipts(
          callerUserId: userId,
          traderId: id,
        );
      } catch (_) {}
      if (!_same(generation, userId, shopId)) return;
      var lots = const LotPage([], null);
      var gold = const ReadPage<GoldObligationView>.ready([], null);
      try {
        lots = await widget.gateway.lots(callerUserId: userId);
        if (!_same(generation, userId, shopId)) return;
        gold = await widget.gateway.goldObligations(callerUserId: userId);
      } catch (_) {}
      if (!_same(generation, userId, shopId)) return;
      setState(() {
        _detail = detail;
        _activity = activity.items;
        _activityCursor = activity.nextCursor;
        _obligationsMissing = !obligations.available;
        _obligations = obligations.items ?? const [];
        _obligationCursor = obligations.nextCursor;
        _receiptsMissing = !receipts.available;
        _receipts = receipts.items ?? const [];
        _receiptCursor = receipts.nextCursor;
        _lots = lots.items;
        _gold = [
          for (final item in gold.items ?? const <GoldObligationView>[])
            if (item.traderId == id) item,
        ];
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

  Future<void> _openGoldSettlement(TraderObligation item) async {
    GoldObligationView? matched;
    for (final row in _gold) {
      if (row.operationId == item.operationId) {
        matched = row;
        break;
      }
    }
    final rows = [
      ?matched,
      for (final row in _gold)
        if (row.operationId != item.operationId) row,
    ];
    if (rows.isEmpty) {
      setState(() {
        _message = 'لا يوجد مستحق ذهبي مفتوح لهذا التاجر في هذه القراءة.';
        _messageError = true;
      });
      return;
    }
    await _openForm(
      GoldSettlementForm(
        scope: _scope,
        obligations: rows,
        lots: _lots,
        initialObligationId: item.operationId,
        loadOlder: (cursor) => widget.gateway.goldObligations(
          callerUserId: widget.userId,
          cursor: cursor,
        ),
      ),
    );
  }

  Future<void> _openForm(Widget page) async {
    final saved = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => page));
    final id = _detail?.id;
    if (saved == true && id != null) {
      await _load();
      if (mounted) await _openTrader(id, quiet: true);
    }
  }

  Future<void> _openReceiptAction(ReceiptSnapshot receipt) async {
    if (receipt.remainingMilligrams <= BigInt.zero) return;
    if (receipt.policy == 'custody') {
      await _openForm(
        OwnershipTransferForm(
          scope: _scope,
          receipts: _receipts,
          nextCursor: _receiptCursor,
          initialReceiptId: receipt.id,
          loadOlder: (cursor) => widget.gateway.receipts(
            callerUserId: widget.userId,
            traderId: _detail?.id,
            ownerKind: 'trader',
            recognition: 'custody',
            cursor: cursor,
          ),
        ),
      );
      return;
    }
    if (receipt.policy == 'deferred') {
      await _openForm(
        InventoryRecognitionForm(
          scope: _scope,
          receipts: _receipts,
          nextCursor: _receiptCursor,
          initialReceiptId: receipt.id,
          loadOlder: (cursor) => widget.gateway.receipts(
            callerUserId: widget.userId,
            traderId: _detail?.id,
            ownerKind: 'shop',
            recognition: 'deferred',
            cursor: cursor,
          ),
        ),
      );
    }
  }

  Future<void> _openManualLink(ReceiptSnapshot receipt) async {
    await _openForm(
      InventoryManualLinkForm(
        scope: _scope,
        receipts: _receipts,
        lots: _lots,
        nextCursor: _receiptCursor,
        initialReceiptId: receipt.id,
        loadOlder: (cursor) => widget.gateway.receipts(
          callerUserId: widget.userId,
          traderId: _detail?.id,
          ownerKind: 'shop',
          recognition: 'deferred',
          cursor: cursor,
        ),
      ),
    );
  }

  InventoryFormScope get _scope => InventoryFormScope(
    flow: _flow,
    gateway: widget.gateway,
    userId: widget.userId,
    shopId: widget.shopId,
    readOnly: widget.readOnly,
    day: _day,
    reloadDay: _readDay,
    onConfirmed: _load,
  );

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return InventoryPage(
      title: 'التجار والأمانات',
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
        if (_pendingOnPage > BigInt.zero)
          Card(
            key: const Key('trader-pending-banner'),
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: ListTile(
              title: Text(
                'يوجد $_pendingOnPage أوزان لم يتم إضافتها إلى المخزون.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ),
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
                      '${trader.phone.isEmpty ? '' : ' — ${trader.phone}'}'
                      '${trader.pendingReceiptCount > BigInt.zero ? ' — معلّق ${trader.pendingReceiptCount}' : ''}',
                    ),
                    trailing: trader.pendingReceiptCount > BigInt.zero
                        ? _StockStatusChip(pending: true)
                        : null,
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
                'الأصل ${gramsOf(bucket.originalMilligrams)} — الحالي ${gramsOf(bucket.currentMilligrams)}'
                '${bucket.pendingReceiptCount > BigInt.zero ? ' — معلّق ${bucket.pendingReceiptCount}' : ''}',
              ),
              trailing: bucket.pendingReceiptCount > BigInt.zero
                  ? const _StockStatusChip(pending: true)
                  : const _StockStatusChip(pending: false),
            ),
          const SizedBox(height: 8),
          Text(
            'أوزان الاستلام وحالة المخزون',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (_receiptsMissing)
            const Text('قائمة أوزان الاستلام غير متاحة في هذا الاتصال.')
          else if (_receipts.isEmpty)
            const Text('لا توجد أوزان استلام مؤكدة لهذا التاجر.')
          else
            for (final receipt in _receipts)
              Card(
                key: Key('trader-receipt-${receipt.id}'),
                child: ListTile(
                  title: Text(
                    '${inventoryCategoryLabel(receipt.category)} عيار ${receipt.karat}'
                    '${receipt.productName.isEmpty ? '' : ' — ${receipt.productName}'}',
                  ),
                  subtitle: Text(
                    'المتبقي ${gramsOf(receipt.remainingMilligrams)} جرام'
                    '${receipt.remainingCount == null ? '' : ' — ${receipt.remainingCount} قطعة'}'
                    '\n${receipt.remainingMilligrams > BigInt.zero ? 'لم تتم إضافتها للمخزون' : 'تمت إضافتها للمخزون'}',
                  ),
                  trailing: _StockStatusChip(
                    pending: receipt.remainingMilligrams > BigInt.zero,
                  ),
                  onTap: receipt.remainingMilligrams > BigInt.zero &&
                          !widget.readOnly &&
                          _day != null
                      ? () => _openReceiptAction(receipt)
                      : null,
                ),
              ),
          if (!_receiptsMissing)
            for (final receipt in _receipts)
              if (receipt.policy == 'deferred' &&
                  receipt.remainingMilligrams > BigInt.zero)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    key: Key('trader-manual-${receipt.id}'),
                    onPressed: widget.readOnly || _day == null
                        ? null
                        : () => _openManualLink(receipt),
                    child: const Text('تمت إضافتها يدويًا'),
                  ),
                ),
          if (_receiptCursor != null)
            OutlinedButton(
              key: const Key('trader-receipts-older'),
              onPressed: () async {
                final page = await widget.gateway.receipts(
                  callerUserId: widget.userId,
                  traderId: detail.id,
                  cursor: _receiptCursor,
                );
                if (!mounted || !page.available) return;
                setState(() {
                  _receipts = [..._receipts, ...?page.items];
                  _receiptCursor = page.nextCursor;
                });
              },
              child: const Text('أوزان استلام أقدم'),
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
              title: Text('${_activityKindLabel(line.kind)} — ${line.shopSequence}'),
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
                      : 'ذهب عيار ${item.karat}',
                ),
                subtitle: Text(
                  'المتبقي ${item.unit == 'egp_piastres' ? poundsOf(item.remaining) : '${gramsOf(item.remaining)} جرام'}'
                  '${item.unit == 'egp_piastres' ? '' : ' — يخصم من المخزون أو الكسر حسب اختيار التسوية'}',
                ),
                onTap: item.remaining <= BigInt.zero
                    ? null
                    : item.unit == 'egp_piastres' &&
                          widget.settlementGateway != null
                    ? () => _openCashSettlement(item)
                    : item.unit != 'egp_piastres'
                    ? () => _openGoldSettlement(item)
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

String _activityKindLabel(String kind) => switch (kind) {
  'inventory_receipt' => 'استلام أمانة',
  'inventory_recognition' => 'اعتراف بالمخزون',
  'ownership_transfer' => 'نقل ملكية',
  'receipt_manual_allocation' => 'ربط يدوي بالمخزون',
  'gold_obligation_acquisition' => 'شراء مقابل ذهب',
  'gold_obligation_settlement' => 'تسوية ذهب',
  'purchase_cash_settlement' => 'تسوية نقدية',
  _ => kind,
};

class _StockStatusChip extends StatelessWidget {
  const _StockStatusChip({required this.pending});

  final bool pending;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = pending ? scheme.tertiaryContainer : scheme.primaryContainer;
    final fg = pending ? scheme.onTertiaryContainer : scheme.onPrimaryContainer;
    return Semantics(
      label: pending ? 'لم تتم إضافتها للمخزون' : 'تمت إضافتها للمخزون',
      child: Container(
        key: Key(pending ? 'stock-status-pending' : 'stock-status-added'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          pending ? 'لم تُضف' : 'أُضيفت',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: fg),
        ),
      ),
    );
  }
}
