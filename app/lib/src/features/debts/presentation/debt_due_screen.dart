import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_tokens.dart';
import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/application/pending_financial_command.dart';
import '../application/debt_due_contract.dart';
import '../application/debt_due_flow.dart';
import '../application/debt_due_gateway.dart';
import '../application/debt_gateway.dart';
import '../domain/debt_calendar_date.dart';
import '../domain/debt_rules.dart';
import 'debt_copy.dart';
import 'debt_due_calendar.dart';

const dueStates = {
  'all': 'الكل',
  'overdue': 'متأخرة',
  'today': 'مستحقة اليوم',
  'upcoming': 'قادمة',
  'inactive': 'غير نشط',
};
String dueDateText(DebtCalendarDate? d) =>
    d == null ? 'بلا موعد' : '\u2066${d.wire}\u2069';
String dueAmount(DebtDueRow r) => r.summary.unit == DebtUnit.money
    ? '${debtMoney(r.summary.remaining)} نقد'
    : '\u2066${r.summary.remaining ~/ BigInt.from(1000)}.${(r.summary.remaining % BigInt.from(1000)).toString().padLeft(3, '0')}\u2069 جرام';
String dueSource(DebtSourceKind kind) => switch (kind) {
  DebtSourceKind.standalone => 'دين مستقل',
  DebtSourceKind.purchaseCashPayable => 'رصيد شراء',
  DebtSourceKind.goldObligation => 'التزام ذهب',
};
String dueFailure(String code) => switch (code) {
  'stale_due' => 'تغير الرصيد أو الموعد أو تاريخ المحل. أعد المراجعة.',
  'stale_due_cursor' =>
    'تغيرت قائمة المواعيد أو تاريخ المحل. ابدأ القائمة من جديد.',
  'due_not_active' => 'لا يمكن تغيير موعد سجل مغلق أو مؤرشف.',
  'invalid_date' => 'أدخل تاريخًا صحيحًا.',
  'discarded' => 'تغيرت الجلسة. أعد تحميل البيانات.',
  'storage' => 'تعذر تحديث الطلب المحفوظ على الجهاز. يبقى الطلب للمراجعة.',
  'read' => 'تعذر الاتصال. البيانات السابقة غير محدثة. أعد المحاولة.',
  _ => debtFailureText(code),
};
bool dueAccessLost(String? code) => const {
  'forbidden',
  'session_expired',
  'unauthenticated',
  'shop_unavailable',
}.contains(code);

class DebtDueScreen extends StatefulWidget {
  const DebtDueScreen({
    super.key,
    required this.gateway,
    required this.store,
    required this.userId,
    required this.shopId,
    required this.canRead,
    required this.canWrite,
    this.sourceKind,
    this.sourceId,
    this.syncTicks,
    this.onMutated,
    this.newKey,
  });
  final DebtDueGateway gateway;
  final FinancialCommandLocker store;
  final String userId, shopId;
  final bool Function() canRead, canWrite;
  final DebtSourceKind? sourceKind;
  final String? sourceId;
  final Listenable? syncTicks;
  final VoidCallback? onMutated;
  final String Function()? newKey;
  @override
  State<DebtDueScreen> createState() => _DebtDueScreenState();
}

class _DebtDueScreenState extends State<DebtDueScreen>
    with WidgetsBindingObserver {
  final _search = TextEditingController();
  final _date = TextEditingController();
  final _form = GlobalKey<FormState>();
  DebtDueDetail? _detail;
  DebtReminderPage? _page;
  List<DebtDueRow> _rows = [];
  PendingFinancialCommand? _pending, _foreign;
  Map<String, Object?>? _review;
  String? _key, _error, _success;
  String _filter = 'all';
  bool _loading = true,
      _busy = false,
      _fresh = false,
      _staleReview = false,
      _staleList = false,
      _draftStarted = false,
      _access = true;
  int _epoch = 0;
  Timer? _poll;
  Object? _session;
  DebtSourceKind? _kind;
  String? _source;
  String get _identity => '${widget.userId}:${widget.shopId}';
  bool _current(String identity, Object? session) =>
      mounted &&
      identity == _identity &&
      session != null &&
      widget.gateway.dueSession(widget.userId) == session &&
      widget.canRead();
  bool get _writes =>
      _access &&
      _fresh &&
      !_loading &&
      !_busy &&
      _pending == null &&
      _foreign == null &&
      widget.canWrite() &&
      _detail?.canSchedule == true;
  @override
  void initState() {
    super.initState();
    _kind = widget.sourceKind;
    _source = widget.sourceId;
    WidgetsBinding.instance.addObserver(this);
    widget.syncTicks?.addListener(_invalidate);
    _poll = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!_busy) _load(background: true);
    });
    _load();
  }

  @override
  void didUpdateWidget(DebtDueScreen old) {
    super.didUpdateWidget(old);
    if (old.syncTicks != widget.syncTicks) {
      old.syncTicks?.removeListener(_invalidate);
      widget.syncTicks?.addListener(_invalidate);
    }
    if (old.userId != widget.userId ||
        old.shopId != widget.shopId ||
        old.gateway != widget.gateway ||
        old.sourceKind != widget.sourceKind ||
        old.sourceId != widget.sourceId) {
      _epoch++;
      _detail = null;
      _page = null;
      _rows = [];
      _pending = null;
      _foreign = null;
      _review = null;
      _key = null;
      _success = null;
      _draftStarted = false;
      _date.clear();
      _search.clear();
      _kind = widget.sourceKind;
      _source = widget.sourceId;
      _busy = false;
      _load();
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.syncTicks?.removeListener(_invalidate);
    _search.dispose();
    _date.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _invalidate();
  }

  void _loseAccess() {
    if (!mounted) return;
    setState(() {
      _epoch++;
      _access = false;
      _fresh = false;
      _loading = false;
      _busy = false;
      _detail = null;
      _page = null;
      _rows = [];
      _review = null;
      _success = null;
      _date.clear();
      _draftStarted = false;
      _error = dueFailure('session_expired');
    });
  }

  void _invalidate() {
    if (!mounted) return;
    if (!widget.canRead() || widget.gateway.dueSession(widget.userId) == null) {
      _loseAccess();
      return;
    }
    setState(() {
      _fresh = false;
      if (_review != null) _staleReview = true;
    });
    if (!_busy) _load(background: true);
  }

  Future<void> _load({bool background = false, bool restart = false}) async {
    final identity = _identity,
        session = widget.gateway.dueSession(widget.userId);
    final epoch = ++_epoch;
    final user = widget.userId, shop = widget.shopId;
    if (!widget.canRead() || session == null) {
      _loseAccess();
      return;
    }
    setState(() {
      _loading = true;
      _fresh = false;
      if (!background) _error = null;
    });
    try {
      final pending = await widget.store.read(user, shop);
      if (!_current(identity, session)) {
        if (mounted && identity == _identity) _loseAccess();
        return;
      }
      if (epoch != _epoch) return;
      final own =
          pending != null &&
          matchesDebtDueEnvelope(pending.key, pending.kind, pending.body);
      if (own) {
        final p = pending.body['p_payload'] as Map;
        if (_source != p['source_id'] || _kind?.wire != p['source_kind']) {
          _draftStarted = false;
          _date.clear();
          _review = null;
          _key = null;
          _success = null;
        }
        _kind = DebtSourceKind.byWire(p['source_kind'] as String);
        _source = p['source_id'] as String;
      }
      final kind = _kind, source = _source;
      setState(() {
        _pending = own ? pending : null;
        _foreign = pending != null && !own ? pending : null;
        if (own && _detail?.row.summary.sourceId != source) _detail = null;
      });
      final detail = source == null
          ? null
          : await widget.gateway.readDue(
              userId: user,
              shopId: shop,
              sourceKind: kind!,
              sourceId: source,
            );
      final page = source != null
          ? null
          : await widget.gateway.readReminders(
              userId: user,
              shopId: shop,
              query: _search.text.trim(),
              filter: _filter,
              cursor: null,
            );
      if (!_current(identity, session)) {
        if (mounted && identity == _identity) _loseAccess();
        return;
      }
      if (epoch != _epoch) return;
      if (detail != null &&
              (detail.row.shopId != widget.shopId ||
                  detail.row.summary.sourceKind != _kind ||
                  detail.row.summary.sourceId != _source) ||
          page != null && page.shopId != widget.shopId) {
        throw const DebtReadException('discarded');
      }
      setState(() {
        final previousSession = _session;
        _session = session;
        _access = true;
        _pending = own ? pending : null;
        _foreign = pending != null && !own ? pending : null;
        if (detail != null) {
          if (_review != null &&
              (detail.row.freshness != _review!['expected_freshness'] ||
                  previousSession != session)) {
            _staleReview = true;
          }
          _detail = detail;
          if (!_draftStarted) {
            _date.text = detail.row.date?.wire ?? '';
            _draftStarted = true;
          }
        }
        if (page != null) {
          if (!restart &&
              _page != null &&
              _rows.isNotEmpty &&
              _page!.freshness != page.freshness) {
            _staleList = true;
          } else {
            if (background &&
                !restart &&
                _page != null &&
                _rows.length > page.items.length) {
              _page = DebtReminderPage(
                items: _page!.items,
                shopId: page.shopId,
                timeZone: page.timeZone,
                localDate: page.localDate,
                snapshotAt: page.snapshotAt,
                snapshotAtShop: page.snapshotAtShop,
                freshness: page.freshness,
                total: page.total,
                offset: _page!.offset,
                nextCursor: _page!.nextCursor,
              );
            } else {
              _page = page;
              if (restart || _rows.isEmpty || !background) _rows = page.items;
            }
            _staleList = false;
          }
        }
        _loading = false;
        _fresh = true;
        if (background && !_staleList) _error = null;
      });
    } catch (e) {
      if (!_current(identity, session)) {
        if (mounted && identity == _identity) _loseAccess();
        return;
      }
      if (epoch != _epoch) return;
      final code = e is DebtReadException ? e.code ?? 'read' : 'read';
      if (dueAccessLost(code)) {
        _loseAccess();
        return;
      }
      setState(() {
        _loading = false;
        _fresh = false;
        _error = dueFailure(code);
      });
    }
  }

  Future<void> _more() async {
    if (_loading ||
        _busy ||
        !_fresh ||
        _staleList ||
        _page?.nextCursor == null) {
      return;
    }
    final identity = _identity,
        session = widget.gateway.dueSession(widget.userId);
    final epoch = ++_epoch;
    setState(() => _busy = true);
    try {
      final next = await widget.gateway.readReminders(
        userId: widget.userId,
        shopId: widget.shopId,
        query: _search.text.trim(),
        filter: _filter,
        cursor: _page!.nextCursor,
      );
      if (!_current(identity, session)) {
        if (mounted && identity == _identity) _loseAccess();
        return;
      }
      if (epoch != _epoch) return;
      if (next.shopId != widget.shopId ||
          next.freshness != _page!.freshness ||
          next.offset != _rows.length ||
          next.items.any(
            (r) => _rows.any((old) => old.summary.debtKey == r.summary.debtKey),
          )) {
        throw const DebtReadException('stale_due_cursor');
      }
      setState(() {
        _rows = [..._rows, ...next.items];
        _page = next;
        _busy = false;
      });
    } catch (e) {
      if (!_current(identity, session)) {
        if (mounted && identity == _identity) _loseAccess();
        return;
      }
      if (epoch != _epoch) return;
      final code = e is DebtReadException ? e.code ?? 'read' : 'read';
      if (dueAccessLost(code)) {
        _loseAccess();
        return;
      }
      setState(() {
        _busy = false;
        _staleList = true;
        _fresh = false;
        _error = dueFailure(code);
      });
    }
  }

  Future<void> _pick() async {
    if (!_writes) return;
    final identity = _identity,
        session = widget.gateway.dueSession(widget.userId);
    final date = DebtCalendarDate.parse(_date.text) ?? _detail!.row.localDate;
    final selected = await showDialog<DebtCalendarDate>(
      context: context,
      builder: (_) => DebtDueCalendarDialog(initial: date),
    );
    if (!_current(identity, session) || !_access) return;
    if (selected != null) {
      setState(() => _date.text = selected.wire);
    }
  }

  Future<void> _prepare({bool clear = false}) async {
    if (!_writes || !clear && _form.currentState?.validate() != true) return;
    final intended = clear ? null : DebtCalendarDate.parse(_date.text);
    final identity = _identity,
        session = widget.gateway.dueSession(widget.userId);
    final epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
      _staleReview = false;
    });
    try {
      final fresh = await widget.gateway.readDue(
        userId: widget.userId,
        shopId: widget.shopId,
        sourceKind: _kind!,
        sourceId: _source!,
      );
      if (!_current(identity, session)) {
        if (mounted && identity == _identity) _loseAccess();
        return;
      }
      if (epoch != _epoch) return;
      if (fresh.row.shopId != widget.shopId ||
          fresh.row.summary.sourceId != _source ||
          fresh.row.summary.sourceKind != _kind) {
        throw const DebtReadException('discarded');
      }
      if (!fresh.canSchedule || !widget.canWrite()) {
        throw const DebtReadException('due_not_active');
      }
      setState(() {
        _detail = fresh;
        _session = session;
        _review = fresh.payload(intended);
        _key = widget.newKey?.call() ?? newIdempotencyKey();
        _busy = false;
        _fresh = true;
      });
    } catch (e) {
      if (!_current(identity, session)) {
        if (mounted && identity == _identity) _loseAccess();
        return;
      }
      if (epoch != _epoch) return;
      final code = e is DebtReadException ? e.code ?? 'read' : 'read';
      if (dueAccessLost(code)) {
        _loseAccess();
        return;
      }
      setState(() {
        _busy = false;
        _fresh = false;
        _error = dueFailure(code);
      });
    }
  }

  Future<void> _confirm({bool retry = false}) async {
    if (_busy || !_access) return;
    if (!retry &&
        (!_writes ||
            _review == null ||
            _staleReview ||
            _session != widget.gateway.dueSession(widget.userId))) {
      return;
    }
    final identity = _identity,
        session = widget.gateway.dueSession(widget.userId);
    setState(() => _busy = true);
    final flow = DebtDueFlow(widget.gateway, widget.store);
    final outcome = retry
        ? await flow.reconcile(
            widget.userId,
            widget.shopId,
            _pending!,
            retry: true,
            canWrite: widget.canWrite(),
          )
        : await flow.submit(
            widget.userId,
            widget.shopId,
            _key!,
            _review!,
            canWrite: widget.canWrite(),
          );
    if (!_current(identity, session)) {
      if (mounted && identity == _identity) _loseAccess();
      return;
    }
    if (dueAccessLost(outcome.error)) {
      _loseAccess();
      return;
    }
    setState(() {
      _busy = false;
      _pending = outcome.pending;
      _review = null;
      _key = null;
      _staleReview = false;
      _error = outcome.error == null ? null : dueFailure(outcome.error!);
      if (outcome.receipt != null) {
        _success =
            'تم حفظ الموعد بعد تأكيد الخادم.${outcome.receipt!.replayed ? ' أُعيدت نتيجة الطلب السابق.' : ''}';
      }
      _fresh = false;
    });
    if (outcome.receipt != null) {
      widget.onMutated?.call();
      _draftStarted = false;
    }
    await _load(background: true);
    if (mounted && _access && outcome.error != null) {
      setState(() => _error = dueFailure(outcome.error!));
    }
  }

  Widget _button(String label, VoidCallback? tap, String key) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
    child: OutlinedButton(
      key: Key(key),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, AppTokens.minControlSize),
      ),
      onPressed: _busy ? null : tap,
      child: Text(label),
    ),
  );
  List<Widget> _identityLines(DebtDueRow r) => [
    Text(r.summary.partyName, style: Theme.of(context).textTheme.titleLarge),
    Text(
      '${dueSource(r.summary.sourceKind)} · ${debtDirectionLabels[r.summary.direction]} · ${debtUnitLabels[r.summary.unit]}${r.summary.karat == null ? '' : ' · عيار ${r.summary.karat}'}',
    ),
    Text('المرجع: \u2066${r.summary.sourceId}\u2069'),
    Text('المتبقي: ${dueAmount(r)}'),
    Text('الحالة: ${debtStatusLabels[r.summary.displayStatus]}'),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_source == null ? 'مواعيد الديون' : 'موعد الاستحقاق'),
    ),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTokens.contentMaxWidth,
          ),
          child: ListView(
            padding: const EdgeInsets.all(AppTokens.spaceMd),
            children: [
              if (!widget.canWrite())
                const Text(
                  'الحساب للقراءة فقط. يمكن قراءة المواعيد ومراجعة الطلب المؤكد.',
                ),
              if (_loading || _busy)
                const LinearProgressIndicator(key: Key('due-preparing')),
              if (_error != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    key: const Key('due-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (_success != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _success!,
                    key: const Key('due-success'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                ),
              if (!_fresh && !_loading && _access)
                const Text(
                  'البيانات غير محدثة. لا يمكن تأكيد تغيير قبل إعادة التحميل.',
                ),
              if (_foreign != null)
                const Text(
                  'يوجد طلب آخر محفوظ. عد إلى الدفتر لمتابعته.',
                  key: Key('due-foreign'),
                ),
              if (_pending != null) ...[
                const Text(
                  'طلب موعد بانتظار تأكيد الخادم. يحتفظ بالمفتاح والموعد الأصليين.',
                  key: Key('due-pending'),
                ),
                _button(
                  'متابعة الطلب الأصلي',
                  () => _confirm(retry: true),
                  'due-retry',
                ),
              ],
              if (_access && _source == null) ..._list(),
              if (_access && _detail != null) ..._selected(),
              if (!_loading && (_error != null || !_fresh) && _access)
                _button('إعادة التحميل', () => _load(), 'due-reload'),
            ],
          ),
        ),
      ),
    ),
  );
  List<Widget> _list() => [
    TextField(
      key: const Key('due-search'),
      controller: _search,
      decoration: const InputDecoration(
        labelText: 'بحث',
        helperText: 'الاسم أو الهاتف أو السبب أو المرجع',
      ),
      textInputAction: TextInputAction.search,
      onSubmitted: (_) {
        if (!_busy) {
          _rows = [];
          _page = null;
          _load(restart: true);
        }
      },
    ),
    const SizedBox(height: AppTokens.spaceMd),
    Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: [
        for (final f in dueStates.entries.where((e) => e.key != 'inactive'))
          FilterChip(
            key: Key('due-filter-${f.key}'),
            label: Text(f.value),
            selected: _filter == f.key,
            onSelected: _busy
                ? null
                : (_) {
                    setState(() {
                      _filter = f.key;
                      _rows = [];
                      _page = null;
                    });
                    _load(restart: true);
                  },
            materialTapTargetSize: MaterialTapTargetSize.padded,
          ),
      ],
    ),
    if (_page != null)
      Text(
        'تاريخ المحل: ${dueDateText(_page!.localDate)}\nوقت القراءة بتوقيت المحل: \u2066${_page!.snapshotAtShop.replaceFirst('T', ' ')}\u2069',
      ),
    if (_staleList) ...[
      const Text(
        'تغيرت القائمة. النتائج السابقة غير محدثة؛ ابدأ العرض من جديد.',
        key: Key('due-list-stale'),
      ),
      _button('بدء القائمة من جديد', () => _load(restart: true), 'due-restart'),
    ],
    if (_fresh && !_staleList && !_loading && _rows.isEmpty)
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('لا توجد مواعيد في هذا العرض.', key: Key('due-empty')),
      ),
    for (final r in _rows)
      Card(
        child: ListTile(
          key: Key('due-row-${r.summary.debtKey}'),
          title: Text(r.summary.partyName),
          subtitle: Text(
            '${dueStates[r.state]} · ${dueDateText(r.date)}\n${dueSource(r.summary.sourceKind)} · ${debtDirectionLabels[r.summary.direction]}${r.summary.karat == null ? '' : ' · عيار ${r.summary.karat}'}\nالمتبقي: ${dueAmount(r)}',
          ),
          onTap: _fresh && !_staleList && !_busy
              ? () => Navigator.of(context).pop(r.summary)
              : null,
        ),
      ),
    if (_page != null && !_staleList)
      Text('المعروض: ${_rows.length} من ${_page!.total}'),
    if (_page?.nextCursor != null)
      _button('عرض المزيد', _fresh && !_staleList ? _more : null, 'due-more'),
  ];
  List<Widget> _selected() {
    final d = _detail!, r = d.row;
    return [
      ..._identityLines(r),
      Text(
        'موعد الاستحقاق: ${dueDateText(r.date)}${r.state == null ? '' : ' · ${dueStates[r.state]}'}',
      ),
      Text('تاريخ المحل: ${dueDateText(r.localDate)}'),
      const SizedBox(height: AppTokens.spaceMd),
      if (_review != null) ...[
        const SizedBox(height: AppTokens.spaceMd),
        const Text('مراجعة موعد الاستحقاق', key: Key('due-review')),
        Text('الموعد السابق: ${dueDateText(r.date)}'),
        Text(
          _review!['due_date'] == null
              ? 'إزالة الموعد'
              : 'الموعد الجديد: ${dueDateText(DebtCalendarDate.parse(_review!['due_date'] as String))}',
        ),
        const Text(
          'الأثر على النقد والذهب والمخزون والأمانة والفواتير: صفر. يتغير الموعد فقط.',
        ),
        if (_staleReview)
          const Text(
            'تغيرت البيانات. أعد فتح المراجعة قبل التأكيد.',
            key: Key('due-review-stale'),
          ),
        _button(
          'تأكيد الموعد',
          _writes && !_staleReview ? () => _confirm() : null,
          'due-confirm',
        ),
        _button(_staleReview ? 'إعادة المراجعة' : 'تعديل الموعد', () {
          setState(() {
            _review = null;
            _key = null;
            _staleReview = false;
          });
          _load();
        }, 'due-edit'),
      ] else if (d.canSchedule &&
          widget.canWrite() &&
          _pending == null &&
          _foreign == null) ...[
        Form(
          key: _form,
          child: TextFormField(
            key: const Key('due-date-field'),
            controller: _date,
            textDirection: TextDirection.ltr,
            enabled: _writes,
            decoration: const InputDecoration(
              labelText: 'تاريخ الاستحقاق',
              hintText: '2026-10-14',
              helperText: 'سنة-شهر-يوم. التاريخ الماضي مسموح.',
              errorMaxLines: 3,
            ),
            validator: (v) => DebtCalendarDate.parse(v ?? '') == null
                ? 'أدخل تاريخًا صحيحًا بصيغة سنة-شهر-يوم.'
                : null,
          ),
        ),
        _button('اختيار من التقويم', _writes ? _pick : null, 'due-picker'),
        _button(
          r.date == null ? 'مراجعة إضافة الموعد' : 'مراجعة تغيير الموعد',
          _writes ? () => _prepare() : null,
          'due-prepare',
        ),
        if (r.date != null)
          _button(
            'مراجعة إزالة الموعد',
            _writes ? () => _prepare(clear: true) : null,
            'due-clear',
          ),
      ] else if (r.summary.displayStatus != 'open' ||
          r.summary.remaining <= BigInt.zero)
        const Text(
          'الموعد محفوظ في السجل. السجلات المغلقة والمؤرشفة لا تظهر في المواعيد النشطة ولا تقبل تغيير الموعد.',
        ),
      if (d.history.isNotEmpty)
        ExpansionTile(
          title: const Text('سجل تغيير الموعد'),
          children: [
            for (final e in d.history)
              ListTile(
                title: Text(
                  '${dueDateText(e.oldDate)} ← ${dueDateText(e.newDate)}',
                ),
                subtitle: Text(
                  '${e.actorName} · \u2066${e.atShop.replaceFirst('T', ' ')}\u2069',
                ),
              ),
          ],
        ),
    ];
  }
}

/// Compact live metadata row in the existing selected-debt detail.
class DebtDueDateRow extends StatefulWidget {
  const DebtDueDateRow({
    super.key,
    required this.gateway,
    required this.userId,
    required this.shopId,
    required this.summary,
    required this.canRead,
    required this.open,
    this.syncTicks,
  });
  final DebtDueGateway gateway;
  final String userId, shopId;
  final DebtSummary summary;
  final bool Function() canRead;
  final VoidCallback open;
  final Listenable? syncTicks;
  @override
  State<DebtDueDateRow> createState() => _DebtDueDateRowState();
}

class _DebtDueDateRowState extends State<DebtDueDateRow>
    with WidgetsBindingObserver {
  DebtDueDetail? _data;
  bool _loading = true;
  String? _error;
  int _epoch = 0;
  Timer? _poll;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.syncTicks?.addListener(_read);
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => _read());
    _read();
  }

  @override
  void didUpdateWidget(DebtDueDateRow old) {
    super.didUpdateWidget(old);
    if (old.syncTicks != widget.syncTicks) {
      old.syncTicks?.removeListener(_read);
      widget.syncTicks?.addListener(_read);
    }
    if (old.summary != widget.summary ||
        old.userId != widget.userId ||
        old.shopId != widget.shopId ||
        old.gateway != widget.gateway) {
      _read();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _read();
  }

  @override
  void dispose() {
    _poll?.cancel();
    widget.syncTicks?.removeListener(_read);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _read() async {
    final epoch = ++_epoch;
    final user = widget.userId, shop = widget.shopId, source = widget.summary;
    final session = widget.gateway.dueSession(user);
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _data = null;
    });
    try {
      if (!widget.canRead() || session == null) {
        throw const DebtReadException('session_expired');
      }
      final d = await widget.gateway.readDue(
        userId: user,
        shopId: shop,
        sourceKind: source.sourceKind,
        sourceId: source.sourceId,
      );
      if (!mounted || epoch != _epoch) return;
      if (!widget.canRead() ||
          session != widget.gateway.dueSession(user) ||
          user != widget.userId ||
          shop != widget.shopId) {
        throw const DebtReadException('discarded');
      }
      if (d.row.shopId != shop ||
          d.row.summary.sourceId != source.sourceId ||
          d.row.summary.sourceKind != source.sourceKind) {
        throw const DebtReadException('discarded');
      }
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _data = null;
        _loading = false;
        _error = dueFailure(e is DebtReadException ? e.code ?? 'read' : 'read');
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_loading) const LinearProgressIndicator(),
      Text(
        _data == null
            ? _error ?? 'جارٍ قراءة موعد الاستحقاق…'
            : 'موعد الاستحقاق: ${dueDateText(_data!.row.date)}${_data!.row.state == null ? '' : ' · ${dueStates[_data!.row.state]}'}',
        key: const Key('debt-due-date'),
      ),
      OutlinedButton(
        key: const Key('debt-due-open'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppTokens.minControlSize),
        ),
        onPressed: widget.canRead() ? widget.open : null,
        child: Text(
          _data?.canSchedule == true
              ? 'إضافة أو تغيير الموعد'
              : 'عرض موعد الاستحقاق',
        ),
      ),
    ],
  );
}
