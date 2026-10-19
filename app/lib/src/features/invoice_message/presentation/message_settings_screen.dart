import 'message_display.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_tokens.dart';
import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/application/pending_financial_command.dart';
import '../application/message_contract.dart';
import '../application/message_flow.dart';
import '../application/message_gateway.dart';
import '../domain/message_template.dart';
import '../domain/synthetic_message.dart';

class MessageSettingsScreen extends StatefulWidget {
  const MessageSettingsScreen({
    super.key,
    required this.gateway,
    required this.store,
    required this.userId,
    required this.shopId,
    required this.canRead,
    required this.canWrite,
    this.syncTicks,
    this.newKey,
  });
  final InvoiceMessageGateway gateway;
  final FinancialCommandLocker store;
  final String userId, shopId;
  final bool Function() canRead, canWrite;
  final Listenable? syncTicks;
  final String Function()? newKey;
  @override
  State<MessageSettingsScreen> createState() => _MessageSettingsScreenState();
}

class _MessageSettingsScreenState extends State<MessageSettingsScreen>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  MessageProfile? _saved;
  PendingFinancialCommand? _pending;
  Map<String, Object?>? _review;
  String _state = 'loading';
  String? _notice;
  bool _busy = false, _dirty = false, _queued = false, _foreign = false;
  int _generation = 0, _base = 0;
  Object? _session;
  InvoiceMessageFlow get _flow =>
      InvoiceMessageFlow(widget.gateway, widget.store);
  bool get _readable =>
      widget.canRead() && widget.gateway.messageSession(widget.userId) != null;
  bool get _writable =>
      _readable && widget.canWrite() && (_saved?.canWrite ?? false);
  bool get _editable =>
      !_busy &&
      _pending == null &&
      !_foreign &&
      _writable &&
      _state != 'loading' &&
      _state != 'expired' &&
      _state != 'access';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.syncTicks?.addListener(_sync);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant MessageSettingsScreen old) {
    super.didUpdateWidget(old);
    if (old.syncTicks != widget.syncTicks) {
      old.syncTicks?.removeListener(_sync);
      widget.syncTicks?.addListener(_sync);
    }
    if (old.userId != widget.userId || old.shopId != widget.shopId) {
      _generation++;
      _lose();
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    widget.syncTicks?.removeListener(_sync);
    _text.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  void _lose() {
    _text.clear();
    _saved = null;
    _review = null;
    _pending = null;
    _state = 'access';
    _notice = 'لم يعد هذا الحساب يصل إلى المتجر.';
  }

  bool _alive(int generation, Object? session) {
    if (!mounted || generation != _generation) return false;
    if (!_readable || widget.gateway.messageSession(widget.userId) != session) {
      setState(_lose);
      return false;
    }
    return true;
  }

  void _sync() {
    if (!mounted) return;
    if (!_readable ||
        (_session != null &&
            widget.gateway.messageSession(widget.userId) != _session)) {
      setState(_lose);
      return;
    }
    if (_busy) {
      _queued = true;
      return;
    }
    unawaited(_load(keepDraft: true));
  }

  Future<void> _load({bool keepDraft = false}) async {
    if (!_readable) {
      if (mounted) setState(_lose);
      return;
    }
    final generation = ++_generation,
        session = widget.gateway.messageSession(widget.userId);
    _session = session;
    if (!keepDraft) setState(() => _state = 'loading');
    try {
      final pending = await widget.store.read(widget.userId, widget.shopId);
      if (!_alive(generation, session)) return;
      final saved = await widget.gateway.readMessage(
        widget.userId,
        widget.shopId,
      );
      if (!_alive(generation, session)) return;
      setState(() {
        final changed = _saved != null && saved.revision != _saved!.revision;
        _saved = saved;
        _foreign = pending != null && pending.kind != invoiceMessageKind;
        if (pending?.kind == invoiceMessageKind) {
          _pending = pending;
          final payload = pending!.body['p_payload'] as Map;
          _text.text = payload['template'] as String? ?? '';
          _base = int.parse(payload['expected_revision'] as String);
          _state = 'unknown';
          _review = null;
          _notice =
              'لم نتأكد من حفظ الطلب الأصلي. تحقّق منه قبل إنشاء طلب آخر.';
        } else if (_foreign) {
          _state = 'blocked';
          _notice = 'يوجد طلب آخر محفوظ. أكمله من مساره قبل حفظ نص الرسالة.';
        } else if (keepDraft && (_dirty || _review != null)) {
          if (changed) {
            _state = 'stale';
            _review = null;
            _notice =
                'تغيّرت المراجعة المحفوظة في جلسة أخرى. مسودتك محفوظة هنا؛ راجعها مع المراجعة الحالية.';
          } else if (_state == 'expired' && _writable) {
            _state = 'draft';
            _notice = 'أصبح الحفظ متاحاً. راجع المسودة قبل الحفظ.';
          }
        } else {
          _pending = null;
          _text.text = saved.template ?? '';
          _base = saved.revision;
          _dirty = false;
          _review = null;
          _state = 'draft';
          _notice = saved.revision == 0
              ? 'يُستخدم النص الافتراضي؛ لم يُحفظ تخصيص بعد.'
              : null;
        }
        if (!_writable && _pending == null) {
          _state = 'expired';
          _review = null;
          _notice =
              'انتهى الاشتراك. يمكنك قراءة النص؛ حفظ تعديل جديد يتطلب اشتراكاً نشطاً.';
        }
      });
    } on MessageGatewayException catch (e) {
      if (!_alive(generation, session)) return;
      setState(() {
        if (_accessError(e.code)) {
          _lose();
        } else {
          _state = 'failure';
          _notice = 'تعذر تحميل النص من الخادم. أعد المحاولة؛ لم يُحفظ تعديل.';
        }
      });
    } catch (_) {
      if (_alive(generation, session)) {
        setState(() {
          _state = 'failure';
          _notice =
              'تعذر قراءة النص أو الطلب المحفوظ. أعد المحاولة دون حذف الطلب.';
        });
      }
    }
  }

  void _edited() {
    setState(() {
      _dirty = true;
      _review = null;
      _state = 'draft';
      _notice = 'مسودة غير محفوظة';
    });
  }

  String? get _validation {
    try {
      final template = MessageTemplate.parse(_text.text);
      final body = template.render(syntheticMessageOperation());
      messageWhatsappUri(body, '01011111111');
      return null;
    } on MessageValidation catch (e) {
      return e.message;
    }
  }

  void _insert(String token) {
    final selection = _text.selection;
    final start = selection.isValid ? selection.start : _text.text.length;
    final end = selection.isValid ? selection.end : start;
    final value = '{$token}';
    _text.value = TextEditingValue(
      text: _text.text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
    );
    _edited();
  }

  Future<void> _reviewDraft() async {
    if (!_editable || _validation != null) return;
    final payload = messagePayload(_base, _text.text);
    final generation = _generation, session = _session;
    setState(() {
      _busy = true;
      _notice = 'جارٍ التحقق من المراجعة والصلاحية...';
    });
    try {
      final review = await widget.gateway.reviewMessage(
        widget.userId,
        widget.shopId,
        payload,
      );
      if (!_alive(generation, session)) return;
      setState(() {
        if (review.status == 'ready' &&
            review.canWrite &&
            review.revision == _base) {
          _review = payload;
          _state = 'review';
          _notice =
              'راجع النص قبل حفظه لجميع جلسات المتجر. لا أثر على النقد أو الذهب أو الإرسال.';
        } else {
          _review = null;
          _state = review.status;
          _notice = review.status == 'stale'
              ? 'تغيّر النص المحفوظ. حدّث المراجعة مع الاحتفاظ بمسودتك.'
              : 'الاشتراك غير نشط؛ لم يُحفظ تعديل.';
        }
      });
    } on MessageGatewayException catch (e) {
      if (_alive(generation, session)) {
        setState(() {
          if (_accessError(e.code)) {
            _lose();
          } else {
            _state = 'failure';
            _notice = 'تعذر التحقق؛ مسودتك لم تُحفظ.';
          }
        });
      }
    } catch (_) {
      if (_alive(generation, session)) {
        setState(() => _notice = 'تعذر التحقق؛ مسودتك لم تُحفظ.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_queued) {
          _queued = false;
          _sync();
        }
      }
    }
  }

  Future<void> _save({bool recover = false, bool retry = false}) async {
    if (_busy || !_readable || (!recover && (_review == null || !_writable))) {
      return;
    }
    final generation = _generation, session = _session;
    setState(() {
      _busy = true;
      _state = 'submitting';
      _notice = recover
          ? 'جارٍ التحقق من الطلب الأصلي...'
          : 'جارٍ حفظ النص على الخادم...';
    });
    final outcome = recover
        ? await _flow.reconcile(
            widget.userId,
            widget.shopId,
            _pending!,
            canWrite: _writable,
            retry: retry,
          )
        : await _flow.submit(
            widget.userId,
            widget.shopId,
            widget.newKey?.call() ?? newIdempotencyKey(),
            _review!,
            canWrite: _writable,
          );
    if (!_alive(generation, session)) {
      if (mounted) {
        setState(() {
          _busy = false;
          _lose();
        });
      }
      return;
    }
    if (_accessError(outcome.error)) {
      setState(() {
        _busy = false;
        _lose();
      });
      return;
    }
    setState(() {
      _busy = false;
      _pending = outcome.pending;
      _review = null;
      if (_pending != null) {
        _state = 'unknown';
        _notice = outcome.error == 'payload_mismatch'
            ? messageFailure(outcome.error)
            : outcome.receipt != null
            ? 'أكد الخادم الحفظ، وتعذر إنهاء الاسترداد المحلي. أعد التحقق من الطلب الأصلي.'
            : 'نتيجة الحفظ غير مؤكدة. تحقّق من الطلب الأصلي أو أعد إرساله بالمفتاح والبيانات نفسيهما.';
      } else if (outcome.receipt != null) {
        _state = 'confirmed';
        _dirty = false;
        _notice = 'أكد الخادم حفظ نص الرسالة.';
      } else {
        _state = outcome.error == 'stale_message'
            ? 'stale'
            : outcome.error == 'shop_not_active'
            ? 'expired'
            : 'failure';
        _notice = messageFailure(outcome.error);
      }
    });
    if (outcome.receipt != null && _pending == null) {
      final notice = _notice;
      await _load();
      if (_alive(_generation, session)) {
        setState(() {
          _state = 'confirmed';
          _notice = notice;
        });
      }
    }
    if (_queued) {
      _queued = false;
      _sync();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_readable && _state != 'access') _lose();
    final error = _validation;
    String? preview;
    try {
      preview = MessageTemplate.parse(
        _text.text,
      ).render(syntheticMessageOperation());
    } on MessageValidation {
      /* inline error */
    }
    final theme = Theme.of(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('نص رسالة الفاتورة')),
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
                  if (_state == 'loading') const LinearProgressIndicator(),
                  if (_saved != null)
                    Text(
                      'المراجعة المحفوظة: \u2066${_saved!.revision}\u2069 · ${_saved!.template == null ? 'النص الافتراضي' : 'نص مخصص'}',
                    ),
                  if (_saved?.atShop != null)
                    Text(
                      'وقت حفظ القالب: \u2066${_saved!.atShop!.replaceAll('T', ' ')}\u2069 (\u2066${_saved!.zone}\u2069)',
                      textDirection: TextDirection.rtl,
                    ),
                  if (_notice != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _notice!,
                          style: TextStyle(
                            color: _state == 'confirmed'
                                ? theme.colorScheme.tertiary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  if (_state != 'access') ...[
                    TextField(
                      key: const Key('message-editor'),
                      controller: _text,
                      enabled: _editable,
                      minLines: 4,
                      maxLines: 9,
                      onChanged: (_) => _edited(),
                      decoration: InputDecoration(
                        labelText: 'نص الرسالة',
                        alignLabelWithHint: true,
                        helperText:
                            '٤٠٠ محرف و٨ فواصل أسطر كحد أقصى. ترك النص فارغاً يستعيد الافتراضي.',
                        helperMaxLines: 4,
                        errorText: error,
                        errorMaxLines: 4,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ExpansionTile(
                      key: const Key('message-tokens'),
                      title: const Text('إدراج حقل متغير'),
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final token in messageTokens.entries)
                              OutlinedButton(
                                onPressed: _editable
                                    ? () => _insert(token.key)
                                    : null,
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(
                                    48,
                                    AppTokens.minControlSize,
                                  ),
                                ),
                                child: Text(token.value),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'معاينة تجريبية لا تُنشئ عملية أو إرسالاً',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    if (preview != null)
                      SelectableText(
                        messageDisplay(preview),
                        key: const Key('message-synthetic-preview'),
                      ),
                    const SizedBox(height: 16),
                    if (_state == 'stale')
                      OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                await _load(keepDraft: true);
                                if (mounted && _saved != null) {
                                  setState(() {
                                    _base = _saved!.revision;
                                    _state = 'draft';
                                    _notice =
                                        'احتُفظ بمسودتك مع المراجعة الحالية. راجعها قبل الحفظ.';
                                  });
                                }
                              },
                        child: const Text('مراجعة مسودتي مع المراجعة الحالية'),
                      ),
                    if (_review != null) ...[
                      Text(
                        _review!['template'] == null
                            ? 'سيُستعاد النص الافتراضي.'
                            : 'سيُحفظ النص المخصص لجميع جلسات المتجر.',
                      ),
                      FilledButton(
                        key: const Key('message-save'),
                        onPressed: _busy || !_writable ? null : () => _save(),
                        child: const Text('تأكيد حفظ النص'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _review = null;
                                _state = 'draft';
                              }),
                        child: const Text('العودة للتعديل'),
                      ),
                    ] else if (_pending == null) ...[
                      FilledButton(
                        key: const Key('message-review'),
                        onPressed:
                            _editable && error == null && _state != 'stale'
                            ? _reviewDraft
                            : null,
                        child: const Text('مراجعة النص قبل الحفظ'),
                      ),
                      OutlinedButton(
                        key: const Key('message-reset'),
                        onPressed: _editable
                            ? () {
                                _text.clear();
                                _edited();
                              }
                            : null,
                        child: const Text('استعادة النص الافتراضي'),
                      ),
                    ],
                    if (_pending != null) ...[
                      FilledButton(
                        key: const Key('message-recover'),
                        onPressed: _busy ? null : () => _save(recover: true),
                        child: const Text('التحقق من الطلب الأصلي'),
                      ),
                      OutlinedButton(
                        onPressed: _busy || !_writable
                            ? null
                            : () => _save(recover: true, retry: true),
                        child: const Text('إعادة إرسال الطلب الأصلي'),
                      ),
                    ],
                    if (_state == 'failure')
                      OutlinedButton(
                        onPressed: _busy ? null : () => _load(keepDraft: true),
                        child: const Text('إعادة التحقق من الخادم'),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

bool _accessError(String? code) => const {
  'forbidden',
  'unauthenticated',
  'session_expired',
  'discarded',
  'shop_unavailable',
}.contains(code);
String messageFailure(String? code) => switch (code) {
  'stale_message' => 'تغيّر النص المحفوظ؛ راجع مسودتك مع المراجعة الحالية.',
  'shop_not_active' => 'الاشتراك غير نشط؛ لم يُحفظ تعديل جديد.',
  'other_pending' => 'يوجد طلب آخر محفوظ؛ أكمله من مساره أولاً.',
  'payload_mismatch' => 'تعارضت بيانات الطلب الأصلي. احتُفظ به للتحقق الآمن.',
  _ => 'تعذر حفظ النص. مسودتك لم تُحفظ على الخادم.',
};
