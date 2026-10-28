import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../domain/audit_trail.dart';

/// Arabic copy for the owner audit browser (AUD-01).
abstract final class AuditTrailCopy {
  static const title = 'سجل العمليات';
  static const readOnly =
      'صفحة السجل للقراءة فقط. لا يغيّر عرض السجل أي رصيد أو عملية.';
  static const loading = 'جارٍ تحميل السجل';
  static const empty = 'لا توجد عمليات مسجّلة.';
  static const emptyFamily = 'لا توجد عمليات في هذا التصنيف.';
  static const loadError = 'تعذر تحميل السجل. حاول مجددًا.';
  static const retry = 'إعادة المحاولة';
  static const loadMore = 'تحميل المزيد';
  static const loadingMore = 'جارٍ تحميل المزيد…';
  static const accessLost =
      'انتهت صلاحية الوصول إلى السجل. سجّل الدخول بحساب مالك المتجر.';
  static const unknownActor = 'الاسم غير متاح';
  static const serverTime = 'توقيت الخادم';
  static const shopTime = 'توقيت المتجر';
  static const sequence = 'تسلسل العملية';
  static const operation = 'رقم العملية';

  static const filters = <AuditTrailFamily?, String>{
    null: 'الكل',
    AuditTrailFamily.change: 'تعديل',
    AuditTrailFamily.delete: 'حذف',
    AuditTrailFamily.deduction: 'خصم',
    AuditTrailFamily.post: 'تسجيل',
  };
}

class AuditTrailScreen extends StatefulWidget {
  const AuditTrailScreen({super.key, required this.gateway});

  final AuditTrailGateway gateway;

  @override
  State<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends State<AuditTrailScreen> {
  AuditTrailFamily? _family;
  List<AuditTrailEntry> _entries = const [];
  DateTime? _nextAt;
  String? _nextId;
  String _timeZone = 'UTC';
  DateTime? _snapshotAt;
  bool _loading = true;
  bool _loadingMore = false;
  bool _accessLost = false;
  AuditTrailFailure? _error;
  int _ticket = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    final request = ++_ticket;
    final family = _family;
    final beforeAt = more ? _nextAt : null;
    final beforeId = more ? _nextId : null;
    setState(() {
      _error = null;
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _accessLost = false;
      }
    });
    try {
      final page = await widget.gateway.list(
        family: family,
        beforeAt: beforeAt,
        beforeId: beforeId,
      );
      if (!mounted || request != _ticket) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _accessLost = false;
        _timeZone = page.timeZone;
        _snapshotAt = page.snapshotAt;
        _nextAt = page.nextCursorAt;
        _nextId = page.nextCursorId;
        _entries = more ? [..._entries, ...page.entries] : page.entries;
      });
    } on AuditTrailException catch (error) {
      if (!mounted || request != _ticket) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (error.failure == AuditTrailFailure.accessLost) {
          _accessLost = true;
          if (!more) _entries = const [];
        } else {
          _error = error.failure;
          if (error.failure == AuditTrailFailure.staleCursor) {
            _nextAt = null;
            _nextId = null;
          }
        }
      });
    }
  }

  void _selectFamily(AuditTrailFamily? family) {
    if (_family == family || _loading || _loadingMore || _accessLost) return;
    setState(() {
      _family = family;
      _entries = const [];
      _nextAt = null;
      _nextId = null;
      _snapshotAt = null;
    });
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text(AuditTrailCopy.title)),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppTokens.contentMaxWidth,
          ),
          child: ListView(
            padding: const EdgeInsets.all(AppTokens.spaceMd),
            children: [
              Text(AuditTrailCopy.readOnly, style: theme.textTheme.bodyMedium),
              const SizedBox(height: AppTokens.spaceMd),
              _filters(theme),
              const SizedBox(height: AppTokens.spaceMd),
              ..._body(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filters(ThemeData theme) {
    return Wrap(
      spacing: AppTokens.spaceSm,
      runSpacing: AppTokens.spaceSm,
      children: [
        for (final entry in AuditTrailCopy.filters.entries)
          ChoiceChip(
            key: Key(
              'audit-filter-${entry.key == null ? 'all' : entry.key!.name}',
            ),
            label: Text(entry.value),
            selected: _family == entry.key,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            onSelected: _loading || _loadingMore || _accessLost
                ? null
                : (_) => _selectFamily(entry.key),
          ),
      ],
    );
  }

  List<Widget> _body(ThemeData theme) {
    if (_loading && _entries.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.all(AppTokens.spaceLg),
          child: Center(
            child: CircularProgressIndicator(
              key: Key('audit-loading'),
              semanticsLabel: AuditTrailCopy.loading,
            ),
          ),
        ),
      ];
    }
    if (_accessLost && _entries.isEmpty) {
      return const [
        Text(
          AuditTrailCopy.accessLost,
          key: Key('audit-access-loss'),
          textAlign: TextAlign.center,
        ),
      ];
    }
    if (_error != null && _entries.isEmpty) {
      return [
        Text(
          AuditTrailCopy.loadError,
          key: const Key('audit-error'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppTokens.spaceMd),
        OutlinedButton(
          key: const Key('audit-retry'),
          onPressed: _load,
          child: const Text(AuditTrailCopy.retry),
        ),
      ];
    }
    if (_entries.isEmpty) {
      return [
        Text(
          _family == null ? AuditTrailCopy.empty : AuditTrailCopy.emptyFamily,
          key: const Key('audit-empty'),
          textAlign: TextAlign.center,
        ),
      ];
    }
    return [
      if (_snapshotAt != null)
        Padding(
          padding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
          child: Text(
            key: const Key('audit-snapshot'),
            'آخر تحديث للقائمة: ${_ltr(_clock(_snapshotAt!))}',
            style: theme.textTheme.labelMedium,
          ),
        ),
      for (final entry in _entries)
        _AuditCard(entry: entry, timeZone: _timeZone),
      if (_accessLost)
        const Padding(
          padding: EdgeInsets.only(top: AppTokens.spaceMd),
          child: Text(
            AuditTrailCopy.accessLost,
            key: Key('audit-access-loss'),
            textAlign: TextAlign.center,
          ),
        )
      else if (_nextAt != null && _nextId != null)
        Padding(
          padding: const EdgeInsets.only(top: AppTokens.spaceMd),
          child: _loadingMore
              ? const Center(
                  child: Text(
                    AuditTrailCopy.loadingMore,
                    key: Key('audit-loading-more'),
                  ),
                )
              : OutlinedButton(
                  key: const Key('audit-load-more'),
                  onPressed: () => _load(more: true),
                  child: const Text(AuditTrailCopy.loadMore),
                ),
        ),
      if (_error != null && !_accessLost)
        Padding(
          padding: const EdgeInsets.only(top: AppTokens.spaceMd),
          child: Column(
            children: [
              const Text(AuditTrailCopy.loadError, textAlign: TextAlign.center),
              const SizedBox(height: AppTokens.spaceSm),
              OutlinedButton(
                key: const Key('audit-retry'),
                onPressed: () => _load(
                  more:
                      _error != AuditTrailFailure.staleCursor &&
                      _nextAt != null,
                ),
                child: const Text(AuditTrailCopy.retry),
              ),
            ],
          ),
        ),
    ];
  }

  String _clock(DateTime utc) {
    final value = utc.toUtc();
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    final h = value.hour.toString().padLeft(2, '0');
    final min = value.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min UTC';
  }
}

String _ltr(String value) => '\u2066$value\u2069';

class _AuditCard extends StatelessWidget {
  const _AuditCard({required this.entry, required this.timeZone});

  final AuditTrailEntry entry;
  final String timeZone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actor = entry.actorDisplayName ?? AuditTrailCopy.unknownActor;
    return Card(
      key: Key('audit-entry-${entry.id}'),
      margin: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              entry.actionLabel,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (entry.actionLabel == 'عملية مسجّلة') ...[
              const SizedBox(height: AppTokens.spaceSm),
              Text(_ltr(entry.action), textDirection: TextDirection.ltr),
            ],
            const SizedBox(height: AppTokens.spaceSm),
            Text(actor),
            const SizedBox(height: AppTokens.spaceSm),
            Text('${AuditTrailCopy.shopTime}: ${_ltr(entry.createdAtShop)}'),
            Text(
              '${AuditTrailCopy.serverTime}: ${_ltr(_utc(entry.createdAt))} ($timeZone)',
              textDirection: TextDirection.rtl,
            ),
            if (entry.shopSequence != null) ...[
              const SizedBox(height: AppTokens.spaceSm),
              Text('${AuditTrailCopy.sequence}: ${_ltr(entry.shopSequence!)}'),
            ],
            Text('${AuditTrailCopy.operation}: ${_ltr(entry.operationId)}'),
            const SizedBox(height: AppTokens.spaceSm),
            Text(entry.summary),
          ],
        ),
      ),
    );
  }

  String _utc(DateTime value) {
    final utc = value.toUtc();
    final y = utc.year.toString().padLeft(4, '0');
    final m = utc.month.toString().padLeft(2, '0');
    final d = utc.day.toString().padLeft(2, '0');
    final h = utc.hour.toString().padLeft(2, '0');
    final min = utc.minute.toString().padLeft(2, '0');
    final s = utc.second.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min:$s UTC';
  }
}
