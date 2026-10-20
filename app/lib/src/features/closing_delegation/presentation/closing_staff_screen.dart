import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_tokens.dart';
import '../../auth/domain/account_identifiers.dart';
import '../../auth/domain/registration_country.dart';
import '../../daily_ledger/application/financial_gateway.dart';
import '../../daily_ledger/application/opening_gateway.dart';
import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/presentation/ledger_form_fields.dart';
import '../application/closing_delegation_gateway.dart';
import '../application/delegation_flow.dart';
import '../data/secure_delegation_pending_store.dart';
import 'staff_count_review_screen.dart';

class ClosingStaffScreen extends StatefulWidget {
  const ClosingStaffScreen({
    super.key,
    required this.gateway,
    required this.dayGateway,
    required this.statusGateway,
    required this.userId,
    required this.shopId,
    required this.canRead,
    required this.canWrite,
    this.invalidations,
    this.store = const SecureDelegationPendingStore(),
  });
  final ClosingDelegationGateway gateway;
  final FinancialGateway dayGateway;
  final OpeningGateway statusGateway;
  final String userId, shopId;
  final bool Function() canRead, canWrite;
  final Listenable? invalidations;
  final DelegationPendingStore store;
  @override
  State<ClosingStaffScreen> createState() => _ClosingStaffScreenState();
}

class _ClosingStaffScreenState extends State<ClosingStaffScreen>
    with WidgetsBindingObserver {
  late final _flow = DelegationFlow(
    gateway: widget.gateway,
    store: widget.store,
    userId: widget.userId,
    scope: 'owner:${widget.shopId}',
  );
  final _name = TextEditingController(),
      _phone = TextEditingController(),
      _password = TextEditingController();
  ClosingStaffDirectory? _directory;
  FinancialDayState? _day;
  bool _busy = false, _loading = true, _restoring = true;
  String? _message;
  Timer? _poll;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.invalidations?.addListener(_invalidate);
    _boot();
    _poll = Timer.periodic(const Duration(minutes: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _generation++;
    _poll?.cancel();
    widget.invalidations?.removeListener(_invalidate);
    WidgetsBinding.instance.removeObserver(this);
    _name.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _boot() async {
    await _flow.restore();
    if (!mounted) return;
    final pending = _flow.pending;
    if (pending?.kind == 'create') {
      _name.text = pending!.payload['name'] as String;
      _phone.text = '+${pending.payload['phone']}';
    }
    setState(() => _restoring = false);
    await _refresh();
  }

  void _invalidate() {
    if (!mounted) return;
    if (!widget.canRead()) {
      _generation++;
      setState(() {
        _directory = null;
        _day = null;
        _name.clear();
        _phone.clear();
        _password.clear();
      });
    } else {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (_busy || _restoring || !widget.canRead()) return;
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      final directory = await widget.gateway.closingStaff(
        userId: widget.userId,
        shopId: widget.shopId,
      );
      final day = await widget.dayGateway.dayState(callerUserId: widget.userId);
      if (mounted && generation == _generation && widget.canRead()) {
        setState(() {
          _directory = directory;
          _day = day;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _directory = null;
          _day = null;
          _message = 'تعذر تحميل فريق العد. حدّث الاتصال قبل إجراء أي تغيير.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<bool> _confirm(String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('مراجعة الطلب'),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('تأكيد'),
            ),
          ],
        ),
      ) ==
      true;
  Future<void> _create() async {
    if (!_editable) return;
    final name = _name.text.trim(),
        phone = RegistrationCountry.internationalPhone(_phone.text);
    if (name.isEmpty ||
        name.runes.length > 120 ||
        name.runes.any((rune) => rune < 32 || rune == 127) ||
        phone == null ||
        !AccountPassword.isAcceptable(_password.text)) {
      setState(() => _message = 'راجع اسم الموظف ورقم الهاتف وكلمة المرور.');
      return;
    }
    if (!await _confirm(
      'إنشاء حساب عد باسم $name ورقم \u2066$phone\u2069. يدخل الموظف برقم الهاتف وكلمة المرور؛ لا تُرسل رسالة تلقائياً، ولا يرى بيانات المتجر إلا نموذج العد عند تكليفه.',
    )) {
      return;
    }
    if (!mounted || !widget.canWrite()) return;
    await _run(
      PendingDelegation(newIdempotencyKey(), 'create', {
        'name': name,
        'phone': phone.replaceFirst('+', ''),
      }),
      password: _password.text,
    );
  }

  bool get _editable =>
      !_busy &&
      !_loading &&
      !_restoring &&
      !_flow.restoringFailed &&
      _flow.pending == null &&
      widget.canWrite() &&
      _directory != null;
  Future<void> _change(String action, String target) async {
    if (!_editable) return;
    final day = _day;
    if (action == 'assign' && day?.isOpen != true) return;
    final text = switch (action) {
      'assign' =>
        'تعيين الموظف لعد يوم ${day!.businessDate} لمدة أربع ساعات. يُسحب أي تكليف عد مفتوح سابق لهذا اليوم. ينتهي الوصول عند التسليم أو السحب أو انتهاء المدة. لا يتغير النقد أو الذهب؛ أنت تراجع وتؤكد التقفيل.',
      'disable' =>
        'إيقاف حساب الموظف وسحب جميع نماذج العد المفتوحة منه. لا تتغير الأرصدة أو العدود المسلّمة.',
      _ => 'سحب وصول الموظف إلى نموذج العد الآن. لا تتغير الأرصدة.',
    };
    if (!await _confirm(text) || !mounted || !widget.canWrite()) return;
    await _run(
      PendingDelegation(newIdempotencyKey(), action, {
        'target': target,
        if (action == 'assign') 'day_id': day!.dayId,
        if (action == 'assign') 'day_version': '${day!.dayVersion}',
      }),
    );
  }

  Future<void> _run(PendingDelegation command, {String? password}) async {
    if (_busy || !widget.canWrite()) return;
    if (command.kind == 'create' &&
        !AccountPassword.isAcceptable(password ?? '')) {
      setState(
        () => _message =
            'أعد إدخال كلمة المرور الأصلية المقبولة لإكمال الطلب نفسه.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await _flow.run(command, password: password);
      if (!mounted) return;
      setState(
        () => _message = _flow.status == DelegationStatus.confirmed
            ? 'تم تأكيد الطلب على الخادم.'
            : _flow.failure == 'payload_mismatch'
            ? _failure(_flow.failure)
            : _flow.pending != null
            ? 'الطلب بانتظار التأكيد. تحقق من حالته.'
            : _failure(_flow.failure),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'تعذر حفظ الطلب أو تأكيده. تحقق من الحالة قبل إنشاء طلب آخر.',
        );
      }
    } finally {
      if (mounted) {
        _password.clear();
        setState(() => _busy = false);
      }
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
      if (mounted) {
        setState(
          () => _message = _flow.status == DelegationStatus.confirmed
              ? 'تأكد تنفيذ الطلب على الخادم.'
              : 'احتفظنا بالطلب الأصلي. أعد التحقق أو المحاولة إذا لم يُسجّل.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'تعذر التحقق. الطلب الأصلي محفوظ.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _refresh();
  }

  String _failure(String? code) => switch (code) {
    'identifier_taken' =>
      'رقم الهاتف مرتبط بحساب قائم. استخدم رقم الموظف المستقل.',
    'payload_mismatch' =>
      'بيانات الطلب لا تطابق المحاولة الأصلية. تحقق من كلمة المرور الأصلية.',
    'stale_day' => 'تغيّر يوم العمل. حدّثه قبل تعيين العد.',
    'staff_limit' => 'وصل الحساب إلى حد حسابات العد المتاحة.',
    _ => 'لم يُقبل الطلب. راجع البيانات والصلاحية وحاول مجدداً.',
  };
  Future<void> _reviewTask(DelegatedClosingTask task) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StaffCountReviewScreen(
          gateway: widget.gateway,
          dayGateway: widget.dayGateway,
          statusGateway: widget.statusGateway,
          userId: widget.userId,
          shopId: widget.shopId,
          taskId: task.id,
          canRead: widget.canRead,
          canWrite: widget.canWrite,
          invalidations: widget.invalidations,
        ),
      ),
    );
    if (mounted) await _refresh();
  }

  String _state(String state) => switch (state) {
    'assigned' => 'مكلّف بالعد',
    'submitted' => 'بانتظار مراجعة المالك',
    'expired' => 'انتهت المدة',
    'revoked' => 'سُحب الوصول',
    'closed' => 'أُغلقت اليومية',
    _ => 'غير متاح',
  };
  @override
  Widget build(BuildContext context) {
    final pending = _flow.pending;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('فريق عد التقفيل')),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTokens.contentMaxWidth,
            ),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_busy || _loading || _restoring)
                  const LinearProgressIndicator(),
                if (!widget.canRead())
                  const Text('لم يعد الوصول إلى فريق هذا المتجر متاحاً.')
                else ...[
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_message!),
                    ),
                  if (_flow.restoringFailed) ...[
                    const Text(
                      'تعذر استعادة الطلب المعلّق. يلزم التحقق قبل طلب جديد.',
                    ),
                    OutlinedButton(
                      onPressed: _busy ? null : _check,
                      child: const Text('إعادة التحقق من الطلب'),
                    ),
                  ],
                  if (pending != null) ...[
                    const Text(
                      'طلب بانتظار التأكيد. بياناته ثابتة حتى تتضح النتيجة.',
                    ),
                    OutlinedButton(
                      key: const Key('owner-staff-pending-check'),
                      onPressed: _busy ? null : _check,
                      child: const Text('التحقق من حالة الطلب'),
                    ),
                    if (_flow.status == DelegationStatus.absent ||
                        _flow.status == DelegationStatus.prepared) ...[
                      if (pending.kind == 'create')
                        TextField(
                          key: const Key('staff-retry-password'),
                          controller: _password,
                          obscureText: true,
                          enabled: !_busy,
                          decoration: ledgerFieldDecoration(
                            context,
                            label: 'كلمة المرور الأصلية لإكمال الطلب',
                          ),
                        ),
                      FilledButton(
                        onPressed: _busy || !widget.canWrite()
                            ? null
                            : () => _run(pending, password: _password.text),
                        child: const Text('إعادة الطلب نفسه'),
                      ),
                    ],
                  ] else if (_directory != null) ...[
                    Text(
                      'إضافة موظف للعد',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'حساب الموظف مخصص لنموذج عد مؤقت. تبقى مراجعة النقد وتأكيد التقفيل للمالك.',
                    ),
                    TextField(
                      key: const Key('staff-name'),
                      controller: _name,
                      enabled: _editable,
                      maxLength: 120,
                      decoration: ledgerFieldDecoration(
                        context,
                        label: 'اسم الموظف',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('staff-phone'),
                      controller: _phone,
                      enabled: _editable,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      decoration: ledgerFieldDecoration(
                        context,
                        label: 'رقم الهاتف مع مفتاح الدولة',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('staff-password'),
                      controller: _password,
                      enabled: _editable,
                      obscureText: true,
                      decoration: ledgerFieldDecoration(
                        context,
                        label: 'كلمة مرور دخول الموظف',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      key: const Key('staff-create'),
                      onPressed: _editable ? _create : null,
                      child: const Text('مراجعة إنشاء الحساب'),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'الموظفون',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (_directory!.staff.isEmpty)
                      const Text('لا توجد حسابات عد بعد.'),
                    for (final staff in _directory!.staff)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                staff.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text('\u2066+${staff.phone}\u2069'),
                              if (!staff.active)
                                const Text('الحساب موقوف')
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    FilledButton(
                                      onPressed:
                                          _editable && _day?.isOpen == true
                                          ? () => _change('assign', staff.id)
                                          : null,
                                      child: const Text(
                                        'تكليف بعدّ اليوم المفتوح',
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _editable
                                          ? () => _change('disable', staff.id)
                                          : null,
                                      child: const Text(
                                        'إيقاف الحساب وسحب الوصول',
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    Text(
                      'مهام العد',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final task in _directory!.tasks)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'يوم ${task.businessDate} · ${_state(task.state)}',
                              ),
                              Text(
                                _directory!.staff
                                    .where((staff) => staff.id == task.staffId)
                                    .map((staff) => staff.name)
                                    .join(),
                              ),
                              if (task.state == 'assigned')
                                OutlinedButton(
                                  onPressed: _editable
                                      ? () => _change('revoke', task.id)
                                      : null,
                                  child: const Text('سحب مهمة العد'),
                                ),
                              if (task.state == 'submitted')
                                FilledButton(
                                  onPressed: !_busy && !_loading
                                      ? () => _reviewTask(task)
                                      : null,
                                  child: const Text(
                                    'مراجعة العد وتقفيل اليومية',
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: _busy || _restoring ? null : _refresh,
                    child: const Text('تحديث فريق العد'),
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
