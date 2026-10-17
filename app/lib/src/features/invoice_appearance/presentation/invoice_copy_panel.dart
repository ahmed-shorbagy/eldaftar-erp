import 'dart:async';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../../theme/app_tokens.dart';
import '../../daily_ledger/application/confirmed_operation_pdf.dart';
import '../../daily_ledger/application/financial_gateway.dart';
import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/application/pending_financial_command.dart';
import '../../daily_ledger/data/pending_financial_command.dart';
import '../application/branded_invoice_pdf.dart';
import '../application/invoice_appearance_contract.dart';
import '../application/invoice_appearance_flow.dart';
import '../application/invoice_appearance_gateway.dart';
import '../application/invoice_copy_files.dart';
import '../domain/branded_invoice_document.dart';

/// Preview and owner-chosen export for the legacy copy and branded editions.
///
/// Branded reads start only after the owner opens the section. Preview, save,
/// share, and a new edition do not confirm dispatch.
class InvoiceCopyPanel extends StatefulWidget {
  const InvoiceCopyPanel({
    super.key,
    required this.operations,
    required this.userId,
    required this.operationId,
    required this.kind,
    required this.operation,
    required this.canRead,
    required this.canWrite,
    this.appearance,
    this.shopId,
    this.store = const PendingFinancialCommands(),
    this.copies = const InvoiceCopyFiles(),
    this.newKey,
    this.chooseDestination,
    this.shareBytes,
    this.syncTicks,
  });

  final FinancialGateway operations;
  final InvoiceAppearanceGateway? appearance;
  final FinancialCommandLocker store;
  final InvoiceCopyFiles copies;
  final String userId;
  final String? shopId;
  final String operationId;
  final String kind;
  final Map<String, Object?>? operation;
  final bool Function() canRead;
  final bool Function() canWrite;
  final String Function()? newKey;
  final Future<String?> Function(String suggestedName)? chooseDestination;
  final Future<void> Function(Uint8List bytes, String filename)? shareBytes;
  final Listenable? syncTicks;

  @override
  State<InvoiceCopyPanel> createState() => _InvoiceCopyPanelState();
}

class _InvoiceCopyPanelState extends State<InvoiceCopyPanel> {
  final _flowStore = _PanelLocker();
  var _busy = false;
  var _opened = false;
  String? _message;
  PendingFinancialCommand? _command;
  InvoicePresentationList? _editions;
  var _copiesCleared = false;

  @override
  void initState() {
    super.initState();
    widget.syncTicks?.addListener(_onSync);
    if (!widget.canRead()) _loseCopies();
  }

  void _onSync() {
    if (!mounted || _busy) return;
    if (!widget.canRead()) {
      setState(() {
        _opened = false;
        _editions = null;
        _message = 'لم يعد الوصول متاحًا. أُلغيت المعاينة.';
        _loseCopies();
      });
      return;
    }
    if (_command != null || !_opened) return;
    unawaited(_openBranded());
  }

  InvoiceAppearanceFlow? get _flow {
    final appearance = widget.appearance;
    if (appearance == null) return null;
    return InvoiceAppearanceFlow(appearance, _flowStore..inner = widget.store);
  }

  @override
  void didUpdateWidget(covariant InvoiceCopyPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncTicks != widget.syncTicks) {
      oldWidget.syncTicks?.removeListener(_onSync);
      widget.syncTicks?.addListener(_onSync);
    }
    if (oldWidget.userId != widget.userId ||
        oldWidget.shopId != widget.shopId) {
      _opened = false;
      _editions = null;
      _command = null;
      _message = 'لم يعد الوصول متاحًا. أُلغيت المعاينة.';
      _loseCopies();
    } else if (!widget.canRead()) {
      _opened = false;
      _editions = null;
      _message = 'لم يعد الوصول متاحًا. أُلغيت المعاينة.';
      _loseCopies();
    }
  }

  @override
  void dispose() {
    widget.syncTicks?.removeListener(_onSync);
    super.dispose();
  }

  void _loseCopies() {
    if (_copiesCleared) return;
    _copiesCleared = true;
    widget.copies.clear();
  }

  ButtonStyle get _button => OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(AppTokens.minControlSize),
  );

  @override
  Widget build(BuildContext context) {
    if (!widget.canRead()) {
      return const Text('لم يعد الوصول متاحًا. أُلغيت المعاينة.');
    }
    final theme = Theme.of(context);
    final branded = widget.appearance != null && widget.shopId != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Text('نسخ الفاتورة', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('invoice-legacy-preview'),
          style: _button,
          onPressed: _busy || widget.operation == null ? null : _previewLegacy,
          child: const Text('معاينة المستند الأصلي الثابت'),
        ),
        OutlinedButton(
          key: const Key('invoice-legacy-save'),
          style: _button,
          onPressed: _busy || widget.operation == null
              ? null
              : () => _exportLegacy(share: false),
          child: const Text('حفظ المستند الأصلي الثابت'),
        ),
        if (branded) ...[
          FilledButton(
            key: const Key('invoice-branded-open'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(AppTokens.minControlSize),
            ),
            onPressed: _busy ? null : _openBranded,
            child: Text(
              _opened ? 'تحديث النسخ الموسومة' : 'عرض النسخ الموسومة',
            ),
          ),
          if (_opened) ..._brandedBody(theme),
        ],
        if (_message != null) Text(_message!, style: theme.textTheme.bodySmall),
      ],
    );
  }

  List<Widget> _brandedBody(ThemeData theme) {
    final command = _command;
    if (command != null) {
      return [
        const Text(
          'طلب نسخة عرض بانتظار التأكيد. أعد التحقق دون تغيير البيانات.',
        ),
        OutlinedButton(
          key: const Key('invoice-presentation-retry'),
          style: _button,
          onPressed: _busy ? null : _retryPresentation,
          child: const Text('إعادة التحقق من طلب النسخة'),
        ),
      ];
    }
    final list = _editions;
    if (list == null) return const [SizedBox.shrink()];
    return [
      if (!widget.canWrite() || !list.canWrite)
        const Text(
          'انتهى الاشتراك. لا يمكن إنشاء نسخة موسومة جديدة. يبقى تصدير النسخ المحفوظة والمستند الأصلي متاحًا.',
        ),
      if (list.items.isEmpty) const Text('لا توجد نسخة موسومة بعد.'),
      for (final item in list.items)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('نسخة موسومة · إصدار ${item.edition}'),
                _digits('وقت إنشاء النسخة: ${item.createdAtShop}'),
                const Text(
                  'وقت العملية يظهر داخل المعاينة منفصلًا عن وقت النسخة.',
                ),
                OutlinedButton(
                  key: Key('invoice-edition-preview-${item.edition}'),
                  style: _button,
                  onPressed: _busy
                      ? null
                      : () => _previewEdition(item.edition, item.contentSha256),
                  child: const Text('معاينة'),
                ),
                OutlinedButton(
                  key: Key('invoice-edition-save-${item.edition}'),
                  style: _button,
                  onPressed: _busy
                      ? null
                      : () => _exportEdition(
                          item.edition,
                          item.contentSha256,
                          share: false,
                        ),
                  child: const Text('حفظ على الجهاز'),
                ),
                OutlinedButton(
                  key: Key('invoice-edition-share-${item.edition}'),
                  style: _button,
                  onPressed: _busy
                      ? null
                      : () => _exportEdition(
                          item.edition,
                          item.contentSha256,
                          share: true,
                        ),
                  child: const Text('مشاركة'),
                ),
              ],
            ),
          ),
        ),
      FilledButton(
        key: const Key('invoice-edition-new'),
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(AppTokens.minControlSize),
        ),
        onPressed: _busy || !widget.canWrite() || !list.canWrite
            ? null
            : _newEdition,
        child: const Text('إصدار نسخة موسومة جديدة'),
      ),
    ];
  }

  Widget _digits(String value) {
    final separator = value.indexOf(': ');
    final label = separator < 0 ? '' : value.substring(0, separator);
    final stamp = separator < 0 ? value : value.substring(separator + 2);
    if (separator < 0 || !RegExp(r'[\u0600-\u06FF]').hasMatch(label)) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(value),
        ),
      );
    }
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$label: '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(stamp),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openBranded() async {
    final appearance = widget.appearance;
    final shopId = widget.shopId;
    if (_busy || appearance == null || shopId == null) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!_authorized(appearance)) {
        await _drop('لم يعد الوصول متاحًا. أُلغيت المعاينة.');
        return;
      }
      final pending = await widget.store.read(widget.userId, shopId);
      if (!_authorized(appearance)) {
        await _drop('لم يعد الوصول متاحًا. أُلغيت المعاينة.');
        return;
      }
      if (pending != null) {
        final payload = pending.body['p_payload'];
        final operation = payload is Map ? payload['operation_id'] : null;
        if (pending.kind == invoicePresentationKind &&
            operation == widget.operationId) {
          if (mounted) {
            setState(() {
              _opened = true;
              _command = pending;
              _editions = null;
              _message =
                  'طلب نسخة عرض بانتظار التأكيد. أعد التحقق دون تغيير البيانات.';
            });
          }
          return;
        }
        if (mounted) {
          setState(
            () => _message =
                'يوجد طلب آخر بانتظار التأكيد. أكمله قبل إصدار نسخة جديدة.',
          );
        }
        return;
      }
      final list = await appearance.listPresentations(
        userId: widget.userId,
        shopId: shopId,
        operationId: widget.operationId,
      );
      if (!_authorized(appearance) ||
          list.shopId != shopId ||
          list.operationId != widget.operationId) {
        await _drop('لم يعد الوصول متاحًا. أُلغيت المعاينة.');
        return;
      }
      if (mounted) {
        setState(() {
          _opened = true;
          _command = null;
          _editions = list;
        });
      }
    } on InvoiceAppearanceException catch (error) {
      if (mounted) setState(() => _message = _failure(error.code));
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'تعذر تحميل النسخ. أعد المحاولة.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retryPresentation() async {
    final flow = _flow;
    final command = _command;
    final shopId = widget.shopId;
    if (flow == null || command == null || shopId == null || _busy) return;
    setState(() => _busy = true);
    final outcome = await flow.reconcile(
      widget.userId,
      shopId,
      command,
      retry: true,
      canWrite: widget.canWrite(),
    );
    if (!mounted) return;
    _command = outcome.pending;
    _message = _outcomeText(outcome);
    if (outcome.receipt != null) {
      _command = null;
      setState(() => _busy = false);
      await _openBranded();
      return;
    }
    setState(() => _busy = false);
  }

  Future<void> _newEdition() async {
    final appearance = widget.appearance;
    final flow = _flow;
    final shopId = widget.shopId;
    if (appearance == null || flow == null || shopId == null || _busy) return;
    if (!widget.canWrite()) {
      setState(
        () => _message =
            'انتهى الاشتراك. لا يمكن إنشاء نسخة موسومة جديدة. يبقى تصدير النسخ المحفوظة والمستند الأصلي متاحًا.',
      );
      return;
    }
    setState(() => _busy = true);
    try {
      if (!_authorized(appearance)) {
        await _drop('لم يعد الوصول متاحًا. أُلغيت المعاينة.');
        return;
      }
      final source = await appearance.readBrandSource(
        userId: widget.userId,
        shopId: shopId,
        operationId: widget.operationId,
      );
      if (!_authorized(appearance) ||
          source.shopId != shopId ||
          source.operationId != widget.operationId) {
        await _drop('تغيّرت النسخة. أُلغيت المعاينة. أعد الفتح.');
        return;
      }
      if (!source.canWrite) {
        setState(
          () => _message =
              'انتهى الاشتراك. لا يمكن إنشاء نسخة موسومة جديدة. يبقى تصدير النسخ المحفوظة والمستند الأصلي متاحًا.',
        );
        return;
      }
      final payload = presentationCommandPayload(
        operationId: source.operationId,
        contentSha256: source.contentSha256,
        expectedAppearanceRevision: source.appearance.revision,
        expectedLatestEdition: source.latestEdition,
      );
      final outcome = await flow.submitPresentation(
        widget.userId,
        shopId,
        (widget.newKey ?? newIdempotencyKey)(),
        payload,
        canWrite: widget.canWrite(),
      );
      if (!mounted || !_authorized(appearance)) {
        await _drop('لم يعد الوصول متاحًا. أُلغيت المعاينة.');
        return;
      }
      _command = outcome.pending;
      _message = _outcomeText(outcome);
      if (outcome.receipt != null) {
        _command = null;
        final list = await appearance.listPresentations(
          userId: widget.userId,
          shopId: shopId,
          operationId: widget.operationId,
        );
        _editions = list;
      }
    } on InvoiceAppearanceException catch (error) {
      _message = _failure(error.code);
    } catch (_) {
      _message = 'تعذر إصدار النسخة. أعد المحاولة.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewLegacy() async {
    final fresh = await _freshOperation();
    if (!mounted || fresh == null) return;
    await _showPreview(
      title: 'المستند الأصلي الثابت',
      facts: [
        Text('رقم العملية ${fresh['shop_sequence'] ?? '—'}'),
        _digits(
          'وقت العملية: ${fresh['occurred_at_cairo'] ?? fresh['occurred_at'] ?? '—'}',
        ),
        const Text('هذه معاينة. المعاينة ليست حفظًا أو مشاركة أو طباعة.'),
      ],
      onSave: () => _exportLegacy(share: false),
      onShare: () => _exportLegacy(share: true),
    );
  }

  Future<void> _previewEdition(int edition, String hash) async {
    final copy = await _freshEdition(edition, hash);
    if (!mounted || copy == null) return;
    await _showPreview(
      title: 'نسخة موسومة · إصدار ${copy.edition}',
      facts: [
        Text('رقم العملية ${copy.shopSequence}'),
        _digits('وقت العملية: ${copy.occurredAtShop}'),
        _digits('وقت إنشاء النسخة: ${copy.createdAtShop}'),
        Text('مراجعة المظهر ${copy.appearance.revision}'),
        const Text('هذه معاينة. المعاينة ليست حفظًا أو مشاركة أو طباعة.'),
      ],
      onSave: () => _exportEdition(edition, hash, share: false),
      onShare: () => _exportEdition(edition, hash, share: true),
    );
  }

  Future<void> _showPreview({
    required String title,
    required List<Widget> facts,
    required Future<void> Function() onSave,
    required Future<void> Function() onShare,
  }) async {
    final transform = TransformationController();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: AppTokens.contentMaxWidth,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    key: const Key('invoice-copy-zoom-in'),
                    tooltip: 'تكبير',
                    onPressed: () => _zoom(transform, 1.25),
                    icon: const Icon(Icons.zoom_in),
                  ),
                  IconButton(
                    key: const Key('invoice-copy-zoom-out'),
                    tooltip: 'تصغير',
                    onPressed: () => _zoom(transform, 0.8),
                    icon: const Icon(Icons.zoom_out),
                  ),
                ],
              ),
              SizedBox(
                height: 220,
                child: InteractiveViewer(
                  transformationController: transform,
                  minScale: 1,
                  maxScale: 4,
                  child: ListView(children: facts),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إغلاق'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await onSave();
            },
            child: const Text('حفظ'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await onShare();
            },
            child: const Text('مشاركة'),
          ),
        ],
      ),
    );
  }

  void _zoom(TransformationController transform, double factor) {
    final current = transform.value.getMaxScaleOnAxis();
    final next = (current * factor).clamp(1.0, 4.0);
    transform.value = Matrix4.identity()..scaleByDouble(next, next, 1, 1);
  }

  Future<void> _exportLegacy({required bool share}) async {
    await _handoff(
      name: 'المستند الأصلي الثابت',
      filename: 'eldaftar-original-${widget.operationId}.pdf',
      share: share,
      produce: () async {
        final fresh = await _freshOperation();
        if (fresh == null) return null;
        try {
          return await buildConfirmedOperationPdf(fresh);
        } on FormatException {
          if (mounted) {
            setState(
              () => _message = 'تعذر تجهيز المستند لأن البيانات غير مكتملة.',
            );
          }
          return null;
        } catch (_) {
          if (mounted) {
            setState(() => _message = 'تعذر تجهيز الخط. أعد المحاولة.');
          }
          return null;
        }
      },
    );
  }

  Future<void> _exportEdition(
    int edition,
    String hash, {
    required bool share,
  }) async {
    await _handoff(
      name: 'نسخة موسومة · إصدار $edition',
      filename: 'eldaftar-branded-${widget.operationId}-e$edition.pdf',
      share: share,
      produce: () async {
        final copy = await _freshEdition(edition, hash);
        if (copy == null) return null;
        if (copy.logoState == 'unverified') {
          if (mounted) {
            setState(
              () =>
                  _message = 'الشعار غير موثّق. لا يمكن تصدير النسخة الموسومة.',
            );
          }
          return null;
        }
        try {
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
          final logo = copy.logoBytes == null
              ? null
              : Uint8List.fromList(copy.logoBytes!);
          return await buildBrandedInvoicePdf(document, logoBytes: logo);
        } on FormatException catch (error) {
          if (mounted) {
            setState(
              () => _message = error.message == 'logo_unverified'
                  ? 'الشعار غير موثّق. لا يمكن تصدير النسخة الموسومة.'
                  : 'تعذر تجهيز النسخة لأن بيانات العملية غير مكتملة.',
            );
          }
          return null;
        } catch (_) {
          if (mounted) {
            setState(
              () => _message = 'تعذر تجهيز الخط أو الصفحات. أعد المحاولة.',
            );
          }
          return null;
        }
      },
    );
  }

  Future<void> _handoff({
    required String name,
    required String filename,
    required bool share,
    required Future<Uint8List?> Function() produce,
  }) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await produce();
      if (!mounted || bytes == null) return;
      if (!widget.canRead()) {
        await _drop('لم يعد الوصول متاحًا. أُلغيت المعاينة.');
        return;
      }
      await widget.copies.write(filename, bytes);
      if (!widget.canRead()) {
        await _drop('لم يعد الوصول متاحًا. أُلغيت المعاينة.');
        return;
      }
      if (share) {
        if (widget.shareBytes != null) {
          await widget.shareBytes!(bytes, filename);
        } else {
          await Printing.sharePdf(bytes: bytes, filename: filename);
        }
        if (!mounted || !widget.canRead()) {
          await _drop('لم يعد الوصول متاحًا. أُلغيت المعاينة.');
          return;
        }
        setState(
          () =>
              _message = 'فُتحت مشاركة «$name». هذا ليس تأكيد إرسال أو تسليم.',
        );
        return;
      }
      final path = widget.chooseDestination != null
          ? await widget.chooseDestination!(filename)
          : (await getSaveLocation(
              suggestedName: filename,
              acceptedTypeGroups: const [
                XTypeGroup(label: 'PDF', extensions: ['pdf']),
              ],
            ))?.path;
      if (!widget.canRead()) {
        await _drop('لم يعد الوصول متاحًا. أُلغيت المعاينة.');
        return;
      }
      if (path == null) return;
      await XFile.fromData(
        bytes,
        mimeType: 'application/pdf',
        name: filename,
      ).saveTo(path);
      if (mounted) {
        setState(() => _message = 'حُفظت النسخة على الجهاز. هذا ليس إرسالًا.');
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message =
              'حفظ أو مشاركة هذه النسخة غير متاح على هذا الجهاز. أعد المحاولة لاحقًا.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Map<String, Object?>?> _freshOperation() async {
    if (!widget.canRead()) {
      await _drop('لم يعد الوصول متاحًا. أُلغيت المعاينة.');
      return null;
    }
    final appearance = widget.appearance;
    if (appearance != null &&
        appearance.appearanceSession(widget.userId) == null) {
      await _drop('لم يعد الوصول متاحًا. أُلغيت المعاينة.');
      return null;
    }
    try {
      final fresh = await widget.operations.operation(
        callerUserId: widget.userId,
        operationId: widget.operationId,
      );
      if (!widget.canRead() || fresh['operation_id'] != widget.operationId) {
        await _drop('لم يعد الوصول متاحًا. أُلغيت المعاينة.');
        return null;
      }
      final shop = fresh['shop_id'];
      if (widget.shopId != null && shop is String && shop != widget.shopId) {
        await _drop('لم يعد الوصول متاحًا. أُلغيت المعاينة.');
        return null;
      }
      final loaded = widget.operation;
      if (loaded != null &&
          (fresh['kind'] != loaded['kind'] ||
              fresh['shop_sequence'] != loaded['shop_sequence'] ||
              canonicalInvoiceJson(fresh['payload']) !=
                  canonicalInvoiceJson(loaded['payload']))) {
        await _drop('تغيّرت النسخة. أُلغيت المعاينة. أعد الفتح.');
        return null;
      }
      return fresh;
    } catch (_) {
      await _drop('تعذر إعادة قراءة العملية. أُلغيت المعاينة.');
      return null;
    }
  }

  Future<InvoicePresentationCopy?> _freshEdition(
    int edition,
    String hash,
  ) async {
    final appearance = widget.appearance;
    final shopId = widget.shopId;
    if (appearance == null || shopId == null || !widget.canRead()) {
      await _drop('لم يعد الوصول متاحًا. أُلغيت المعاينة.');
      return null;
    }
    if (appearance.appearanceSession(widget.userId) == null) {
      await _drop('لم يعد الوصول متاحًا. أُلغيت المعاينة.');
      return null;
    }
    try {
      final copy = await appearance.readPresentation(
        userId: widget.userId,
        shopId: shopId,
        operationId: widget.operationId,
        edition: edition,
      );
      if (!widget.canRead() ||
          copy.shopId != shopId ||
          copy.operationId != widget.operationId ||
          copy.edition != edition ||
          copy.contentSha256 != hash ||
          !copy.contentMatches) {
        await _drop('تغيّرت النسخة. أُلغيت المعاينة. أعد الفتح.');
        return null;
      }
      return copy;
    } on InvoiceAppearanceException catch (error) {
      await _drop(_failure(error.code));
      return null;
    } catch (_) {
      await _drop('تعذر إعادة قراءة النسخة. أُلغيت المعاينة.');
      return null;
    }
  }

  bool _authorized(InvoiceAppearanceGateway appearance) =>
      widget.canRead() && appearance.appearanceSession(widget.userId) != null;

  Future<void> _drop(String message) async {
    _loseCopies();
    _opened = false;
    _editions = null;
    if (mounted) setState(() => _message = message);
  }

  String _outcomeText(InvoiceCommandOutcome outcome) {
    if (outcome.receipt != null && outcome.error == null) {
      return 'حُفظت النسخة الموسومة على الخادم. هذا ليس إرسالًا.';
    }
    if (outcome.error == 'shop_not_active') {
      return 'انتهى الاشتراك. لا يمكن إنشاء نسخة موسومة جديدة. يبقى تصدير النسخ المحفوظة والمستند الأصلي متاحًا.';
    }
    if (outcome.pending != null && outcome.error == null) {
      return 'طلب نسخة عرض بانتظار التأكيد. أعد التحقق دون تغيير البيانات.';
    }
    return _failure(outcome.error);
  }

  String _failure(String? code) => switch (code) {
    'session_expired' ||
    'unauthenticated' ||
    'forbidden' => 'لم يعد الوصول متاحًا. أُلغيت المعاينة.',
    'stale_operation' ||
    'stale_appearance' ||
    'stale_presentation' => 'تغيّرت النسخة. أُلغيت المعاينة. أعد الفتح.',
    'shop_not_active' =>
      'انتهى الاشتراك. لا يمكن إنشاء نسخة موسومة جديدة. يبقى تصدير النسخ المحفوظة والمستند الأصلي متاحًا.',
    'payload_mismatch' =>
      'الطلب المحفوظ لا يطابق هذه البيانات. لا تُرسل نسخة أخرى.',
    'other_pending' =>
      'يوجد طلب آخر بانتظار التأكيد. أكمله قبل إصدار نسخة جديدة.',
    _ => 'تعذر إكمال النسخة. أعد المحاولة.',
  };
}

/// Forwards the one locker while the flow calls save and clear.
final class _PanelLocker implements FinancialCommandLocker {
  FinancialCommandLocker? inner;

  @override
  Future<void> clear(String userId, String shopId, String key) =>
      inner!.clear(userId, shopId, key);

  @override
  Future<PendingFinancialCommand?> read(String userId, String shopId) =>
      inner!.read(userId, shopId);

  @override
  Future<void> save(
    String userId,
    String shopId,
    PendingFinancialCommand command,
  ) => inner!.save(userId, shopId, command);
}
