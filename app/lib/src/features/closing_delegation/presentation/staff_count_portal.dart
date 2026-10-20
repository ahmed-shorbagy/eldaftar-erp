import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_tokens.dart';
import '../../daily_ledger/application/idempotency_key.dart';
import '../application/closing_delegation_gateway.dart';
import '../application/delegation_flow.dart';
import '../data/secure_delegation_pending_store.dart';
import 'physical_count_editor.dart';
import 'physical_count_summary.dart';

class StaffCountPortal extends StatefulWidget {
  const StaffCountPortal({
    super.key,
    required this.gateway,
    required this.userId,
    required this.onSignOut,
    required this.onToggleTheme,
    this.store = const SecureDelegationPendingStore(),
  });
  final ClosingDelegationGateway gateway;
  final String userId;
  final Future<void> Function() onSignOut;
  final Future<void> Function(Brightness) onToggleTheme;
  final DelegationPendingStore store;
  @override
  State<StaffCountPortal> createState() => _StaffCountPortalState();
}

class _StaffCountPortalState extends State<StaffCountPortal>
    with WidgetsBindingObserver {
  late final _flow = DelegationFlow(
    gateway: widget.gateway,
    store: widget.store,
    userId: widget.userId,
    scope: 'staff',
  );
  StaffCountAssignment? _assignment;
  Map<String, Object?>? _review;
  bool _busy = false, _loading = true, _expired = false, _restoring = true;
  String? _message;
  Timer? _poll, _expiry;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _generation++;
    _poll?.cancel();
    _expiry?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _boot() async {
    await _flow.restore();
    if (mounted) {
      setState(() => _restoring = false);
      await _refresh();
    }
  }

  Future<void> _refresh() async {
    if (_busy || _restoring) return;
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      final assignment = await widget.gateway.myClosingAssignment(
        userId: widget.userId,
      );
      if (!mounted || generation != _generation) return;
      final changed = _assignment?.id != assignment.id;
      _expiry?.cancel();
      setState(() {
        _assignment = assignment;
        _expired = false;
        if (changed) _review = null;
      });
      if (assignment.assigned) {
        _expiry = Timer(assignment.remaining!, () {
          if (!mounted) return;
          setState(() {
            _expired = true;
            _review = null;
            _assignment = null;
            _message = 'انتهت مدة المهمة. تم إغلاق نموذج العد.';
          });
          _refresh();
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _assignment = null;
          _review = null;
          _message =
              'تعذر التحقق من المهمة. حدّث الاتصال قبل إدخال أو إرسال العد.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _send([PendingDelegation? retry]) async {
    if (_busy || _loading || _expired) return;
    final assignment = _assignment;
    final command =
        retry ??
        (assignment?.assigned == true && _review != null
            ? PendingDelegation(newIdempotencyKey(), 'submit', {
                'task_id': assignment!.id,
                'observations': _review,
              })
            : null);
    if (command == null) return;
    setState(() => _busy = true);
    try {
      await _flow.run(command);
      if (!mounted) return;
      setState(
        () => _message = _flow.status == DelegationStatus.confirmed
            ? 'تم إرسال العد إلى المالك. انتهى وصولك إلى النموذج؛ المالك يراجع ويؤكد التقفيل.'
            : _flow.pending != null
            ? 'طلب الإرسال بانتظار التأكيد. تحقق من حالته قبل أي محاولة جديدة.'
            : 'لم يُقبل الإرسال. قد تكون المهمة سُحبت أو تغيّر يوم العمل. حدّث المهمة.',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'تعذر حفظ طلب العد أو تأكيده. تحقق من الحالة؛ لم نعرضه كمحفوظ.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _refresh();
  }

  Future<void> _check() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_flow.restoringFailed) {
        await _flow.restore();
      } else {
        await _flow.check();
      }
      if (mounted && _flow.status == DelegationStatus.confirmed) {
        setState(
          () =>
              _message = 'تأكد إرسال العد إلى المالك. انتهى وصولك إلى النموذج.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'تعذر التحقق. احتفظنا بالطلب الأصلي.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final assignment = _assignment, pending = _flow.pending;
    final editable =
        !_busy &&
        !_loading &&
        !_restoring &&
        !_expired &&
        pending == null &&
        !_flow.restoringFailed;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مهمة العد'),
          actions: [
            IconButton(
              tooltip: 'تغيير المظهر',
              onPressed: () =>
                  widget.onToggleTheme(Theme.of(context).brightness),
              icon: const Icon(Icons.brightness_6_outlined),
            ),
            IconButton(
              tooltip: 'تسجيل الخروج',
              onPressed: _busy ? null : widget.onSignOut,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTokens.contentMaxWidth,
            ),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_busy || _loading) const LinearProgressIndicator(),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_message!),
                  ),
                if (_flow.restoringFailed) ...[
                  const Text(
                    'تعذر استعادة الطلب المعلّق. يلزم التحقق قبل إرسال عد جديد.',
                  ),
                  OutlinedButton(
                    onPressed: _busy ? null : _check,
                    child: const Text('إعادة التحقق من الطلب'),
                  ),
                ] else if (pending != null) ...[
                  const Text(
                    'عد بانتظار التأكيد. بيانات هذا الطلب ثابتة حتى نعرف نتيجته.',
                  ),
                  OutlinedButton(
                    key: const Key('staff-pending-check'),
                    onPressed: _busy ? null : _check,
                    child: const Text('التحقق من حالة الإرسال'),
                  ),
                  if (_flow.status == DelegationStatus.absent)
                    FilledButton(
                      onPressed: _busy ? null : () => _send(pending),
                      child: const Text('إعادة إرسال الطلب نفسه'),
                    ),
                ] else if (assignment?.assigned == true) ...[
                  Text(
                    '${assignment!.shopName} · ${assignment.staffName}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text('عد يوم ${assignment.businessDate}'),
                  Offstage(
                    key: ValueKey('editor-${assignment.id}'),
                    offstage: _review != null,
                    child: PhysicalCountEditor(
                      assignment: assignment,
                      enabled: editable,
                      onReview: (value) => setState(() => _review = value),
                    ),
                  ),
                  if (_review != null) ...[
                    PhysicalCountSummary(observations: _review!),
                    const Text(
                      'سيُرسل هذا العد إلى المالك للمراجعة. لن يُقفل يوم العمل ولن يتغير النقد أو الذهب.',
                    ),
                    FilledButton(
                      key: const Key('staff-count-submit'),
                      onPressed: editable ? () => _send() : null,
                      child: const Text('تأكيد إرسال العد إلى المالك'),
                    ),
                    TextButton(
                      onPressed: editable
                          ? () => setState(() => _review = null)
                          : null,
                      child: const Text('رجوع للتعديل'),
                    ),
                  ],
                ] else if (!_loading) ...[
                  Text(
                    assignment?.state == 'not_staff'
                        ? 'لا توجد عضوية أو مهمة مرتبطة بهذا الحساب.'
                        : 'لا توجد مهمة عد متاحة حالياً. تظهر المهمة هنا بعد تعيين المالك لها.',
                  ),
                ],
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _busy ? null : _refresh,
                  child: const Text('تحديث المهمة'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
