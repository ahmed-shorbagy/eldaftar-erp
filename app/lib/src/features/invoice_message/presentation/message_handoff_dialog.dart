import 'message_display.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_tokens.dart';
import '../application/message_gateway.dart';
import '../application/message_handoff.dart';
import '../domain/message_template.dart';

class MessageHandoffDialog extends StatefulWidget {
  const MessageHandoffDialog({
    super.key,
    required this.handoff,
    required this.user,
    required this.shop,
    required this.operation,
    required this.canRead,
    this.invalidations,
  });
  final MessageHandoff handoff;
  final String user, shop, operation;
  final bool Function() canRead;
  final Listenable? invalidations;
  @override
  State<MessageHandoffDialog> createState() => _MessageHandoffDialogState();
}

class _MessageHandoffDialogState extends State<MessageHandoffDialog>
    with WidgetsBindingObserver {
  MessagePreview? _preview;
  bool _busy = true, _opened = false;
  bool _boundaryLost = false;
  String _notice = 'جارٍ تجهيز رسالة من العملية المؤكدة...';
  Timer? _boundaryTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.invalidations?.addListener(_checkBoundary);
    _boundaryTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkBoundary(),
    );
    unawaited(_prepare());
  }

  void _checkBoundary() {
    if (!mounted) return;
    final preview = _preview;
    if (!widget.canRead() ||
        preview != null &&
            widget.handoff.gateway.messageSession(widget.user) !=
                preview.session) {
      if (preview != null) {
        setState(() {
          _preview = null;
          _opened = false;
          _boundaryLost = true;
          _notice = 'تغيّرت جلسة الحساب أو صلاحية الوصول. أعد فتح العملية.';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkBoundary();
  }

  @override
  void dispose() {
    _boundaryTimer?.cancel();
    widget.invalidations?.removeListener(_checkBoundary);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _prepare() async {
    setState(() => _busy = true);
    try {
      if (!widget.canRead()) throw const MessageGatewayException('discarded');
      final preview = await widget.handoff.prepare(
        widget.user,
        widget.shop,
        widget.operation,
      );
      if (!mounted) return;
      if (!widget.canRead()) throw const MessageGatewayException('discarded');
      setState(() {
        _preview = preview;
        _notice = 'راجع الرسالة. فتح واتساب لا يؤكد الإرسال أو التسليم.';
      });
    } on MessageValidation catch (e) {
      if (mounted) setState(() => _notice = e.message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _preview = null;
          _notice =
              'تعذر تجهيز رسالة مصرح بها. تحقّق من الاتصال والحساب ثم أعد المحاولة.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open() async {
    if (_busy || _preview == null) return;
    if (!widget.canRead()) {
      setState(() {
        _preview = null;
        _notice = 'لم يعد الحساب يصل إلى المستند. أعد فتح العملية.';
      });
      return;
    }
    setState(() {
      _busy = true;
      _notice = 'جارٍ إعادة التحقق قبل فتح واتساب...';
    });
    final result = await widget.handoff.open(
      widget.user,
      widget.shop,
      widget.operation,
      _preview!,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!widget.canRead() || result.error == 'discarded') {
        _preview = null;
        _opened = false;
        _boundaryLost = true;
        _notice = 'تغيّرت جلسة الحساب أو صلاحية الوصول. أعد فتح العملية.';
      } else if (result.updated != null) {
        _preview = result.updated;
        _notice =
            'تغيّر القالب أو بيانات المستند. راجع النص الحالي واضغط فتح واتساب مرة أخرى.';
      } else if (result.error != null) {
        _preview = null;
        if (const {
          'forbidden',
          'unauthenticated',
          'shop_unavailable',
          'session_expired',
        }.contains(result.error)) {
          _opened = false;
          _boundaryLost = true;
          _notice =
              'لم يعد الحساب يصل إلى المستند. أعد فتح العملية بعد التحقق من الحساب.';
        } else {
          _notice = result.error == 'validation'
              ? result.validationMessage ?? 'تعذر التحقق من نص الرسالة.'
              : 'تعذر التحقق من البيانات الحالية؛ لم يُفتح واتساب. أعد المحاولة.';
        }
      } else {
        _notice = switch (result.launch) {
          MessageLaunch.opened =>
            'فُتح رابط واتساب. بعد إرسال الرسالة فعلاً، أكّد الإرسال في المستند.',
          MessageLaunch.unavailable =>
            'لا يتوفر تطبيق أو معالج للرابط. لم يتم تأكيد الإرسال.',
          MessageLaunch.failure =>
            'تعذر فتح رابط واتساب. لم يتم تأكيد الإرسال.',
          _ => 'نتيجة فتح الرابط غير معروفة. لم يتم تأكيد الإرسال.',
        };
        if (result.launch == MessageLaunch.opened) _opened = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      title: const Text('مراجعة رسالة واتساب'),
      constraints: const BoxConstraints(maxWidth: AppTokens.contentMaxWidth),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_busy) const LinearProgressIndicator(),
            Semantics(liveRegion: true, child: Text(_notice)),
            if (_preview != null) ...[
              const SizedBox(height: 12),
              Text(
                'مراجعة النص: \u2066${_preview!.source.profile.revision}\u2069',
              ),
              Text(
                'الوجهة من المستند المؤكد: \u2066${messageEgyptianPhone((_preview!.source.operation['payload'] as Map)['customer_phone'])}\u2069',
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: 12),
              SelectableText(
                messageDisplay(_preview!.body),
                key: const Key('message-operation-preview'),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_preview == null)
          TextButton(
            onPressed: _busy || _boundaryLost ? null : _prepare,
            child: const Text('إعادة التحقق'),
          ),
        if (_preview != null)
          FilledButton(
            key: const Key('message-open'),
            onPressed: _busy ? null : _open,
            child: const Text('فتح واتساب بعد المراجعة'),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(_opened),
          child: const Text('العودة للمستند'),
        ),
      ],
    ),
  );
}
