import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/application/pending_financial_command.dart';
import '../application/branded_invoice_pdf.dart';
import '../application/invoice_appearance_contract.dart';
import '../application/invoice_copy_files.dart';
import '../application/invoice_appearance_flow.dart';
import '../application/invoice_appearance_gateway.dart';
import '../application/logo_codec.dart';
import '../data/logo_upload_store.dart';
import '../domain/appearance_rules.dart';
import '../domain/branded_invoice_document.dart';
import '../domain/logo_bytes.dart';

/// Owner invoice appearance. Review, then save. No tour or guide card.
class InvoiceAppearanceScreen extends StatefulWidget {
  const InvoiceAppearanceScreen({
    super.key,
    required this.gateway,
    required this.store,
    required this.userId,
    required this.shopId,
    required this.canRead,
    required this.canWrite,
    this.logoStore = const FileLogoUploadStore(),
    this.syncTicks,
    this.pickLogo,
    this.newKey,
  });

  final InvoiceAppearanceGateway gateway;
  final FinancialCommandLocker store;
  final LogoUploadStore logoStore;
  final String userId;
  final String shopId;
  final bool Function() canRead;
  final bool Function() canWrite;
  final Listenable? syncTicks;
  final Future<Uint8List?> Function()? pickLogo;
  final String Function()? newKey;

  @override
  State<InvoiceAppearanceScreen> createState() =>
      _InvoiceAppearanceScreenState();
}

enum _AppearancePhase {
  loading,
  draft,
  review,
  submitting,
  unknown,
  confirmed,
  failure,
  stale,
  uploadPending,
  uploadFailure,
  expired,
  accessLoss,
}

class _InvoiceAppearanceScreenState extends State<InvoiceAppearanceScreen> {
  final _slogan = TextEditingController();
  final _address = TextEditingController();
  var _phase = _AppearancePhase.loading;
  var _template = InvoiceTemplate.header;
  var _accent = InvoiceAccent.brown;
  var _savedRevision = 0;
  var _expectedRevision = 0;
  String? _logoAssetId;
  String? _logoSha256;
  String? _message;
  PendingFinancialCommand? _command;
  Map<String, Object?>? _reviewPayload;
  var _copiesCleared = false;

  void _loseAccess() {
    if (!_copiesCleared) {
      _copiesCleared = true;
      unawaited(const InvoiceCopyFiles().clear());
    }
    _phase = _AppearancePhase.accessLoss;
    _message = 'لم يعد هذا الحساب يصل إلى المتجر.';
  }

  var _busy = false;
  var _generation = 0;
  var _logoGeneration = 0;
  var _dirty = false;

  InvoiceAppearanceFlow get _flow =>
      InvoiceAppearanceFlow(widget.gateway, widget.store);

  @override
  void initState() {
    super.initState();
    widget.syncTicks?.addListener(_onSync);
    if (!widget.canRead()) {
      _loseAccess();
    } else {
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(covariant InvoiceAppearanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncTicks != widget.syncTicks) {
      oldWidget.syncTicks?.removeListener(_onSync);
      widget.syncTicks?.addListener(_onSync);
    }
    if (oldWidget.userId != widget.userId ||
        oldWidget.shopId != widget.shopId) {
      _generation++;
      _logoGeneration++;
      _command = null;
      _loseAccess();
    }
  }

  @override
  void dispose() {
    widget.syncTicks?.removeListener(_onSync);
    _slogan.dispose();
    _address.dispose();
    super.dispose();
  }

  bool get _alive => mounted && widget.canRead() && widget.userId.isNotEmpty;

  void _onSync() {
    if (!_alive || _busy || _phase == _AppearancePhase.submitting) return;
    unawaited(_load(keepDraft: _dirty || _phase == _AppearancePhase.unknown));
  }

  Future<void> _load({bool keepDraft = false}) async {
    final generation = ++_generation;
    if (!widget.canRead()) {
      if (mounted) setState(_loseAccess);
      return;
    }
    if (!keepDraft && mounted) {
      setState(() => _phase = _AppearancePhase.loading);
    }
    try {
      final pending = await widget.store.read(widget.userId, widget.shopId);
      if (!_alive || generation != _generation) return;
      if (pending != null && pending.kind == invoiceAppearanceKind) {
        _restore(pending);
        setState(() {
          _command = pending;
          _phase = _AppearancePhase.unknown;
          _message =
              'طلب مظهر فاتورة بانتظار التأكيد. أعد التحقق دون تغيير البيانات.';
        });
        return;
      }
      final snapshot = await widget.gateway.readAppearance(
        userId: widget.userId,
        shopId: widget.shopId,
      );
      final upload = await widget.logoStore.read(widget.userId, widget.shopId);
      if (!_alive || generation != _generation) return;
      if (snapshot.shopId != widget.shopId) {
        setState(_loseAccess);
        return;
      }
      if (!keepDraft) {
        _applySaved(snapshot.value);
        _dirty = false;
      } else if (snapshot.value.revision != _savedRevision) {
        _savedRevision = snapshot.value.revision;
        _phase = _AppearancePhase.stale;
        _message = 'تغيّرت المراجعة المحفوظة. راجع الحقول ثم احفظ من جديد.';
        setState(() {});
        return;
      }
      var phase = widget.canWrite()
          ? _AppearancePhase.draft
          : _AppearancePhase.expired;
      var message = snapshot.value.revision == 0
          ? 'لم يُحفظ مظهر بعد'
          : 'المراجعة المحفوظة: ${snapshot.value.revision}';
      if (upload?.phase == LogoUploadPhase.uploadPending ||
          upload?.phase == LogoUploadPhase.confirmPending) {
        phase = _AppearancePhase.uploadPending;
        message = upload!.phase == LogoUploadPhase.confirmPending
            ? 'رُفع الملف ولم يؤكد الخادم الشعار بعد.'
            : 'رفع الشعار لم يكتمل. لم يُحفظ.';
      } else if (upload?.phase == LogoUploadPhase.failed) {
        phase = _AppearancePhase.uploadFailure;
        message = upload?.message ?? 'تعذر حفظ الشعار.';
      }
      if (!widget.canWrite()) {
        phase = _AppearancePhase.expired;
        message = 'انتهى الاشتراك. يمكن قراءة المظهر دون حفظ جديد.';
      }
      setState(() {
        _phase = phase;
        _message = message;
      });
    } on InvoiceAppearanceException catch (error) {
      if (!_alive || generation != _generation) return;
      if (error.code == 'session_expired' || error.code == 'forbidden') {
        setState(_loseAccess);
        return;
      }
      setState(() {
        _phase = _AppearancePhase.failure;
        _message = _failureText(error.code);
      });
    } catch (_) {
      if (!_alive || generation != _generation) return;
      setState(() {
        _phase = _AppearancePhase.failure;
        _message = 'تعذر تحميل مظهر الفاتورة. أعد المحاولة.';
      });
    }
  }

  void _applySaved(InvoiceAppearanceValue value) {
    _savedRevision = value.revision;
    _expectedRevision = value.revision;
    _template = value.template;
    _accent = value.accent;
    _slogan.text = value.slogan ?? '';
    _address.text = value.address ?? '';
    _logoAssetId = value.logoAssetId;
    _logoSha256 = value.logoSha256;
    _reviewPayload = null;
  }

  void _restore(PendingFinancialCommand command) {
    final payload = Map<String, Object?>.from(command.body['p_payload'] as Map);
    _template = InvoiceTemplate.parse(payload['template']) ?? _template;
    _accent = InvoiceAccent.parse(payload['accent']) ?? _accent;
    _slogan.text = payload['slogan'] as String? ?? '';
    _address.text = payload['address'] as String? ?? '';
    _logoAssetId = payload['logo_asset_id'] as String?;
    _expectedRevision = int.parse(payload['expected_revision'] as String);
    _reviewPayload = payload;
    _dirty = true;
  }

  Map<String, Object?> _payload() => appearanceCommandPayload(
    expectedRevision: _expectedRevision,
    template: _template,
    accent: _accent,
    slogan: _slogan.text,
    address: _address.text,
    logoAssetId: _logoAssetId,
  );

  Future<void> _review() async {
    if (_busy || !widget.canWrite()) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _phase = _AppearancePhase.review;
      _message = 'جارٍ مراجعة المظهر...';
    });
    try {
      final payload = _payload();
      final review = await widget.gateway.reviewAppearance(
        userId: widget.userId,
        shopId: widget.shopId,
        payload: payload,
      );
      if (!_alive || generation != _generation) return;
      if (review.status == 'stale') {
        _savedRevision = review.currentRevision;
        setState(() {
          _phase = _AppearancePhase.stale;
          _message = 'تغيّرت المراجعة المحفوظة. راجع الحقول ثم احفظ من جديد.';
        });
        return;
      }
      if (review.status == 'expired' || !review.canWrite) {
        setState(() {
          _phase = _AppearancePhase.expired;
          _message = 'انتهى الاشتراك. يمكن قراءة المظهر دون حفظ جديد.';
        });
        return;
      }
      setState(() {
        _reviewPayload = payload;
        _phase = _AppearancePhase.review;
        _message = 'راجع الحقول ثم احفظ. لن يُنشأ مستند مالي.';
      });
    } on InvoiceAppearanceException catch (error) {
      if (!_alive || generation != _generation) return;
      setState(() {
        _phase = _AppearancePhase.failure;
        _message = _failureText(error.code);
      });
    } catch (_) {
      if (!_alive || generation != _generation) return;
      setState(() {
        _phase = _AppearancePhase.failure;
        _message = 'تعذر مراجعة المظهر. المسودة ما زالت هنا.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final payload = _reviewPayload;
    if (_busy || payload == null || !widget.canWrite()) return;
    final generation = _generation;
    final key = _command?.key ?? (widget.newKey ?? newIdempotencyKey)();
    setState(() {
      _busy = true;
      _phase = _AppearancePhase.submitting;
      _message = 'جارٍ حفظ مظهر الفاتورة...';
    });
    final outcome = await _flow.submitAppearance(
      widget.userId,
      widget.shopId,
      key,
      payload,
      canWrite: widget.canWrite(),
    );
    if (!_alive || generation != _generation) return;
    _applyOutcome(outcome);
  }

  Future<void> _retry() async {
    final command = _command;
    if (_busy || command == null) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _phase = _AppearancePhase.submitting;
    });
    final outcome = await _flow.reconcile(
      widget.userId,
      widget.shopId,
      command,
      retry: true,
      canWrite: widget.canWrite(),
    );
    if (!_alive || generation != _generation) return;
    _applyOutcome(outcome);
  }

  void _applyOutcome(InvoiceCommandOutcome outcome) {
    if (outcome.receipt != null && outcome.error == null) {
      _command = null;
      _savedRevision = outcome.receipt!.revision ?? _savedRevision;
      _expectedRevision = _savedRevision;
      _dirty = false;
      _reviewPayload = null;
      setState(() {
        _busy = false;
        _phase = _AppearancePhase.confirmed;
        _message =
            'حُفظت المراجعة $_savedRevision. لم تتغير العمليات أو الإرسال.';
      });
      return;
    }
    if (outcome.pending != null && outcome.error == null) {
      _command = outcome.pending;
      setState(() {
        _busy = false;
        _phase = _AppearancePhase.unknown;
        _message = 'تعذر تأكيد الحفظ. أعد التحقق من الطلب نفسه.';
      });
      return;
    }
    if (outcome.error == 'stale_appearance') {
      setState(() {
        _busy = false;
        _command = null;
        _phase = _AppearancePhase.stale;
        _message = 'تغيّرت المراجعة المحفوظة. راجع الحقول ثم احفظ من جديد.';
      });
      return;
    }
    if (outcome.error == 'shop_not_active') {
      setState(() {
        _busy = false;
        _phase = _AppearancePhase.expired;
        _message = 'انتهى الاشتراك. لم يُحفظ تغيير جديد.';
      });
      return;
    }
    if (outcome.error == 'discarded' || outcome.error == 'session_expired') {
      setState(() {
        _busy = false;
        _phase = _AppearancePhase.accessLoss;
        _message = 'تغيّر الحساب أو انقطع الوصول. أُلغي عرض هذه المسودة.';
      });
      return;
    }
    setState(() {
      _busy = false;
      _command = outcome.pending;
      _phase = outcome.pending == null
          ? _AppearancePhase.failure
          : _AppearancePhase.unknown;
      _message = _failureText(outcome.error);
    });
  }

  Future<void> _pickLogo() async {
    if (_busy || !widget.canWrite()) return;
    final picker = widget.pickLogo;
    final selected = picker == null ? await _platformPick() : await picker();
    if (selected == null || !_alive) return;
    final generation = ++_logoGeneration;
    try {
      final prepared = await prepareLogo(selected);
      if (!_alive || generation != _logoGeneration) return;
      final record = LogoUploadRecord(
        phase: LogoUploadPhase.uploadPending,
        sha256: prepared.sha256,
        mime: prepared.facts.mime,
        objectName: prepared.objectName(widget.shopId),
      );
      await widget.logoStore.save(
        widget.userId,
        widget.shopId,
        record,
        prepared.bytes,
      );
      if (!_alive || generation != _logoGeneration) return;
      setState(() {
        _phase = _AppearancePhase.uploadPending;
        _message = 'رفع الشعار لم يكتمل. لم يُحفظ.';
        _dirty = true;
      });
      final upload = await widget.gateway.uploadInvoiceLogo(
        userId: widget.userId,
        shopId: widget.shopId,
        objectName: record.objectName,
        mimeType: prepared.facts.mime,
        bytes: prepared.bytes,
      );
      if (!_alive || generation != _logoGeneration) return;
      if (upload.disposition == LogoUploadDisposition.unknown) {
        setState(() => _message = 'رفع الشعار لم يكتمل. لم يُحفظ.');
        return;
      }
      if (upload.disposition == LogoUploadDisposition.rejected) {
        await widget.logoStore.save(
          widget.userId,
          widget.shopId,
          LogoUploadRecord(
            phase: LogoUploadPhase.failed,
            sha256: prepared.sha256,
            mime: prepared.facts.mime,
            objectName: record.objectName,
            message: 'تعذر حفظ الشعار.',
          ),
          prepared.bytes,
        );
        setState(() {
          _phase = _AppearancePhase.uploadFailure;
          _message = 'تعذر حفظ الشعار.';
        });
        return;
      }
      await widget.logoStore.save(
        widget.userId,
        widget.shopId,
        LogoUploadRecord(
          phase: LogoUploadPhase.confirmPending,
          sha256: prepared.sha256,
          mime: prepared.facts.mime,
          objectName: record.objectName,
        ),
        prepared.bytes,
      );
      setState(() => _message = 'رُفع الملف ولم يؤكد الخادم الشعار بعد.');
      final confirmed = await widget.gateway.confirmInvoiceLogo(
        userId: widget.userId,
        shopId: widget.shopId,
        base64Bytes: base64Encode(prepared.bytes),
        sha256: prepared.sha256,
      );
      if (!_alive || generation != _logoGeneration) return;
      if (confirmed.shopId != widget.shopId ||
          confirmed.sha256 != prepared.sha256) {
        setState(() {
          _phase = _AppearancePhase.uploadFailure;
          _message = 'تعذر حفظ الشعار.';
        });
        return;
      }
      await widget.logoStore.save(
        widget.userId,
        widget.shopId,
        LogoUploadRecord(
          phase: LogoUploadPhase.confirmed,
          sha256: confirmed.sha256,
          mime: confirmed.mime,
          objectName: record.objectName,
          assetId: confirmed.assetId,
        ),
        prepared.bytes,
      );
      setState(() {
        _logoAssetId = confirmed.assetId;
        _logoSha256 = confirmed.sha256;
        _phase = _AppearancePhase.draft;
        _reviewPayload = null;
        _message =
            'تم التحقق من الشعار على الخادم. لن يظهر في النسخ إلا بعد حفظ المظهر.';
      });
    } on LogoByteRejection {
      if (!_alive || generation != _logoGeneration) return;
      setState(() {
        _phase = _AppearancePhase.uploadFailure;
        _message = 'تعذر قبول الشعار. استخدم صورة PNG أو JPEG ضمن الحد.';
      });
    } on InvoiceAppearanceException catch (error) {
      if (!_alive || generation != _logoGeneration) return;
      setState(() {
        _phase = error.code == null
            ? _AppearancePhase.uploadPending
            : _AppearancePhase.uploadFailure;
        _message = error.code == null
            ? 'رُفع الملف ولم يؤكد الخادم الشعار بعد.'
            : 'تعذر حفظ الشعار.';
      });
    }
  }

  Future<Uint8List?> _platformPick() async {
    const group = XTypeGroup(
      label: 'شعار',
      extensions: ['png', 'jpg', 'jpeg'],
      mimeTypes: ['image/png', 'image/jpeg'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return null;
    return file.readAsBytes();
  }

  Future<void> _clearLogo() async {
    _logoGeneration++;
    final current = await widget.logoStore.read(widget.userId, widget.shopId);
    if (current != null && current.phase != LogoUploadPhase.confirmed) {
      await widget.logoStore.clear(widget.userId, widget.shopId);
    }
    if (!mounted) return;
    setState(() {
      _logoAssetId = null;
      _logoSha256 = null;
      _dirty = true;
      _reviewPayload = null;
      _phase = widget.canWrite()
          ? _AppearancePhase.draft
          : _AppearancePhase.expired;
      _message =
          'سيُزال الشعار من المظهر الجديد دون حذف النسخ أو ملفات الشعار السابقة.';
    });
  }

  Future<void> _synthetic() async {
    final document = BrandedInvoiceDocument(
      operationId: '00000000-0000-4000-8000-000000000000',
      kind: 'sale',
      shopName: 'متجر المعاينة',
      shopSequence: '0',
      occurredAtUtc: '2026-10-17T00:00:00.000000Z',
      occurredAtShop: '2026-10-17T00:00:00',
      copyCreatedAtUtc: '2026-10-17T00:00:00.000000Z',
      copyCreatedAtShop: '2026-10-17T00:00:00',
      timeZone: 'Africa/Cairo',
      edition: 0,
      contentSha256: '0' * 64,
      appearanceRevision: _savedRevision,
      template: _template,
      accent: _accent,
      renderVersion: 1,
      lines: const [
        BrandedInvoiceLine(
          category: 'worked_jewelry',
          categoryLabel: 'مشغولات',
          karat: 21,
          milligrams: '1000',
          gramsText: '1.000',
          itemName: 'صنف معاينة',
        ),
      ],
      tenders: const [
        BrandedTender(method: 'cash', methodLabel: 'نقدي', piastres: '100'),
      ],
      logoRequired: false,
      slogan: normalizeSlogan(_slogan.text),
      address: normalizeAddress(_address.text),
      totalPiastres: '100',
      synthetic: true,
    );
    Uint8List? bytes;
    try {
      bytes = await buildBrandedInvoicePdf(document);
    } catch (_) {
      bytes = null;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('appearance-synthetic-dialog'),
        title: const Text('معاينة تجريبية لا تُنشئ عملية أو إرسالاً'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('القالب: ${_templateLabel(_template)}'),
              Text('اللون: ${_accentLabel(_accent)}'),
              Text(_slogan.text.trim().isEmpty ? 'بلا شعار نصي' : _slogan.text),
              Text(_address.text.trim().isEmpty ? 'بلا عنوان' : _address.text),
              Text(
                bytes == null
                    ? 'تعذر تجهيز المعاينة. أعد المحاولة.'
                    : 'هذه معاينة فقط. لم يُحفظ الملف ولم يُرسل.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final readOnly =
        !widget.canWrite() ||
        _phase == _AppearancePhase.expired ||
        _phase == _AppearancePhase.accessLoss ||
        _phase == _AppearancePhase.submitting ||
        _phase == _AppearancePhase.unknown;
    final buttonStyle = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(AppTokens.minControlSize),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('مظهر الفاتورة')),
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
                Text(
                  key: const Key('appearance-status'),
                  _message ?? _phaseLabel(_phase),
                ),
                Text(
                  key: const Key('appearance-revision'),
                  _savedRevision == 0
                      ? 'لم يُحفظ مظهر بعد'
                      : 'المراجعة المحفوظة: $_savedRevision',
                ),
                if (_phase == _AppearancePhase.loading)
                  const LinearProgressIndicator(key: Key('appearance-loading')),
                if (_phase == _AppearancePhase.accessLoss)
                  const Text('لم يعد هذا الحساب يصل إلى المتجر.')
                else ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('appearance-slogan'),
                    controller: _slogan,
                    enabled: !readOnly,
                    maxLength: invoiceSloganMax,
                    decoration: const InputDecoration(labelText: 'الشعار'),
                    onChanged: (_) => setState(_markDirty),
                  ),
                  TextField(
                    key: const Key('appearance-address'),
                    controller: _address,
                    enabled: !readOnly,
                    maxLength: invoiceAddressMax,
                    minLines: 2,
                    maxLines: invoiceAddressMaxLines,
                    decoration: const InputDecoration(labelText: 'العنوان'),
                    onChanged: (_) => setState(_markDirty),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<InvoiceTemplate>(
                    selected: {_template},
                    onSelectionChanged: readOnly
                        ? null
                        : (value) => setState(() {
                            _template = value.first;
                            _markDirty();
                          }),
                    segments: const [
                      ButtonSegment(
                        value: InvoiceTemplate.header,
                        label: Text('رأس ملون'),
                      ),
                      ButtonSegment(
                        value: InvoiceTemplate.compact,
                        label: Text('موجز'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final accent in InvoiceAccent.values)
                        ChoiceChip(
                          key: Key('appearance-accent-${accent.wire}'),
                          label: Text(_accentLabel(accent)),
                          selected: _accent == accent,
                          onSelected: readOnly
                              ? null
                              : (_) => setState(() {
                                  _accent = accent;
                                  _markDirty();
                                }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _logoAssetId == null || _logoSha256 == null
                        ? 'بلا شعار'
                        : 'شعار مرتبط بهذه المراجعة',
                  ),
                  OutlinedButton(
                    key: const Key('appearance-logo-pick'),
                    style: buttonStyle,
                    onPressed: readOnly || _busy ? null : _pickLogo,
                    child: const Text('اختيار شعار'),
                  ),
                  OutlinedButton(
                    key: const Key('appearance-logo-clear'),
                    style: buttonStyle,
                    onPressed: readOnly || _busy ? null : _clearLogo,
                    child: const Text('إزالة الشعار من المظهر الجديد'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const Key('appearance-synthetic'),
                    style: buttonStyle,
                    onPressed: _phase == _AppearancePhase.accessLoss
                        ? null
                        : _synthetic,
                    child: const Text(
                      'معاينة تجريبية لا تُنشئ عملية أو إرسالاً',
                    ),
                  ),
                  FilledButton(
                    key: const Key('appearance-review'),
                    style: buttonStyle,
                    onPressed: readOnly || _busy ? null : _review,
                    child: const Text('مراجعة'),
                  ),
                  FilledButton(
                    key: const Key('appearance-save'),
                    style: buttonStyle,
                    onPressed: _busy || _reviewPayload == null || readOnly
                        ? null
                        : _save,
                    child: const Text('حفظ المظهر'),
                  ),
                  if (_phase == _AppearancePhase.unknown ||
                      _phase == _AppearancePhase.failure ||
                      _phase == _AppearancePhase.uploadFailure ||
                      _phase == _AppearancePhase.uploadPending)
                    OutlinedButton(
                      key: const Key('appearance-retry'),
                      style: buttonStyle,
                      onPressed: _busy
                          ? null
                          : _phase == _AppearancePhase.unknown
                          ? _retry
                          : _phase == _AppearancePhase.uploadPending ||
                                _phase == _AppearancePhase.uploadFailure
                          ? _pickLogo
                          : () => _load(keepDraft: true),
                      child: const Text('إعادة المحاولة'),
                    ),
                  if (_phase == _AppearancePhase.stale)
                    OutlinedButton(
                      key: const Key('appearance-accept-revision'),
                      style: buttonStyle,
                      onPressed: () => setState(() {
                        _expectedRevision = _savedRevision;
                        _reviewPayload = null;
                        _phase = widget.canWrite()
                            ? _AppearancePhase.draft
                            : _AppearancePhase.expired;
                        _message =
                            'ستُراجع الحقول على المراجعة $_savedRevision.';
                      }),
                      child: const Text('مراجعة على المراجعة الحالية'),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _markDirty() {
    _dirty = true;
    _reviewPayload = null;
    if (_phase == _AppearancePhase.review ||
        _phase == _AppearancePhase.confirmed) {
      _phase = _AppearancePhase.draft;
    }
  }
}

String _phaseLabel(_AppearancePhase phase) => switch (phase) {
  _AppearancePhase.loading => 'جارٍ التحميل',
  _AppearancePhase.draft => 'مسودة',
  _AppearancePhase.review => 'مراجعة',
  _AppearancePhase.submitting => 'جارٍ الحفظ',
  _AppearancePhase.unknown => 'النتيجة غير معروفة',
  _AppearancePhase.confirmed => 'تم الحفظ',
  _AppearancePhase.failure => 'تعذر الحفظ',
  _AppearancePhase.stale => 'مراجعة قديمة',
  _AppearancePhase.uploadPending => 'رفع الشعار لم يكتمل',
  _AppearancePhase.uploadFailure => 'تعذر حفظ الشعار',
  _AppearancePhase.expired => 'قراءة فقط',
  _AppearancePhase.accessLoss => 'انقطع الوصول',
};

String _templateLabel(InvoiceTemplate template) =>
    template == InvoiceTemplate.header ? 'رأس ملون' : 'موجز';

String _accentLabel(InvoiceAccent accent) => switch (accent) {
  InvoiceAccent.brown => 'بني',
  InvoiceAccent.gold => 'ذهبي',
  InvoiceAccent.neutral => 'محايد',
};

String _failureText(String? code) => switch (code) {
  'other_pending' => 'يوجد طلب آخر بانتظار التأكيد. أكمله قبل حفظ المظهر.',
  'payload_mismatch' =>
    'الطلب المحفوظ لا يطابق هذه البيانات. لا تُرسل نسخة أخرى.',
  'invalid_input' => 'راجع الشعار أو العنوان أو القالب قبل الحفظ.',
  'asset_missing' => 'الشعار غير مؤكد على الخادم.',
  'shop_not_active' => 'انتهى الاشتراك. لم يُحفظ تغيير جديد.',
  _ => 'تعذر إكمال الطلب. أعد المحاولة.',
};
