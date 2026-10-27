import 'package:flutter/material.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../../theme/app_tokens.dart';
import '../domain/support_models.dart';

/// Arabic copy for the owner support contact (HELP-02, ADR 0036).
abstract final class SupportCopy {
  static const title = 'تواصل مع الدعم';
  static const formTitle = 'استفسار جديد';
  static const categoryLabel = 'التصنيف (اختياري)';
  static const bodyLabel = 'نص الاستفسار';
  static const bodyHint = 'اكتب استفسارك هنا (من 10 إلى 1000 حرف).';
  static const submit = 'إرسال الاستفسار';
  static const submitting = 'جارٍ الإرسال…';
  static const saved = 'تم حفظ استفسارك بنجاح.';
  static const savedReplayed = 'تأكدنا أن استفسارك محفوظ من قبل.';
  static const saveFailed =
      'تعذر إرسال الاستفسار ولم يتم الحفظ. نصك محفوظ هنا؛ حاول مجددًا.';
  static const invalidBody =
      'النص مطلوب بين 10 و1000 حرف بعد إزالة المسافات، ولا يقبل محارف تحكم غير السطر الجديد.';
  static const limitReached =
      'بلغت الحد الأقصى للاستفسارات المفتوحة. يمكنك إرسال استفسار جديد بعد إغلاق استفساراتك السابقة.';
  static const unauthorized =
      'انتهت صلاحية وصولك. سجّل الدخول بحساب مالك المتجر للمتابعة.';
  static const listTitle = 'استفساراتك';
  static const listEmpty = 'لا توجد استفسارات سابقة.';
  static const listError = 'تعذر تحميل الاستفسارات. حاول مجددًا.';
  static const retry = 'إعادة المحاولة';
  static const loadMore = 'تحميل المزيد';
  static const loadingMore = 'جارٍ تحميل المزيد…';
  static const categoryNone = 'بدون تصنيف';
  static const replyPrefix = 'رد الدعم: ';
  static const noReply = 'لم يصل رد بعد.';
  static String freshness(String time) => 'آخر تحديث للقائمة: $time';
  static String remaining(int count) => 'الحروف المتبقية: $count';
  static String overLimit(int count) => 'تجاوزت الحد بـ $count حرفًا';
  static String openCount(int open, int limit) =>
      'استفساراتك المفتوحة: $open من $limit';

  static const categoryLabels = <SupportCategory, String>{
    SupportCategory.subscription: 'اتصال بالاشتراك',
    SupportCategory.technical: 'مشكلة تقنية',
    SupportCategory.financialQuestion: 'سؤال بعد النقد',
    SupportCategory.other: 'أخرى',
  };

  static String statusLabel(SupportInquiryStatus status) => switch (status) {
    SupportInquiryStatus.fresh => 'جديدة',
    SupportInquiryStatus.inProgress => 'قيد المعالجة',
    SupportInquiryStatus.answered => 'تم الرد',
    SupportInquiryStatus.closed => 'مغلقة',
  };

  static String categoryLabelOf(SupportCategory? category) =>
      category == null ? categoryNone : categoryLabels[category]!;
}

bool _timeZonesReady = false;

/// Shop-local wall-clock text with LTR digits, falling back to an explicit
/// UTC label when the zone is unknown.
String supportDateText(DateTime utc, String timeZone) {
  var local = utc.toUtc();
  var zoneLabel = ' UTC';
  if (!_timeZonesReady) {
    try {
      tzdata.initializeTimeZones();
      _timeZonesReady = true;
    } catch (_) {
      // Fall back to the UTC rendering below.
    }
  }
  if (_timeZonesReady) {
    try {
      local = tz.TZDateTime.from(utc.toUtc(), tz.getLocation(timeZone));
      zoneLabel = '';
    } catch (_) {
      local = utc.toUtc();
      zoneLabel = ' UTC';
    }
  }
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final h = local.hour.toString().padLeft(2, '0');
  final min = local.minute.toString().padLeft(2, '0');
  return '\u2066$y-$m-$d $h:$min$zoneLabel\u2069';
}

enum _SubmitPhase { idle, inFlight, saved, savedReplayed, failed }

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, required this.gateway});

  final SupportGateway gateway;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  SupportCategory? _category;
  late final TextEditingController _bodyController = TextEditingController();

  _SubmitPhase _phase = _SubmitPhase.idle;
  SupportFailure? _failure;
  String? _pendingKey;
  String _pendingBody = '';
  SupportCategory? _pendingCategory;

  List<SupportInquiry>? _inquiries;
  DateTime? _nextAt;
  String? _nextId;
  int _openCount = 0;
  int _openLimit = 10;
  String _timeZone = 'UTC';
  DateTime? _snapshotAt;
  bool _listLoading = true;
  bool _loadingMore = false;
  bool _listError = false;

  @override
  void initState() {
    super.initState();
    _reloadList();
  }

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  String get _draft => _bodyController.text;

  String? get _normalizedDraft => normalizeSupportBody(_draft);

  bool get _formBlocked =>
      _phase == _SubmitPhase.inFlight ||
      _failure == SupportFailure.unauthorized ||
      _failure == SupportFailure.inquiryLimit;

  void _onDraftChanged(String value) {
    setState(() {
      _dropPendingKeyIfDraftChanged();
      if (_phase == _SubmitPhase.saved ||
          _phase == _SubmitPhase.savedReplayed) {
        _phase = _SubmitPhase.idle;
      }
    });
  }

  void _onCategoryChanged(SupportCategory? value) {
    setState(() {
      _category = value;
      _dropPendingKeyIfDraftChanged();
      if (_phase == _SubmitPhase.saved ||
          _phase == _SubmitPhase.savedReplayed) {
        _phase = _SubmitPhase.idle;
      }
    });
  }

  /// A minted key only fits the exact draft it was created for; any edit
  /// invalidates it so the next submit starts a fresh key.
  void _dropPendingKeyIfDraftChanged() {
    if (_pendingKey == null) return;
    if (supportDraftChanged(
      storedDraftBody: _pendingBody,
      storedDraftCategory: _pendingCategory,
      draftBody: _draft,
      draftCategory: _category,
    )) {
      _pendingKey = null;
      _pendingBody = '';
      _pendingCategory = null;
    }
  }

  Future<void> _reloadList() async {
    setState(() {
      _listLoading = true;
      _listError = false;
    });
    try {
      final page = await widget.gateway.listInquiries();
      if (!mounted) return;
      setState(() {
        _inquiries = page.inquiries;
        _nextAt = page.nextCursorAt;
        _nextId = page.nextCursorId;
        _openCount = page.openCount;
        _openLimit = page.openLimit;
        _timeZone = page.timeZone;
        _snapshotAt = page.snapshotAt;
        _listLoading = false;
      });
    } on SupportException {
      if (!mounted) return;
      setState(() {
        _listLoading = false;
        _listError = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _listLoading = false;
        _listError = true;
      });
    }
  }

  Future<void> _loadMore() async {
    final cursorAt = _nextAt;
    final cursorId = _nextId;
    if (cursorAt == null || cursorId == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await widget.gateway.listInquiries(
        cursorAt: cursorAt,
        cursorId: cursorId,
      );
      if (!mounted) return;
      setState(() {
        _inquiries = [...?_inquiries, ...page.inquiries];
        _nextAt = page.nextCursorAt;
        _nextId = page.nextCursorId;
        _openCount = page.openCount;
        _openLimit = page.openLimit;
        _snapshotAt = page.snapshotAt;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      // Keep the cursor so the owner can retry the same page.
      setState(() {
        _loadingMore = false;
        _listError = true;
      });
    }
  }

  Future<void> _submit() async {
    if (_formBlocked) return;
    final body = _normalizedDraft;
    if (body == null) {
      setState(() => _failure = SupportFailure.invalidInput);
      return;
    }
    // One key per draft; kept across retryable failures, dropped on
    // definitive validation failures (which never reach the server) and on
    // any draft edit.
    final key = _pendingKey ??= newSupportIdempotencyKey();
    _pendingBody = body;
    _pendingCategory = _category;
    setState(() {
      _phase = _SubmitPhase.inFlight;
      _failure = null;
    });
    try {
      final result = await widget.gateway.createInquiry(
        key: key,
        category: _category,
        bodyAr: body,
      );
      if (!mounted) return;
      setState(() {
        _phase = result.replayed
            ? _SubmitPhase.savedReplayed
            : _SubmitPhase.saved;
        _pendingKey = null;
        _pendingBody = '';
        _pendingCategory = null;
        _bodyController.clear();
        _category = null;
      });
      await _reloadList();
    } on SupportException catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _SubmitPhase.failed;
        _failure = error.failure;
        if (error.failure != SupportFailure.unavailable) {
          // The server answered definitively; the key was not consumed.
          _pendingKey = null;
          _pendingBody = '';
          _pendingCategory = null;
        }
        if (error.failure == SupportFailure.inquiryLimit) {
          _openCount = _openLimit;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _SubmitPhase.failed;
        _failure = SupportFailure.unavailable;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(SupportCopy.title)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTokens.contentMaxWidth,
          ),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildForm(theme),
              const SizedBox(height: AppTokens.spaceLg),
              _buildListSection(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    final normalized = _normalizedDraft;
    final remaining = _draft.runes.length <= 1000
        ? 1000 - _draft.runes.length
        : null;
    final over = remaining == null ? _draft.runes.length - 1000 : null;
    final canSubmit = normalized != null && !_formBlocked;
    return Card(
      key: const Key('support-form'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              SupportCopy.formTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              key: const Key('support-open-count'),
              SupportCopy.openCount(_openCount, _openLimit),
              style: theme.textTheme.labelMedium,
            ),
            const SizedBox(height: AppTokens.spaceMd),
            Text(SupportCopy.categoryLabel, style: theme.textTheme.labelLarge),
            const SizedBox(height: AppTokens.spaceSm),
            Wrap(
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceSm,
              children: [
                for (final category in SupportCategory.values)
                  ChoiceChip(
                    key: Key('support-category-${category.name}'),
                    label: Text(SupportCopy.categoryLabels[category]!),
                    selected: _category == category,
                    onSelected: _formBlocked
                        ? null
                        : (_) => _onCategoryChanged(category),
                  ),
                ChoiceChip(
                  key: const Key('support-category-none'),
                  label: const Text(SupportCopy.categoryNone),
                  selected: _category == null,
                  onSelected: _formBlocked
                      ? null
                      : (_) => _onCategoryChanged(null),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceMd),
            TextField(
              key: const Key('support-body'),
              controller: _bodyController,
              enabled: !_formBlocked,
              minLines: 4,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              onChanged: _onDraftChanged,
              decoration: const InputDecoration(
                labelText: SupportCopy.bodyLabel,
                hintText: SupportCopy.bodyHint,
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              key: const Key('support-char-count'),
              remaining != null
                  ? SupportCopy.remaining(remaining)
                  : SupportCopy.overLimit(over!),
              style: theme.textTheme.labelMedium?.copyWith(
                color: remaining == null ? theme.colorScheme.error : null,
              ),
            ),
            if (_phase == _SubmitPhase.inFlight) ...[
              const SizedBox(height: AppTokens.spaceSm),
              const Text(
                key: Key('support-state-pending'),
                SupportCopy.submitting,
              ),
              const SizedBox(height: AppTokens.spaceSm),
              const LinearProgressIndicator(),
            ],
            if (_phase == _SubmitPhase.saved ||
                _phase == _SubmitPhase.savedReplayed) ...[
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                key: const Key('support-state-saved'),
                _phase == _SubmitPhase.saved
                    ? SupportCopy.saved
                    : SupportCopy.savedReplayed,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (_failure != null && !_formBlocked) ...[
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                key: const Key('support-state-failed'),
                _failureMessage(_failure!),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (_failure == SupportFailure.unauthorized) ...[
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                key: const Key('support-state-unauthorized'),
                SupportCopy.unauthorized,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            if (_failure == SupportFailure.inquiryLimit) ...[
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                key: const Key('support-state-limit'),
                SupportCopy.limitReached,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: AppTokens.spaceMd),
            FilledButton(
              key: const Key('support-submit'),
              onPressed: canSubmit ? _submit : null,
              child: const Text(SupportCopy.submit),
            ),
          ],
        ),
      ),
    );
  }

  String _failureMessage(SupportFailure failure) => switch (failure) {
    SupportFailure.invalidInput => SupportCopy.invalidBody,
    SupportFailure.payloadMismatch => SupportCopy.saveFailed,
    SupportFailure.notFound => SupportCopy.saveFailed,
    SupportFailure.staleCursor => SupportCopy.listError,
    SupportFailure.inquiryLimit => SupportCopy.limitReached,
    SupportFailure.unauthorized => SupportCopy.unauthorized,
    SupportFailure.unavailable => SupportCopy.saveFailed,
  };

  Widget _buildListSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          SupportCopy.listTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        if (_snapshotAt != null) ...[
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            key: const Key('support-freshness'),
            SupportCopy.freshness(supportDateText(_snapshotAt!, _timeZone)),
            style: theme.textTheme.labelMedium,
          ),
        ],
        const SizedBox(height: AppTokens.spaceMd),
        if (_listLoading)
          const Padding(
            padding: EdgeInsets.all(AppTokens.spaceLg),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_listError && (_inquiries == null || _inquiries!.isEmpty))
          Column(
            children: [
              Text(SupportCopy.listError, textAlign: TextAlign.center),
              const SizedBox(height: AppTokens.spaceMd),
              OutlinedButton(
                key: const Key('support-list-retry'),
                onPressed: _reloadList,
                child: const Text(SupportCopy.retry),
              ),
            ],
          )
        else if (_inquiries == null || _inquiries!.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppTokens.spaceLg),
            child: Center(
              child: Text(
                key: Key('support-list-empty'),
                SupportCopy.listEmpty,
              ),
            ),
          )
        else ...[
          for (final inquiry in _inquiries!)
            _InquiryCard(inquiry: inquiry, timeZone: _timeZone),
          if (_nextAt != null && _nextId != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceMd),
              child: _loadingMore
                  ? const Center(
                      child: Text(
                        key: Key('support-loading-more'),
                        SupportCopy.loadingMore,
                      ),
                    )
                  : OutlinedButton(
                      key: const Key('support-more'),
                      onPressed: _loadMore,
                      child: const Text(SupportCopy.loadMore),
                    ),
            ),
          if (_listError)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceMd),
              child: Column(
                children: [
                  Text(SupportCopy.listError, textAlign: TextAlign.center),
                  const SizedBox(height: AppTokens.spaceSm),
                  OutlinedButton(
                    key: const Key('support-list-retry'),
                    onPressed: _nextAt != null ? _loadMore : _reloadList,
                    child: const Text(SupportCopy.retry),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _InquiryCard extends StatelessWidget {
  const _InquiryCard({required this.inquiry, required this.timeZone});

  final SupportInquiry inquiry;
  final String timeZone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: Key('support-item-${inquiry.id}'),
      margin: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceSm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  SupportCopy.categoryLabelOf(inquiry.category),
                  style: theme.textTheme.labelLarge,
                ),
                Text(
                  supportDateText(inquiry.createdAt, timeZone),
                  style: theme.textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              key: const Key('support-item-body'),
              inquiry.bodyAr,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _StatusChip(status: inquiry.status),
            ),
            if (inquiry.replyAr != null) ...[
              const SizedBox(height: AppTokens.spaceSm),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(AppTokens.fieldRadius),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    key: const Key('support-item-reply'),
                    '${SupportCopy.replyPrefix}${inquiry.replyAr!}',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final SupportInquiryStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final answered =
        status == SupportInquiryStatus.answered ||
        status == SupportInquiryStatus.closed;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: answered
            ? theme.colorScheme.secondaryContainer
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTokens.fieldRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Text(
          key: Key('support-item-status-${status.name}'),
          SupportCopy.statusLabel(status),
          style: theme.textTheme.labelMedium?.copyWith(
            color: answered
                ? theme.colorScheme.onSecondaryContainer
                : theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
