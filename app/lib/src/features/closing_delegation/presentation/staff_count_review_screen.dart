import 'package:flutter/material.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/cash_input.dart';
import '../../daily_ledger/application/financial_gateway.dart';
import '../../daily_ledger/application/opening_gateway.dart';
import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/application/pending_financial_command.dart';
import '../../daily_ledger/data/pending_financial_command.dart';
import '../../daily_ledger/domain/closing_count_observation.dart';
import '../../daily_ledger/domain/opening_catalog.dart';
import '../../daily_ledger/domain/opening_issue.dart';
import '../../daily_ledger/domain/quantities.dart';
import '../../daily_ledger/presentation/ledger_form_fields.dart';
import '../../daily_ledger/presentation/opening_copy.dart';
import '../application/closing_delegation_gateway.dart';
import 'physical_count_summary.dart';

class StaffCountReviewScreen extends StatefulWidget {
  const StaffCountReviewScreen({
    super.key,
    required this.gateway,
    required this.dayGateway,
    required this.statusGateway,
    required this.userId,
    required this.shopId,
    required this.taskId,
    required this.canRead,
    required this.canWrite,
    this.invalidations,
    this.store = const PendingFinancialCommands(),
  });
  final ClosingDelegationGateway gateway;
  final FinancialGateway dayGateway;
  final OpeningGateway statusGateway;
  final FinancialCommandLocker store;
  final String userId, shopId, taskId;
  final bool Function() canRead, canWrite;
  final Listenable? invalidations;
  @override
  State<StaffCountReviewScreen> createState() => _StaffCountReviewScreenState();
}

class _StaffCountReviewScreenState extends State<StaffCountReviewScreen> {
  final _cash = {
    for (final method in CashMethod.canonicalOrder)
      method.code: TextEditingController(),
  };
  DelegatedClosingTask? _task;
  FinancialDayState? _day;
  Map<String, Object?>? _cashReview;
  PendingFinancialCommand? _pending;
  bool _loading = true, _busy = false, _unknown = false, _blocked = false;
  int _readGeneration = 0;
  String? _message;
  @override
  void initState() {
    super.initState();
    widget.invalidations?.addListener(_invalidate);
    _load();
  }

  @override
  void dispose() {
    _readGeneration++;
    widget.invalidations?.removeListener(_invalidate);
    for (final value in _cash.values) {
      value.dispose();
    }
    super.dispose();
  }

  void _invalidate() {
    if (!mounted) return;
    _readGeneration++;
    if (!widget.canRead()) {
      setState(() {
        _task = null;
        _day = null;
        _cashReview = null;
        for (final field in _cash.values) {
          field.clear();
        }
      });
    } else if (!_busy) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!widget.canRead()) return;
    final generation = ++_readGeneration;
    setState(() => _loading = true);
    try {
      final pending = await widget.store.read(widget.userId, widget.shopId);
      final directory = await widget.gateway.closingStaff(
        userId: widget.userId,
        shopId: widget.shopId,
      );
      final day = await widget.dayGateway.dayState(callerUserId: widget.userId);
      if (!mounted || !widget.canRead() || generation != _readGeneration) {
        return;
      }
      final tasks = directory.tasks.where((task) => task.id == widget.taskId);
      setState(() {
        _task = tasks.isEmpty ? null : tasks.first;
        _day = day;
        _blocked =
            pending != null &&
            (pending.kind != 'staff_close' ||
                pending.body['p_task_id'] != widget.taskId);
        _pending = _blocked ? null : pending;
        if (_pending != null) {
          _unknown = true;
          _cashReview = Map<String, Object?>.from(
            _pending!.body['p_cash'] as Map,
          );
          for (final entry in _cash.entries) {
            final raw = _cashReview![entry.key];
            final value = raw is String ? Piastres.parseWire(raw) : null;
            if (value is Accepted<Piastres>) {
              entry.value.text = value.value.poundsText;
            }
          }
        }
      });
      if (_pending != null) await _check();
    } catch (_) {
      if (mounted && generation == _readGeneration) {
        setState(() {
          _task = null;
          _day = null;
          _cashReview = null;
          _message = 'تعذر تحديث العد ويوم العمل. لم يُنفذ التقفيل.';
        });
      }
    } finally {
      if (mounted && generation == _readGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  bool get _current =>
      _task?.state == 'submitted' &&
      _day?.isOpen == true &&
      _task?.dayId == _day?.dayId &&
      _task?.dayVersion == '${_day?.dayVersion}';
  void _review() {
    if (!_current || !widget.canWrite() || _blocked) return;
    final cash = <String, Object?>{};
    for (final entry in _cash.entries) {
      final amount = Piastres.parsePounds(cashInputValue(entry.value.text));
      if (amount is! Accepted<Piastres>) {
        setState(() => _message = 'أدخل النقد الفعلي لكل وسيلة.');
        return;
      }
      cash[entry.key] = amount.value.wire;
    }
    final observations = _task!.observations!;
    if (!closingObservationsMatch({
      'version': 2,
      'cash': cash,
      ...observations,
    }, _day!.counts!)) {
      setState(
        () => _message =
            'يوجد فرق في النقد أو العد عن الدفتر. لا يمكن التقفيل. راجع الفرق وسوِّه ثم اطلب عدّاً جديداً.',
      );
      return;
    }
    setState(() {
      _cashReview = cash;
      _message = null;
    });
  }

  Future<void> _send() async {
    if (_busy || !widget.canWrite() || _cashReview == null || _blocked) return;
    final command =
        _pending ??
        PendingFinancialCommand(
          key: newIdempotencyKey(),
          kind: 'staff_close',
          body: {
            'p_key': '',
            'p_task_id': widget.taskId,
            'p_cash': _cashReview,
          },
        );
    final envelope =
        _pending ??
        PendingFinancialCommand(
          key: command.key,
          kind: command.kind,
          body: {...command.body, 'p_key': command.key},
        );
    setState(() => _busy = true);
    try {
      await widget.store.save(widget.userId, widget.shopId, envelope);
      _pending = envelope;
      final result = await widget.gateway.closeFromStaffCount(
        userId: widget.userId,
        key: envelope.key,
        taskId: widget.taskId,
        cash: Map<String, Object?>.from(envelope.body['p_cash'] as Map),
      );
      if (!mounted) return;
      if (result is FinancialCommitted) {
        await widget.store.clear(widget.userId, widget.shopId, envelope.key);
        if (mounted) Navigator.pop(context, true);
      } else if (result is FinancialRejected ||
          result is FinancialCountMismatch) {
        await widget.store.clear(widget.userId, widget.shopId, envelope.key);
        if (mounted) {
          setState(() {
            _pending = null;
            _cashReview = null;
            _unknown = false;
            _message =
                'لم يُقبل التقفيل. تغيّر يوم العمل أو لا يطابق العد الدفتر. حدّث قبل المحاولة.';
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _unknown = true;
            _message = 'طلب التقفيل بانتظار التأكيد. تحقق قبل أي محاولة جديدة.';
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _unknown = true;
          _message =
              'تعذر حفظ الطلب أو تأكيده. تحقق من الحالة؛ لم نعرض اليومية كمغلقة.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check() async {
    final pending = _pending;
    if (pending == null || _busy) return;
    setState(() => _busy = true);
    try {
      final status = await widget.statusGateway.status(
        callerUserId: widget.userId,
        idempotencyKey: pending.key,
      );
      if (!mounted) return;
      if (status is StatusCompleted) {
        await widget.store.clear(widget.userId, widget.shopId, pending.key);
        if (mounted) Navigator.pop(context, true);
      } else {
        setState(() {
          _unknown = status is! StatusAbsent;
          _message = _unknown
              ? 'النتيجة غير مؤكدة. أعد التحقق.'
              : 'لم يُسجل الطلب. يمكنك إعادة الطلب نفسه.';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _unknown = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('مراجعة عد الموظف')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTokens.contentMaxWidth,
          ),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_loading || _busy) const LinearProgressIndicator(),
              if (!widget.canRead())
                const Text('لم يعد الوصول إلى العد متاحاً لهذا الحساب.')
              else ...[
                if (_message != null) Text(_message!),
                if (_blocked)
                  const Text(
                    'يوجد طلب مالي آخر بانتظار التأكيد. أكمله من الدفتر أولاً.',
                  ),
                if (_task?.observations != null)
                  PhysicalCountSummary(observations: _task!.observations!),
                if (!_loading && !_current && _pending == null)
                  const Text(
                    'هذا العد غير متاح لتقفيل يوم العمل الحالي. حدّث اليوم أو اطلب عدّاً جديداً.',
                  ),
                if (_current && !_blocked) ...[
                  const Text(
                    'أدخل النقد الفعلي بنفسك؛ الموظف لم يرَ أرصدة النقد.',
                  ),
                  for (final method in CashMethod.canonicalOrder)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: TextField(
                        key: Key('owner-staff-cash-${method.code}'),
                        controller: _cash[method.code],
                        readOnly: _busy || _cashReview != null,
                        inputFormatters: const [CashInputFormatter()],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        textDirection: TextDirection.ltr,
                        decoration: ledgerFieldDecoration(
                          context,
                          label: cashMethodLabel(method),
                        ),
                      ),
                    ),
                  if (_cashReview != null)
                    const Text(
                      'تمت مطابقة العد والنقد المدخلين مع الدفتر. وزن المخزون الفارغ لم يُقَس. سيُغلق يوم العمل دون تغيير أرصدة النقد أو الذهب، مع تسجيل الموظف والمالك في التدقيق.',
                    ),
                  if (_pending == null)
                    FilledButton(
                      key: const Key('owner-staff-close'),
                      onPressed: _busy || _loading || !widget.canWrite()
                          ? null
                          : _cashReview == null
                          ? _review
                          : _send,
                      child: Text(
                        _cashReview == null
                            ? 'مراجعة النقد والعد'
                            : 'تأكيد تقفيل اليومية بصفتي المالك',
                      ),
                    ),
                  if (_cashReview != null && _pending == null)
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() => _cashReview = null),
                      child: const Text('تعديل النقد'),
                    ),
                ],
                if (_pending != null) ...[
                  OutlinedButton(
                    onPressed: _busy ? null : _check,
                    child: const Text('التحقق من حالة التقفيل'),
                  ),
                  if (!_unknown)
                    FilledButton(
                      onPressed: _busy || !widget.canWrite() ? null : _send,
                      child: const Text('إعادة طلب التقفيل نفسه'),
                    ),
                ],
                OutlinedButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('تحديث العد ويوم العمل'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
