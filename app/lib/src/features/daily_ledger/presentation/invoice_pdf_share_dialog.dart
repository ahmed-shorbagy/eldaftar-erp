import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../application/confirmed_operation_pdf.dart';
import '../application/financial_gateway.dart';
import '../application/idempotency_key.dart';
import '../application/ledger_activity.dart';
import 'opening_copy.dart';
import '../../invoice_appearance/application/invoice_appearance_gateway.dart';
import '../../invoice_appearance/application/invoice_appearance_flow.dart';
import '../../invoice_appearance/application/invoice_appearance_contract.dart';
import '../../invoice_appearance/application/branded_invoice_pdf.dart';
import '../../invoice_appearance/domain/branded_invoice_document.dart';
import '../application/pending_financial_command.dart';
import '../data/pending_financial_command.dart';

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
  PendingFinancialCommand? _presentationPending;
  final _copies = const PendingFinancialCommands();
  bool _legacyFallback = false;
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
        !validConfirmedInvoiceFacts(
          value,
          operationId: widget.operationId,
          shopId: widget.shopId,
        )) {
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
      final pending = widget.gateway is InvoiceAppearanceGateway
          ? await _copies.read(widget.userId, widget.shopId)
          : null;
      if (!mounted || generation != _generation || !widget.canRead()) return;
      setState(() {
        _operation = value;
        _opened = false;
        _message = null;
        final payload = pending?.body['p_payload'];
        _presentationPending =
            pending?.kind == invoicePresentationKind &&
                payload is Map &&
                payload['operation_id'] == widget.operationId
            ? pending
            : null;
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

  Future<Uint8List?> _brandedBytes() async {
    final gateway = widget.gateway;
    if (gateway is! InvoiceAppearanceGateway) {
      return buildConfirmedOperationPdf(_operation!);
    }
    final appearance = gateway as InvoiceAppearanceGateway;
    try {
      if (!widget.canRead() ||
          appearance.appearanceSession(widget.userId) == null) {
        return null;
      }
      final source = await appearance.readBrandSource(
        userId: widget.userId,
        shopId: widget.shopId,
        operationId: widget.operationId,
      );
      if (!mounted ||
          !widget.canRead() ||
          source.shopId != widget.shopId ||
          source.operationId != widget.operationId) {
        return null;
      }
      var edition = source.latestEdition;
      if (edition == 0) {
        if (!widget.canWrite() || !source.canWrite) {
          throw const FormatException('readonly_copy');
        }
        final payload = presentationCommandPayload(
          operationId: widget.operationId,
          contentSha256: source.contentSha256,
          expectedAppearanceRevision: source.appearance.revision,
          expectedLatestEdition: 0,
        );
        final outcome = await InvoiceAppearanceFlow(appearance, _copies)
            .submitPresentation(
              widget.userId,
              widget.shopId,
              newIdempotencyKey(),
              payload,
              canWrite: widget.canWrite(),
            );
        if (!mounted || !widget.canRead()) return null;
        if (outcome.pending != null) {
          final other = outcome.pending!, body = other.body['p_payload'];
          if (other.kind != invoicePresentationKind ||
              body is! Map ||
              body['operation_id'] != widget.operationId) {
            throw const FormatException('other_pending');
          }
          setState(() {
            _presentationPending = other;
            _message =
                'طلب إصدار الفاتورة بانتظار التأكيد. تحقق من الطلب نفسه قبل المشاركة.';
          });
          return null;
        }
        final receipt = outcome.receipt;
        if (receipt == null ||
            outcome.error != null ||
            receipt.operationId != widget.operationId ||
            receipt.contentSha256 != source.contentSha256 ||
            receipt.edition == null) {
          throw const FormatException('copy_not_confirmed');
        }
        edition = receipt.edition!;
      }
      final copy = await appearance.readPresentation(
        userId: widget.userId,
        shopId: widget.shopId,
        operationId: widget.operationId,
        edition: edition,
      );
      if (!mounted ||
          !widget.canRead() ||
          appearance.appearanceSession(widget.userId) == null ||
          copy.shopId != widget.shopId ||
          copy.operationId != widget.operationId ||
          copy.edition != edition ||
          copy.contentSha256 != source.contentSha256 ||
          !copy.contentMatches ||
          copy.logoState == 'unverified') {
        throw const FormatException('copy_stale');
      }
      final document = BrandedInvoiceDocument.fromConfirmed(
        source: copy.documentSource,
        edition: copy.edition,
        contentSha256: copy.contentSha256,
        appearanceRevision: copy.appearance.revision,
        template: copy.appearance.template,
        accent: copy.appearance.accent,
        renderVersion: copy.renderVersion,
        copyCreatedAtUtc: copy.createdAtUtc,
        copyCreatedAtShop: copy.createdAtShop,
        slogan: copy.appearance.slogan,
        address: copy.appearance.address,
        logoAssetId: copy.appearance.logoAssetId,
        logoSha256: copy.appearance.logoSha256,
        logoRequired: copy.appearance.logoAssetId != null,
      );
      return buildBrandedInvoicePdf(
        document,
        logoBytes: copy.logoBytes == null
            ? null
            : Uint8List.fromList(copy.logoBytes!),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _legacyFallback = true;
          _message =
              'تعذر تجهيز النسخة بمظهر المتجر. أعد المحاولة أو اختر المستند الأصلي صراحةً.';
        });
      }
      return null;
    }
  }

  Future<void> _checkPresentation() async {
    final pending = _presentationPending, gateway = widget.gateway;
    if (_busy ||
        pending == null ||
        gateway is! InvoiceAppearanceGateway ||
        !widget.canRead()) {
      return;
    }
    setState(() => _busy = true);
    try {
      final outcome =
          await InvoiceAppearanceFlow(
            gateway as InvoiceAppearanceGateway,
            _copies,
          ).reconcile(
            widget.userId,
            widget.shopId,
            pending,
            retry: true,
            canWrite: widget.canWrite(),
          );
      if (!mounted || !widget.canRead()) return;
      setState(() {
        _presentationPending = outcome.pending;
        _message = outcome.receipt != null
            ? 'تأكد إصدار الفاتورة. يمكنك مشاركتها الآن.'
            : outcome.pending != null
            ? 'الإصدار بانتظار التأكيد؛ احتفظنا بالطلب الأصلي.'
            : 'لم يكتمل إصدار النسخة. حدّث الفاتورة وحاول مجدداً.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'تعذر تأكيد إصدار النسخة. أعد التحقق.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share({bool legacy = false}) async {
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
      final bytes = legacy
          ? await buildConfirmedOperationPdf(fresh)
          : await _brandedBytes();
      if (bytes == null) return;
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
                  Text(
                    'وقت العملية: ${formatShopTwelveHourTime(displayedShopTime(occurredAtUtc: _operation!['occurred_at'] as String, occurredAtShop: (_operation!['occurred_at_shop'] ?? _operation!['occurred_at_cairo']) as String))}',
                  ),
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
                    onPressed: _busy || _presentationPending != null
                        ? null
                        : _share,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('مشاركة PDF'),
                  ),
                  if (_presentationPending != null)
                    OutlinedButton(
                      onPressed: _busy ? null : _checkPresentation,
                      child: const Text('التحقق وإكمال إصدار النسخة'),
                    ),
                  if (_legacyFallback)
                    OutlinedButton(
                      key: const Key('invoice-pdf-legacy-share'),
                      onPressed: _busy ? null : () => _share(legacy: true),
                      child: const Text('مشاركة المستند الأصلي'),
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
