import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_tokens.dart';
import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/application/pending_financial_command.dart';
import '../../daily_ledger/domain/opening_catalog.dart';
import '../../daily_ledger/domain/opening_issue.dart';
import '../../daily_ledger/domain/quantities.dart';
import '../../../theme/cash_input.dart';
import '../../daily_ledger/presentation/opening_copy.dart';
import '../application/debt_command_flow.dart';
import '../application/debt_contract.dart';
import '../application/debt_gateway.dart';
import '../domain/debt_rules.dart';
import 'debt_copy.dart';
import '../application/debt_statement_gateway.dart';
import '../application/debt_statement_flow.dart';
import 'debt_statement_screen.dart';

class DebtScreen extends StatefulWidget {
  const DebtScreen({
    super.key,
    required this.gateway,
    required this.store,
    required this.userId,
    required this.shopId,
    required this.readOnly,
    this.refreshGeneration = 0,
    this.syncTicks,
    this.onMutated,
    this.newKey,
    this.canWrite,
    this.canRead,
    this.statementPlatform,
  });

  final DebtGateway gateway;
  final FinancialCommandLocker store;
  final String userId;
  final String shopId;
  final bool readOnly;
  final int refreshGeneration;
  final Listenable? syncTicks;
  final VoidCallback? onMutated;
  final String Function()? newKey;
  final bool Function()? canWrite;
  final bool Function()? canRead;
  final DebtStatementPlatform? statementPlatform;

  @override
  State<DebtScreen> createState() => _DebtScreenState();
}

enum _Stage {
  list,
  declare,
  declareReview,
  detail,
  settle,
  settleReview,
  cancelReview,
  archiveReview,
  success,
}

class _TenderDraft {
  String method = 'cash';
  final amount = TextEditingController();
  void dispose() => amount.dispose();
}

class _DebtScreenState extends State<DebtScreen> {
  final _formKey = GlobalKey<FormState>();
  final _search = TextEditingController();
  final _party = TextEditingController();
  final _phone = TextEditingController();
  final _reason = TextEditingController();
  final _external = TextEditingController();
  final _amount = TextEditingController();
  final _settleAmount = TextEditingController();
  final _settleReason = TextEditingController();
  final _product = TextEditingController();
  final _count = TextEditingController();
  final _actionReason = TextEditingController();
  int _generation = 0;
  bool _backendReady = false;
  bool _pendingLoadFailed = false;
  bool _statementOpening = false;
  PendingFinancialCommand? _foreignPending;

  _Stage _stage = _Stage.list;
  DebtDirection _direction = DebtDirection.shopOwes;
  DebtUnit _unit = DebtUnit.money;
  int _karat = 21;
  String _category = 'worked_jewelry';
  DebtLedgerEffect _ledgerEffect = DebtLedgerEffect.move;
  String _filter = 'open';
  bool _loading = true;
  bool _busy = false;
  bool _reviewStale = false;
  String? _error;
  String? _cursor;
  String? _idempotency;
  DebtPage? _page;
  DebtDetail? _detail;
  DebtContext? _context;
  DebtDeclaration? _declaration;
  DebtSettlement? _settlement;
  DebtRpcCommitted? _saved;
  PendingFinancialCommand? _pending;
  bool _pendingUnknown = false;
  final _tenders = <_TenderDraft>[_TenderDraft()];
  final _lotGrams = <String, TextEditingController>{};
  final _lotCounts = <String, TextEditingController>{};
  final _pickedLots = <String>{};

  String get _identity => '${widget.userId}:${widget.shopId}';
  bool _current(String identity, int generation) =>
      mounted && identity == _identity && generation == _generation;
  DebtCommandFlow get _commands =>
      DebtCommandFlow(gateway: widget.gateway, store: widget.store);
  bool get _readOnly =>
      widget.readOnly || (widget.canWrite != null && !widget.canWrite!());

  @override
  void initState() {
    super.initState();
    widget.syncTicks?.addListener(_onSync);
    _load();
  }

  @override
  void didUpdateWidget(DebtScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncTicks != widget.syncTicks) {
      oldWidget.syncTicks?.removeListener(_onSync);
      widget.syncTicks?.addListener(_onSync);
    }
    if (oldWidget.shopId != widget.shopId ||
        oldWidget.userId != widget.userId ||
        oldWidget.gateway != widget.gateway ||
        oldWidget.store != widget.store) {
      _generation++;
      _stage = _Stage.list;
      _detail = null;
      _context = null;
      _page = null;
      _saved = null;
      _pending = null;
      _foreignPending = null;
      _idempotency = null;
      _declaration = null;
      _settlement = null;
      _backendReady = false;
      _busy = false;
      _reviewStale = false;
      _filter = 'open';
      _search.clear();
      for (final field in [
        _party,
        _phone,
        _reason,
        _external,
        _amount,
        _settleAmount,
        _settleReason,
        _product,
        _count,
        _actionReason,
      ]) {
        field.clear();
      }
      _pickedLots.clear();
      _load();
    } else if (oldWidget.refreshGeneration != widget.refreshGeneration) {
      _onSync();
    }
  }

  @override
  void dispose() {
    widget.syncTicks?.removeListener(_onSync);
    _search.dispose();
    _party.dispose();
    _phone.dispose();
    _reason.dispose();
    _external.dispose();
    _amount.dispose();
    _settleAmount.dispose();
    _settleReason.dispose();
    _product.dispose();
    _count.dispose();
    _actionReason.dispose();
    for (final tender in _tenders) {
      tender.dispose();
    }
    for (final controller in _lotGrams.values) {
      controller.dispose();
    }
    for (final controller in _lotCounts.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onSync() {
    if (!mounted) return;
    setState(() => _reviewStale = _stage.name.contains('Review'));
    if (!_busy && (_stage == _Stage.list || _stage == _Stage.detail)) _load();
  }

  bool get _writesBlocked =>
      _readOnly ||
      _busy ||
      _loading ||
      !_backendReady ||
      _pending != null ||
      _foreignPending != null ||
      _pendingLoadFailed;

  Future<void> _load({bool clearError = true}) async {
    final identity = _identity;
    final generation = ++_generation;
    final userId = widget.userId, shopId = widget.shopId;
    final selected = _detail?.summary;
    setState(() {
      _loading = true;
      _backendReady = false;
      if (clearError) _error = null;
    });
    try {
      final pending = await widget.store.read(userId, shopId);
      final page = await widget.gateway.readList(
        callerUserId: userId,
        query: _search.text.trim(),
        filter: _filter,
        limit: 20,
        cursor: null,
      );
      final context = await widget.gateway.readContext(callerUserId: userId);
      DebtDetail? detail;
      if (selected != null &&
          _stage != _Stage.list &&
          _stage != _Stage.success) {
        detail = await widget.gateway.readDetail(
          callerUserId: userId,
          sourceKind: selected.sourceKind.wire,
          sourceId: selected.sourceId,
        );
        if (detail.summary.sourceId != selected.sourceId ||
            detail.summary.sourceKind != selected.sourceKind) {
          throw const DebtReadException();
        }
      }
      if (!_current(identity, generation)) return;
      setState(() {
        _page = page;
        _cursor = page.nextCursor;
        _context = context;
        if (detail != null) _detail = detail;
        _pending = pending != null && debtRpcs.containsKey(pending.kind)
            ? pending
            : null;
        _foreignPending = pending != null && !debtRpcs.containsKey(pending.kind)
            ? pending
            : null;
        _pendingUnknown = _pending != null;
        _pendingLoadFailed = false;
        _loading = false;
        _backendReady = true;
      });
    } catch (error) {
      if (!_current(identity, generation)) return;
      setState(() {
        _loading = false;
        _pendingLoadFailed = true;
        _backendReady = false;
        _error = error is DebtReadException
            ? debtFailureText(error.code ?? 'read')
            : 'تعذر تحميل البيانات أو الطلب المحفوظ. أعد التحميل قبل أي تغيير.';
      });
    }
  }

  Future<void> _reloadReview() async {
    if (_pending != null || _foreignPending != null || _busy) return;
    final stage = _stage;
    await _load();
    if (!mounted || !_backendReady) return;
    setState(() {
      _reviewStale = false;
      _idempotency = null;
      _settlement = null;
      _stage = switch (stage) {
        _Stage.declareReview => _Stage.declare,
        _Stage.settleReview => _Stage.settle,
        _ => _Stage.detail,
      };
    });
  }

  Future<void> _more() async {
    final cursor = _cursor;
    if (cursor == null || _busy || _loading) return;
    final identity = _identity;
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      final page = await widget.gateway.readList(
        callerUserId: widget.userId,
        query: _search.text.trim(),
        filter: _filter,
        limit: 20,
        cursor: cursor,
      );
      if (!_current(identity, generation)) return;
      setState(() {
        final items = {
          for (final item in [...?_page?.items, ...page.items])
            item.debtKey: item,
        };
        _page = DebtPage(
          items: items.values.toList(),
          nextCursor: page.nextCursor,
          timeZone: page.timeZone,
        );
        _cursor = page.nextCursor;
        _busy = false;
      });
    } catch (error) {
      if (!_current(identity, generation)) return;
      setState(() {
        _busy = false;
        _error = debtFailureText(
          error is DebtReadException ? error.code ?? 'read' : 'read',
        );
      });
    }
  }

  Future<void> _openDetail(DebtSummary summary) async {
    if (_busy || _loading) return;
    final identity = _identity;
    final generation = ++_generation;
    setState(() => _busy = true);
    try {
      final detail = await widget.gateway.readDetail(
        callerUserId: widget.userId,
        sourceKind: summary.sourceKind.wire,
        sourceId: summary.sourceId,
      );
      final context = await widget.gateway.readContext(
        callerUserId: widget.userId,
      );
      if (!_current(identity, generation)) return;
      if (detail.summary.sourceId != summary.sourceId ||
          detail.summary.sourceKind != summary.sourceKind) {
        throw const DebtReadException();
      }
      setState(() {
        _detail = detail;
        _context = context;
        _stage = _Stage.detail;
        _busy = false;
        _error = null;
        _idempotency = null;
        _backendReady = true;
      });
    } catch (error) {
      if (!_current(identity, generation)) return;
      setState(() {
        _busy = false;
        _error = debtFailureText(
          error is DebtReadException ? error.code ?? 'read' : 'read',
        );
      });
    }
  }

  void _reviewDeclare() {
    if (_writesBlocked) return;
    if (_formKey.currentState?.validate() != true) return;
    final result = debtDeclaration(
      direction: _direction,
      unit: _unit,
      karat: _unit == DebtUnit.gold ? _karat : null,
      amountText: _unit == DebtUnit.money
          ? cashInputValue(_amount.text)
          : _amount.text.trim(),
      partyName: _party.text,
      contactPhone: _phone.text,
      reason: _reason.text,
      externalReference: _external.text,
    );
    if (result is DebtRejected<DebtDeclaration>) {
      setState(() => _error = debtIssueText(result.issue));
      return;
    }
    setState(() {
      _declaration = (result as DebtAccepted<DebtDeclaration>).value;
      _idempotency = widget.newKey?.call() ?? newIdempotencyKey();
      _reviewStale = false;
      _error = null;
      _stage = _Stage.declareReview;
    });
  }

  void _reviewSettle() {
    if (_writesBlocked) return;
    final detail = _detail;
    final day = _context?.day;
    if (detail == null || _formKey.currentState?.validate() != true) return;
    final moving = _ledgerEffect == DebtLedgerEffect.move;
    final result = debtSettlement(
      sourceKind: detail.summary.sourceKind,
      sourceId: detail.summary.sourceId,
      direction: detail.summary.direction,
      unit: detail.summary.unit,
      karat: detail.summary.karat,
      remaining: detail.summary.remaining,
      recordVersion: detail.summary.recordVersion,
      amountText: detail.summary.unit == DebtUnit.money
          ? cashInputValue(_settleAmount.text)
          : _settleAmount.text.trim(),
      ledgerEffect: detail.noLedgerAllowed
          ? _ledgerEffect
          : DebtLedgerEffect.move,
      reason: _settleReason.text,
      settlementReference: widget.newKey?.call() ?? newIdempotencyKey(),
      dayId: moving ? day?.dayId : null,
      dayVersion: moving ? day?.dayVersion : null,
      tenders: _moneyTenders(detail),
      deliveries: _goldDeliveries(detail),
      receipt: _goldReceipt(detail),
    );
    if (result is DebtRejected<DebtSettlement>) {
      setState(() => _error = debtIssueText(result.issue));
      return;
    }
    final settlement = (result as DebtAccepted<DebtSettlement>).value;
    setState(() {
      _settlement = settlement;
      _idempotency = settlement.settlementReference;
      _reviewStale = false;
      _error = null;
      _stage = _Stage.settleReview;
    });
  }

  List<DebtTender>? _moneyTenders(DebtDetail detail) {
    if (detail.summary.unit != DebtUnit.money ||
        _ledgerEffect == DebtLedgerEffect.none) {
      return null;
    }
    return [
      for (final tender in _tenders)
        if (cashInputValue(tender.amount.text).isNotEmpty)
          DebtTender(
            method: tender.method,
            piastres: _piastres(tender.amount.text),
          ),
    ];
  }

  BigInt _piastres(String text) {
    final parsed = Piastres.parsePounds(cashInputValue(text));
    return parsed is Accepted<Piastres> ? parsed.value.value : BigInt.zero;
  }

  List<DebtDelivery>? _goldDeliveries(DebtDetail detail) {
    if (detail.summary.unit != DebtUnit.gold ||
        detail.summary.direction != DebtDirection.shopOwes ||
        _ledgerEffect == DebtLedgerEffect.none) {
      return null;
    }
    final lots = _context?.lots ?? const <DebtLot>[];
    return [
      for (final id in _pickedLots)
        if (lots.where((lot) => lot.id == id).isNotEmpty)
          DebtDelivery(
            lotId: id,
            milligrams: _grams(_lotGrams[id]?.text ?? ''),
            count: lots.firstWhere((lot) => lot.id == id).scrap
                ? null
                : BigInt.tryParse(_lotCounts[id]?.text.trim() ?? ''),
            scrap: lots.firstWhere((lot) => lot.id == id).scrap,
          ),
    ];
  }

  BigInt _grams(String text) {
    final parsed = Milligrams.parseGrams(text.trim());
    return parsed is Accepted<Milligrams> ? parsed.value.value : BigInt.zero;
  }

  DebtReceipt? _goldReceipt(DebtDetail detail) {
    if (detail.summary.unit != DebtUnit.gold ||
        detail.summary.direction != DebtDirection.owedToShop ||
        _ledgerEffect == DebtLedgerEffect.none) {
      return null;
    }
    final parsed = Milligrams.parseGrams(_settleAmount.text.trim());
    if (parsed is! Accepted<Milligrams>) return null;
    final scrap = _category == 'scrap';
    return DebtReceipt(
      category: _category,
      productName: _product.text,
      milligrams: parsed.value.value,
      count: scrap ? null : BigInt.tryParse(_count.text.trim()),
    );
  }

  Future<void> _confirm(String kind, Map<String, Object?> payload) async {
    if (_writesBlocked || _reviewStale || _idempotency == null) return;
    final identity = _identity;
    final generation = ++_generation;
    final userId = widget.userId, shopId = widget.shopId;
    setState(() => _busy = true);
    final result = await _commands.submit(
      userId: userId,
      shopId: shopId,
      idempotencyKey: _idempotency!,
      kind: kind,
      payload: payload,
      readOnly: _readOnly,
    );
    if (!_current(identity, generation)) return;
    await _handleResult(result, kind);
  }

  Future<void> _handleResult(DebtSubmitResult result, String kind) async {
    if (result is DebtSaved) {
      widget.onMutated?.call();
      setState(() {
        _saved = result.committed;
        _pending = null;
        _stage = _Stage.success;
        _busy = false;
        _error = null;
      });
    } else if (result is DebtFailed || result is DebtNotSent) {
      final code = result is DebtFailed
          ? result.code
          : (result as DebtNotSent).code;
      setState(() {
        _busy = false;
        _idempotency = null;
        if (result is DebtFailed) _pending = null;
        _error = debtFailureText(code);
        _stage = kind == 'debt_declare' ? _Stage.declare : _Stage.detail;
      });
      await _load(clearError: false);
    } else {
      final unknown = result as DebtUnconfirmed;
      setState(() {
        _busy = false;
        _pending = unknown.command;
        _pendingUnknown = unknown.statusUnknown;
        _error = null;
      });
    }
  }

  Future<void> _retry() async {
    final pending = _pending;
    if (pending == null || _busy) return;
    final identity = _identity;
    final generation = ++_generation;
    final userId = widget.userId, shopId = widget.shopId;
    setState(() => _busy = true);
    final result = await _commands.reconcile(
      userId: userId,
      shopId: shopId,
      command: pending,
      retry: true,
    );
    if (!_current(identity, generation)) return;
    await _handleResult(result, pending.kind);
  }

  void _reviewAction(_Stage stage) {
    if (_writesBlocked) return;
    if (_formKey.currentState?.validate() != true) return;
    final detail = _detail;
    if (detail == null) return;
    final reason = debtReason(_actionReason.text);
    if (reason is DebtRejected<String>) {
      setState(() => _error = debtIssueText(reason.issue));
      return;
    }
    setState(() {
      _idempotency = widget.newKey?.call() ?? newIdempotencyKey();
      _reviewStale = false;
      _error = null;
      _stage = stage;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('الديون')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTokens.contentMaxWidth,
            ),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              children: [
                if (_readOnly)
                  Text(
                    'الحساب للقراءة فقط. يمكن عرض الديون دون تسجيل أو سداد.',
                    style: theme.textTheme.bodyMedium,
                  ),
                if (_foreignPending != null)
                  const Text(
                    'يوجد طلب آخر بانتظار التأكيد. عد إلى الدفتر لمتابعته.',
                    key: Key('debt-other-pending'),
                  ),
                if (_reviewStale)
                  _button(
                    'تحميل البيانات وإعادة المراجعة',
                    _reloadReview,
                    key: const Key('debt-reload-review'),
                  ),
                if (_pendingLoadFailed)
                  _button(
                    'إعادة التحميل',
                    _load,
                    key: const Key('debt-reload'),
                  ),
                if (_error != null)
                  Text(
                    _error!,
                    key: const Key('debt-error'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                if (_pending != null) _pendingCard(),
                ...switch (_pending != null ? _Stage.list : _stage) {
                  _Stage.list => _list(theme),
                  _Stage.declare => _declareForm(),
                  _Stage.declareReview => _declareReview(),
                  _Stage.detail => _detailView(),
                  _Stage.settle => _settleForm(),
                  _Stage.settleReview => _settleReview(),
                  _Stage.cancelReview => _actionReview(cancel: true),
                  _Stage.archiveReview => _actionReview(cancel: false),
                  _Stage.success => _successView(),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _list(ThemeData theme) {
    final items = _page?.items ?? const <DebtSummary>[];
    return [
      TextField(
        key: const Key('debt-search'),
        controller: _search,
        decoration: const InputDecoration(
          labelText: 'بحث',
          helperText: 'الاسم أو الهاتف أو السبب أو المرجع',
        ),
        textInputAction: TextInputAction.search,
        onSubmitted: (_) {
          if (!_busy) _load();
        },
      ),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final entry in debtFilterLabels.entries)
            FilterChip(
              key: Key('debt-filter-${entry.key}'),
              label: Text(entry.value),
              selected: _filter == entry.key,
              onSelected: (_) {
                if (_busy) return;
                setState(() => _filter = entry.key);
                _load();
              },
            ),
        ],
      ),
      const SizedBox(height: 12),
      if (!_writesBlocked)
        _button('تسجيل دين', _openDeclare, key: const Key('debt-open-declare')),
      if (_loading) const LinearProgressIndicator(key: Key('debt-loading')),
      if (!_loading && items.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Text('لا توجد ديون في هذا العرض.'),
        ),
      for (final item in items)
        Card(
          child: ListTile(
            key: Key('debt-item-${item.sourceId}'),
            title: Text(item.partyName),
            subtitle: Text(
              '${debtDirectionLabels[item.direction]} · ${debtUnitLabels[item.unit]}'
              '${item.karat == null ? '' : ' · عيار ${item.karat}'}\n'
              'الأصل ${item.unit == DebtUnit.money ? debtMoney(item.original) : debtGold(item.original)}'
              ' · المسدد ${item.unit == DebtUnit.money ? debtMoney(item.settled) : debtGold(item.settled)}'
              '${item.cancelled == BigInt.zero ? '' : ' · الملغى ${item.unit == DebtUnit.money ? debtMoney(item.cancelled) : debtGold(item.cancelled)}'}'
              ' · المتبقي ${item.unit == DebtUnit.money ? debtMoney(item.remaining) : debtGold(item.remaining)}',
            ),
            trailing: Text(
              debtStatusLabels[item.displayStatus] ?? 'حالة غير متاحة',
            ),
            onTap: () => _openDetail(item),
          ),
        ),
      if (_cursor != null)
        _button('عرض المزيد', _more, key: const Key('debt-load-more')),
    ];
  }

  void _openDeclare() {
    if (_writesBlocked) return;
    setState(() {
      _stage = _Stage.declare;
      _error = null;
      _idempotency = null;
    });
  }

  List<Widget> _declareForm() => [
    _back('الديون', () => setState(() => _stage = _Stage.list)),
    Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<DebtDirection>(
            isExpanded: true,
            initialValue: _direction,
            decoration: const InputDecoration(labelText: 'الاتجاه'),
            items: [
              for (final direction in DebtDirection.values)
                DropdownMenuItem(
                  value: direction,
                  child: Text(debtDirectionLabels[direction]!),
                ),
            ],
            onChanged: (value) =>
                setState(() => _direction = value ?? _direction),
          ),
          DropdownButtonFormField<DebtUnit>(
            isExpanded: true,
            initialValue: _unit,
            decoration: const InputDecoration(labelText: 'الوحدة'),
            items: [
              for (final unit in DebtUnit.values)
                DropdownMenuItem(
                  value: unit,
                  child: Text(debtUnitLabels[unit]!),
                ),
            ],
            onChanged: (value) => setState(() => _unit = value ?? _unit),
          ),
          if (_unit == DebtUnit.gold)
            DropdownButtonFormField<int>(
              isExpanded: true,
              initialValue: _karat,
              decoration: const InputDecoration(labelText: 'العيار'),
              items: [
                for (final karat in ScrapKarats.allowed.toList()..sort())
                  DropdownMenuItem(value: karat, child: Text('$karat')),
              ],
              onChanged: (value) => setState(() => _karat = value ?? _karat),
            ),
          TextFormField(
            key: const Key('debt-party'),
            controller: _party,
            decoration: const InputDecoration(labelText: 'الطرف'),
            validator: (value) => debtParty(value ?? '') is DebtAccepted<String>
                ? null
                : 'اكتب اسم الطرف.',
          ),
          TextFormField(
            key: const Key('debt-phone'),
            controller: _phone,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'الهاتف'),
            keyboardType: TextInputType.phone,
            validator: (value) => debtPhone(value ?? '') is DebtAccepted<String>
                ? null
                : 'الهاتف غير صالح.',
          ),
          TextFormField(
            key: const Key('debt-reason'),
            controller: _reason,
            decoration: const InputDecoration(labelText: 'السبب'),
            validator: (value) =>
                debtReason(value ?? '') is DebtAccepted<String>
                ? null
                : 'اكتب السبب.',
          ),
          TextFormField(
            key: const Key('debt-external'),
            controller: _external,
            decoration: const InputDecoration(labelText: 'مرجع خارجي'),
          ),
          TextFormField(
            key: const Key('debt-amount'),
            controller: _amount,
            decoration: InputDecoration(
              labelText: _unit == DebtUnit.money ? 'المبلغ' : 'الوزن بالجرام',
              helperText: _unit == DebtUnit.gold
                  ? 'ثلاثة أرقام عشرية كحد أقصى'
                  : null,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: _unit == DebtUnit.money
                ? [const CashInputFormatter()]
                : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            textDirection: TextDirection.ltr,
            validator: (value) {
              final parsed = _unit == DebtUnit.money
                  ? Piastres.parsePounds(cashInputValue(value ?? ''))
                  : Milligrams.parseGrams((value ?? '').trim());
              return parsed is Accepted ? null : 'أدخل قيمة أكبر من صفر.';
            },
          ),
          const SizedBox(height: 12),
          _button(
            'مراجعة التسجيل',
            _reviewDeclare,
            key: const Key('debt-submit'),
          ),
        ],
      ),
    ),
  ];

  List<Widget> _declareReview() {
    final draft = _declaration;
    if (draft == null) return const [Text('أعد إدخال الدين.')];
    return [
      _back('تعديل البيانات', () => setState(() => _stage = _Stage.declare)),
      const Text(
        'تسجيل دين تاريخي. لا يتحرك نقد أو ذهب أو أمانة أو مخزون قابل للبيع.',
      ),
      Text('الاتجاه: ${debtDirectionLabels[draft.direction]}'),
      Text('الوحدة: ${debtUnitLabels[draft.unit]}'),
      if (draft.karat != null) Text('العيار: ${draft.karat}'),
      Text('الطرف: ${draft.partyName}'),
      Text(
        'الهاتف: ${draft.contactPhone.isEmpty ? 'بدون هاتف' : draft.contactPhone}',
      ),
      Text('السبب: ${draft.reason}'),
      Text(
        key: const Key('debt-review'),
        draft.unit == DebtUnit.money
            ? 'المبلغ: ${debtMoney(draft.amount, exact: true)}'
            : 'الوزن: ${debtGold(draft.amount, exact: true)}',
      ),
      _effectLines(draft.effect),
      _confirmButton('تأكيد التسجيل', () {
        _confirm('debt_declare', draft.toPayload());
      }),
    ];
  }

  List<Widget> _detailView() {
    final detail = _detail;
    if (detail == null) return const [Text('اختر دينًا من القائمة.')];
    final item = detail.summary;
    return [
      _back('الديون', () => setState(() => _stage = _Stage.list)),
      Text(item.partyName, style: Theme.of(context).textTheme.titleLarge),
      Text(
        '${debtDirectionLabels[item.direction]} · ${debtUnitLabels[item.unit]}${item.karat == null ? '' : ' · عيار ${item.karat}'}',
      ),
      Text(
        'الأصل: ${item.unit == DebtUnit.money ? debtMoney(item.original) : debtGold(item.original)}',
      ),
      Text(
        'المسدد: ${item.unit == DebtUnit.money ? debtMoney(item.settled) : debtGold(item.settled)}',
      ),
      if (item.cancelled > BigInt.zero)
        Text(
          'الملغى: ${item.unit == DebtUnit.money ? debtMoney(item.cancelled) : debtGold(item.cancelled)}',
        ),
      Text(
        key: const Key('debt-remaining'),
        'المتبقي: ${item.unit == DebtUnit.money ? debtMoney(item.remaining) : debtGold(item.remaining)}',
      ),
      Text(
        'الحالة: ${debtStatusLabels[item.displayStatus] ?? 'حالة غير متاحة'}',
      ),
      Text('السبب: ${item.reason}'),
      if (item.contactPhone != null && item.contactPhone!.isNotEmpty)
        Text('الهاتف: ${item.contactPhone}'),
      if (item.externalReference != null)
        Text('المرجع: ${item.externalReference}'),
      Text('أُنشئ: ${formatServerCairoTimestamp(item.createdAtShop)}'),
      if (widget.gateway is DebtStatementGateway)
        _button(
          'كشف حساب دين PDF',
          _statementOpening
              ? null
              : () async {
                  if (_statementOpening) return;
                  setState(() => _statementOpening = true);
                  final gateway = widget.gateway as DebtStatementGateway;
                  try {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => DebtStatementScreen(
                          gateway: gateway,
                          platform: widget.statementPlatform,
                          userId: widget.userId,
                          shopId: widget.shopId,
                          sourceKind: item.sourceKind,
                          sourceId: item.sourceId,
                          syncTicks: widget.syncTicks,
                          canRead: () =>
                              mounted && (widget.canRead?.call() ?? true),
                        ),
                      ),
                    );
                  } finally {
                    if (mounted) setState(() => _statementOpening = false);
                  }
                },
          key: const Key('debt-statement'),
        ),
      const SizedBox(height: 8),
      Text('السجل', style: Theme.of(context).textTheme.titleMedium),
      for (final event in detail.history) _historyEntry(event, item.unit),
      if (detail.canSettle && !_writesBlocked)
        _button('سداد', _startSettlement, key: const Key('debt-settle')),
      if (detail.canCancel && !_writesBlocked)
        _button(
          'إلغاء الدين',
          () => setState(() => _stage = _Stage.cancelReview),
          key: const Key('debt-cancel'),
        ),
      if (detail.canArchive && !_writesBlocked)
        _button(
          'أرشفة',
          () => setState(() => _stage = _Stage.archiveReview),
          key: const Key('debt-archive'),
        ),
    ];
  }

  Widget _historyEntry(DebtHistoryEntry event, DebtUnit unit) {
    final payload = event.payload;
    String amount(BigInt value) => unit == DebtUnit.money
        ? debtMoney(value)
        : debtGold(value, exact: true);
    final delta = BigInt.tryParse('${payload['amount']}');
    final cancel = BigInt.tryParse(
      '${payload['cancelled_amount'] ?? payload['cancelled_payable_piastres']}',
    );
    final remaining = BigInt.tryParse('${payload['remaining_amount']}');
    final lines = <String>[
      '${event.actorDisplayName ?? 'المالك'} · ${formatServerCairoTimestamp(event.atShop)}',
      if (delta != null)
        '${const {'declared', 'posted'}.contains(event.eventType)
            ? 'الأصل'
            : const {'cancelled', 'linked_return'}.contains(event.eventType)
            ? 'الإلغاء'
            : 'السداد'}: ${amount(delta)}',
      if (cancel != null && cancel > BigInt.zero) 'الملغى: ${amount(cancel)}',
      if (remaining != null) 'المتبقي بعد العملية: ${amount(remaining)}',
      if (payload['ledger_effect'] == 'none' && event.eventType == 'settled')
        'سداد بلا حركة في دفتر المحل',
      if (BigInt.tryParse('${payload['cash_piastres']}') case final BigInt cash
          when cash != BigInt.zero)
        'النقد: ${debtMoney(cash)}',
      if (BigInt.tryParse('${payload['gold_milligrams']}')
          case final BigInt gold when gold != BigInt.zero)
        'الذهب: ${debtGold(gold, exact: true)}',
      if (payload['reason'] is String) 'السبب: ${payload['reason']}',
    ];
    return ListTile(title: Text(event.label), subtitle: Text(lines.join('\n')));
  }

  void _startSettlement() {
    if (_writesBlocked || _detail == null) return;
    final item = _detail!.summary;
    setState(() {
      _ledgerEffect = DebtLedgerEffect.move;
      _category = [
        ...StockCategory.canonicalOrder.map((c) => c.code),
        'scrap',
      ].firstWhere((c) => debtCategoryAllows(c, item.karat ?? 21));
      _pickedLots.clear();
      _settleAmount.clear();
      _settleReason.clear();
      _count.clear();
      _product.clear();
      _idempotency = null;
      _stage = _Stage.settle;
    });
  }

  List<Widget> _settleForm() {
    final detail = _detail;
    if (detail == null) return const [Text('أعد فتح الدين.')];
    final money = detail.summary.unit == DebtUnit.money;
    final outgoing = detail.summary.direction == DebtDirection.shopOwes;
    return [
      _back('تفاصيل الدين', () => setState(() => _stage = _Stage.detail)),
      if (!detail.noLedgerAllowed)
        const Text(
          'هذا الرصيد مرتبط بقيد شراء أو التزام ذهب. السداد يحرك النقد أو الذهب لأن القيد الأصلي سجّل الأثر. لا يوجد سداد بلا قيد.',
        )
      else ...[
        const Text(
          'يمكن تسجيل السداد بلا حركة نقد أو مخزون لأن التسجيل الأصلي لم يمس الدفتر.',
        ),
        DropdownButtonFormField<DebtLedgerEffect>(
          isExpanded: true,
          initialValue: _ledgerEffect,
          decoration: const InputDecoration(labelText: 'أثر السداد'),
          items: const [
            DropdownMenuItem(
              value: DebtLedgerEffect.move,
              child: Text('يحرك النقد أو الذهب'),
            ),
            DropdownMenuItem(
              value: DebtLedgerEffect.none,
              child: Text('بلا قيد'),
            ),
          ],
          onChanged: (value) =>
              setState(() => _ledgerEffect = value ?? DebtLedgerEffect.move),
        ),
      ],
      Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              key: const Key('debt-settle-amount'),
              controller: _settleAmount,
              textDirection: TextDirection.ltr,
              inputFormatters: money
                  ? [const CashInputFormatter()]
                  : [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(
                labelText: money ? 'مبلغ السداد' : 'وزن السداد بالجرام',
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'أدخل مبلغ السداد.' : null,
            ),
            TextFormField(
              key: const Key('debt-settle-reason'),
              controller: _settleReason,
              decoration: const InputDecoration(labelText: 'سبب السداد'),
              validator: (value) =>
                  debtReason(value ?? '') is DebtAccepted<String>
                  ? null
                  : 'اكتب السبب.',
            ),
            if (money && _ledgerEffect == DebtLedgerEffect.move)
              ..._tenderFields(),
            if (!money && outgoing && _ledgerEffect == DebtLedgerEffect.move)
              ..._lotFields(detail.summary.karat),
            if (!money && !outgoing && _ledgerEffect == DebtLedgerEffect.move)
              ..._receiptFields(detail.summary.karat ?? 21),
            const SizedBox(height: 12),
            _button(
              'مراجعة السداد',
              _reviewSettle,
              key: const Key('debt-submit'),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _tenderFields() => [
    for (var index = 0; index < _tenders.length; index++) ...[
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: _tenders[index].method,
        decoration: const InputDecoration(labelText: 'طريقة الدفع'),
        items: [
          for (final method in CashMethod.canonicalOrder)
            DropdownMenuItem(
              value: method.code,
              child: Text(debtMethodLabels[method.code]!),
            ),
        ],
        onChanged: (value) => setState(
          () => _tenders[index].method = value ?? _tenders[index].method,
        ),
      ),
      TextFormField(
        key: Key('debt-tender-$index'),
        controller: _tenders[index].amount,
        textDirection: TextDirection.ltr,
        inputFormatters: [const CashInputFormatter()],
        decoration: const InputDecoration(labelText: 'المبلغ'),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      ),
    ],
    if (_tenders.length < 4)
      TextButton(
        onPressed: () => setState(() => _tenders.add(_TenderDraft())),
        child: const Text('إضافة طريقة'),
      ),
  ];

  List<Widget> _lotFields(int? karat) {
    final lots = [
      for (final lot in _context?.lots ?? const <DebtLot>[])
        if (lot.karat == karat) lot,
    ];
    if (lots.isEmpty) {
      return const [Text('لا توجد قطع مملوكة بهذا العيار.')];
    }
    return [
      for (final lot in lots)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CheckboxListTile(
              key: Key('debt-lot-pick-${lot.id}'),
              value: _pickedLots.contains(lot.id),
              title: Text(
                '${lot.displayName} · ${debtCategoryLabels[lot.category] ?? lot.category}',
              ),
              subtitle: Text(debtGold(lot.milligrams)),
              onChanged: (checked) {
                setState(() {
                  if (checked ?? false) {
                    _pickedLots.add(lot.id);
                    _lotGrams.putIfAbsent(lot.id, TextEditingController.new);
                    if (!lot.scrap) {
                      _lotCounts.putIfAbsent(lot.id, TextEditingController.new);
                    }
                  } else {
                    _pickedLots.remove(lot.id);
                  }
                });
              },
            ),
            if (_pickedLots.contains(lot.id)) ...[
              TextFormField(
                key: Key('debt-lot-grams-${lot.id}'),
                controller: _lotGrams[lot.id],
                decoration: const InputDecoration(
                  labelText: 'الوزن بالجرام من هذه القطعة',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              if (!lot.scrap)
                TextFormField(
                  key: Key('debt-lot-count-${lot.id}'),
                  controller: _lotCounts[lot.id],
                  decoration: const InputDecoration(labelText: 'العدد'),
                  keyboardType: TextInputType.number,
                ),
            ],
          ],
        ),
    ];
  }

  List<Widget> _receiptFields(int karat) {
    final categories = [
      for (final category in [
        ...StockCategory.canonicalOrder.map((item) => item.code),
        'scrap',
      ])
        if (debtCategoryAllows(category, karat)) category,
    ];
    return [
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: categories.contains(_category)
            ? _category
            : categories.first,
        key: const Key('debt-receipt-category'),
        decoration: const InputDecoration(labelText: 'الفئة'),
        items: [
          for (final category in categories)
            DropdownMenuItem(
              value: category,
              child: Text(debtCategoryLabels[category] ?? category),
            ),
        ],
        onChanged: (value) => setState(() => _category = value ?? _category),
      ),
      TextFormField(
        key: const Key('debt-receipt-product'),
        controller: _product,
        decoration: const InputDecoration(labelText: 'اسم الصنف'),
        validator: (value) =>
            (value ?? '').trim().isEmpty ? 'اكتب اسم الصنف.' : null,
      ),
      if (_category != 'scrap')
        TextFormField(
          key: const Key('debt-receipt-count'),
          controller: _count,
          decoration: const InputDecoration(labelText: 'العدد'),
          keyboardType: TextInputType.number,
        ),
    ];
  }

  List<Widget> _settleReview() {
    final settlement = _settlement;
    if (settlement == null) return const [Text('أعد مراجعة السداد.')];
    final none = settlement.ledgerEffect == DebtLedgerEffect.none;
    return [
      _back('تعديل السداد', () => setState(() => _stage = _Stage.settle)),
      Text(
        'الطرف: ${_detail!.summary.partyName} · ${debtDirectionLabels[settlement.direction]}',
      ),
      if (settlement.karat != null) Text('عيار ${settlement.karat}'),
      Text(
        'المتبقي بعد السداد: ${settlement.unit == DebtUnit.money ? debtMoney(settlement.expectedRemaining - settlement.amount) : debtGold(settlement.expectedRemaining - settlement.amount, exact: true)}',
      ),
      Text(
        none
            ? 'سداد بلا قيد. لا يتحرك النقد أو الذهب أو الأمانة أو المخزون القابل للبيع. يُسجل الاختيار والسبب.'
            : 'راجع الأثر قبل التأكيد. لن يُحفظ السداد قبل رد الخادم.',
      ),
      Text('السبب: ${settlement.reason}'),
      Text(
        key: const Key('debt-review'),
        settlement.unit == DebtUnit.money
            ? 'السداد: ${debtMoney(settlement.amount, exact: true)}'
            : 'السداد: ${debtGold(settlement.amount, exact: true)}',
      ),
      _effectLines(settlement.effect),
      if (settlement.tenders != null)
        for (final tender in settlement.tenders!)
          Text(
            '${debtMethodLabels[tender.method]}: ${debtMoney(tender.piastres, exact: true)}',
          ),
      if (settlement.receipt != null)
        Text(
          'استلام ذهب مملوك للمحل: ${debtCategoryLabels[settlement.receipt!.category]} · ${settlement.receipt!.productName} · ${debtGold(settlement.receipt!.milligrams, exact: true)}${settlement.receipt!.count == null ? '' : ' · عدد ${settlement.receipt!.count}'}',
        ),
      for (final line in settlement.deliveries ?? const <DebtDelivery>[])
        Text(
          'تسليم من المخزون المملوك: ${_context!.lots.firstWhere((lot) => lot.id == line.lotId).displayName} · ${debtGold(line.milligrams, exact: true)}${line.count == null ? '' : ' · عدد ${line.count}'}',
        ),
      _confirmButton('تأكيد السداد', () {
        _confirm('debt_settle', settlement.toPayload());
      }),
    ];
  }

  List<Widget> _actionReview({required bool cancel}) {
    final detail = _detail;
    if (detail == null) return const [Text('أعد فتح الدين.')];
    if (_stage == _Stage.detail || _idempotency == null) {
      return [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                cancel
                    ? 'إلغاء دين قائم لم يُسدد منه شيء. لا يتحرك نقد أو ذهب أو أمانة.'
                    : 'الأرشفة تحفظ السجل والمتبقي ولا تسقط الدين.',
              ),
              TextFormField(
                key: const Key('debt-action-reason'),
                controller: _actionReason,
                decoration: const InputDecoration(labelText: 'السبب'),
                validator: (value) =>
                    debtReason(value ?? '') is DebtAccepted<String>
                    ? null
                    : 'اكتب السبب.',
              ),
              _button(
                'مراجعة',
                () => _reviewAction(
                  cancel ? _Stage.cancelReview : _Stage.archiveReview,
                ),
                key: const Key('debt-submit'),
              ),
            ],
          ),
        ),
      ];
    }
    return [
      Text(
        cancel
            ? 'تأكيد الإلغاء. الأثر على النقد والذهب والأمانة والمخزون صفر.'
            : 'تأكيد الأرشفة. يبقى الأصل والمسدد والمتبقي في السجل.',
      ),
      Text('السبب: ${_actionReason.text}'),
      _effectLines(DebtEffect.zero),
      _confirmButton(cancel ? 'تأكيد الإلغاء' : 'تأكيد الأرشفة', () {
        final reason = (_actionReason.text);
        final payload = cancel
            ? debtCancelPayload(
                sourceId: detail.summary.sourceId,
                expectedRemaining: detail.summary.remaining,
                expectedVersion: detail.summary.recordVersion!,
                reason: reason,
              )
            : debtArchivePayload(
                sourceKind: detail.summary.sourceKind,
                sourceId: detail.summary.sourceId,
                expectedRemaining: detail.summary.remaining,
                expectedVersion: detail.summary.recordVersion,
                reason: reason,
              );
        _confirm(cancel ? 'debt_cancel' : 'debt_archive', payload);
      }),
    ];
  }

  List<Widget> _successView() {
    final saved = _saved;
    return [
      Text(
        'تم حفظ الطلب بعد تأكيد الخادم.',
        key: const Key('debt-success'),
        style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
      ),
      if (saved != null) ...[
        Text(saved.replayed ? 'أُعيدت نتيجة الطلب السابق.' : 'طلب جديد.'),
        Text(
          'الحالة: ${debtStatusLabels[saved.displayStatus] ?? 'حالة غير متاحة'}',
        ),
        _effectLines(saved.effect),
      ],
      _button('العودة إلى الديون', () {
        setState(() => _stage = _Stage.list);
        _load();
      }, key: const Key('debt-done')),
    ];
  }

  Widget _pendingCard() => Card(
    key: const Key('debt-pending'),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _pendingUnknown
                ? 'طلب ديون بانتظار تأكيد الحفظ'
                : 'طلب ديون محفوظ ولم يُؤكد بعد',
          ),
          _button('متابعة طلب الديون', _retry, key: const Key('debt-retry')),
        ],
      ),
    ),
  );

  Widget _effectLines(DebtEffect effect) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('النقد: ${debtMoney(effect.cashPiastres, exact: true)}'),
      Text('الذهب: ${debtGold(effect.goldMilligrams, exact: true)}'),
      Text('العدد: ${debtSignedCount(effect.goldCount)}'),
      Text('الأمانة: ${debtGold(effect.custodyMilligrams, exact: true)}'),
      Text(
        'المخزون القابل للبيع: ${debtGold(effect.saleableStockMilligrams, exact: true)}',
      ),
    ],
  );

  Widget _confirmButton(String label, VoidCallback onPressed) => _button(
    _reviewStale ? 'تغيرت البيانات. أعد المراجعة' : label,
    _reviewStale || _busy || _writesBlocked ? null : onPressed,
    key: const Key('debt-confirm'),
  );

  Widget _button(String label, VoidCallback? onPressed, {Key? key}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Semantics(
      button: true,
      label: label,
      child: FilledButton(
        key: key,
        onPressed: _busy || (_pending != null && key != const Key('debt-retry'))
            ? null
            : onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppTokens.minControlSize),
        ),
        child: Text(label),
      ),
    ),
  );

  Widget _back(String label, VoidCallback onPressed) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: TextButton(
      key: const Key('debt-back'),
      onPressed: _busy || _pending != null ? null : onPressed,
      child: Text(label),
    ),
  );
}
