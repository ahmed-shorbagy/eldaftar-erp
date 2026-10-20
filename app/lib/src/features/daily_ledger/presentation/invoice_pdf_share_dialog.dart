import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../application/confirmed_operation_pdf.dart';
import '../application/financial_gateway.dart';
import '../application/idempotency_key.dart';
import '../application/ledger_activity.dart';
import 'opening_copy.dart';

/// Explicit PDF handoff. Opening the native sheet never confirms delivery.
Future<bool?> showInvoicePdfShareDialog({
  required BuildContext context,
  required FinancialGateway gateway,
  required String userId,
  required String shopId,
  required String operationId,
  required bool Function() canRead,
  required bool Function() canWrite,
  Listenable? invalidations,
  Future<bool> Function(Uint8List bytes, String filename)? share,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => InvoicePdfShareDialog(
    gateway: gateway,
    userId: userId,
    shopId: shopId,
    operationId: operationId,
    canRead: canRead,
    canWrite: canWrite,
    invalidations: invalidations,
    share: share,
  ),
);

class InvoicePdfShareDialog extends StatefulWidget {
  const InvoicePdfShareDialog({
    super.key,
    required this.gateway,
    required this.userId,
    required this.shopId,
    required this.operationId,
    required this.canRead,
    required this.canWrite,
    this.invalidations,
    this.share,
  });
  final FinancialGateway gateway;
  final String userId, shopId, operationId;
  final bool Function() canRead, canWrite;
  final Listenable? invalidations;
  final Future<bool> Function(Uint8List, String)? share;
  @override
  State<InvoicePdfShareDialog> createState() => _InvoicePdfShareDialogState();
}

class _InvoicePdfShareDialogState extends State<InvoicePdfShareDialog> {
  Map<String, Object?>? _operation;
  bool _busy = false, _opened = false, _confirmed = false;
  String? _message, _confirmationKey;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    widget.invalidations?.addListener(_invalidate);
    _load();
  }

  @override
  void dispose() {
    widget.invalidations?.removeListener(_invalidate);
    super.dispose();
  }

  void _invalidate() {
    if (!mounted) return;
    _generation++;
    setState(() {
      if (!widget.canRead()) _operation = null;
      _opened = false;
      _message = 'تغيّرت حالة الوصول أو البيانات. حدّث الفاتورة قبل المشاركة.';
    });
  }

  Future<Map<String, Object?>> _read() async {
    if (!widget.canRead()) throw StateError('access');
    final value = await widget.gateway.operation(
      callerUserId: widget.userId,
      operationId: widget.operationId,
    );
    if (!mounted ||
        !widget.canRead() ||
        !validConfirmedInvoiceFacts(value, operationId: widget.operationId, shopId: widget.shopId)) {
      throw StateError('stale');
    }
    return value;
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() => _busy = true);
    final generation = ++_generation;
    try {
      final value = await _read();
      if (!mounted || generation != _generation) return;
      setState(() {
        _operation = value;
        _opened = false;
        _message = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _operation = null;
          _message = 'تعذر تحميل الفاتورة المؤكدة. حدّث وحاول مجدداً.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final operation = _operation;
    if (_busy || operation == null || !widget.canRead()) return;
    setState(() => _busy = true);
    final generation = _generation;
    try {
      final fresh = await _read();
      if (!mounted || generation != _generation) return;
      if (jsonEncode(fresh) != jsonEncode(operation)) {
        setState(() {
          _operation = fresh;
          _opened = false;
          _message =
              'تغيّرت الفاتورة. راجع البيانات ثم اضغط المشاركة مرة أخرى.';
        });
        return;
      }
      final bytes = await buildConfirmedOperationPdf(fresh);
      final checked = await _read();
      if (!mounted ||
          generation != _generation ||
          jsonEncode(checked) != jsonEncode(fresh)) {
        if (mounted) {
          setState(() {
            _operation = null;
            _opened = false;
            _message = 'تغيّرت الفاتورة. حدّث قبل المشاركة.';
          });
        }
        return;
      }
      final filename = 'eldaftar-invoice-${fresh['shop_sequence']}.pdf';
      final opened = widget.share == null
          ? await Printing.sharePdf(bytes: bytes, filename: filename)
          : await widget.share!(bytes, filename);
      if (!mounted || generation != _generation || !widget.canRead()) return;
      setState(() {
        _opened = opened;
        _message = opened
            ? 'فُتحت المشاركة. اختر واتساب والعميل الموضح، ثم أكد هنا بعد الإرسال فعلاً.'
            : 'لم تُفتح المشاركة. لم يُؤكد الإرسال.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _opened = false;
          _message = 'تعذر تجهيز أو مشاركة PDF. لم يُؤكد الإرسال.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final gateway = widget.gateway;
    if (_busy ||
        !_opened ||
        !widget.canWrite() ||
        gateway is! InvoiceDispatchGateway) {
      return;
    }
    setState(() {
      _busy = true;
      _confirmationKey ??= newIdempotencyKey();
    });
    try {
      final result = await (gateway as InvoiceDispatchGateway)
          .confirmWhatsappSend(
            callerUserId: widget.userId,
            operationId: widget.operationId,
            idempotencyKey: _confirmationKey!,
          );
      if (!mounted || !widget.canRead()) return;
      setState(() {
        _confirmed = result is FinancialCommitted;
        _message = _confirmed
            ? 'أكد المالك إرسال الفاتورة عبر واتساب.'
            : 'لم نتأكد من حفظ التأكيد. أعد المحاولة بنفس الطلب.';
        if (result is FinancialRejected) _confirmationKey = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'لم نتأكد من حفظ التأكيد. أعد المحاولة بنفس الطلب.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final payload = _operation?['payload'];
    final name = payload is Map ? payload['customer_name'] : null;
    final phone = payload is Map ? payload['customer_phone'] : null;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: const Text('مشاركة فاتورة PDF'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_busy) const LinearProgressIndicator(),
                if (_operation != null && widget.canRead()) ...[
            Text('رقم العملية: ${_operation!['shop_sequence']}'),
            Text('وقت العملية: ${formatShopTwelveHourTime(displayedShopTime(occurredAtUtc: _operation!['occurred_at'] as String, occurredAtShop: (_operation!['occurred_at_shop'] ?? _operation!['occurred_at_cairo']) as String))}'),
                  Text(
                    name is String && name.isNotEmpty
                        ? 'العميل: $name'
                        : 'اسم العميل غير مسجل',
                  ),
                  Text(
                    phone is String && phone.isNotEmpty
                        ? 'رقم العميل: \u2066$phone\u2069'
                        : 'رقم العميل غير مسجل؛ اختر المستلم بنفسك.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'اختر واتساب من خيارات الجهاز وراجع المستلم. فتح المشاركة لا يعني الإرسال أو التسليم.',
                  ),
                  FilledButton.icon(
                    key: const Key('invoice-pdf-share'),
                    onPressed: _busy ? null : _share,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('مشاركة PDF'),
                  ),
                  if (_opened &&
                      !_confirmed &&
                      widget.gateway is InvoiceDispatchGateway)
                    OutlinedButton(
                      key: const Key('invoice-pdf-confirm'),
                      onPressed: _busy || !widget.canWrite() ? null : _confirm,
                      child: const Text('تأكيد الإرسال بعد إرساله'),
                    ),
                ],
                if (_message != null) Text(_message!),
                TextButton(
                  onPressed: _busy ? null : _load,
                  child: const Text('تحديث الفاتورة'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, _confirmed),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}
