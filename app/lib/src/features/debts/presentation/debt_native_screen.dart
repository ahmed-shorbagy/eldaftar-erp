import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_tokens.dart';
import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/application/pending_financial_command.dart';
import '../application/debt_gateway.dart';
import '../application/debt_native_contract.dart';
import '../application/debt_native_flow.dart';
import '../application/debt_native_gateway.dart';
import '../application/debt_due_gateway.dart';
import '../application/debt_reminder_coordinator.dart';
import '../application/debt_reminder_device.dart';
import '../domain/debt_rules.dart';
import 'debt_due_screen.dart';

String deviceReminderText(DeviceReminderState s) => switch (s) {
  DeviceReminderState.disabled => 'تذكيرات هذا الجهاز معطلة.',
  DeviceReminderState.preparing =>
    'جارٍ التحقق من البيانات وإعداد تذكيرات الجهاز…',
  DeviceReminderState.registered =>
    'اكتملت مطابقة طلبات الجهاز مع النظام. لا يثبت ذلك عرض التنبيه أو قراءته.',
  DeviceReminderState.pending => 'جدولة الجهاز معلقة؛ لم يؤكدها النظام.',
  DeviceReminderState.failed =>
    'تعذرت مطابقة طلبات الجهاز. الإلغاء أو الجدولة ما زال بحاجة إلى إعادة المحاولة.',
  DeviceReminderState.permissionDenied =>
    'الإشعارات محظورة أو معطلة في إعدادات النظام.',
  DeviceReminderState.unsupported =>
    'إعداد الإشعارات غير مدعوم أو غير متاح في هذه النسخة.',
  DeviceReminderState.missed =>
    'فات وقت التذكير؛ لن يُرسل تنبيه متأخر تلقائيًا.',
  DeviceReminderState.outsideHorizon =>
    'خارج نطاق ٣٠ يومًا. يحتاج الجهاز إلى فتح التطبيق لاحقًا للمطابقة.',
  DeviceReminderState.capacity =>
    'تجاوز سعة ٣٢ طلبًا على الجهاز. لم يُجدول هذا الموعد.',
  DeviceReminderState.invalidTime =>
    'وقت غير موجود أو ملتبس بعد تغيير التاريخ أو المنطقة الزمنية. اختر وقتًا آخر.',
  DeviceReminderState.stale =>
    'تعذرت قراءة بيانات حديثة. قد تبقى تذكيرات قديمة حتى المطابقة.',
  DeviceReminderState.clockMismatch =>
    'ساعة الجهاز تختلف عن وقت الخادم. صحح ساعة النظام ثم أعد المطابقة.',
};
String nativeFailure(String? code) => switch (code) {
  'unresolved_wall_time' =>
    'الوقت غير موجود أو ملتبس بسبب التوقيت الصيفي. اختر وقتًا آخر.',
  'invalid_time' => 'أدخل وقتًا صحيحًا بصيغة ساعة:دقيقة من 00:00 إلى 23:59.',
  'due_date_required' => 'أضف تاريخ استحقاق أولًا.',
  'stale_native' || 'stale_native_cursor' =>
    'تغير الرصيد أو الموعد أو توقيت المحل. أعد القراءة والمراجعة.',
  _ => dueFailure(code ?? 'read'),
};

class DebtNativeScreen extends StatefulWidget {
  const DebtNativeScreen({
    super.key,
    required this.gateway,
    required this.store,
    required this.userId,
    required this.shopId,
    required this.canRead,
    required this.canWrite,
    this.sourceKind,
    this.sourceId,
    this.reminders,
    this.syncTicks,
    this.onMutated,
    this.newKey,
  });
  final DebtNativeGateway gateway;
  final FinancialCommandLocker store;
  final String userId, shopId;
  final DebtSourceKind? sourceKind;
  final String? sourceId;
  final bool Function() canRead, canWrite;
  final DebtReminderCoordinator? reminders;
  final Listenable? syncTicks;
  final VoidCallback? onMutated;
  final String Function()? newKey;
  @override
  State<DebtNativeScreen> createState() => _DebtNativeScreenState();
}

class _DebtNativeScreenState extends State<DebtNativeScreen>
    with WidgetsBindingObserver {
  final _time = TextEditingController();
  final _form = GlobalKey<FormState>();
  DebtNativeDetail? _detail;
  DebtNativeReview? _review;
  PendingFinancialCommand? _pending, _foreign;
  DebtSourceKind? _kind;
  String? _source, _key, _error, _success;
  Object? _session;
  bool _loading = true,
      _busy = false,
      _fresh = false,
      _stale = false,
      _draft = false,
      _access = true;
  int _epoch = 0;
  Timer? _poll;
  StreamSubscription<ReminderDeviceReport>? _device;
  bool get _writes =>
      _access &&
      _fresh &&
      !_busy &&
      !_loading &&
      _pending == null &&
      _foreign == null &&
      widget.canWrite() &&
      _detail?.canWrite == true;
  bool _current(int epoch, Object? session) =>
      mounted &&
      epoch == _epoch &&
      _access &&
      widget.canRead() &&
      session != null &&
      widget.gateway.nativeSession(widget.userId) == session;
  @override
  void initState() {
    super.initState();
    _kind = widget.sourceKind;
    _source = widget.sourceId;
    WidgetsBinding.instance.addObserver(this);
    widget.syncTicks?.addListener(_invalidate);
    _device = widget.reminders?.changes.listen((_) {
      if (mounted) setState(() {});
    });
    _poll = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!_busy) _load(background: true);
    });
    _load();
  }

  @override
  void didUpdateWidget(DebtNativeScreen old) {
    super.didUpdateWidget(old);
    if (old.syncTicks != widget.syncTicks) {
      old.syncTicks?.removeListener(_invalidate);
      widget.syncTicks?.addListener(_invalidate);
    }
    if (old.userId != widget.userId ||
        old.shopId != widget.shopId ||
        old.gateway != widget.gateway ||
        old.sourceId != widget.sourceId ||
        old.sourceKind != widget.sourceKind) {
      _epoch++;
      _detail = null;
      _review = null;
      _pending = null;
      _foreign = null;
      _draft = false;
      _time.clear();
      _busy = false;
      _access = true;
      _success = null;
      _kind = widget.sourceKind;
      _source = widget.sourceId;
      _load();
    }
  }

  @override
  void dispose() {
    _epoch++;
    _poll?.cancel();
    _device?.cancel();
    widget.syncTicks?.removeListener(_invalidate);
    WidgetsBinding.instance.removeObserver(this);
    _time.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _invalidate();
      unawaited(widget.reminders?.reconcile());
    }
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
      _review = null;
      _success = null;
      _time.clear();
      _error = nativeFailure('session_expired');
    });
    unawaited(widget.reminders?.bind(null, null));
  }

  void _invalidate() {
    if (!mounted) return;
    if (!widget.canRead() ||
        widget.gateway.nativeSession(widget.userId) == null) {
      _loseAccess();
      return;
    }
    setState(() {
      _fresh = false;
      if (_review != null) _stale = true;
    });
    if (!_busy) _load(background: true);
  }

  Future<void> _load({bool background = false}) async {
    final session = widget.gateway.nativeSession(widget.userId),
        epoch = ++_epoch;
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
      final p = await widget.store.read(widget.userId, widget.shopId);
      if (!_current(epoch, session)) {
        if (mounted && epoch == _epoch) _loseAccess();
        return;
      }
      final own = p != null && matchesDebtNativeEnvelope(p.key, p.kind, p.body);
      if (own) {
        final payload = p.body['p_payload'] as Map;
        if (_source != payload['source_id'] ||
            _kind?.wire != payload['source_kind']) {
          _draft = false;
          _time.clear();
          _review = null;
          _key = null;
          _success = null;
        }
        _kind = DebtSourceKind.byWire(payload['source_kind'] as String);
        _source = payload['source_id'] as String;
      }
      _pending = own ? p : null;
      _foreign = p != null && !own ? p : null;
      final d = _source == null
          ? null
          : await widget.gateway.readNative(
              userId: widget.userId,
              shopId: widget.shopId,
              sourceKind: _kind!,
              sourceId: _source!,
            );
      if (!_current(epoch, session)) {
        if (mounted && epoch == _epoch) _loseAccess();
        return;
      }
      if (d != null &&
          (d.row.due.shopId != widget.shopId ||
              d.row.due.summary.sourceId != _source ||
              d.row.due.summary.sourceKind != _kind)) {
        throw const DebtReadException('discarded');
      }
      setState(() {
        if (_review != null &&
            (_review!.detail.row.freshness != d?.row.freshness ||
                _session != session)) {
          _stale = true;
        }
        _session = session;
        _detail = d;
        _loading = false;
        _fresh = true;
        _access = true;
        if (d != null && !_draft) {
          _time.text = d.row.time ?? '';
          _draft = true;
        }
        if (background) _error = null;
      });
    } catch (e) {
      if (!mounted || epoch != _epoch) return;
      if (!_current(epoch, session) ||
          e is DebtReadException && dueAccessLost(e.code)) {
        _loseAccess();
        return;
      }
      setState(() {
        _loading = false;
        _fresh = false;
        _error = nativeFailure(e is DebtReadException ? e.code : null);
      });
    }
  }

  Future<void> _prepare({bool clear = false}) async {
    if (!_writes || !clear && _form.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    final intended = clear ? null : _time.text,
        session = widget.gateway.nativeSession(widget.userId),
        epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
      _success = null;
      _stale = false;
    });
    try {
      final r = await widget.gateway.reviewNative(
        userId: widget.userId,
        shopId: widget.shopId,
        sourceKind: _kind!,
        sourceId: _source!,
        time: intended,
      );
      if (!_current(epoch, session)) {
        if (mounted && epoch == _epoch) _loseAccess();
        return;
      }
      if (!r.detail.canWrite || !widget.canWrite()) {
        throw const DebtReadException('shop_not_active');
      }
      if (r.detail.row.due.shopId != widget.shopId ||
          r.detail.row.due.summary.sourceId != _source ||
          r.detail.row.due.summary.sourceKind != _kind ||
          r.time != intended) {
        throw const DebtReadException('discarded');
      }
      setState(() {
        _detail = r.detail;
        _review = r;
        _session = session;
        _key = widget.newKey?.call() ?? newIdempotencyKey();
        _busy = false;
        _fresh = true;
      });
    } catch (e) {
      if (!mounted || epoch != _epoch) return;
      if (!_current(epoch, session) ||
          e is DebtReadException && dueAccessLost(e.code)) {
        _loseAccess();
        return;
      }
      setState(() {
        _busy = false;
        _fresh = false;
        _error = nativeFailure(e is DebtReadException ? e.code : null);
      });
    }
  }

  Future<void> _confirm({bool retry = false}) async {
    if (_busy ||
        !_access ||
        !retry &&
            (!_writes ||
                _review == null ||
                _stale ||
                _session != widget.gateway.nativeSession(widget.userId))) {
      return;
    }
    final session = widget.gateway.nativeSession(widget.userId),
        epoch = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    final flow = DebtNativeFlow(widget.gateway, widget.store);
    final out = retry
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
            _review!.detail.row.payload(_review!.time),
            canWrite: widget.canWrite(),
          );
    if (!_current(epoch, session)) {
      if (mounted && epoch == _epoch) _loseAccess();
      return;
    }
    if (dueAccessLost(out.error)) {
      _loseAccess();
      return;
    }
    setState(() {
      _busy = false;
      _pending = out.pending;
      _review = null;
      _key = null;
      _stale = false;
      _fresh = false;
      _error = out.error == null ? null : nativeFailure(out.error);
      if (out.receipt != null) {
        _success =
            'حُفظ وقت التذكير بعد تأكيد الخادم. جدولة الجهاز مرحلة مستقلة.';
        _draft = false;
      }
    });
    if (out.receipt != null) {
      widget.onMutated?.call();
      unawaited(widget.reminders?.reconcile());
    }
    await _load(background: true);
    if (mounted && _access && out.error != null) {
      setState(() => _error = nativeFailure(out.error));
    }
  }

  Future<void> _deviceAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذر تحديث إعداد الجهاز. أعد المحاولة.');
      }
    }
    if (mounted) setState(() => _busy = false);
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
  @override
  Widget build(BuildContext context) {
    final device = widget.reminders,
        report =
            device?.report ??
            const ReminderDeviceReport(DeviceReminderState.unsupported);
    final d = _detail, r = d?.row;
    return Scaffold(
      appBar: AppBar(
        title: Text(_source == null ? 'تذكيرات هذا الجهاز' : 'وقت تذكير الدين'),
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
                if (_loading || _busy)
                  const LinearProgressIndicator(key: Key('native-preparing')),
                if (_error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      key: const Key('native-error'),
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
                      key: const Key('native-success'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                  ),
                if (!widget.canWrite())
                  const Text(
                    'الحساب للقراءة فقط. تستمر التذكيرات المؤكدة، ويمكن تعطيل هذا الجهاز.',
                  ),
                if (_foreign != null)
                  const Text(
                    'يوجد طلب آخر محفوظ. عد إلى الدفتر لمتابعته.',
                    key: Key('native-foreign'),
                  ),
                if (_pending != null) ...[
                  const Text(
                    'وقت التذكير بانتظار تأكيد الخادم. يبقى الطلب الأصلي محفوظًا.',
                    key: Key('native-pending'),
                  ),
                  _button(
                    'متابعة الطلب الأصلي',
                    () => _confirm(retry: true),
                    'native-retry',
                  ),
                ],
                if (_access && r != null) ...[
                  Text(
                    r.due.summary.partyName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '${dueSource(r.due.summary.sourceKind)} · المتبقي: ${dueAmount(r.due)}${r.due.summary.karat == null ? '' : ' · عيار ${r.due.summary.karat}'}',
                  ),
                  Text('تاريخ الاستحقاق: ${dueDateText(r.due.date)}'),
                  Text('توقيت المحل: \u2066${r.due.timeZone}\u2069'),
                  Text(
                    'الوقت المحفوظ: \u2066${r.time ?? 'بلا تذكير'}\u2069',
                    key: const Key('native-saved-time'),
                  ),
                  if (r.triggerAt != null)
                    Text(
                      'الوقت العالمي: \u2066${r.triggerAt!.toIso8601String()}\u2069',
                    ),
                  if (!r.timeValid)
                    Text(deviceReminderText(DeviceReminderState.invalidTime)),
                  if (r.time != null &&
                      r.triggerAt != null &&
                      !r.triggerAt!.isAfter(d!.at))
                    Text(deviceReminderText(DeviceReminderState.missed)),
                  if (report.rows[r.due.summary.debtKey] != null)
                    Text(
                      deviceReminderText(report.rows[r.due.summary.debtKey]!),
                    ),
                  if (_review != null) ...[
                    const Text('مراجعة وقت التذكير', key: Key('native-review')),
                    Text(
                      'السابق: \u2066${r.time ?? 'بلا تذكير'}\u2069 · الجديد: \u2066${_review!.time ?? 'إزالة التذكير'}\u2069',
                    ),
                    if (_review!.triggerAt != null)
                      Text(
                        'الموعد العالمي بعد تحويل الخادم: \u2066${_review!.triggerAt!.toIso8601String()}\u2069',
                      ),
                    const Text(
                      'الأثر على النقد والذهب والمخزون والأمانة والفواتير: صفر. حفظ الوقت لا يؤكد جدولة الجهاز أو عرض التنبيه.',
                    ),
                    if (_stale)
                      const Text(
                        'تغيرت البيانات. أعد المراجعة قبل التأكيد.',
                        key: Key('native-stale'),
                      ),
                    _button(
                      'تأكيد وقت التذكير',
                      _writes && !_stale ? () => _confirm() : null,
                      'native-confirm',
                    ),
                    _button('تعديل الوقت', () {
                      setState(() {
                        _review = null;
                        _key = null;
                        _stale = false;
                      });
                      _load();
                    }, 'native-edit'),
                  ] else if (d!.canWrite &&
                      widget.canWrite() &&
                      _pending == null &&
                      _foreign == null) ...[
                    const SizedBox(height: AppTokens.spaceMd),
                    Form(
                      key: _form,
                      child: TextFormField(
                        key: const Key('native-time'),
                        controller: _time,
                        enabled: _writes,
                        textDirection: TextDirection.ltr,
                        keyboardType: TextInputType.datetime,
                        decoration: const InputDecoration(
                          labelText: 'وقت التذكير الاختياري',
                          hintText: '00:00',
                          helperText: 'ساعة:دقيقة — من 00:00 إلى 23:59',
                          errorMaxLines: 3,
                        ),
                        validator: (v) => validReminderTime(v ?? '')
                            ? null
                            : 'أدخل وقتًا صحيحًا بصيغة ساعة:دقيقة.',
                      ),
                    ),
                    if (r.due.date != null)
                      _button(
                        'مراجعة الوقت',
                        _writes ? () => _prepare() : null,
                        'native-prepare',
                      )
                    else
                      const Text('أضف تاريخ استحقاق قبل اختيار وقت التذكير.'),
                    if (r.time != null)
                      _button(
                        'مراجعة إزالة وقت التذكير',
                        _writes ? () => _prepare(clear: true) : null,
                        'native-clear',
                      ),
                  ] else if (r.due.summary.displayStatus != 'open')
                    const Text(
                      'هذا السجل مغلق أو مؤرشف. لا تُجدول له تذكيرات نشطة.',
                    ),
                  if (widget.gateway is DebtDueGateway)
                    _button('عرض أو تغيير تاريخ الاستحقاق', () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => DebtDueScreen(
                            gateway: widget.gateway as DebtDueGateway,
                            store: widget.store,
                            userId: widget.userId,
                            shopId: widget.shopId,
                            canRead: widget.canRead,
                            canWrite: widget.canWrite,
                            sourceKind: _kind,
                            sourceId: _source,
                            syncTicks: widget.syncTicks,
                            onMutated: widget.onMutated,
                            newKey: widget.newKey,
                          ),
                        ),
                      );
                      if (mounted) {
                        _invalidate();
                        unawaited(device?.reconcile());
                      }
                    }, 'native-date'),
                  if (d!.history.isNotEmpty)
                    ExpansionTile(
                      title: const Text('سجل أوقات التذكير'),
                      children: [
                        for (final e in d.history)
                          ListTile(
                            title: Text(
                              '\u2066${e.oldTime ?? 'بلا وقت'}\u2069 ← \u2066${e.newTime ?? 'بلا وقت'}\u2069',
                            ),
                            subtitle: Text(
                              '${e.actor} · \u2066${e.atShop.replaceFirst('T', ' ')}\u2069 · ${r.due.timeZone}\nتاريخ وتوقيت الموعد عند الحفظ: \u2066${e.date ?? 'بلا تاريخ'}\u2069 · ${e.zone}',
                            ),
                          ),
                      ],
                    ),
                ],
                ...[
                  const SizedBox(height: AppTokens.spaceLg),
                  const Text('تذكيرات هذا الجهاز'),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      deviceReminderText(report.state),
                      key: const Key('native-device-status'),
                    ),
                  ),
                  const Text(
                    'تنبيهات نظام اختيارية لمرة واحدة خلال ٣٠ يومًا وبحد أقصى ٣٢ طلبًا. الإذن لا يعني الجدولة، والجدولة لا تثبت العرض. قد يؤخر النظام التنبيه، ويعتمد الصوت على إعداداته وساعة الجهاز.',
                  ),
                  const Text(
                    'المحتوى على شاشة القفل عام بلا أسماء أو مبالغ. قد تتكرر التنبيهات على أجهزتك المفعلة، وقد يظهر تنبيه قديم إن لم يتصل الجهاز بعد سداد أو إلغاء أو فقد الوصول.',
                  ),
                  if (_access &&
                      device != null &&
                      !device.enabled &&
                      report.state != DeviceReminderState.unsupported)
                    _button(
                      'تفعيل تذكيرات هذا الجهاز',
                      () => _deviceAction(device.enable),
                      'native-enable',
                    ),
                  if (device != null && device.enabled)
                    _button(
                      'تعطيل وإلغاء تذكيرات هذا الجهاز',
                      () => _deviceAction(device.disable),
                      'native-disable',
                    ),
                  if (device != null)
                    _button(
                      'إعادة مطابقة طلبات الجهاز',
                      () => _deviceAction(device.reconcile),
                      'native-reconcile',
                    ),
                  if (device != null &&
                      report.state != DeviceReminderState.unsupported)
                    _button(
                      'فتح إعدادات إشعارات النظام',
                      () => _deviceAction(() async {
                        if (!await device.port.openSettings() && mounted) {
                          setState(
                            () => _error =
                                'إعدادات الإشعارات غير متاحة. افتح إعدادات النظام ثم إشعارات الدفتر.',
                          );
                        }
                      }),
                      'native-settings',
                    ),
                  for (final e
                      in (_access
                              ? report.rows
                              : const <String, DeviceReminderState>{})
                          .entries
                          .where(
                            (e) => e.value != DeviceReminderState.registered,
                          ))
                    Text(
                      'المرجع: \u2066${e.key}\u2069\n${deviceReminderText(e.value)}',
                    ),
                ],
                if (!_loading && !_fresh && _access)
                  _button('إعادة القراءة', () => _load(), 'native-reload'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
