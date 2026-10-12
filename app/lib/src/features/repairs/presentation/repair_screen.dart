import '../../../theme/cash_input.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../../daily_ledger/presentation/opening_copy.dart';
import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/application/pending_financial_command.dart';
import '../../daily_ledger/domain/opening_issue.dart';
import '../../daily_ledger/domain/quantities.dart';
import '../application/repair_command_flow.dart';
import '../application/repair_contract.dart';
import '../application/repair_gateway.dart';
import '../domain/repair_rules.dart';
import 'repair_copy.dart';

/// Arabic repair custody workspace. No reference mockup; layout is documented
/// in docs/design-system.md.
class RepairScreen extends StatefulWidget {
  const RepairScreen({
    super.key,
    required this.gateway,
    required this.store,
    required this.userId,
    required this.shopId,
    required this.readOnly,
    this.refreshGeneration = 0,
    this.syncTicks,
    this.onCollected,
    this.newKey,
    this.canWrite,
  });

  final RepairGateway gateway;
  final FinancialCommandLocker store;
  final String userId;
  final String shopId;
  final bool readOnly;
  final int refreshGeneration;
  final Listenable? syncTicks;
  final VoidCallback? onCollected;
  final String Function()? newKey;
  final bool Function()? canWrite;

  @override
  State<RepairScreen> createState() => _RepairScreenState();
}

enum _Stage {
  list,
  intake,
  intakeReview,
  detail,
  handover,
  handoverReview,
  cancelReview,
  archiveReview,
  success,
}

class _TenderDraft {
  String? method;
  final amount = TextEditingController();
  void dispose() => amount.dispose();
}

class _RepairScreenState extends State<RepairScreen> {
  final _flowKey = GlobalKey<FormState>();
  final _query = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _item = TextEditingController();
  final _grams = TextEditingController();
  final _issue = TextEditingController();
  final _notes = TextEditingController();
  final _estimate = TextEditingController();
  final _finalFee = TextEditingController();
  final _collected = TextEditingController();
  final _reason = TextEditingController();
  final _tenders = <_TenderDraft>[_TenderDraft()];

  _Stage _stage = _Stage.list;
  String _filter = 'open';
  bool _loading = true;
  bool _busy = false;
  bool _showErrors = false;
  bool _reviewStale = false;
  String? _error;
  String? _notice;
  RepairPage? _page;
  RepairDetail? _detail;
  RepairContext? _context;
  PendingFinancialCommand? _pending;
  bool _pendingUnknown = false;
  bool _otherPending = false;
  bool _pendingLoadFailed = false;
  bool _backendReady = false;
  int? _karat;
  RepairCollectionMode _mode = RepairCollectionMode.all;
  RepairIntakeCommand? _intake;
  RepairHandoverCommand? _handover;
  String? _frozenKey;
  String? _frozenKind;
  String? _success;
  int _readGeneration = 0;
  bool _refreshQueued = false;
  String get _identity => "${widget.userId}:${widget.shopId}";
  bool get _readOnly =>
      widget.canWrite == null ? widget.readOnly : !widget.canWrite!();
  bool get _writesBlocked =>
      _busy ||
      _pending != null ||
      _otherPending ||
      _pendingLoadFailed ||
      !_backendReady ||
      _readOnly;

  RepairCommandFlow get _flow =>
      RepairCommandFlow(gateway: widget.gateway, store: widget.store);

  @override
  void initState() {
    super.initState();
    widget.syncTicks?.addListener(_onSync);
    _boot();
  }

  @override
  void didUpdateWidget(RepairScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncTicks != widget.syncTicks) {
      oldWidget.syncTicks?.removeListener(_onSync);
      widget.syncTicks?.addListener(_onSync);
    }
    if (oldWidget.userId != widget.userId ||
        oldWidget.shopId != widget.shopId) {
      _readGeneration++;
      _page = null;
      _detail = null;
      _context = null;
      _pending = null;
      _otherPending = false;
      _pendingLoadFailed = false;
      _backendReady = false;
      _busy = false;
      _stage = _Stage.list;
      _clearKey();
      for (final controller in [
        _query,
        _name,
        _phone,
        _item,
        _grams,
        _issue,
        _notes,
        _estimate,
        _finalFee,
        _collected,
        _reason,
      ]) {
        controller.clear();
      }
      _boot();
      return;
    }
    if (oldWidget.refreshGeneration != widget.refreshGeneration ||
        oldWidget.userId != widget.userId ||
        oldWidget.shopId != widget.shopId) {
      _onExternalRefresh();
    }
  }

  void _onExternalRefresh() {
    if (_busy) {
      _refreshQueued = true;
      return;
    }
    setState(() {});
    if (_isReview) {
      setState(() => _reviewStale = true);
      return;
    }
    if (_stage == _Stage.list) {
      _loadList();
      return;
    }
    if (_stage == _Stage.detail || _stage == _Stage.handover) {
      final id = _detail?.summary.id;
      if (id != null) _openDetail(id, keepStage: true);
    }
  }

  bool get _isReview =>
      _stage == _Stage.intakeReview ||
      _stage == _Stage.handoverReview ||
      _stage == _Stage.cancelReview ||
      _stage == _Stage.archiveReview;

  void _onSync() {
    if (!mounted) return;
    _onExternalRefresh();
  }

  @override
  void dispose() {
    widget.syncTicks?.removeListener(_onSync);
    _query.dispose();
    _name.dispose();
    _phone.dispose();
    _item.dispose();
    _grams.dispose();
    _issue.dispose();
    _notes.dispose();
    _estimate.dispose();
    _finalFee.dispose();
    _collected.dispose();
    _reason.dispose();
    for (final tender in _tenders) {
      tender.dispose();
    }
    super.dispose();
  }

  Future<void> _boot() async {
    final identity = _identity;
    await _restorePending();
    if (!mounted || identity != _identity) return;
    await _loadList();
  }

  Future<void> _restorePending() async {
    final identity = _identity;
    try {
      final pending = await widget.store.read(widget.userId, widget.shopId);
      if (!mounted || identity != _identity) return;
      setState(() {
        _pendingLoadFailed = false;
        final ours =
            pending != null &&
            ownsRepairCommand(pending.key, pending.kind, pending.body);
        _pending = ours ? pending : null;
        _otherPending = pending != null && !ours;
      });
    } catch (_) {
      if (mounted && identity == _identity) {
        setState(() => _pendingLoadFailed = true);
      }
    }
  }

  Future<void> _reloadReview() async {
    if (_stage == _Stage.intakeReview) {
      setState(() {
        _reviewStale = false;
        _stage = _Stage.intake;
      });
      return;
    }
    final id = _detail?.summary.id;
    if (id == null) return;
    await _openDetail(id);
  }

  Future<void> _loadList() async {
    final generation = ++_readGeneration;
    setState(() {
      _loading = true;
      _busy = false;
      _error = null;
    });
    try {
      final page = await widget.gateway.list(
        callerUserId: widget.userId,
        query: _query.text.trim(),
        filter: _filter,
        limit: 20,
        cursor: null,
      );
      if (!mounted || generation != _readGeneration) return;
      setState(() {
        _backendReady = true;
        _page = page;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _readGeneration) return;
      setState(() {
        _loading = false;
        if (error is RepairReadException && error.code == 'rpc_unavailable') {
          _backendReady = false;
        }
        _error = repairFailureText(
          error is RepairReadException
              ? error.code ?? 'unavailable'
              : 'unavailable',
        );
      });
    }
  }

  Future<void> _loadMore() async {
    final originalPage = _page;
    final cursor = originalPage?.nextCursor;
    if (cursor == null || _busy) return;
    final generation = ++_readGeneration;
    setState(() => _busy = true);
    try {
      final page = await widget.gateway.list(
        callerUserId: widget.userId,
        query: _query.text.trim(),
        filter: _filter,
        limit: 20,
        cursor: cursor,
      );
      if (!mounted || generation != _readGeneration) return;
      setState(() {
        _page = RepairPage(
          items: [...?originalPage?.items, ...page.items],
          nextCursor: page.nextCursor,
        );
        _releaseBusy();
      });
    } catch (error) {
      if (!mounted || generation != _readGeneration) return;
      setState(() {
        _releaseBusy();
        _error = repairFailureText(
          error is RepairReadException
              ? error.code ?? 'unavailable'
              : 'unavailable',
        );
      });
    }
  }

  Future<void> _openDetail(String id, {bool keepStage = false}) async {
    final generation = ++_readGeneration;
    setState(() {
      _loading = true;
      _busy = false;
      _error = null;
    });
    try {
      final detail = await widget.gateway.detail(
        callerUserId: widget.userId,
        repairId: id,
      );
      RepairContext? context;
      if (!_readOnly && detail.summary.status == 'ready') {
        context = await widget.gateway.context(callerUserId: widget.userId);
      }
      if (!mounted || generation != _readGeneration) return;
      setState(() {
        _detail = detail;
        _context = context;
        _loading = false;
        _reviewStale = false;
        if (!keepStage) _stage = _Stage.detail;
      });
    } catch (error) {
      if (!mounted || generation != _readGeneration) return;
      setState(() {
        _loading = false;
        _error = repairFailureText(
          error is RepairReadException
              ? error.code ?? 'unavailable'
              : 'unavailable',
        );
      });
    }
  }

  void _go(_Stage stage) => setState(() {
    _stage = stage;
    _showErrors = false;
    _notice = null;
    _reviewStale = false;
  });

  String _key(String kind) {
    if (_frozenKey != null && _frozenKind == kind) return _frozenKey!;
    final created = widget.newKey?.call() ?? newIdempotencyKey();
    _frozenKey = created;
    _frozenKind = kind;
    return created;
  }

  void _clearKey() {
    _frozenKey = null;
    _frozenKind = null;
  }

  void _releaseBusy() {
    _busy = false;
    if (!_refreshQueued) return;
    _refreshQueued = false;
    Future<void>.microtask(() {
      if (mounted) _onExternalRefresh();
    });
  }

  Future<void> _submit({
    required String kind,
    required Map<String, Object?> payload,
    required bool collected,
  }) async {
    if (_writesBlocked || _reviewStale) return;
    final identity = _identity;
    setState(() => _busy = true);
    final result = await _flow.submit(
      userId: widget.userId,
      shopId: widget.shopId,
      idempotencyKey: _key(kind),
      kind: kind,
      payload: payload,
      readOnly: _readOnly,
    );
    if (!mounted || identity != _identity) return;
    if (result is RepairSaved) {
      _clearKey();
      if (collected) widget.onCollected?.call();
      setState(() {
        _releaseBusy();
        _pending = null;
        _success = 'تم حفظ الطلب.';
        _stage = _Stage.success;
      });
      return;
    }
    if (result is RepairFailed) {
      _clearKey();
      setState(() {
        _releaseBusy();
        _pending = null;
        _notice = repairFailureText(result.code);
      });
      return;
    }
    if (result is RepairNotSent) {
      if (result.code != 'other_pending') _clearKey();
      setState(() {
        _releaseBusy();
        _notice = repairFailureText(result.code);
      });
      return;
    }
    final unconfirmed = result as RepairUnconfirmed;
    setState(() {
      _releaseBusy();
      _pending = unconfirmed.command;
      _pendingUnknown = unconfirmed.statusUnknown;
      _stage = _Stage.list;
      _notice = unconfirmed.statusUnknown
          ? 'النتيجة غير مؤكدة. أعد المحاولة بنفس الطلب.'
          : 'الطلب محفوظ على الجهاز ولم يُؤكد بعد.';
    });
  }

  Future<void> _retryPending() async {
    final pending = _pending;
    if (pending == null || _busy) return;
    final identity = _identity;
    setState(() => _busy = true);
    final result = await _flow.reconcile(
      userId: widget.userId,
      shopId: widget.shopId,
      command: pending,
      retry: true,
    );
    if (!mounted || identity != _identity) return;
    if (result is RepairSaved) {
      _clearKey();
      if (pending.kind == 'repair_handover') {
        final payload = pending.body['p_payload'];
        final collected = payload is Map ? payload['collected_piastres'] : null;
        if (collected is String &&
            collected != '0' &&
            BigInt.tryParse(collected) != BigInt.zero) {
          widget.onCollected?.call();
        }
      }
      setState(() {
        _releaseBusy();
        _pending = null;
        _success = result.replayed
            ? 'تم التأكد من الطلب المحفوظ.'
            : 'تم حفظ الطلب.';
        _stage = _Stage.success;
      });
      return;
    }
    if (result is RepairFailed) {
      _clearKey();
      setState(() {
        _releaseBusy();
        _pending = null;
        _notice = repairFailureText(result.code);
      });
      return;
    }
    if (result is RepairNotSent) {
      setState(() {
        _releaseBusy();
        _notice = repairFailureText(result.code);
      });
      return;
    }
    if (result is RepairUnconfirmed) {
      setState(() {
        _releaseBusy();
        _pending = result.command;
        _pendingUnknown = result.statusUnknown;
        _notice = 'ما زالت النتيجة غير مؤكدة.';
      });
    }
  }

  void _reviewIntake() {
    final fieldsValid = _flowKey.currentState?.validate() ?? false;
    final reviewed = RepairRules.reviewIntake(
      customerName: _name.text,
      customerPhone: _phone.text,
      itemDescription: _item.text,
      gramsText: _grams.text,
      karat: _karat,
      issue: _issue.text,
      intakeNotes: _notes.text,
      estimatedPounds: cashInputValue(_estimate.text),
    );
    if (!fieldsValid || reviewed is RepairRejected<RepairIntakeCommand>) {
      setState(() {
        _showErrors = true;
        _notice = reviewed is RepairRejected<RepairIntakeCommand>
            ? repairIssueText(reviewed.issue)
            : repairIssueText(RepairIssue.invalidInput);
      });
      return;
    }
    setState(() {
      _intake = (reviewed as RepairAccepted<RepairIntakeCommand>).value;
      _stage = _Stage.intakeReview;
      _notice = null;
      _reviewStale = false;
    });
  }

  void _reviewHandover() {
    final detail = _detail;
    final day = _context?.day;
    if (detail == null) return;
    final tenders = <RepairTender>[];
    for (final row
        in _mode == RepairCollectionMode.none ? <_TenderDraft>[] : _tenders) {
      final text = row.amount.text.trim();
      if ((row.method == null || row.method!.isEmpty) && text.isEmpty) {
        continue;
      }
      final amountText = text.isEmpty && _mode == RepairCollectionMode.all
          ? _finalFee.text.trim()
          : text;
      final parsed = amountText.isEmpty
          ? null
          : Piastres.parsePounds(cashInputValue(amountText));
      if (row.method == null || parsed is! Accepted<Piastres>) {
        setState(() {
          _showErrors = true;
          _notice = repairIssueText(RepairIssue.collectionMismatch);
        });
        return;
      }
      tenders.add(
        RepairTender(method: row.method!, piastres: parsed.value.value),
      );
    }
    final reviewed = RepairRules.reviewHandover(
      repairId: detail.summary.id,
      expectedVersion: detail.summary.recordVersion,
      custodyMilligrams: detail.summary.measuredMilligrams,
      finalPounds: cashInputValue(_finalFee.text),
      mode: _mode,
      collectedPounds: _mode == RepairCollectionMode.all
          ? cashInputValue(_finalFee.text)
          : _mode == RepairCollectionMode.none
          ? ''
          : cashInputValue(_collected.text),
      tenders: _mode == RepairCollectionMode.none ? const [] : tenders,
      expectedDayId: _mode == RepairCollectionMode.none || day?.isOpen != true
          ? null
          : day!.dayId,
      expectedDayVersion:
          _mode == RepairCollectionMode.none || day?.isOpen != true
          ? null
          : day!.dayVersion,
    );
    if (reviewed is RepairRejected<RepairHandoverCommand>) {
      setState(() {
        _showErrors = true;
        _notice = repairIssueText(reviewed.issue);
      });
      return;
    }
    final command = (reviewed as RepairAccepted<RepairHandoverCommand>).value;
    if (command.collectedPiastres > BigInt.zero && day?.isOpen != true) {
      setState(() => _notice = repairFailureText('day_closed'));
      return;
    }
    setState(() {
      _handover = command;
      _stage = _Stage.handoverReview;
      _notice = null;
      _reviewStale = false;
    });
  }

  Future<void> _advance(String status) async {
    final detail = _detail;
    if (detail == null ||
        !RepairRules.canAdvanceStatus(detail.summary.status, status)) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تأكيد الحالة: ${repairStatusLabel(status)}'),
        content: const Text(
          'تبقى القطعة في الحيازة. لا يتغير المخزون القابل للبيع ولا النقد.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final command = RepairStatusCommand(
      repairId: detail.summary.id,
      expectedVersion: detail.summary.recordVersion,
      status: status,
    );
    await _submit(
      kind: 'repair_status',
      payload: command.payload(),
      collected: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        leading: _stage == _Stage.list
            ? null
            : IconButton(
                tooltip: 'رجوع',
                onPressed: _busy
                    ? null
                    : () => _go(
                        _stage == _Stage.intakeReview
                            ? _Stage.intake
                            : _stage == _Stage.handover ||
                                  _stage == _Stage.handoverReview ||
                                  _stage == _Stage.cancelReview ||
                                  _stage == _Stage.archiveReview
                            ? _Stage.detail
                            : _Stage.list,
                      ),
                icon: const Icon(Icons.arrow_back),
              ),
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
                if (_readOnly) _banner(repairFailureText('shop_not_active')),
                if (_pending != null) _pendingBanner(),
                if (_otherPending)
                  _banner(
                    'يوجد طلب دفتر محفوظ. افتح الدفتر للتحقق منه قبل تسجيل صيانة جديدة.',
                  ),
                if (_pendingLoadFailed) ...[
                  _banner(
                    'تعذّر قراءة الطلب المحفوظ. تبقى الكتابة متوقفة حتى استعادة الطلب.',
                    error: true,
                  ),
                  TextButton(
                    onPressed: _busy ? null : _boot,
                    child: const Text('إعادة قراءة الطلب المحفوظ'),
                  ),
                ],
                if (_notice != null) _banner(_notice!, error: true),
                if (_error != null) ...[
                  _banner(_error!, error: true),
                  TextButton(
                    key: const Key('repair-read-retry'),
                    onPressed: _busy
                        ? null
                        : () {
                            final id = _detail?.summary.id;
                            if (_stage == _Stage.detail && id != null) {
                              _openDetail(id);
                            } else {
                              _loadList();
                            }
                          },
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: LinearProgressIndicator(),
                  ),
                _body(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _title => switch (_stage) {
    _Stage.list || _Stage.success => 'الصيانة',
    _Stage.intake || _Stage.intakeReview => 'استلام إصلاح',
    _Stage.detail => 'تفاصيل الإصلاح',
    _Stage.handover || _Stage.handoverReview => 'تسليم الإصلاح',
    _Stage.cancelReview => 'إلغاء الإصلاح',
    _Stage.archiveReview => 'أرشفة الإصلاح',
  };

  Widget _body() => switch (_stage) {
    _Stage.list => _list(),
    _Stage.intake => _intakeForm(),
    _Stage.intakeReview => _intakeReview(),
    _Stage.detail => _detailView(),
    _Stage.handover => _handoverForm(),
    _Stage.handoverReview => _handoverReview(),
    _Stage.cancelReview => _cancelReview(),
    _Stage.archiveReview => _archiveReview(),
    _Stage.success => _successView(),
  };

  Widget _banner(String text, {bool error = false}) => Padding(
    padding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
    child: Text(
      text,
      style: TextStyle(
        color: error
            ? Theme.of(context).colorScheme.error
            : Theme.of(context).colorScheme.onSurface,
      ),
    ),
  );

  Widget _pendingBanner() => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _pendingUnknown
                ? 'نتيجة طلب الصيانة غير مؤكدة. أعد التحقق من الطلب المحفوظ.'
                : 'طلب صيانة محفوظ بانتظار التأكيد.',
          ),
          const SizedBox(height: AppTokens.spaceSm),
          const Text('إعادة المحاولة تتابع الطلب المحفوظ دون تكرار أثره.'),
          const SizedBox(height: AppTokens.spaceSm),
          FilledButton(
            key: const Key('repair-pending-retry'),
            onPressed: _busy ? null : _retryPending,
            child: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );

  Widget _list() {
    final items = _page?.items ?? const <RepairSummary>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('repair-search'),
          controller: _query,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            labelText: 'بحث في الصيانة',
            helperText: 'الاسم أو الهاتف أو القطعة أو العطل',
            helperMaxLines: 2,
          ),
          onSubmitted: (_) => _loadList(),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        Wrap(
          spacing: AppTokens.spaceSm,
          runSpacing: AppTokens.spaceSm,
          children: [
            for (final entry in repairFilterLabels.entries)
              ChoiceChip(
                key: Key('repair-filter-${entry.key}'),
                label: Text(entry.value),
                selected: _filter == entry.key,
                onSelected: (_) {
                  setState(() => _filter = entry.key);
                  _loadList();
                },
              ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceMd),
        if (!_readOnly)
          FilledButton.icon(
            key: const Key('repair-new'),
            onPressed: _writesBlocked ? null : () => _go(_Stage.intake),
            icon: const Icon(Icons.add),
            label: const Text('استلام قطعة'),
          ),
        const SizedBox(height: AppTokens.spaceMd),
        if (items.isEmpty && !_loading)
          const Text('لا توجد سجلات في هذه التصفية.')
        else
          for (final item in items)
            Card(
              child: InkWell(
                key: Key('repair-row-${item.id}'),
                onTap: () => _openDetail(item.id),
                child: Padding(
                  padding: const EdgeInsets.all(AppTokens.spaceMd),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(item.customerName),
                      Text(item.itemDescription),
                      Text(
                        '${repairStatusLabel(item.status)} · عيار ${item.karat} · '
                        '${repairWeight(item.measuredMilligrams, exact: false)}',
                      ),
                      if (item.outstandingPiastres > BigInt.zero)
                        Text('متبقي ${repairMoney(item.outstandingPiastres)}'),
                    ],
                  ),
                ),
              ),
            ),
        if (_page?.nextCursor != null)
          OutlinedButton(
            key: const Key('repair-load-more'),
            onPressed: _busy ? null : _loadMore,
            child: const Text('عرض المزيد'),
          ),
      ],
    );
  }

  Widget _intakeForm() => Form(
    key: _flowKey,
    autovalidateMode: _showErrors
        ? AutovalidateMode.onUserInteraction
        : AutovalidateMode.disabled,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(_name, 'اسم العميل', key: const Key('repair-customer-name')),
        _field(
          _phone,
          'هاتف العميل',
          key: const Key('repair-phone'),
          requiredField: false,
        ),
        _field(_item, 'وصف القطعة', key: const Key('repair-item')),
        _field(
          _grams,
          'الوزن بالجرام',
          key: const Key('repair-grams'),
          hint: 'ثلاث خانات، مثل 1.255',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        DropdownButtonFormField<int>(
          key: const Key('repair-karat'),
          initialValue: _karat,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'العيار'),
          items: [
            for (final karat in repairKarats)
              DropdownMenuItem(value: karat, child: Text('$karat')),
          ],
          onChanged: (value) => setState(() => _karat = value),
          validator: (value) => value == null ? 'اختر العيار.' : null,
        ),
        _field(_issue, 'العطل', key: const Key('repair-issue')),
        _field(
          _notes,
          'ملاحظات الاستلام',
          key: const Key('repair-notes'),
          requiredField: false,
          maxLines: 3,
        ),
        _field(
          _estimate,
          'أجرة تقديرية',
          key: const Key('repair-estimate'),
          requiredField: false,
          hint: 'اختياري',
          keyboard: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        FilledButton(
          key: const Key('repair-intake-submit'),
          onPressed: _writesBlocked ? null : _reviewIntake,
          child: const Text('مراجعة أثر الاستلام'),
        ),
      ],
    ),
  );

  Widget _intakeReview() {
    final command = _intake;
    if (command == null) return const SizedBox.shrink();
    return Column(
      key: const Key('repair-intake-review'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('العميل: ${command.customerName}'),
        Text('القطعة: ${command.itemDescription}'),
        Text('الوزن: ${repairWeight(command.measuredMilligrams, exact: true)}'),
        Text('الوزن المدخل: ${repairGramsExact(command.measuredMilligrams)}'),
        Text('العيار: ${command.karat}'),
        Text('العطل: ${command.issue}'),
        Text('الأجرة التقديرية: ${repairMoney(command.estimatedFeePiastres)}'),
        const SizedBox(height: AppTokens.spaceMd),
        const Text('تزيد الحيازة بهذا الوزن مرة واحدة.'),
        const Text('المخزون القابل للبيع: 0'),
        const Text('النقد: 0'),
        if (_reviewStale) _staleReview(),
        const SizedBox(height: AppTokens.spaceMd),
        FilledButton(
          key: const Key('repair-intake-confirm'),
          onPressed: _writesBlocked || _reviewStale
              ? null
              : () => _submit(
                  kind: 'repair_intake',
                  payload: command.payload(),
                  collected: false,
                ),
          child: const Text('تأكيد الاستلام'),
        ),
      ],
    );
  }

  Widget _detailView() {
    final detail = _detail;
    if (detail == null) return const Text('تعذّر عرض السجل.');
    final item = detail.summary;
    final active = const {
      'received',
      'in_progress',
      'ready',
    }.contains(item.status);
    return Column(
      key: const Key('repair-detail'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(item.customerName, style: Theme.of(context).textTheme.titleLarge),
        Text(repairStatusLabel(item.status)),
        Text(item.itemDescription),
        Text('العيار ${item.karat}'),
        Text(
          'الوزن الظاهر: ${repairWeight(item.measuredMilligrams, exact: false)}',
        ),
        Text('الوزن الأصلي: ${repairGramsExact(item.measuredMilligrams)}'),
        Text('العطل: ${item.issue}'),
        Text(
          'ملاحظات الاستلام: ${detail.intakeNotes.isEmpty ? '—' : detail.intakeNotes}',
        ),
        Text(
          'الهاتف: ${item.customerPhone.isEmpty ? '—' : item.customerPhone}',
        ),
        Text('أجرة تقديرية: ${repairMoney(item.estimatedFeePiastres)}'),
        if (item.finalFeePiastres != null) ...[
          Text('الأجرة النهائية: ${repairMoney(item.finalFeePiastres)}'),
          Text('المحصّل: ${repairMoney(item.collectedPiastres)}'),
          Text('المتبقي: ${repairMoney(item.outstandingPiastres)}'),
        ],
        Text(item.custodyHeld ? 'الحيازة قائمة' : 'الحيازة مُحررة'),
        Text('وقت الاستلام: ${formatServerCairoTimestamp(item.intakeAtShop)}'),
        if (detail.cancellationReason != null)
          Text('سبب الإلغاء: ${detail.cancellationReason}'),
        const SizedBox(height: AppTokens.spaceMd),
        Text('سجل المالك', style: Theme.of(context).textTheme.titleMedium),
        for (final event in detail.events)
          Text(
            '${event.actorDisplayName} · ${formatServerCairoTimestamp(event.createdAtShop)} · ${repairEventLabel(event.eventType)}',
          ),
        const SizedBox(height: AppTokens.spaceMd),
        if (!_readOnly && item.status == 'received')
          _statusButton(
            'in_progress',
            'بدء الإصلاح',
            'repair-status-in-progress',
          ),
        if (!_readOnly && item.status == 'in_progress')
          _statusButton(
            'ready',
            'تعليمها جاهزة للتسليم',
            'repair-status-ready',
          ),
        if (!_readOnly && item.status == 'ready')
          FilledButton(
            key: const Key('repair-handover-open'),
            onPressed: _writesBlocked
                ? null
                : () {
                    if (item.estimatedFeePiastres != null) {
                      final parsed = Piastres.parseWire(
                        item.estimatedFeePiastres.toString(),
                      );
                      if (parsed is Accepted<Piastres>) {
                        _finalFee.text = editableCashText(parsed.value.poundsText);
                      }
                    }
                    _go(_Stage.handover);
                  },
            child: const Text('تسليم القطعة'),
          ),
        if (!_readOnly && active)
          OutlinedButton(
            key: const Key('repair-cancel'),
            onPressed: _writesBlocked ? null : () => _go(_Stage.cancelReview),
            child: const Text('إلغاء وإرجاع القطعة'),
          ),
        if (!_readOnly &&
            (item.status == 'delivered' || item.status == 'cancelled'))
          OutlinedButton(
            key: const Key('repair-archive'),
            onPressed: _writesBlocked ? null : () => _go(_Stage.archiveReview),
            child: const Text('أرشفة السجل'),
          ),
      ],
    );
  }

  Widget _statusButton(String status, String label, String keyName) => Padding(
    padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
    child: FilledButton(
      key: Key(keyName),
      onPressed: _writesBlocked ? null : () => _advance(status),
      child: Text(label),
    ),
  );

  Widget _staleReview() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _banner('تغيرت البيانات. أعد التحميل قبل التأكيد.', error: true),
      OutlinedButton(
        key: const Key('repair-review-reload'),
        onPressed: _busy ? null : _reloadReview,
        child: const Text('إعادة التحميل'),
      ),
    ],
  );

  Widget _handoverForm() {
    final methods = _context?.cashMethods ?? const <RepairCashMethod>[];
    return Form(
      autovalidateMode: _showErrors
          ? AutovalidateMode.onUserInteraction
          : AutovalidateMode.disabled,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('repair-handover-final'),
            controller: _finalFee,
            inputFormatters: const [CashInputFormatter()],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'الأجرة النهائية'),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Wrap(
            spacing: AppTokens.spaceSm,
            children: [
              for (final mode in RepairCollectionMode.values)
                ChoiceChip(
                  key: Key('repair-collection-${mode.name}'),
                  label: Text(repairCollectionLabels[mode]!),
                  selected: _mode == mode,
                  onSelected: (_) => setState(() => _mode = mode),
                ),
            ],
          ),
          if (_mode == RepairCollectionMode.part)
            TextField(
              key: const Key('repair-collected'),
              controller: _collected,
              inputFormatters: const [CashInputFormatter()],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'المبلغ المحصّل'),
            ),
          if (_mode != RepairCollectionMode.none && methods.isEmpty)
            _banner(
              'لا توجد طريقة نقد متاحة في الأرصدة المفتوحة.',
              error: true,
            ),
          if (_mode != RepairCollectionMode.none && methods.isNotEmpty) ...[
            for (var index = 0; index < _tenders.length; index++)
              _tenderRow(index, methods),
            if (_tenders.length < 4 && _tenders.length < methods.length)
              TextButton(
                onPressed: () => setState(() => _tenders.add(_TenderDraft())),
                child: const Text('إضافة طريقة دفع'),
              ),
          ],
          const SizedBox(height: AppTokens.spaceMd),
          FilledButton(
            key: const Key('repair-handover-review'),
            onPressed: _writesBlocked ? null : _reviewHandover,
            child: const Text('مراجعة التسليم'),
          ),
        ],
      ),
    );
  }

  Widget _tenderRow(int index, List<RepairCashMethod> methods) {
    final row = _tenders[index];
    final methodField = DropdownButtonFormField<String>(
      key: Key('repair-tender-method-$index'),
      initialValue: row.method,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'طريقة الدفع'),
      items: [
        for (final method in methods)
          DropdownMenuItem(
            value: method.method,
            child: Text(
              '${repairMethodLabels[method.method] ?? method.method} · ${repairMoney(method.balancePiastres)}',
            ),
          ),
      ],
      onChanged: (value) => setState(() => row.method = value),
    );
    final amountField = TextField(
      key: Key('repair-tender-amount-$index'),
      controller: row.amount,
      inputFormatters: const [CashInputFormatter()],
      textDirection: TextDirection.ltr,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: const InputDecoration(labelText: 'المبلغ'),
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth < 480
          ? Column(
              children: [
                methodField,
                const SizedBox(height: AppTokens.spaceSm),
                amountField,
              ],
            )
          : Row(
              children: [
                Expanded(child: methodField),
                const SizedBox(width: AppTokens.spaceSm),
                Expanded(child: amountField),
              ],
            ),
    );
  }

  Widget _handoverReview() {
    final command = _handover;
    if (command == null) return const SizedBox.shrink();
    return Column(
      key: const Key('repair-handover-summary'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('الأجرة النهائية: ${repairMoney(command.finalFeePiastres)}'),
        Text('المحصّل: ${repairMoney(command.collectedPiastres)}'),
        Text(
          'المتبقي على الإصلاح: ${repairMoney(command.outstandingPiastres)}',
        ),
        Text(
          'تحرير الحيازة: ${repairWeight(command.custodyMilligrams, exact: true)}',
        ),
        const Text('المخزون القابل للبيع: 0'),
        if (command.collectedPiastres == BigInt.zero)
          const Text('لا يُسجّل نقد ولا حركة في دفتر اليوم.')
        else
          for (final tender in command.tenders)
            Text(
              '${repairMethodLabels[tender.method] ?? tender.method}: ${repairMoney(tender.piastres)}',
            ),
        const Text('المتبقي محفوظ على سجل الصيانة.'),
        if (_reviewStale) _staleReview(),
        const SizedBox(height: AppTokens.spaceMd),
        FilledButton(
          key: const Key('repair-handover-confirm'),
          onPressed: _writesBlocked || _reviewStale
              ? null
              : () => _submit(
                  kind: 'repair_handover',
                  payload: command.payload(),
                  collected: command.collectedPiastres > BigInt.zero,
                ),
          child: const Text('تأكيد التسليم'),
        ),
      ],
    );
  }

  Widget _cancelReview() {
    final detail = _detail;
    if (detail == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'يلغي السجل النشط ويرجع القطعة للعميل. تُحرر الحيازة مرة واحدة ولا تُحصّل أجرة.',
        ),
        const SizedBox(height: AppTokens.spaceSm),
        TextField(
          key: const Key('repair-cancel-reason'),
          controller: _reason,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'سبب الإرجاع'),
        ),
        if (_reviewStale) _staleReview(),
        const SizedBox(height: AppTokens.spaceMd),
        FilledButton(
          key: const Key('repair-cancel-confirm'),
          onPressed: _writesBlocked || _reviewStale
              ? null
              : () {
                  final reviewed = RepairRules.reviewCancel(
                    repairId: detail.summary.id,
                    expectedVersion: detail.summary.recordVersion,
                    reason: _reason.text,
                    custodyMilligrams: detail.summary.measuredMilligrams,
                    confirmReturn: true,
                  );
                  if (reviewed is RepairRejected<RepairCancelCommand>) {
                    setState(() => _notice = repairIssueText(reviewed.issue));
                    return;
                  }
                  final command =
                      (reviewed as RepairAccepted<RepairCancelCommand>).value;
                  _submit(
                    kind: 'repair_cancel',
                    payload: command.payload(),
                    collected: false,
                  );
                },
          child: const Text('تأكيد الإرجاع'),
        ),
      ],
    );
  }

  Widget _archiveReview() {
    final detail = _detail;
    if (detail == null) return const SizedBox.shrink();
    final item = detail.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'الأرشفة تخفي السجل عن المفتوحة ولا تعكس النقد ولا تسقط المتبقي.',
        ),
        Text('المتبقي بعد الأرشفة: ${repairMoney(item.outstandingPiastres)}'),
        const Text('أثر النقد: 0'),
        if (_reviewStale) _staleReview(),
        const SizedBox(height: AppTokens.spaceMd),
        FilledButton(
          key: const Key('repair-archive-confirm'),
          onPressed: _writesBlocked || _reviewStale
              ? null
              : () {
                  final reviewed = RepairRules.reviewArchive(
                    repairId: item.id,
                    expectedVersion: item.recordVersion,
                    outstandingPiastres: item.outstandingPiastres,
                    terminal:
                        item.status == 'delivered' ||
                        item.status == 'cancelled',
                    confirmArchive: true,
                  );
                  if (reviewed is RepairRejected<RepairArchiveCommand>) {
                    setState(() => _notice = repairIssueText(reviewed.issue));
                    return;
                  }
                  final command =
                      (reviewed as RepairAccepted<RepairArchiveCommand>).value;
                  _submit(
                    kind: 'repair_archive',
                    payload: command.payload(),
                    collected: false,
                  );
                },
          child: const Text('تأكيد الأرشفة'),
        ),
      ],
    );
  }

  Widget _successView() => Column(
    key: const Key('repair-success'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        _success ?? 'تم حفظ الطلب.',
        style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
      ),
      const SizedBox(height: AppTokens.spaceMd),
      FilledButton(
        key: const Key('repair-back-to-list'),
        onPressed: () {
          _go(_Stage.list);
          _loadList();
        },
        child: const Text('العودة إلى السجلات'),
      ),
    ],
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    required Key key,
    bool requiredField = true,
    String? hint,
    TextInputType? keyboard,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
    child: TextFormField(
      key: key,
      controller: controller,
      keyboardType: keyboard,
      inputFormatters: identical(controller, _estimate)
          ? const [CashInputFormatter()]
          : null,
      textDirection: identical(controller, _estimate) ? TextDirection.ltr : null,
      maxLines: maxLines,
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator: (value) {
        if (!requiredField) return null;
        if (value == null || value.trim().isEmpty) return 'هذا الحقل مطلوب.';
        return null;
      },
    ),
  );
}
