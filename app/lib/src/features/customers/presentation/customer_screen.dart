import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_tokens.dart';
import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/application/pending_financial_command.dart';
import '../application/customer_contract.dart';
import '../application/customer_gateway.dart';
import '../application/customer_command_flow.dart';
import '../domain/customer_rules.dart';
import '../domain/customer_statistics.dart';
import '../domain/customer_saved_number.dart';
import '../domain/customer_contact.dart';
import '../application/customer_contact_flow.dart';
import '../data/url_customer_contact_launcher.dart';
import 'customer_whatsapp_icon.dart';

String customerError(String? code) => switch (code) {
  'invalid_name' => 'أدخل اسم العميل بالعربية.',
  'invalid_phone' =>
    'أدخل رقم هاتف صحيحًا؛ أضف رمز الدولة للأرقام غير المصرية.',
  'duplicate_phone' => 'رقم الهاتف مكرر في هذا الملف.',
  'primary_required' => 'اختر رقم الهاتف الأساسي.',
  'duplicate_primary' => 'اختر رقمًا أساسيًا واحدًا.',
  'phone_conflict' => 'هذا الرقم مسجل لعميل آخر في المحل.',
  'stale_customer' => 'تغيّر ملف العميل. ارجع إلى التفاصيل وأعد المراجعة.',
  'stale_number' => 'تغيّر رقم الهاتف. افتح الملف وأعد اختيار الرقم.',
  'duplicate_link' => 'العملية مرتبطة بعميل بالفعل.',
  'customer_archived' => 'استعد الملف قبل ربط عملية جديدة.',
  'other_pending' => 'يوجد طلب آخر بانتظار التأكيد.',
  'storage' =>
    'تعذر تحديث الطلب المحفوظ على الجهاز؛ أعد التحقق قبل أي تغيير جديد.',
  'shop_not_active' => 'انتهى الاشتراك؛ الملفات متاحة للقراءة فقط.',
  'forbidden' ||
  'session_expired' ||
  'unauthenticated' => 'انتهى الوصول. سجّل الدخول مرة أخرى.',
  'invalid_cursor' => 'تغيّرت صفحة النتائج. افتح القائمة من البداية.',
  'not_found' => 'هذا الملف غير متاح.',
  'read_failed' =>
    'تعذر تحديث ملف العميل وإحصائياته. البيانات المعروضة قد تكون قديمة؛ أعد المحاولة.',
  _ => 'تعذر إتمام الطلب. تحقق من الاتصال وأعد المحاولة.',
};
String customerDate(String value) =>
    '\u2066${value.replaceFirst('T', ' ').split('.').first}\u2069';
const _events = {
  'created': 'إنشاء ملف العميل',
  'edited': 'تعديل الاسم وأرقام الهاتف',
  'note_added': 'إضافة ملاحظة',
  'status_changed': 'تغيير حالة العميل',
  'archived': 'أرشفة الملف',
  'restored': 'استعادة الملف',
  'linked': 'ربط عملية مؤكدة',
  'unlinked': 'تصحيح ارتباط العملية',
  'saved_number_changed': 'تغيير إقرار حفظ الرقم لواتساب',
};

class CustomerScreen extends StatefulWidget {
  const CustomerScreen({
    super.key,
    required this.gateway,
    required this.store,
    required this.userId,
    required this.shopId,
    this.readOnly = false,
    this.canWrite,
    this.refreshGeneration = 0,
    this.syncTicks,
    this.newKey,
    this.contactLauncher = const UrlCustomerContactLauncher(),
    this.canRead,
  });
  final CustomerGateway gateway;
  final FinancialCommandLocker store;
  final String userId, shopId;
  final bool readOnly;
  final bool Function()? canWrite;
  final int refreshGeneration;
  final Listenable? syncTicks;
  final String Function()? newKey;
  final CustomerContactLauncher contactLauncher;
  final bool Function()? canRead;
  @override
  State<CustomerScreen> createState() => _CustomerScreenState();
}

class _PhoneDraft {
  _PhoneDraft(String value, this.primary)
    : controller = TextEditingController(text: value);
  final TextEditingController controller;
  bool primary;
}

class _CustomerScreenState extends State<CustomerScreen> {
  final _search = TextEditingController(),
      _name = TextEditingController(),
      _note = TextEditingController(),
      _candidateSearch = TextEditingController();
  final _form = GlobalKey<FormState>();
  final _phones = <_PhoneDraft>[];
  Timer? _debounce;
  int _epoch = 0, _request = 0;
  String _stage = 'list', _sort = 'name', _filter = 'active';
  bool _loading = false,
      _busy = false,
      _stale = false,
      _storeFailed = false,
      _foreign = false,
      _vip = false,
      _open = false,
      _syncQueued = false,
      _accessLost = false;
  String? _error, _cursor, _candidateCursor, _editId, _selectedId;
  BigInt? _editVersion;
  List<CustomerRecord> _items = [];
  List<Map<String, Object?>> _candidates = [];
  CustomerDetail? _detail;
  PendingFinancialCommand? _pending;
  Map<String, Object?>? _review;
  Map<String, Object?>? _operation;
  CustomerRecord? _contactRecord;
  CustomerContact? _savedPhone;
  String _savedState = 'unknown';
  CustomerContactAction _contactAction = CustomerContactAction.dialer;
  String _contactReturnStage = 'list';
  String? _contactNumber, _contactMessage;
  Object? _contactStamp;
  int _contactRevision = 0, _contactRequest = 0;
  bool _contactBusy = false, _contactQueued = false, _contactFallback = false;
  bool _contactReady = false;
  bool get _canContact => !_accessLost && (widget.canRead?.call() ?? true);
  Object? _sessionStamp() {
    final gateway = widget.gateway;
    return gateway is CustomerContactSession
        ? (gateway as CustomerContactSession).contactSession(widget.userId)
        : '${widget.userId}:${widget.shopId}';
  }

  bool get _readOnly =>
      _accessLost ||
      widget.readOnly ||
      widget.canWrite != null && !widget.canWrite!();
  bool get _blocked =>
      _readOnly ||
      _busy ||
      _loading ||
      _pending != null ||
      _foreign ||
      _storeFailed;
  bool _current(int e, int r) => mounted && e == _epoch && r == _request;
  CustomerCommandFlow get _flow =>
      CustomerCommandFlow(widget.gateway, widget.store);
  @override
  void initState() {
    super.initState();
    widget.syncTicks?.addListener(_sync);
    _reload();
  }

  @override
  void didUpdateWidget(CustomerScreen old) {
    super.didUpdateWidget(old);
    if (old.syncTicks != widget.syncTicks) {
      old.syncTicks?.removeListener(_sync);
      widget.syncTicks?.addListener(_sync);
    }
    if (old.userId != widget.userId ||
        old.shopId != widget.shopId ||
        old.gateway != widget.gateway ||
        old.store != widget.store) {
      _epoch++;
      _contactRevision++;
      _contactRequest++;
      _contactRecord = null;
      _contactBusy = false;
      _contactMessage = null;
      _contactReady = false;
      _request++;
      _items = [];
      _detail = null;
      _contactStamp = null;
      _selectedId = null;
      _pending = null;
      _foreign = false;
      _review = null;
      _operation = null;
      _stage = 'list';
      _busy = false;
      _accessLost = false;
      _search.clear();
      _note.clear();
      _name.clear();
      _clearPhones();
      _reload();
    } else if (old.refreshGeneration != widget.refreshGeneration) {
      _sync();
    }
  }

  @override
  void dispose() {
    widget.syncTicks?.removeListener(_sync);
    _debounce?.cancel();
    for (final c in [_search, _name, _note, _candidateSearch]) {
      c.dispose();
    }
    _clearPhones();
    super.dispose();
  }

  void _clearPhones() {
    for (final p in _phones) {
      p.controller.dispose();
    }
    _phones.clear();
  }

  void _sync() {
    if (!mounted) return;
    _contactRevision++;
    if (_stage == 'contact') {
      if (_contactBusy) {
        _contactQueued = true;
      } else if (_contactRecord != null) {
        _prepareContact(_contactRecord!, _contactAction, refresh: true);
      }
      return;
    }
    if (_busy) {
      _syncQueued = true;
      return;
    }
    if ({
      'edit',
      'note',
      'status',
      'saved',
      'saved_preparing',
      'review',
      'candidates',
    }.contains(_stage)) {
      setState(() => _stale = true);
      return;
    }
    _reload();
  }

  void _failure(Object e) {
    _error = e is CustomerReadException
        ? e.code ?? 'read_failed'
        : 'read_failed';
    if ({'session_expired', 'forbidden', 'unauthenticated'}.contains(_error)) {
      _accessLost = true;
      _contactRecord = null;
      _contactStamp = null;
      _contactReady = false;
      _items = [];
      _detail = null;
      _review = null;
      _candidates = [];
      _stage = 'list';
    }
  }

  Future<void> _reload({bool older = false}) async {
    final epoch = _epoch, request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pending = await widget.store.read(widget.userId, widget.shopId);
      if (!_current(epoch, request)) return;
      _storeFailed = false;
      _pending = pending != null && customerRpcs.containsKey(pending.kind)
          ? pending
          : null;
      _foreign = pending != null && _pending == null;
      final detailId = _detail?.customer.id ?? _selectedId;
      if (_stage == 'list' || detailId == null) {
        final page = await widget.gateway.customers(
          callerUserId: widget.userId,
          query: _search.text.trim(),
          sort: _sort,
          filter: _filter,
          cursor: older ? _cursor : null,
        );
        if (!_current(epoch, request)) return;
        _items = older
            ? [
                ..._items,
                ...page.items.where((n) => !_items.any((c) => c.id == n.id)),
              ]
            : page.items;
        _cursor = page.cursor;
        _accessLost = false;
      } else {
        final d = await widget.gateway.customer(
          callerUserId: widget.userId,
          id: detailId,
        );
        if (!_current(epoch, request)) return;
        _detail = d;
        _accessLost = false;
      }
    } catch (e) {
      if (!_current(epoch, request)) return;
      _failure(e);
      if (e is! CustomerReadException) {
        _storeFailed = true;
        _error = 'storage';
      }
    } finally {
      if (_current(epoch, request)) setState(() => _loading = false);
    }
  }

  Future<void> _openCustomer(CustomerRecord c) async {
    if (_busy) return;
    setState(() {
      _detail = null;
      _selectedId = c.id;
      _stage = 'detail';
      _loading = true;
      _error = null;
    });
    final e = _epoch, r = ++_request;
    try {
      final d = await widget.gateway.customer(
        callerUserId: widget.userId,
        id: c.id,
      );
      if (!_current(e, r)) return;
      setState(() => _detail = d);
    } catch (x) {
      if (_current(e, r)) setState(() => _failure(x));
    } finally {
      if (_current(e, r)) setState(() => _loading = false);
    }
  }

  void _back() {
    if (_busy) return;
    if (_stage == 'contact') {
      _contactRevision++;
      _contactRequest++;
      setState(() {
        _stage = _contactReturnStage;
        _contactBusy = false;
        _contactMessage = null;
        _contactQueued = false;
        _contactReady = false;
      });
      _reload();
      return;
    }
    setState(() {
      _error = null;
      _stale = false;
      _review = null;
      _operation = null;
      _stage = _stage == 'detail' || _stage == 'success'
          ? 'list'
          : _detail == null
          ? 'list'
          : 'detail';
    });
    _reload();
  }

  void _edit([CustomerRecord? c]) {
    if (_blocked) return;
    _clearPhones();
    _name.text = c?.name ?? '';
    _editId = c?.id;
    _editVersion = c?.version;
    for (final p in c?.phones ?? <CustomerContact>[]) {
      _phones.add(_PhoneDraft(p.raw, p.primary));
    }
    setState(() {
      _error = null;
      _stale = false;
      _stage = 'edit';
    });
  }

  Map<String, Object?> _payload(String kind) => {
    'version': 1,
    'kind': kind,
    'customer_id': _detail!.customer.id,
    'expected_version': _detail!.customer.version.toString(),
  };
  Future<void> _send(Map<String, Object?> payload) async {
    if (_blocked || _stale) return;
    final e = _epoch;
    final stamp = _sessionStamp();
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await _flow.submit(
      widget.userId,
      widget.shopId,
      (widget.newKey ?? newIdempotencyKey)(),
      payload,
    );
    if (!mounted || e != _epoch) return;
    if (stamp == null || stamp != _sessionStamp() || !_canContact) {
      setState(() {
        _busy = false;
        _failure(const CustomerReadException('session_expired'));
      });
      return;
    }
    _apply(result);
    setState(() => _busy = false);
    if (_syncQueued) {
      _syncQueued = false;
      if (result.pending == null) _reload();
    }
  }

  void _apply(CustomerOutcome result) {
    _pending = result.pending;
    _error = result.error;
    if ({
      'session_expired',
      'forbidden',
      'unauthenticated',
    }.contains(result.error)) {
      _failure(CustomerReadException(result.error));
      return;
    }
    if (result.receipt != null) {
      _detail = CustomerDetail(
        result.receipt!.customer,
        const CustomerSection([], null),
        const CustomerSection([], null),
        const CustomerSection([], null),
      );
      _stage = 'success';
      _review = null;
      _stale = false;
    } else if (result.error == 'stale_customer' ||
        result.error == 'stale_number') {
      _stale = true;
    }
  }

  Future<void> _retry() async {
    final pending = _pending;
    if (pending == null || _busy) return;
    final e = _epoch;
    final stamp = _sessionStamp();
    setState(() => _busy = true);
    final result = await _flow.reconcile(
      widget.userId,
      widget.shopId,
      pending,
      retry: !_readOnly,
    );
    if (!mounted || e != _epoch) return;
    if (stamp == null || stamp != _sessionStamp() || !_canContact) {
      setState(() {
        _busy = false;
        _failure(const CustomerReadException('session_expired'));
      });
      return;
    }
    setState(() {
      _apply(result);
      _busy = false;
    });
  }

  void _saveEdit() {
    if (!_form.currentState!.validate()) return;
    final phones = _phones
        .map(
          (p) => CustomerPhone(
            number: p.controller.text.trim(),
            primary: p.primary,
          ),
        )
        .toList();
    final issue = customerPhoneIssue(phones);
    if (issue != null) {
      setState(() => _error = issue);
      return;
    }
    final kind = _editId == null ? 'customer_create' : 'customer_edit';
    _send({
      'version': 1,
      'kind': kind,
      'display_name': _name.text.trim(),
      'phones': phones.map((p) => p.toWire()).toList(),
      if (_editId != null) 'customer_id': _editId,
      if (_editVersion != null) 'expected_version': _editVersion.toString(),
      if (_editId == null) 'is_vip': false,
      if (_editId == null) 'has_open_request': false,
    });
  }

  Future<void> _loadCandidates({bool older = false}) async {
    if (_busy || _loading) return;
    final e = _epoch, r = ++_request;
    setState(() {
      _stage = 'candidates';
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.gateway.customerCandidates(
        callerUserId: widget.userId,
        query: _candidateSearch.text.trim(),
        cursor: older ? _candidateCursor : null,
      );
      if (!_current(e, r)) return;
      setState(() {
        _candidates = older
            ? [
                ..._candidates,
                ...page.items.where(
                  (n) => !_candidates.any(
                    (c) => c['operation_id'] == n['operation_id'],
                  ),
                ),
              ]
            : page.items;
        _candidateCursor = page.cursor;
      });
    } catch (x) {
      if (_current(e, r)) setState(() => _failure(x));
    } finally {
      if (_current(e, r)) setState(() => _loading = false);
    }
  }

  Future<void> _more(String section) async {
    final d = _detail;
    if (d == null || _loading) return;
    final e = _epoch, r = ++_request;
    setState(() => _loading = true);
    try {
      final next = await widget.gateway.customer(
        callerUserId: widget.userId,
        id: d.customer.id,
        notesCursor: section == 'notes' ? d.notes.cursor : null,
        historyCursor: section == 'history' ? d.history.cursor : null,
        linksCursor: section == 'links' ? d.links.cursor : null,
      );
      if (!_current(e, r)) return;
      setState(
        () => _detail = CustomerDetail(
          next.customer,
          section == 'notes'
              ? CustomerSection([
                  ...d.notes.items,
                  ...next.notes.items,
                ], next.notes.cursor)
              : next.notes,
          section == 'history'
              ? CustomerSection([
                  ...d.history.items,
                  ...next.history.items,
                ], next.history.cursor)
              : next.history,
          section == 'links'
              ? CustomerSection([
                  ...d.links.items,
                  ...next.links.items,
                ], next.links.cursor)
              : next.links,
        ),
      );
    } catch (x) {
      if (_current(e, r)) setState(() => _failure(x));
    } finally {
      if (_current(e, r)) setState(() => _loading = false);
    }
  }

  Widget _action(
    String label,
    VoidCallback? tap, {
    Key? key,
    bool primary = false,
  }) => primary
      ? FilledButton(key: key, onPressed: tap, child: Text(label))
      : OutlinedButton(key: key, onPressed: tap, child: Text(label));
  Widget _heading(String label) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(label, style: Theme.of(context).textTheme.titleLarge),
  );
  Widget _contact(String value) =>
      Text(value, textDirection: TextDirection.ltr);
  Future<void> _prepareSaved(CustomerContact phone) async {
    if (_blocked || phone.saved == null || _detail == null) return;
    final customer = _detail!.customer;
    final epoch = _epoch, request = ++_request, stamp = _sessionStamp();
    setState(() {
      _stage = 'saved_preparing';
      _loading = true;
      _stale = false;
      _error = null;
    });
    try {
      final fresh = await widget.gateway.customer(
        callerUserId: widget.userId,
        id: customer.id,
      );
      if (!_current(epoch, request) || _stage != 'saved_preparing') return;
      if (stamp == null || stamp != _sessionStamp() || !_canContact) {
        throw const CustomerReadException('session_expired');
      }
      final numbers = fresh.customer.phones.where(
        (n) =>
            n.normalized == phone.normalized && n.saved?.id == phone.saved!.id,
      );
      if (_stale ||
          fresh.customer.id != customer.id ||
          fresh.customer.version != customer.version ||
          numbers.length != 1) {
        _detail = fresh;
        _stage = 'detail';
        _error = 'stale_number';
      } else {
        _detail = fresh;
        _savedPhone = numbers.single;
        _savedState = numbers.single.saved!.state;
        _stage = 'saved';
      }
    } catch (e) {
      if (_current(epoch, request)) {
        _stage = 'detail';
        _failure(e);
      }
    } finally {
      if (_current(epoch, request)) setState(() => _loading = false);
    }
  }

  Future<void> _prepareContact(
    CustomerRecord record,
    CustomerContactAction action, {
    bool refresh = false,
  }) async {
    if (_contactBusy || !_canContact || _busy) return;
    final epoch = _epoch, revision = ++_contactRevision;
    final request = ++_contactRequest;
    final stamp = _sessionStamp();
    if (stamp == null) {
      setState(() => _failure(const CustomerReadException('session_expired')));
      return;
    }
    if (!refresh) _contactReturnStage = _stage;
    setState(() {
      _stage = 'contact';
      _contactRecord = record;
      _contactNumber = null;
      _contactAction = action;
      _contactBusy = true;
      _contactFallback = false;
      _contactReady = false;
      _contactMessage = 'جارٍ تجهيز أرقام العميل الحالية…';
    });
    bool current() =>
        mounted &&
        epoch == _epoch &&
        request == _contactRequest &&
        _stage == 'contact';
    try {
      final d = await widget.gateway.customer(
        callerUserId: widget.userId,
        id: record.id,
      );
      if (!current() ||
          revision != _contactRevision ||
          stamp != _sessionStamp() ||
          !_canContact) {
        return;
      }
      if (d.customer.id != record.id ||
          !mayContactCustomer(
            authorizedReader: _canContact,
            status: d.customer.status,
          )) {
        throw const CustomerReadException('forbidden');
      }
      setState(() {
        _contactRecord = d.customer;
        _contactStamp = stamp;
        _contactReady = true;
        final valid = d.customer.phones
            .where((p) => customerContactUri(action, p.normalized) != null)
            .toList();
        _contactNumber = valid.isEmpty
            ? null
            : (valid.where((p) => p.primary).firstOrNull ?? valid.first)
                  .normalized;
        _contactMessage = refresh
            ? 'تم تحديث الأرقام. راجع اختيارك قبل الفتح.'
            : null;
      });
    } catch (e) {
      if (!current() ||
          revision != _contactRevision ||
          stamp != _sessionStamp()) {
        return;
      }
      setState(() {
        _contactNumber = null;
        _contactMessage = customerError(
          e is CustomerReadException ? e.code : 'read_failed',
        );
        if (e is CustomerReadException &&
            {
              'forbidden',
              'session_expired',
              'unauthenticated',
            }.contains(e.code)) {
          _failure(e);
        }
      });
    } finally {
      if (mounted && epoch == _epoch && request == _contactRequest) {
        setState(() => _contactBusy = false);
        if (!_canContact || _sessionStamp() == null) {
          setState(
            () => _failure(const CustomerReadException('session_expired')),
          );
        }
      }
      if (current()) {
        if (_contactQueued) {
          _contactQueued = false;
          _prepareContact(record, action, refresh: true);
        } else if (revision != _contactRevision || stamp != _sessionStamp()) {
          setState(() {
            _contactNumber = null;
            _contactReady = false;
            _contactMessage =
                'تغيّر الوصول أو الملف؛ أعد تجهيز الأرقام قبل الفتح.';
          });
        }
      }
    }
  }

  Future<void> _launchContact(CustomerContactAction action) async {
    final record = _contactRecord, number = _contactNumber;
    if (_contactBusy ||
        !_contactReady ||
        record == null ||
        number == null ||
        !_canContact) {
      return;
    }
    if (_contactStamp == null || _contactStamp != _sessionStamp()) {
      await _prepareContact(record, _contactAction, refresh: true);
      return;
    }
    final epoch = _epoch, revision = _contactRevision, stamp = _contactStamp;
    final request = ++_contactRequest;
    bool current() =>
        mounted &&
        epoch == _epoch &&
        revision == _contactRevision &&
        request == _contactRequest &&
        _stage == 'contact' &&
        _canContact &&
        stamp == _sessionStamp();
    setState(() {
      _contactBusy = true;
      _contactMessage = 'جارٍ التحقق وفتح جهة الاتصال…';
      _contactFallback = false;
    });
    try {
      final result =
          await CustomerContactFlow(
            widget.gateway,
            widget.contactLauncher,
          ).launch(
            userId: widget.userId,
            reviewed: record,
            number: number,
            action: action,
            stillAuthorized: current,
          );
      if (!current()) return;
      setState(() {
        _contactFallback =
            action == CustomerContactAction.whatsapp &&
            result == ContactHandoff.unavailable;
        _contactMessage = switch (result) {
          ContactHandoff.opened => switch (action) {
            CustomerContactAction.dialer =>
              'تم فتح واجهة الاتصال. ابدأ المكالمة أو أكدها من هناك.',
            CustomerContactAction.whatsapp =>
              'تم تسليم طلب فتح محادثة واتساب. لم يُؤكد إرسال أي رسالة.',
            CustomerContactAction.whatsappLink =>
              'تم فتح رابط محادثة واتساب خارجيًا؛ قد يظهر في المتصفح. لم يُؤكد إرسال أي رسالة.',
          },
          ContactHandoff.unavailable =>
            action == CustomerContactAction.dialer
                ? 'لوحة الاتصال غير متاحة على هذا الجهاز.'
                : action == CustomerContactAction.whatsappLink
                ? 'لا توجد جهة متاحة لفتح رابط المحادثة على هذا الجهاز.'
                : 'جهة واتساب غير متاحة. يمكنك اختيار فتح رابط المحادثة خارجيًا.',
          ContactHandoff.cancelled => 'أُلغي طلب الفتح قبل تسليمه.',
          ContactHandoff.denied =>
            'رفض النظام فتح جهة الاتصال. راجع إعدادات الجهاز.',
          ContactHandoff.permanentlyDenied =>
            'منع النظام فتح جهة الاتصال. راجع الأذونات في إعدادات الجهاز.',
          ContactHandoff.changed =>
            'تغيّر الملف؛ أعد تجهيز الأرقام وراجع اختيارك.',
          ContactHandoff.stale => 'تغيّر الوصول؛ أعد تجهيز الأرقام قبل الفتح.',
          ContactHandoff.busy => 'طلب فتح آخر قيد التجهيز.',
          ContactHandoff.failed =>
            'تعذر فتح جهة الاتصال. يمكنك إعادة المحاولة.',
        };
        if (result == ContactHandoff.changed) {
          _contactNumber = null;
          _contactReady = false;
        }
      });
    } catch (e) {
      if (!current()) return;
      setState(() {
        _contactNumber = null;
        _contactReady = false;
        _contactMessage = customerError(
          e is CustomerReadException ? e.code : 'read_failed',
        );
        if (e is CustomerReadException &&
            {
              'forbidden',
              'session_expired',
              'unauthenticated',
            }.contains(e.code)) {
          _failure(e);
        }
      });
    } finally {
      if (mounted && epoch == _epoch && request == _contactRequest) {
        setState(() => _contactBusy = false);
      }
      if (mounted &&
          epoch == _epoch &&
          request == _contactRequest &&
          (!_canContact || _sessionStamp() == null)) {
        setState(
          () => _failure(const CustomerReadException('session_expired')),
        );
      }
      if (mounted &&
          epoch == _epoch &&
          request == _contactRequest &&
          _stage == 'contact') {
        if (_contactQueued) {
          _contactQueued = false;
          _prepareContact(record, _contactAction, refresh: true);
        } else if (!current()) {
          setState(() {
            _contactNumber = null;
            _contactReady = false;
            _contactFallback = false;
            _contactMessage = 'تغيّر الوصول؛ أعد تجهيز الأرقام قبل الفتح.';
          });
        }
      }
    }
  }

  List<Widget> _contactWidgets() {
    final c = _contactRecord;
    if (c == null) return [];
    return [
      _heading(
        _contactAction == CustomerContactAction.dialer
            ? 'الاتصال بالعميل'
            : 'محادثة واتساب',
      ),
      Text(c.name),
      if (_contactBusy) const LinearProgressIndicator(),
      if (_contactMessage != null)
        Semantics(liveRegion: true, child: Text(_contactMessage!)),
      _heading('اختر رقم الهاتف'),
      if (c.phones.isEmpty) const Text('لا يوجد رقم هاتف للاتصال.'),
      RadioGroup<String>(
        groupValue: _contactNumber,
        onChanged: (value) {
          if (_contactReady && !_contactBusy && _canContact) {
            setState(() {
              _contactNumber = value;
              _contactFallback = false;
              _contactMessage = null;
            });
          }
        },
        child: Column(
          children: [
            for (final p in c.phones)
              RadioListTile<String>(
                value: p.normalized,
                enabled:
                    _contactReady &&
                    !_contactBusy &&
                    _canContact &&
                    customerContactUri(_contactAction, p.normalized) != null,
                title: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: _contact(p.normalized),
                ),
                subtitle: Text(p.primary ? 'الرقم الأساسي' : 'رقم إضافي'),
              ),
          ],
        ),
      ),
      if (_contactNumber != null) ...[
        const Text('الرقم المختار'),
        _contact(_contactNumber!),
      ],
      const SizedBox(height: 16),
      _action(
        _contactAction == CustomerContactAction.dialer
            ? 'فتح لوحة الاتصال'
            : 'فتح محادثة واتساب',
        _contactBusy || !_canContact || _contactNumber == null
            ? null
            : () => _launchContact(_contactAction),
        key: const Key('customer-contact-open'),
        primary: true,
      ),
      if (_contactFallback)
        _action(
          'فتح رابط واتساب خارجيًا',
          _contactBusy || !_canContact || _contactNumber == null
              ? null
              : () => _launchContact(CustomerContactAction.whatsappLink),
        ),
      _action(
        'تحديث أرقام الاتصال',
        _contactBusy || !_canContact
            ? null
            : () => _prepareContact(c, _contactAction, refresh: true),
      ),
      if (_contactNumber == null && !_readOnly)
        _action(
          'تعديل بيانات العميل',
          _blocked || _contactBusy
              ? null
              : () {
                  _detail = CustomerDetail(
                    c,
                    const CustomerSection([], null),
                    const CustomerSection([], null),
                    const CustomerSection([], null),
                  );
                  _edit(c);
                },
        ),
      _action(
        'إلغاء',
        _contactBusy
            ? null
            : () {
                _back();
              },
      ),
    ];
  }

  Widget _card(CustomerRecord c, {bool clickable = true}) => Card(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          key: Key('customer-${c.id}'),
          onTap: clickable ? () => _openCustomer(c) : null,
          leading: MediaQuery.textScalerOf(context).scale(16) > 20
              ? null
              : CircleAvatar(child: Text(c.name.characters.first)),
          titleAlignment: ListTileTitleAlignment.top,
          title: Text(
            c.name,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (c.phones.isEmpty)
                const Text('بدون رقم هاتف')
              else
                _contact(c.phones.firstWhere((p) => p.primary).normalized),
              if (clickable)
                Text(
                  c.phones.isEmpty
                      ? 'حالة حفظ الرقم الأساسي لواتساب: غير متاحة؛ بدون هاتف'
                      : 'حالة حفظ الرقم الأساسي لواتساب: ${savedNumberLabel(c.phones.firstWhere((p) => p.primary).saved?.state)}',
                ),
              Text(
                c.lastAtShop == null
                    ? 'لا توجد عمليات مرتبطة'
                    : 'آخر عملية: ${customerDate(c.lastAtShop!)}',
              ),
              if (clickable && c.statistics != null) ...[
                const Text('اشترى العميل من المحل (جرام)'),
                _weightTiles(c.statistics!, compact: true),
                const Text('صافي العمليات المؤكدة المرتبطة فقط'),
              ],
              if (c.latestNote != null)
                Text(
                  c.latestNote!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              Wrap(
                spacing: 8,
                children: [
                  if (c.vip)
                    const Chip(
                      avatar: Icon(Icons.star_outline),
                      label: Text('عميل مميز'),
                    ),
                  if (c.openRequest) const Chip(label: Text('طلب مفتوح')),
                  if (c.archived) const Chip(label: Text('مؤرشف')),
                ],
              ),
            ],
          ),
        ),
        if (clickable)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 16,
              end: 16,
              bottom: 8,
            ),
            child: Tooltip(
              message: 'محادثة واتساب مع ${c.name}',
              child: TextButton.icon(
                key: Key('customer-whatsapp-${c.id}'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  minimumSize: const Size(48, 48),
                ),
                onPressed:
                    !_canContact ||
                        _contactBusy ||
                        _loading ||
                        !c.phones.any(
                          (p) =>
                              customerContactUri(
                                CustomerContactAction.whatsapp,
                                p.normalized,
                              ) !=
                              null,
                        )
                    ? null
                    : () => _prepareContact(c, CustomerContactAction.whatsapp),
                icon: const CustomerWhatsappIcon(),
                label: const Text('واتساب'),
              ),
            ),
          ),
      ],
    ),
  );
  Widget _weightTiles(CustomerStatistics statistics, {bool compact = false}) =>
      Wrap(
        spacing: AppTokens.spaceMd,
        runSpacing: AppTokens.spaceSm,
        children: [
          for (final karat in compact ? [18, 21, 24] : customerKarats)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'عيار $karat',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: compact
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  if (!compact) const Text('اشترى العميل'),
                  Text(
                    customerGrams(statistics.at(karat).boughtMilligrams),
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (!compact) ...[
                    const Text('باع العميل للمحل'),
                    Text(
                      customerGrams(statistics.at(karat).soldMilligrams),
                      textDirection: TextDirection.ltr,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ],
              ),
            ),
        ],
      );

  List<Widget> _statisticsWidgets(CustomerRecord customer) {
    final s = customer.statistics;
    final op = s?.lastOperation;
    const kinds = {
      'sale': 'شراء العميل من المحل',
      'purchase': 'بيع العميل للمحل',
      'sale_return': 'مرتجع شراء العميل',
      'purchase_return': 'مرتجع بيع العميل للمحل',
    };
    return [
      _heading('إحصائيات العملاء'),
      if (s == null)
        const Text('الإحصائيات غير متاحة؛ افتح الملف مجددًا لتحديثه.')
      else ...[
        const Text(
          'الأوزان الصافية بالجرام بعد المرتجعات المؤكدة. تشمل العمليات المرتبطة صراحة بهذا الملف فقط، وليست كامل تاريخ العميل.',
        ),
        if (!s.hasActivity)
          const Text('لا توجد عمليات مؤكدة مرتبطة؛ جميع الأوزان والأعداد صفر.'),
        _weightTiles(s),
        Text('عدد عمليات شراء العميل من المحل: \u2066${s.boughtCount}\u2069'),
        Text('عدد عمليات بيع العميل للمحل: \u2066${s.soldCount}\u2069'),
        const Text('يبقى عدد العمليات بعد المرتجع الجزئي أو الكامل.'),
        if (op != null)
          Text(
            'آخر عملية مؤكدة: ${kinds[op.kind]} · رقم \u2066${op.sequence}\u2069 · ${customerDate(op.createdAtShop)}',
          )
        else
          const Text('لا توجد عملية مؤكدة مرتبطة لعرض تاريخها.'),
      ],
    ];
  }

  List<Widget> _list() => [
    TextField(
      key: const Key('customer-search'),
      controller: _search,
      decoration: const InputDecoration(
        labelText: 'بحث',
        helperText: 'اسم العميل أو رقم الهاتف',
        prefixIcon: Icon(Icons.search),
      ),
      onChanged: (_) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 350), () => _reload());
      },
    ),
    const SizedBox(height: 16),
    DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: _sort,
      decoration: const InputDecoration(labelText: 'الترتيب'),
      items: const [
        DropdownMenuItem(value: 'name', child: Text('الاسم')),
        DropdownMenuItem(value: 'last_operation', child: Text('آخر عملية')),
      ],
      onChanged: _loading
          ? null
          : (v) {
              if (v != null) setState(() => _sort = v);
              _reload();
            },
    ),
    const SizedBox(height: 8),
    Wrap(
      spacing: 8,
      children: [
        for (final entry in const {
          'active': 'العملاء',
          'archived': 'المؤرشفون',
          'vip': 'المميزون',
          'open_request': 'طلبات مفتوحة',
          'all': 'الكل',
        }.entries)
          FilterChip(
            label: Text(entry.value),
            selected: _filter == entry.key,
            onSelected: _loading
                ? null
                : (_) {
                    setState(() => _filter = entry.key);
                    _reload();
                  },
          ),
      ],
    ),
    if (!_readOnly)
      _action(
        'إضافة عميل جديد',
        _blocked ? null : () => _edit(),
        key: const Key('customer-create'),
        primary: true,
      ),
    if (_items.isEmpty && !_loading)
      const Padding(
        padding: EdgeInsets.all(24),
        child: Text('لا توجد ملفات مطابقة. يمكنك تغيير البحث أو إضافة عميل.'),
      ),
    ..._items.map(_card),
    if (_cursor != null)
      _action(
        'عرض المزيد من العملاء',
        _loading ? null : () => _reload(older: true),
      ),
  ];
  List<Widget> _editForm() => [
    Form(
      key: _form,
      child: Column(
        children: [
          TextFormField(
            key: const Key('customer-name'),
            controller: _name,
            enabled: !_blocked,
            decoration: const InputDecoration(labelText: 'اسم العميل'),
            validator: (v) => validCustomerName((v ?? '').trim())
                ? null
                : customerError('invalid_name'),
          ),
          _heading('أرقام الهاتف'),
          const Text(
            'يمكن حفظ العميل بدون هاتف. اختر رقمًا أساسيًا عند إضافة الأرقام.',
          ),
          for (var i = 0; i < _phones.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  TextFormField(
                    key: Key('customer-phone-$i'),
                    controller: _phones[i].controller,
                    enabled: !_blocked,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: 'رقم الهاتف ${i + 1}',
                      helperText: 'رقم مصري محلي أو رقم دولي يبدأ بـ +',
                      helperMaxLines: 3,
                      errorMaxLines: 3,
                    ),
                    validator: (v) =>
                        normalizeCustomerPhone((v ?? '').trim()) == null
                        ? customerError('invalid_phone')
                        : null,
                  ),
                  Row(
                    children: [
                      Checkbox(
                        value: _phones[i].primary,
                        onChanged: _blocked
                            ? null
                            : (v) => setState(() {
                                for (final p in _phones) {
                                  p.primary = false;
                                }
                                _phones[i].primary = true;
                              }),
                      ),
                      const Expanded(child: Text('الرقم الأساسي')),
                      IconButton(
                        tooltip: 'إزالة رقم الهاتف',
                        onPressed: _blocked
                            ? null
                            : () => setState(() {
                                final removed = _phones.removeAt(i);
                                removed.controller.dispose();
                                if (removed.primary && _phones.isNotEmpty) {
                                  _phones.first.primary = true;
                                }
                              }),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (_phones.length < 10)
            _action(
              'إضافة رقم هاتف',
              _blocked
                  ? null
                  : () => setState(
                      () => _phones.add(_PhoneDraft('', _phones.isEmpty)),
                    ),
              key: const Key('customer-add-phone'),
            ),
          const SizedBox(height: 16),
          _action(
            'حفظ العميل',
            _blocked || _stale ? null : _saveEdit,
            key: const Key('customer-save'),
            primary: true,
          ),
        ],
      ),
    ),
  ];
  Widget _operationCard(Map<String, Object?> op, {VoidCallback? tap}) => Card(
    child: ListTile(
      onTap: tap,
      title: Text('${op['label_ar']} · رقم ${op['shop_sequence']}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(op['party_name'] as String? ?? 'الطرف غير مسجل في العملية'),
          if (op['party_phone'] != null) _contact(op['party_phone'] as String),
          Text(customerDate(op['operation_created_at_shop'] as String)),
          if (op['link_status'] == 'unlinked') const Text('ارتباط تم تصحيحه'),
          if (op['linked_at_shop'] != null)
            Text(
              'تاريخ الربط: ${customerDate(op['linked_at_shop'] as String)}',
            ),
        ],
      ),
    ),
  );
  List<Widget> _detailWidgets() {
    final d = _detail;
    if (d == null) return [];
    final c = d.customer;
    return [
      _card(c, clickable: false),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: !_canContact || _loading || c.phones.isEmpty
                ? null
                : () => _prepareContact(c, CustomerContactAction.dialer),
            icon: const Icon(Icons.phone_outlined),
            label: const Text('الاتصال'),
          ),
          OutlinedButton.icon(
            onPressed: !_canContact || _loading || c.phones.isEmpty
                ? null
                : () => _prepareContact(c, CustomerContactAction.whatsapp),
            icon: const CustomerWhatsappIcon(),
            label: const Text('واتساب'),
          ),
        ],
      ),
      if (c.phones.isEmpty)
        const Text(
          'أضف رقم هاتف من تعديل بيانات العميل عند توفر صلاحية التعديل.',
        ),
      ..._statisticsWidgets(c),
      _heading('بيانات العميل'),
      if (c.phones.isEmpty)
        const Text('حالة حفظ الرقم لواتساب غير متاحة؛ بدون هاتف.'),
      for (final p in c.phones)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _contact(p.normalized),
              if (p.primary) const Text('الرقم الأساسي'),
              Text(savedNumberLabel(p.saved?.state)),
              if (p.saved?.declaredAtShop != null)
                Text(
                  '${p.saved!.actorName} · ${customerDate(p.saved!.declaredAtShop!)}',
                ),
              if (!_readOnly && p.saved != null)
                _action(
                  'تحديد حالة حفظ الرقم لواتساب',
                  _blocked ? null : () => _prepareSaved(p),
                  key: Key('saved-number-${p.saved!.id}'),
                ),
            ],
          ),
        ),
      Text('آخر تحديث للملف: ${customerDate(c.updatedAtShop)}'),
      if (!_readOnly)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _action('تعديل بيانات العميل', _blocked ? null : () => _edit(c)),
            _action(
              'حالة العميل',
              _blocked
                  ? null
                  : () => setState(() {
                      _vip = c.vip;
                      _open = c.openRequest;
                      _stage = 'status';
                      _stale = false;
                    }),
            ),
            _action(
              'إضافة ملاحظة',
              _blocked
                  ? null
                  : () => setState(() {
                      _note.clear();
                      _stage = 'note';
                      _stale = false;
                    }),
            ),
            if (!c.archived)
              _action(
                'ربط عملية مؤكدة',
                _blocked
                    ? null
                    : () {
                        _candidateSearch.clear();
                        _candidates = [];
                        _stale = false;
                        _loadCandidates();
                      },
              ),
            _action(
              c.archived ? 'استعادة الملف' : 'أرشفة الملف',
              _blocked
                  ? null
                  : () => setState(() {
                      _review = _payload(
                        c.archived ? 'customer_restore' : 'customer_archive',
                      );
                      _stage = 'review';
                      _stale = false;
                    }),
            ),
          ],
        ),
      _heading('الملاحظات'),
      if (d.notes.items.isEmpty) const Text('لا توجد ملاحظات.'),
      for (final n in d.notes.items)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(n['body'] as String),
                Text(
                  '${customerDate(n['created_at_shop'] as String)} · ${n['actor_display_name']}',
                ),
              ],
            ),
          ),
        ),
      if (d.notes.cursor != null)
        _action('عرض ملاحظات أقدم', _loading ? null : () => _more('notes')),
      _heading('العمليات المرتبطة'),
      if (d.links.items.isEmpty)
        const Text('لا توجد عمليات مرتبطة بهذا العميل.'),
      for (final op in d.links.items)
        Column(
          children: [
            _operationCard(op),
            if (op['link_status'] == 'active' && !_readOnly)
              _action(
                'تصحيح الارتباط',
                _blocked
                    ? null
                    : () => setState(() {
                        _operation = op;
                        _review = {
                          ..._payload('customer_unlink'),
                          'operation_id': op['operation_id'],
                        };
                        _stage = 'review';
                        _stale = false;
                      }),
              ),
          ],
        ),
      if (d.links.cursor != null)
        _action('عرض عمليات أقدم', _loading ? null : () => _more('links')),
      _heading('سجل التغييرات'),
      for (final event in d.history.items)
        Card(
          child: ListTile(
            title: Text(_events[event['event_type']]!),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${customerDate(event['created_at_shop'] as String)} · ${event['actor_display_name']}',
                ),
                if (event['event_type'] == 'status_changed')
                  Text(
                    'مميز: ${(event['payload'] as Map)['is_vip'] == true ? 'نعم' : 'لا'} · طلب مفتوح: ${(event['payload'] as Map)['has_open_request'] == true ? 'نعم' : 'لا'}',
                  ),
                if (event['event_type'] == 'edited')
                  Text(
                    'الاسم المسجل: ${(event['payload'] as Map)['display_name']}',
                  ),
                if (event['event_type'] == 'saved_number_changed') ...[
                  _contact(
                    (event['payload'] as Map)['normalized_number'] as String,
                  ),
                  Text(
                    savedNumberLabel(
                      (event['payload'] as Map)['state'] as String,
                    ),
                  ),
                ],
                if (event['event_type'] == 'edited')
                  ExpansionTile(
                    title: const Text('تفاصيل تعديل الاسم والهاتف'),
                    children: [
                      if ((event['payload'] as Map)['before'] is Map)
                        Text(
                          'الاسم السابق: ${((event['payload'] as Map)['before'] as Map)['display_name']}',
                        ),
                      const Text('أرقام الهاتف المسجلة بعد التعديل'),
                      for (final phone
                          in ((event['payload'] as Map)['phones'] as List? ??
                              []))
                        if (phone is Map && phone['normalized'] is String)
                          _contact(phone['normalized'] as String),
                    ],
                  ),
              ],
            ),
          ),
        ),
      if (d.history.cursor != null)
        _action('عرض تغييرات أقدم', _loading ? null : () => _more('history')),
    ];
  }

  List<Widget> _content() => switch (_stage) {
    'list' => _list(),
    'edit' => _editForm(),
    'detail' => _detailWidgets(),
    'contact' => _contactWidgets(),
    'saved_preparing' => [const Text('جارٍ تجهيز حالة الرقم الحالية…')],
    'saved' => [
      _heading('حالة حفظ الرقم لواتساب'),
      if (_savedPhone != null) _contact(_savedPhone!.normalized),
      const Text(
        'إقرار من المالك؛ لا يتحقق التطبيق من واتساب أو جهات اتصال الجهاز.',
      ),
      RadioGroup<String>(
        groupValue: _savedState,
        onChanged: (v) {
          if (!_blocked && !_stale && v != null) {
            setState(() => _savedState = v);
          }
        },
        child: Column(
          children: [
            for (final state in savedNumberStates)
              RadioListTile<String>(
                value: state,
                title: Text(
                  state == 'unknown'
                      ? 'مسح الإقرار — لم يحدد المالك الحالة'
                      : savedNumberLabel(state),
                ),
                enabled: !_blocked && !_stale,
              ),
          ],
        ),
      ),
      _action(
        'مراجعة إقرار المالك',
        _blocked || _stale || _savedPhone == null
            ? null
            : () => setState(() {
                _review = {
                  ..._payload('customer_saved_number'),
                  'number_id': _savedPhone!.saved!.id,
                  'normalized_number': _savedPhone!.normalized,
                  'state': _savedState,
                };
                _stage = 'review';
              }),
        primary: true,
      ),
    ],
    'note' => [
      TextField(
        key: const Key('customer-note'),
        controller: _note,
        enabled: !_blocked,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: 'ملاحظة جديدة',
          helperText: 'تُحفظ بتاريخها دون تعديل الملاحظات السابقة.',
        ),
      ),
      _action(
        'حفظ الملاحظة',
        _blocked || _stale
            ? null
            : () {
                final note = _note.text.trim();
                if (!validCustomerNote(note)) {
                  setState(() => _error = 'invalid_input');
                  return;
                }
                _send({..._payload('customer_note'), 'body': note});
              },
        primary: true,
      ),
    ],
    'status' => [
      SwitchListTile(
        title: const Text('عميل مميز'),
        value: _vip,
        onChanged: _blocked ? null : (v) => setState(() => _vip = v),
      ),
      SwitchListTile(
        title: const Text('طلب مفتوح'),
        value: _open,
        onChanged: _blocked ? null : (v) => setState(() => _open = v),
      ),
      _action(
        'حفظ الحالة',
        _blocked || _stale
            ? null
            : () => _send({
                ..._payload('customer_status'),
                'is_vip': _vip,
                'has_open_request': _open,
              }),
        primary: true,
      ),
    ],
    'candidates' => [
      TextField(
        controller: _candidateSearch,
        decoration: const InputDecoration(
          labelText: 'بحث في العمليات المؤكدة',
          helperText: 'الطرف أو الهاتف أو رقم العملية',
        ),
        onSubmitted: (_) => _loadCandidates(),
      ),
      _action('بحث', _loading ? null : () => _loadCandidates()),
      if (_candidates.isEmpty && !_loading)
        const Text('لا توجد عمليات بيع أو شراء غير مرتبطة مطابقة.'),
      ..._candidates.map(
        (op) => _operationCard(
          op,
          tap: _blocked || _stale
              ? null
              : () => setState(() {
                  _operation = op;
                  _review = {
                    ..._payload('customer_link'),
                    'operation_id': op['operation_id'],
                  };
                  _stage = 'review';
                }),
        ),
      ),
      if (_candidateCursor != null)
        _action(
          'عرض عمليات أقدم',
          _loading ? null : () => _loadCandidates(older: true),
        ),
    ],
    'review' => [
      _heading('مراجعة التغيير'),
      if (_detail != null) Text('العميل: ${_detail!.customer.name}'),
      if (_operation != null) _operationCard(_operation!),
      if (_review?['kind'] == 'customer_saved_number') ...[
        _contact(_review!['normalized_number'] as String),
        Text(savedNumberLabel(_review!['state'] as String)),
        const Text(
          'هذا إقرار من المالك، وليس تحققًا تلقائيًا من واتساب أو الجهاز.',
        ),
      ],
      Text(switch (_review?['kind']) {
        'customer_link' => 'سيُربط هذا البيع أو الشراء بالعميل الذي اخترته.',
        'customer_unlink' => 'سيُلغى الارتباط الحالي مع الاحتفاظ بسجله.',
        'customer_archive' =>
          'سيُخفى الملف من القائمة المعتادة ويمكن استعادته لاحقًا.',
        'customer_restore' => 'سيعود الملف إلى قائمة العملاء.',
        _ => '',
      }),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'لا يتغير النقد أو الذهب أو المخزون أو الديون. بيانات العملية والفاتورة الأصلية تبقى محفوظة.',
        ),
      ),
      _action(
        'تأكيد التغيير',
        _blocked || _stale || _review == null ? null : () => _send(_review!),
        key: const Key('customer-confirm'),
        primary: true,
      ),
    ],
    'success' => [
      Icon(
        Icons.check_circle_outline,
        size: 48,
        color: Theme.of(context).colorScheme.tertiary,
      ),
      Text(
        'تم تأكيد التغيير وحفظه',
        key: const Key('customer-success'),
        style: Theme.of(context).textTheme.titleLarge,
      ),
      if (_detail != null) Text(_detail!.customer.name),
      _action(
        'عرض ملف العميل',
        _pending != null || _detail == null
            ? null
            : () => _openCustomer(_detail!.customer),
      ),
      _action(
        'قائمة العملاء',
        _pending != null
            ? null
            : () {
                setState(() => _stage = 'list');
                _reload();
              },
      ),
    ],
    _ => [],
  };
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _stage == 'list' && !_busy,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop && !_busy) _back();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          _stage == 'list'
              ? 'العملاء'
              : _stage == 'edit'
              ? _editId == null
                    ? 'إضافة عميل'
                    : 'تعديل العميل'
              : 'ملف العميل',
        ),
        leading: _stage == 'list'
            ? null
            : IconButton(
                tooltip: 'رجوع',
                onPressed: _busy ? null : _back,
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
              padding: const EdgeInsets.all(16),
              children: [
                if (_readOnly)
                  Text(
                    _accessLost
                        ? 'انتهى الوصول إلى المحل؛ سجّل الدخول مرة أخرى.'
                        : 'انتهى الاشتراك؛ ملفات العملاء للقراءة فقط.',
                  ),
                if (_pending != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Text(
                            'طلب محفوظ بانتظار التحقق من الخادم. لا تنشئ طلبًا آخر.',
                            key: Key('customer-pending'),
                          ),
                          _action(
                            'التحقق وإعادة المحاولة',
                            _busy ? null : _retry,
                            key: const Key('customer-retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_foreign)
                  const Text(
                    'يوجد طلب محفوظ في قسم آخر. افتح القسم المختص للتحقق منه.',
                  ),
                if (_stale)
                  const Text(
                    'تغيّر الملف أثناء المراجعة. ارجع إلى التفاصيل ثم أعد المراجعة؛ لم تُحفظ المسودة.',
                  ),
                if (_error != null)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      customerError(_error),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (_error != null && {'list', 'detail'}.contains(_stage))
                  _action('إعادة المحاولة', _loading ? null : () => _reload()),
                if (_loading || _busy) const LinearProgressIndicator(),
                ..._content(),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
