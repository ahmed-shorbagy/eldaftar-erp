import 'dart:convert';

import 'package:flutter/material.dart';

import '../../daily_ledger/application/idempotency_key.dart';
import '../../daily_ledger/application/pending_financial_command.dart';
import '../application/inventory_command_flow.dart';
import '../domain/inventory_models.dart';
import 'inventory_copy.dart';
import 'inventory_widgets.dart';

const reviewStaleCopy = 'تغيّرت البيانات. راجع الأثر من جديد قبل الإرسال.';
const dayStaleCopy =
    'تغيّر يوم العمل أو إصداره. راجع الأثر من جديد قبل الإرسال.';

/// Notifies when a visible field changes so a stored review cannot be sent.
class FormRevision extends ChangeNotifier {
  final _bound = <TextEditingController>[];
  var _closed = false;

  void bind(Iterable<TextEditingController> controllers) {
    for (final controller in controllers) {
      if (_bound.contains(controller)) continue;
      controller.addListener(touch);
      _bound.add(controller);
    }
  }

  void touch() {
    if (_closed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    for (final controller in _bound) {
      controller.removeListener(touch);
    }
    _bound.clear();
    super.dispose();
  }
}

mixin InvalidatesReview<T extends StatefulWidget> on State<T> {
  final revision = FormRevision();

  void bindReview(Iterable<TextEditingController> controllers) {
    revision.bind(controllers);
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    revision.touch();
  }
}

class CommandHost extends StatefulWidget {
  const CommandHost({
    super.key,
    required this.title,
    required this.readOnly,
    required this.flow,
    required this.userId,
    required this.shopId,
    required this.day,
    required this.reloadDay,
    required this.fields,
    required this.onReview,
    this.watched = const [],
    this.canReview = true,
    this.embedded = false,
    this.onFinished,
  });

  final String title;
  final bool readOnly;
  final InventoryCommandFlow flow;
  final String userId;
  final String shopId;
  final DayAnchor? day;
  final Future<DayAnchor?> Function() reloadDay;
  final List<Widget> fields;
  final InventoryResult<ReviewedCommand> Function(DayAnchor day) onReview;
  final List<Listenable> watched;
  final bool canReview;
  final bool embedded;
  final VoidCallback? onFinished;

  @override
  State<CommandHost> createState() => _CommandHostState();
}

class _CommandHostState extends State<CommandHost> {
  DayAnchor? _day;
  ReviewedCommand? _review;
  PendingFinancialCommand? _pending;
  String? _key;
  String? _message;
  bool _busy = false;
  bool _unconfirmed = false;
  bool _saved = false;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _day = widget.day;
    for (final source in widget.watched) {
      source.addListener(_invalidate);
    }
  }

  @override
  void dispose() {
    for (final source in widget.watched) {
      source.removeListener(_invalidate);
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CommandHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameWatch(oldWidget.watched, widget.watched)) {
      for (final source in oldWidget.watched) {
        source.removeListener(_invalidate);
      }
      for (final source in widget.watched) {
        source.addListener(_invalidate);
      }
    }
    final dayChanged =
        oldWidget.day?.dayId != widget.day?.dayId ||
        oldWidget.day?.versionWire != widget.day?.versionWire;
    if (!_unconfirmed && !_busy) _day = widget.day;
    if (dayChanged && _review != null && !_busy && !_unconfirmed && !_saved) {
      setState(() {
        _review = null;
        _error = true;
        _message = dayStaleCopy;
      });
    }
  }

  void _invalidate() {
    if (!mounted || _busy || _unconfirmed || _saved || _review == null) return;
    setState(() {
      _review = null;
      _error = true;
      _message = reviewStaleCopy;
    });
  }

  Future<void> _onReview() async {
    final day = _day;
    if (day == null || widget.readOnly || _busy || _unconfirmed) return;
    final result = widget.onReview(day);
    setState(() {
      if (result is InventoryAccepted<ReviewedCommand>) {
        _review = result.value;
        _message = 'راجع الأثر ثم أكد. لم يُرسل شيء بعد.';
        _error = false;
      } else if (result is InventoryRejected<ReviewedCommand>) {
        _review = null;
        _message = inventoryIssueCopy(result.code);
        _error = true;
      }
    });
  }

  bool _fresh(ReviewedCommand stored, ReviewedCommand next, DayAnchor day) {
    final payloadDay = stored.payload['expected_day_id'];
    final payloadVersion = stored.payload['expected_day_version'];
    return next.kind == stored.kind &&
        payloadDay == day.dayId &&
        payloadVersion == day.versionWire &&
        jsonEncode(next.payload) == jsonEncode(stored.payload);
  }

  Future<void> _submit() async {
    final stored = _review;
    final day = _day;
    if (stored == null ||
        day == null ||
        _busy ||
        widget.readOnly ||
        _unconfirmed) {
      return;
    }
    final fresh = widget.onReview(day);
    if (fresh is! InventoryAccepted<ReviewedCommand> ||
        !_fresh(stored, fresh.value, day)) {
      setState(() {
        _review = null;
        _error = true;
        _message = fresh is InventoryAccepted<ReviewedCommand>
            ? (fresh.value.payload['expected_day_id'] == day.dayId &&
                      fresh.value.payload['expected_day_version'] ==
                          day.versionWire
                  ? reviewStaleCopy
                  : dayStaleCopy)
            : reviewStaleCopy;
      });
      return;
    }
    final review = fresh.value;
    final key = _key ?? newIdempotencyKey();
    setState(() {
      _busy = true;
      _key = key;
      _message = null;
    });
    final result = await widget.flow.submit(
      userId: widget.userId,
      shopId: widget.shopId,
      idempotencyKey: key,
      command: review,
      readOnly: widget.readOnly,
    );
    if (!mounted) return;
    await _apply(result);
  }

  Future<void> _retry() async {
    final pending = _pending;
    if (pending == null || _busy) return;
    setState(() => _busy = true);
    final result = await widget.flow.reconcile(
      userId: widget.userId,
      shopId: widget.shopId,
      command: pending,
      retry: true,
    );
    if (!mounted) return;
    await _apply(result);
  }

  Future<void> _apply(InventorySubmitResult result) async {
    if (result is InventorySaved) {
      setState(() {
        _busy = false;
        _saved = true;
        _unconfirmed = false;
        _error = false;
        _message = result.replayed
            ? 'الخادم أعاد نتيجة الأمر المحفوظ نفسه. لم يُكرر الأثر.'
            : 'حفظ الخادم الأمر. هذا التأكيد من رد الخادم.';
      });
      return;
    }
    if (result is InventoryFailed) {
      DayAnchor? day = _day;
      if (result.rereview) day = await widget.reloadDay();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _unconfirmed = false;
        _pending = null;
        _key = null;
        _review = result.rereview ? null : _review;
        _day = day;
        _error = true;
        _message = inventoryFailureCopy(result.code);
      });
      return;
    }
    if (result is InventoryUnconfirmed) {
      setState(() {
        _busy = false;
        _unconfirmed = true;
        _pending = result.command;
        _key = result.command.key;
        _error = true;
        _message = result.statusUnknown
            ? 'لم يتأكد الحفظ. الطلب محفوظ على الجهاز ولم يُحتسب في الأرصدة.'
            : 'لم يظهر الطلب على الخادم. أعد المحاولة بالمفتاح نفسه دون إنشاء أمر جديد.';
      });
      return;
    }
    if (result is InventoryNotSent) {
      setState(() {
        _busy = false;
        _error = true;
        _key = null;
        _message = inventoryFailureCopy(result.code);
      });
    }
  }

  bool _sameWatch(List<Listenable> previous, List<Listenable> next) {
    if (previous.length != next.length) return false;
    for (var index = 0; index < previous.length; index++) {
      if (!identical(previous[index], next[index])) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.readOnly || _unconfirmed || _busy;
    final children = <Widget>[
      if (widget.embedded)
        Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
      if (widget.readOnly)
        const Text(
          'الاشتراك منتهٍ. هذا النموذج للقراءة ولا يرسل أوامر.',
          key: Key('command-readonly'),
        ),
      if (_day == null && !widget.readOnly)
        const Text(
          'لا يوجد يوم عمل مفتوح. افتح اليوم من الدفتر قبل أي أمر.',
          key: Key('command-no-day'),
        ),
      if (_message != null) ...[
        InventoryNotice(message: _message!, error: _error),
        const SizedBox(height: 12),
      ],
      ...widget.fields.map(
        (field) => IgnorePointer(ignoring: locked, child: field),
      ),
      const SizedBox(height: 12),
      if (_review != null) ...[
        EffectList(_review!),
        const SizedBox(height: 12),
      ],
      CommandActions(
        busy: _busy,
        readOnly: widget.readOnly || _saved,
        canReview: widget.canReview && _day != null && !_saved,
        canSubmit: _review != null && !_saved,
        unconfirmed: _unconfirmed,
        onReview: _onReview,
        onSubmit: _submit,
        onRetry: _retry,
      ),
      if (_saved) ...[
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('command-done'),
          onPressed: () {
            if (widget.embedded) {
              widget.onFinished?.call();
              return;
            }
            Navigator.pop(context, true);
          },
          child: const Text('العودة إلى القائمة'),
        ),
      ],
    ];
    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    return PopScope(
      canPop: !_busy,
      child: InventoryPage(title: widget.title, children: children),
    );
  }
}
