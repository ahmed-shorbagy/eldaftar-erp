import 'package:flutter/material.dart';

import '../../../theme/amount_format.dart';
import '../../../theme/app_tokens.dart';
import '../application/ledger_trade_change.dart';
import '../application/financial_gateway.dart';
import '../application/opening_gateway.dart';
import '../application/pending_financial_command.dart';
import '../application/idempotency_key.dart';
import '../data/pending_financial_command.dart';

/// Server-calculated net effects must be reviewed before a durable command exists.
class LedgerTradeChangeScreen extends StatefulWidget {
  const LedgerTradeChangeScreen({
    super.key,
    required this.review,
    required this.gateway,
    required this.statusGateway,
    required this.userId,
    required this.canRead,
    required this.canWrite,
    this.replacement,
    this.syncTicks,
    this.locker = const PendingFinancialCommands(),
  });
  final LedgerTradeChangeReview review;
  final LedgerTradeChangeGateway gateway;
  final OpeningGateway statusGateway;
  final String userId;
  final bool Function() canRead, canWrite;
  final Map<String, Object?>? replacement;
  final Listenable? syncTicks;
  final FinancialCommandLocker locker;
  @override
  State<LedgerTradeChangeScreen> createState() =>
      _LedgerTradeChangeScreenState();
}

class _LedgerTradeChangeScreenState extends State<LedgerTradeChangeScreen> {
  bool _busy = false, _unknown = false, _stale = false, _saved = false;
  String? _message;
  bool _denied = false;
  PendingFinancialCommand? _pending;
  @override
  void initState() {
    super.initState();
    widget.syncTicks?.addListener(_changed);
  }

  @override
  void dispose() {
    widget.syncTicks?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted && !_busy && !_unknown && !_saved) {
      setState(() => _stale = true);
    }
    if (mounted && !widget.canRead()) setState(() => _stale = true);
  }

  Future<void> _send({bool statusOnly = false}) async {
    if (_busy ||
        _saved ||
        !widget.canRead() ||
        (!statusOnly && !widget.canWrite()) ||
        (_stale && !_unknown)) {
      return;
    }
    setState(() => _busy = true);
    try {
      var pending = _pending;
      if (pending == null) {
        final existing = await widget.locker.read(
          widget.userId,
          widget.review.shopId,
        );
        if (!mounted) return;
        if (existing != null) {
          setState(
            () => _message =
                'يوجد طلب مالي محفوظ. تحقق منه في الدفتر قبل تسجيل تغيير جديد.',
          );
          return;
        }
        final key = newIdempotencyKey();
        pending = PendingFinancialCommand(
          key: key,
          kind: tradeChangeKind,
          body: widget.review.request(key, widget.replacement),
        );
        await widget.locker.save(widget.userId, widget.review.shopId, pending);
        _pending = pending;
      }
      FinancialCommandResult result;
      if (statusOnly) {
        final status = await widget.statusGateway.status(
          callerUserId: widget.userId,
          idempotencyKey: pending.key,
        );
        result = switch (status) {
          StatusCompleted(:final operationId) => FinancialCommitted(
            operationId,
            replayed: true,
          ),
          StatusRejected(:final code) => FinancialRejected(code),
          _ => const FinancialUnknown(),
        };
      } else {
        result = await widget.gateway.postTradeChange(
          userId: widget.userId,
          command: pending,
        );
      }
      if (result is FinancialCommitted) {
        await widget.locker.clear(
          widget.userId,
          widget.review.shopId,
          pending.key,
        );
        if (mounted) {
          setState(() {
            _saved = true;
            _unknown = false;
            _message = widget.review.action == 'delete'
                ? 'تم مسح العملية وتحديث الأرصدة بنجاح.'
                : 'تم تعديل العملية وتحديث الأرصدة بنجاح.';
          });
        }
      } else if (result is FinancialRejected) {
        final code = result.code;
        if (const {
          'forbidden',
          'unauthenticated',
          'session_expired',
          'shop_unavailable',
        }.contains(code)) {
          _denied = true;
        }
        // An access/status failure doesn't establish whether a previous post committed.
        if (statusOnly || _unknown) {
          if (mounted) {
            setState(() {
              _unknown = true;
              _message =
                  'تعذر التحقق من الطلب. يبقى محفوظًا حتى تتأكد النتيجة.';
            });
          }
        } else {
          await widget.locker.clear(
            widget.userId,
            widget.review.shopId,
            pending.key,
          );
          if (mounted) {
            setState(() {
              _unknown = false;
              _stale = true;
              _message = tradeChangeFailure(code);
            });
          }
        }
      } else if (mounted) {
        setState(() {
          _unknown = true;
          _message =
              'لم نتأكد من الحفظ. الطلب محفوظ قيد المتابعة. لا تعِد إدخاله.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _unknown = _pending != null;
          _message = _unknown
              ? 'تعذر التأكد من الحفظ. تحقق أو أعد المحاولة بالطلب نفسه.'
              : 'تعذر حفظ الطلب على الجهاز. لم يُرسل التغيير.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final readable = !_denied && widget.canRead();
    final effects = widget.review.effects;
    String signed(String value, {bool gold = false}) {
      final amount = BigInt.parse(value);
      if (amount == BigInt.zero) return 'لا تغيير';
      final direction = amount.isNegative ? 'نقص' : 'زيادة';
      final absolute = amount.abs();
      if (gold) {
        final shown = displayGoldEffect(absolute).replaceAllMapped(
          RegExp(r'[0-9][0-9,.]*'),
          (match) => '\u2066${match[0]}\u2069',
        );
        return '$direction $shown';
      }
      final pounds =
          '${absolute ~/ BigInt.from(100)}.${(absolute % BigInt.from(100)).toString().padLeft(2, '0')}';
      return '$direction \u2066${displayPounds(pounds)}\u2069';
    }

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.review.action == 'delete'
                ? 'مراجعة مسح العملية'
                : 'مراجعة تعديل العملية',
          ),
        ),
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
                  if (!readable)
                    const Text('لم تعد بيانات العملية متاحة لهذا الحساب.')
                  else ...[
                    Text(
                      widget.review.action == 'delete'
                          ? 'سيُلغى أثر العملية وتختفي من الدفتر والفواتير النشطة. يبقى سجل التدقيق محفوظًا.'
                          : 'سيُستبدل القيد بالبيانات المعدّلة. يبقى الأصل في سجل التدقيق.',
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'الأثر الصافي على أرصدة المحل',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    for (final raw in effects['cash'] as List) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${switch (raw['method']) {
                          'cash' => 'نقدي',
                          'instant_transfer' => 'انستا',
                          'card' => 'فيزا',
                          _ => 'محفظة',
                        }}: ${signed(raw['delta_piastres'] as String)}',
                      ),
                    ],
                    if ((effects['cash'] as List).isEmpty)
                      const Text('لا تغيير في النقدية.'),
                    for (final raw in effects['stock'] as List)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'المخزون · ${_category(raw['category'])} · عيار ${raw['karat']}: ${signed(raw['delta_milligrams'] as String, gold: true)} · \u2066${raw['delta_count']}\u2069 قطعة',
                        ),
                      ),
                    for (final raw in effects['scrap'] as List)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'الكسر · عيار ${raw['karat']}: ${signed(raw['delta_milligrams'] as String, gold: true)}',
                        ),
                      ),
                    if ((effects['stock'] as List).isEmpty &&
                        (effects['scrap'] as List).isEmpty)
                      const Text('لا تغيير في المخزون أو الكسر.'),
                    const SizedBox(height: 12),
                    Text(
                      'التغير في مستحقات الشراء: ${signed(effects['payable_delta_piastres'] as String)}',
                    ),
                    const SizedBox(height: 16),
                    if (widget.replacement != null) ...[
                      Text(
                        'البيانات بعد التعديل',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      ..._record(widget.replacement!),
                    ],
                    ExpansionTile(
                      title: const Text('تفاصيل العملية الأصلية'),
                      children: _record(
                        Map<String, Object?>.from(
                          widget.review.source['payload'] as Map,
                        ),
                      ),
                    ),
                  ],
                  if (_busy) const LinearProgressIndicator(),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _message!,
                        key: const Key('trade-change-status'),
                      ),
                    ),
                  if (_stale && !_saved)
                    const Text(
                      'أعد فتح المراجعة لقراءة الأثر الحالي قبل التأكيد.',
                    ),
                  if (_saved)
                    FilledButton(
                      key: const Key('trade-change-done'),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('العودة إلى الدفتر'),
                    )
                  else if (_unknown) ...[
                    FilledButton(
                      onPressed: _busy || !widget.canRead()
                          ? null
                          : () => _send(statusOnly: true),
                      child: const Text('التحقق من النتيجة'),
                    ),
                    OutlinedButton(
                      key: const Key('trade-change-retry'),
                      onPressed: _busy || !readable || !widget.canWrite()
                          ? null
                          : _send,
                      child: const Text('إعادة المحاولة بالطلب نفسه'),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => Navigator.pop(context, false),
                      child: const Text('العودة مع بقاء الطلب قيد المتابعة'),
                    ),
                  ] else
                    FilledButton(
                      key: const Key('trade-change-confirm'),
                      onPressed:
                          _busy || _stale || !readable || !widget.canWrite()
                          ? null
                          : _send,
                      child: Text(
                        widget.review.action == 'delete'
                            ? 'تأكيد المسح وتحديث الأرصدة'
                            : 'تأكيد التعديل وتحديث الأرصدة',
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _record(Map<String, Object?> payload) => [
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        'الإجمالي: \u2066${_money(payload['total_piastres'] as String)}\u2069',
      ),
    ),
    for (final raw in payload['items'] as List)
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          '${raw['item_name']} · ${_category(raw['category'])} · عيار ${raw['karat']} · ${displayGoldEffect(BigInt.parse(raw['milligrams'] as String))}${raw['count'] == null ? '' : ' · ${raw['count']} قطعة'}',
        ),
      ),
    for (final raw in (payload['tenders'] as List? ?? const []))
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          '${_method(raw['method'])}: \u2066${_money(raw['piastres'] as String)}\u2069',
        ),
      ),
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        (payload['customer_name'] as String? ?? '').isEmpty &&
                (payload['customer_phone'] as String? ?? '').isEmpty
            ? 'لا توجد بيانات عميل'
            : 'العميل: ${payload['customer_name']} · \u2066${payload['customer_phone']}\u2069',
      ),
    ),
    if ((payload['description'] as String? ?? '').isNotEmpty)
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text('الوصف: ${payload['description']}'),
      ),
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        (payload['note'] as String? ?? '').isEmpty
            ? 'لا توجد ملاحظات'
            : 'ملاحظات: ${payload['note']}',
      ),
    ),
  ];
}

String _category(Object? value) => switch (value) {
  'worked_jewelry' => 'مشغولات',
  'bullion' => 'سبائك',
  'coin' => 'جنيهات',
  'scrap' => 'كسر',
  _ => 'صنف',
};
String _method(Object? value) => switch (value) {
  'cash' => 'نقدي',
  'instant_transfer' => 'انستا',
  'card' => 'فيزا',
  _ => 'محفظة',
};

String _money(String wire) {
  final value = BigInt.parse(wire);
  return displayPounds(
    '${value ~/ BigInt.from(100)}.${(value % BigInt.from(100)).toString().padLeft(2, '0')}',
  );
}
