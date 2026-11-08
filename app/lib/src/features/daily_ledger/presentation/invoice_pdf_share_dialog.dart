import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../../theme/amount_format.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/whatsapp_icon.dart';
import '../application/confirmed_operation_pdf.dart';
import '../application/financial_gateway.dart';
import '../application/invoice_whatsapp_share.dart';
import '../data/platform_invoice_whatsapp_share.dart';
import '../../invoice_message/application/message_gateway.dart';
import '../../invoice_message/application/message_handoff.dart';
import '../../invoice_message/data/url_message_launcher.dart';
import '../../invoice_message/domain/message_template.dart';
import '../application/idempotency_key.dart';
import '../application/ledger_activity.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';
import 'opening_copy.dart';
import '../../invoice_appearance/application/invoice_appearance_gateway.dart';
import '../../invoice_appearance/application/invoice_appearance_flow.dart';
import '../../invoice_appearance/application/invoice_appearance_contract.dart';
import '../../invoice_appearance/application/branded_invoice_pdf.dart';
import '../../invoice_appearance/domain/branded_invoice_document.dart';
import '../application/pending_financial_command.dart';
import '../data/pending_financial_command.dart';

typedef InvoiceShare = Future<bool> Function(Uint8List bytes, String filename);

/// Native share is a handoff. Dismissed or unavailable never means sent.
bool invoiceShareHandoffOpened(ShareResultStatus status) =>
    status == ShareResultStatus.success;

/// Explicit invoice handoff. Opening the native sheet never confirms delivery.
Future<bool?> showInvoicePdfShareDialog({
  required BuildContext context,
  required FinancialGateway gateway,
  required String userId,
  required String shopId,
  required String operationId,
  required bool Function() canRead,
  required bool Function() canWrite,
  Listenable? invalidations,
  InvoiceShare? share,
  InvoiceWhatsappShare? whatsapp,
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
    whatsapp: whatsapp,
  ),
);

/// Only the facts printed on the invoice. Live fields such as return
/// remainders may change without changing what the customer receives.
String invoiceFactsFingerprint(Map<String, Object?> operation) => jsonEncode({
  'operation_id': operation['operation_id'],
  'kind': operation['kind'],
  'shop_sequence': operation['shop_sequence'],
  'shop_name': operation['shop_name'],
  'occurred_at': operation['occurred_at'],
  'trade_change': operation['trade_change'],
  'payload': operation['payload'],
});

enum _Action { whatsapp, pdf, legacy, confirm, check }

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
    this.whatsapp,
  });
  final FinancialGateway gateway;
  final String userId, shopId, operationId;
  final bool Function() canRead, canWrite;
  final Listenable? invalidations;
  final InvoiceShare? share;
  final InvoiceWhatsappShare? whatsapp;
  @override
  State<InvoicePdfShareDialog> createState() => _InvoicePdfShareDialogState();
}

final class _Brand {
  const _Brand(this.document, this.logo, this.fingerprint);
  final BrandedInvoiceDocument document;
  final Uint8List? logo;
  final String fingerprint;
}

class _InvoicePdfShareDialogState extends State<InvoicePdfShareDialog> {
  Map<String, Object?>? _operation;
  bool _loading = false, _opened = false, _confirmed = false;
  bool _failed = false, _messageIsError = false;
  _Action? _busy;
  String? _message, _confirmationKey;
  PendingFinancialCommand? _presentationPending;
  final _copies = const PendingFinancialCommands();
  bool _legacyFallback = false;
  _Brand? _brand;
  int _accessEpoch = 0;

  bool get _idle => !_loading && _busy == null;

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

  /// Sync ticks after the sale are expected. Only lost access clears the
  /// invoice; data changes are caught by the fact check before every share.
  void _invalidate() {
    if (!mounted || widget.canRead()) return;
    _accessEpoch++;
    setState(() {
      _operation = null;
      _brand = null;
      _opened = false;
      _say('انتهت صلاحية الوصول إلى هذه الفاتورة.', error: true);
    });
  }

  void _say(String? message, {bool error = false}) {
    _message = message;
    _messageIsError = error;
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
    if (!_idle) return;
    setState(() => _loading = true);
    final epoch = _accessEpoch;
    try {
      final value = await _read();
      final pending = widget.gateway is InvoiceAppearanceGateway
          ? await _copies.read(widget.userId, widget.shopId)
          : null;
      if (!mounted || epoch != _accessEpoch || !widget.canRead()) return;
      setState(() {
        _operation = value;
        _failed = false;
        _opened = false;
        _say(null);
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
          _failed = true;
          _say('تعذر تحميل الفاتورة المؤكدة.', error: true);
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Issues the first branded edition when none exists, then reuses it.
  Future<_Brand?> _prepareBrand(String fingerprint) async {
    final cached = _brand;
    if (cached != null && cached.fingerprint == fingerprint) return cached;
    final appearance = widget.gateway as InvoiceAppearanceGateway;
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
          _say(
            'إصدار نسخة الفاتورة بانتظار تأكيد الخادم. اضغط «التحقق» ثم شارك.',
          );
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
    final brand = _Brand(
      BrandedInvoiceDocument.fromConfirmed(
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
      ),
      copy.logoBytes == null ? null : Uint8List.fromList(copy.logoBytes!),
      fingerprint,
    );
    _brand = brand;
    return brand;
  }

  Future<Uint8List?> _pdf(
    Map<String, Object?> operation,
    _Action action,
  ) async {
    final legacy =
        action == _Action.legacy || widget.gateway is! InvoiceAppearanceGateway;
    if (legacy) return buildConfirmedOperationPdf(operation);
    try {
      final brand = await _prepareBrand(invoiceFactsFingerprint(operation));
      if (brand == null) return null;
      return await buildBrandedInvoicePdf(
        brand.document,
        logoBytes: brand.logo,
        output: BrandedInvoiceOutput.print,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _legacyFallback = true;
          _say(
            'تعذر تجهيز الفاتورة بمظهر المتجر. أعد المحاولة أو شارك المستند الأصلي.',
            error: true,
          );
        });
      }
      return null;
    }
  }

  Future<void> _share(_Action action) async {
    final operation = _operation;
    if (!_idle || operation == null || !widget.canRead()) return;
    setState(() {
      _busy = action;
      _say(null);
    });
    final epoch = _accessEpoch;
    try {
      final fresh = await _read();
      if (!mounted || epoch != _accessEpoch) return;
      if (invoiceFactsFingerprint(fresh) !=
          invoiceFactsFingerprint(operation)) {
        setState(() {
          _operation = fresh;
          _brand = null;
          _opened = false;
          _say('تغيّرت الفاتورة. راجع البيانات ثم أعد المشاركة.', error: true);
        });
        return;
      }
      final pdf = await _pdf(fresh, action);
      if (pdf == null || !mounted || epoch != _accessEpoch) return;
      final checked = await _read();
      if (!mounted || epoch != _accessEpoch) return;
      if (invoiceFactsFingerprint(checked) != invoiceFactsFingerprint(fresh)) {
        setState(() {
          _operation = checked;
          _brand = null;
          _opened = false;
          _say('تغيّرت الفاتورة. راجع البيانات ثم أعد المشاركة.', error: true);
        });
        return;
      }
      final filename = 'eldaftar-invoice-${fresh['shop_sequence']}.pdf';
      if (action == _Action.whatsapp) {
        await _handoffWhatsapp(pdf, filename, fresh);
        return;
      }
      final opened = widget.share != null
          ? await widget.share!(pdf, filename)
          : await Printing.sharePdf(bytes: pdf, filename: filename);
      if (!mounted || epoch != _accessEpoch || !widget.canRead()) return;
      setState(() {
        if (opened) {
          _opened = true;
          _say('اختر العميل في واتساب وأرسل، ثم أكّد الإرسال هنا.');
        } else if (_opened) {
          _say(
            'أُلغيت المشاركة الأخيرة. إذا أرسلت النسخة السابقة، أكّد الإرسال هنا.',
          );
        } else {
          _say('لم يتأكد اكتمال المشاركة. لم يُسجّل إرسال.', error: true);
        }
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _say(
            'تعذر تجهيز الفاتورة أو مشاركتها. حاول مجدداً.',
            error: true,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<String> _messageText() async {
    final gateway = widget.gateway;
    if (gateway is! InvoiceMessageGateway) return '';
    final messages = gateway as InvoiceMessageGateway;
    try {
      final preview = await MessageHandoff(
        messages,
        const UrlMessageLauncher(),
        canRead: widget.canRead,
      ).prepare(widget.userId, widget.shopId, widget.operationId);
      return preview.body;
    } on MessageValidation {
      try {
        final source = await messages.readMessageSource(
          widget.userId,
          widget.shopId,
          widget.operationId,
        );
        return MessageTemplate.parse(
          source.profile.template,
        ).render(source.operation);
      } catch (_) {
        return '';
      }
    } catch (_) {
      return '';
    }
  }

  Future<void> _handoffWhatsapp(
    Uint8List pdf,
    String filename,
    Map<String, Object?> operation,
  ) async {
    final payload = operation['payload'];
    final phone = payload is Map
        ? messageWhatsappPhone(payload['customer_phone'])
        : null;
    final text = await _messageText();
    if (!mounted || !widget.canRead()) return;
    final box = context.findRenderObject() as RenderBox?;
    final result =
        await (widget.whatsapp ?? const PlatformInvoiceWhatsappShare())
            .sharePdf(
              pdf: pdf,
              filename: filename,
              phoneDigits: phone,
              text: text,
              origin: box == null
                  ? null
                  : box.localToGlobal(Offset.zero) & box.size,
            );
    if (!mounted || !widget.canRead()) return;
    if (result == WhatsappShareResult.notInstalled) {
      if (widget.share != null) {
        await widget.share!(pdf, filename);
      } else {
        await _sharePdfSheet(pdf, filename, text);
      }
      if (!mounted || !widget.canRead()) return;
      setState(() {
        _opened = true;
        _say('واتساب غير مثبت. اختر تطبيقاً للمشاركة.');
      });
      return;
    }
    setState(() {
      switch (result) {
        case WhatsappShareResult.opened:
          _opened = true;
          _say(
            defaultTargetPlatform == TargetPlatform.windows
                ? phone == null
                      ? 'فُتح واتساب. اختر العميل، ثم اسحب ملف الفاتورة المحدد إلى المحادثة وأرسل، ثم أكّد هنا.'
                      : 'فُتحت محادثة العميل. اسحب ملف الفاتورة المحدد إلى المحادثة وأرسل، ثم أكّد هنا.'
                : phone == null
                ? 'فُتح واتساب ومعه الفاتورة. اختر العميل وأرسل، ثم أكّد هنا.'
                : 'فُتحت محادثة العميل في واتساب ومعها الفاتورة والرسالة. أرسلها ثم أكّد هنا.',
          );
        case WhatsappShareResult.sheetOpened:
          _opened = true;
          _say('اختر واتساب ثم العميل وأرسل، ثم أكّد هنا.');
        case WhatsappShareResult.failed:
          _say('تعذر فتح واتساب. حاول مجدداً.', error: true);
        case WhatsappShareResult.notInstalled:
          break;
      }
    });
  }

  Future<void> _sharePdfSheet(
    Uint8List bytes,
    String filename,
    String text,
  ) async {
    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(bytes, mimeType: 'application/pdf', name: filename),
          ],
          text: text,
          fileNameOverrides: [filename],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      // The status sentence still tells the owner to pick another app.
    }
  }

  Future<void> _checkPresentation() async {
    final pending = _presentationPending, gateway = widget.gateway;
    if (!_idle ||
        pending == null ||
        gateway is! InvoiceAppearanceGateway ||
        !widget.canRead()) {
      return;
    }
    setState(() => _busy = _Action.check);
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
        _say(
          outcome.receipt != null
              ? 'تأكد إصدار الفاتورة. يمكنك مشاركتها الآن.'
              : outcome.pending != null
              ? 'الإصدار بانتظار التأكيد؛ احتفظنا بالطلب الأصلي.'
              : 'لم يكتمل إصدار النسخة. حاول المشاركة مجدداً.',
          error: outcome.receipt == null && outcome.pending == null,
        );
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _say('تعذر تأكيد إصدار النسخة. أعد التحقق.', error: true),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _confirm() async {
    final gateway = widget.gateway;
    if (!_idle ||
        !_opened ||
        !widget.canWrite() ||
        gateway is! InvoiceDispatchGateway) {
      return;
    }
    setState(() {
      _busy = _Action.confirm;
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
        _say(
          _confirmed
              ? 'أكد المالك إرسال الفاتورة عبر واتساب.'
              : 'لم نتأكد من حفظ التأكيد. أعد المحاولة بنفس الطلب.',
          error: !_confirmed,
        );
        if (result is FinancialRejected) _confirmationKey = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _say(
            'لم نتأكد من حفظ التأكيد. أعد المحاولة بنفس الطلب.',
            error: true,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final operation = widget.canRead() ? _operation : null;
    final shareBlocked = !_idle || _presentationPending != null;
    return PopScope(
      canPop: _idle,
      child: AlertDialog(
        title: const Text('إرسال الفاتورة'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_loading) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: AppTokens.spaceSm),
                  const Text('جارٍ تحميل الفاتورة…'),
                ],
                if (operation != null) ...[
                  _InvoiceSummary(operation: operation),
                  const SizedBox(height: AppTokens.spaceMd),
                  FilledButton.icon(
                    key: const Key('invoice-whatsapp-pdf'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(
                        AppTokens.minControlSize,
                      ),
                    ),
                    onPressed: shareBlocked
                        ? null
                        : () => _share(_Action.whatsapp),
                    icon: _busy == _Action.whatsapp
                        ? const _Spinner()
                        : const WhatsappIcon(),
                    label: const Text('إرسال الفاتورة PDF على واتساب'),
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  OutlinedButton.icon(
                    key: const Key('invoice-pdf-share'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(
                        AppTokens.minControlSize,
                      ),
                    ),
                    onPressed: shareBlocked ? null : () => _share(_Action.pdf),
                    icon: _busy == _Action.pdf
                        ? const _Spinner()
                        : const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('PDF للطباعة أو المشاركة'),
                  ),
                  if (_presentationPending != null) ...[
                    const SizedBox(height: AppTokens.spaceSm),
                    OutlinedButton.icon(
                      onPressed: _idle ? _checkPresentation : null,
                      icon: _busy == _Action.check
                          ? const _Spinner()
                          : const Icon(Icons.sync),
                      label: const Text('التحقق وإكمال إصدار النسخة'),
                    ),
                  ],
                  if (_legacyFallback)
                    TextButton(
                      key: const Key('invoice-pdf-legacy-share'),
                      onPressed: _idle ? () => _share(_Action.legacy) : null,
                      child: const Text('مشاركة المستند الأصلي'),
                    ),
                  if (_opened &&
                      !_confirmed &&
                      widget.gateway is InvoiceDispatchGateway) ...[
                    const SizedBox(height: AppTokens.spaceMd),
                    Container(
                      padding: const EdgeInsets.all(AppTokens.spaceMd),
                      decoration: BoxDecoration(
                        color: colors.secondaryContainer,
                        borderRadius: BorderRadius.circular(
                          AppTokens.fieldRadius,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'هل وصلت الفاتورة للعميل؟',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSecondaryContainer,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppTokens.spaceSm),
                          FilledButton(
                            key: const Key('invoice-pdf-confirm'),
                            onPressed: _idle && widget.canWrite()
                                ? _confirm
                                : null,
                            child: _busy == _Action.confirm
                                ? const _Spinner()
                                : const Text('نعم، أُرسلت'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_confirmed) ...[
                    const SizedBox(height: AppTokens.spaceMd),
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: colors.tertiary),
                        const SizedBox(width: AppTokens.spaceSm),
                        Expanded(
                          child: Text(
                            'أكد المالك إرسال الفاتورة عبر واتساب.',
                            style: TextStyle(color: colors.tertiary),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
                if (_message != null && !_confirmed) ...[
                  const SizedBox(height: AppTokens.spaceSm),
                  Text(
                    _message!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _messageIsError
                          ? colors.error
                          : colors.onSurfaceVariant,
                    ),
                  ),
                ],
                if (_failed && !_loading)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      key: const Key('invoice-pdf-reload'),
                      onPressed: _load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _idle ? () => Navigator.pop(context, _confirmed) : null,
            child: Text(_confirmed ? 'تم' : 'إغلاق'),
          ),
        ],
      ),
    );
  }
}

class _InvoiceSummary extends StatelessWidget {
  const _InvoiceSummary({required this.operation});
  final Map<String, Object?> operation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final payload = operation['payload'];
    final name = payload is Map ? payload['customer_name'] : null;
    final phone = payload is Map ? payload['customer_phone'] : null;
    final total = payload is Map ? payload['total_piastres'] : null;
    final parsedTotal = total is String ? Piastres.parseWire(total) : null;
    final time = formatShopTwelveHourTime(
      displayedShopTime(
        occurredAtUtc: operation['occurred_at'] as String,
        occurredAtShop:
            (operation['occurred_at_shop'] ?? operation['occurred_at_cairo'])
                as String,
      ),
    );
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return Container(
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTokens.fieldRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'فاتورة رقم ${operation['shop_sequence']}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(time, style: muted),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Row(
            children: [
              Icon(Icons.person_outline, size: 18, color: colors.primary),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: Text(
                  name is String && name.isNotEmpty
                      ? 'العميل: $name'
                      : 'اسم العميل غير مسجل',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.phone_outlined, size: 18, color: colors.primary),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: Text(
                  phone is String && phone.isNotEmpty
                      ? 'رقم العميل: \u2066$phone\u2069'
                      : 'رقم العميل غير مسجل؛ اختر المستلم بنفسك.',
                  style: phone is String && phone.isNotEmpty ? null : muted,
                ),
              ),
            ],
          ),
          if (parsedTotal is Accepted<Piastres>) ...[
            const Divider(height: AppTokens.spaceLg),
            Row(
              children: [
                const Expanded(child: Text('الإجمالي')),
                Text(
                  '${displayPounds(parsedTotal.value.poundsText)} جنيه',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.primary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) => const SizedBox.square(
    dimension: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}
