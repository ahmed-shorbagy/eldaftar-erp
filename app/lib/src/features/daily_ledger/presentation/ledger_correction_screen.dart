import 'dart:convert';
import '../../../theme/amount_format.dart';

import 'package:flutter/material.dart';

import '../application/financial_gateway.dart';
import '../application/idempotency_key.dart';
import '../application/opening_gateway.dart';
import '../application/pending_financial_command.dart';
import '../data/pending_financial_command.dart';
import '../domain/ledger_compensation.dart';
import '../domain/opening_catalog.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';
import 'ledger_form_fields.dart';

class LedgerCorrectionScreen extends StatefulWidget {
  const LedgerCorrectionScreen({
    super.key,
    required this.gateway,
    required this.statusGateway,
    required this.dayGateway,
    required this.userId,
    required this.shopId,
    required this.book,
    required this.counted,
    this.writesEnabled = true,
  });

  final LedgerCorrectionGateway gateway;
  final OpeningGateway statusGateway;
  final FinancialGateway dayGateway;
  final String userId;
  final String shopId;
  final Map<String, Object?> book;
  final Map<String, Object?> counted;
  final bool writesEnabled;

  @override
  State<LedgerCorrectionScreen> createState() => _LedgerCorrectionScreenState();
}

class _LedgerCorrectionScreenState extends State<LedgerCorrectionScreen> {
  final _reason = TextEditingController();
  final _cash = <String, TextEditingController>{};
  final _stockGrams = <TextEditingController>[];
  final _stockCounts = <TextEditingController>[];
  final _scrapGrams = <TextEditingController>[];
  final _pending = const PendingFinancialCommands();
  CorrectionReview? _review;
  Map<String, Object?>? _countedPayload;
  String? _dayId;
  int? _dayVersion;
  String? _key;
  String? _message;
  bool _busy = false;
  bool _unknown = false;
  bool _blocked = false;
  bool _restoring = true;

  List<Map<String, Object?>> get _bookStock => _rows(widget.book['stock']);
  List<Map<String, Object?>> get _bookScrap => _rows(widget.book['scrap']);

  @override
  void initState() {
    super.initState();
    final countedCash = _map(widget.counted['cash']);
    for (final method in CashMethod.canonicalOrder) {
      _cash[method.code] = TextEditingController(
        text: _pounds(countedCash[method.code]),
      );
    }
    final countedStock = _rows(widget.counted['stock']);
    for (final row in _bookStock) {
      final match = countedStock.cast<Map<String, Object?>?>().firstWhere(
        (item) =>
            item?['category'] == row['category'] &&
            item?['karat'] == row['karat'],
        orElse: () => null,
      );
      _stockGrams.add(
        TextEditingController(text: _grams(match?['milligrams'])),
      );
      _stockCounts.add(TextEditingController(text: '${match?['count'] ?? ''}'));
    }
    final countedScrap = _rows(widget.counted['scrap']);
    for (final row in _bookScrap) {
      final match = countedScrap.cast<Map<String, Object?>?>().firstWhere(
        (item) => item?['karat'] == row['karat'],
        orElse: () => null,
      );
      _scrapGrams.add(
        TextEditingController(text: _grams(match?['milligrams'])),
      );
    }
    _loadPending();
  }

  Future<void> _loadPending() async {
    try {
      final existing = await _pending.read(widget.userId, widget.shopId);
      if (!mounted) return;
      setState(() {
        _restoring = false;
        if (existing == null) return;
        if (existing.kind != 'ledger_correction') {
          _blocked = true;
          _message =
              'عملية مالية أخرى بانتظار تأكيد الخادم. ارجع إلى الدفتر للتحقق.';
          return;
        }
        _key = existing.key;
        _unknown = true;
        _message = 'طلب محفوظ. تحقق من حالته قبل إعادة الإرسال.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _restoring = false;
          _blocked = true;
          _message = 'تعذر قراءة الطلب المحفوظ. ارجع إلى الدفتر وأعد التحقق.';
        });
      }
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    for (final field in _cash.values) {
      field.dispose();
    }
    for (final field in _stockGrams) {
      field.dispose();
    }
    for (final field in _stockCounts) {
      field.dispose();
    }
    for (final field in _scrapGrams) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _prepareReview() async {
    if (_busy || _restoring || _unknown || _blocked || !widget.writesEnabled) {
      return;
    }
    setState(() => _busy = true);
    try {
      final countedCash = <String, BigInt>{};
      for (final method in CashMethod.canonicalOrder) {
        final parsed = Piastres.parsePounds(_cash[method.code]!.text.trim());
        if (parsed is! Accepted<Piastres>) {
          setState(() => _message = 'أدخل النقد المعدود لكل وسيلة .');
          return;
        }
        countedCash[method.code] = parsed.value.value;
      }
      final countedStock = <MetalEffect>[];
      final stockPayload = <Map<String, Object?>>[];
      for (var index = 0; index < _bookStock.length; index++) {
        final grams = Milligrams.parseGrams(_stockGrams[index].text.trim());
        final count = PieceCount.parseWire(_stockCounts[index].text.trim());
        if (grams is! Accepted<Milligrams> || count is! Accepted<PieceCount>) {
          setState(() => _message = 'أدخل الوزن والعدد المعدودين لكل صنف.');
          return;
        }
        final row = _bookStock[index];
        countedStock.add(
          MetalEffect(
            category: row['category'] as String,
            karat: row['karat'] as int,
            milligrams: grams.value.value,
            count: count.value.value,
          ),
        );
        stockPayload.add({
          'category': row['category'],
          'karat': row['karat'],
          'milligrams': grams.value.wire,
          'count': count.value.wire,
        });
      }
      final countedScrap = <MetalEffect>[];
      final scrapPayload = <Map<String, Object?>>[];
      for (var index = 0; index < _bookScrap.length; index++) {
        final grams = Milligrams.parseGrams(_scrapGrams[index].text.trim());
        if (grams is! Accepted<Milligrams>) {
          setState(() => _message = 'أدخل وزن الكسر المعدود لكل عيار.');
          return;
        }
        final row = _bookScrap[index];
        countedScrap.add(
          MetalEffect(
            category: 'scrap',
            karat: row['karat'] as int,
            milligrams: grams.value.value,
          ),
        );
        scrapPayload.add({
          'karat': row['karat'],
          'milligrams': grams.value.wire,
        });
      }
      final reviewed = reviewCountedCorrection(
        reason: _reason.text,
        countedCash: countedCash,
        bookCash: _bookCash(),
        countedStock: countedStock,
        bookStock: [
          for (final row in _bookStock)
            MetalEffect(
              category: row['category'] as String,
              karat: row['karat'] as int,
              milligrams: _wire(row['milligrams']),
              count: _wire(row['count']),
            ),
        ],
        countedScrap: countedScrap,
        bookScrap: [
          for (final row in _bookScrap)
            MetalEffect(
              category: 'scrap',
              karat: row['karat'] as int,
              milligrams: _wire(row['milligrams']),
            ),
        ],
      );
      if (reviewed is! CompensationAccepted<CorrectionReview>) {
        setState(() {
          _review = null;
          _message =
              (reviewed as CompensationRejected<CorrectionReview>).code ==
                  'stock_pair_mismatch'
              ? 'الوزن والعدد يجب أن يتحرّكا معًا للقطع.'
              : 'أدخل سببًا وفرقًا غير صفري داخل الأرصدة الموجودة.';
        });
        return;
      }
      try {
        final day = await widget.dayGateway.dayState(
          callerUserId: widget.userId,
        );
        if (!mounted) return;
        if (!day.isOpen || day.dayId == null || day.dayVersion == null) {
          setState(() => _message = 'افتح يوم عمل قبل تسجيل التسوية.');
          return;
        }
        if (jsonEncode(_canonicalCounts(day.counts)) !=
            jsonEncode(_canonicalCounts(widget.book))) {
          setState(
            () => _message =
                'تغيّرت الأرصدة. ارجع إلى الدفتر وعدّ الأرصدة من جديد.',
          );
          return;
        }
        setState(() {
          _review = reviewed.value;
          _dayId = day.dayId;
          _dayVersion = day.dayVersion;
          _countedPayload = {
            'cash': {
              for (final method in CashMethod.canonicalOrder)
                method.code: countedCash[method.code].toString(),
            },
            'stock': stockPayload,
            'scrap': scrapPayload,
          };
          _message = null;
        });
      } catch (_) {
        if (mounted) setState(() => _message = 'تعذر قراءة يوم العمل.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() async {
    if (_busy || _review == null || _countedPayload == null || _dayId == null) {
      return;
    }
    final key = _key ?? newIdempotencyKey();
    final payload = <String, Object?>{
      'version': 1,
      'kind': 'ledger_correction',
      'expected_day_id': _dayId,
      'expected_day_version': '$_dayVersion',
      'reason': _review!.reason,
      'counted': _countedPayload,
    };
    final body = <String, Object?>{
      'p_idempotency_key': key,
      'p_payload': payload,
    };
    var saved = false;
    setState(() {
      _busy = true;
      _key = key;
      _message = 'بانتظار تأكيد الخادم';
    });
    try {
      await _pending.save(
        widget.userId,
        widget.shopId,
        PendingFinancialCommand(
          key: key,
          kind: 'ledger_correction',
          body: body,
        ),
      );
      saved = true;
      final result = await widget.gateway.postCorrection(
        callerUserId: widget.userId,
        idempotencyKey: key,
        payload: payload,
      );
      if (!mounted) return;
      await _apply(result, key);
    } catch (_) {
      if (!mounted) return;
      if (!saved) {
        setState(() {
          _key = null;
          _message = 'تعذر حفظ طلب التسوية.';
        });
        return;
      }
      await _readStatus(key, retryIfAbsent: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reconcile() async {
    final key = _key;
    if (key == null) return;
    setState(() => _busy = true);
    try {
      await _readStatus(key, retryIfAbsent: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _readStatus(String key, {required bool retryIfAbsent}) async {
    try {
      final status = await widget.statusGateway.status(
        callerUserId: widget.userId,
        idempotencyKey: key,
      );
      if (!mounted) return;
      if (status is StatusCompleted) {
        await _pending.clear(widget.userId, widget.shopId, key);
        if (mounted) Navigator.pop(context, true);
        return;
      }
      if (status is StatusAbsent && retryIfAbsent) {
        final command = await _pending.read(widget.userId, widget.shopId);
        if (!mounted || command == null || command.key != key) return;
        final result = await widget.dayGateway.retryPending(
          callerUserId: widget.userId,
          command: command,
        );
        if (!mounted) return;
        await _apply(result, key);
        return;
      }
      setState(() {
        _unknown = true;
        _message = status is StatusAbsent
            ? 'لم يؤكد الخادم التسوية. أعد المحاولة بالمفتاح نفسه.'
            : 'حالة التسوية غير معروفة. أعد التحقق.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _unknown = true;
          _message = 'تعذر التحقق من التسوية. أعد المحاولة.';
        });
      }
    }
  }

  Future<void> _apply(FinancialCommandResult result, String key) async {
    if (result is FinancialCommitted) {
      await _pending.clear(widget.userId, widget.shopId, key);
      if (mounted) Navigator.pop(context, true);
      return;
    }
    if (result is FinancialRejected) {
      await _pending.clear(widget.userId, widget.shopId, key);
      if (!mounted) return;
      setState(() {
        _key = null;
        _review = null;
        _unknown = false;
        _message = result.code == 'stale_day'
            ? 'تغيّرت الأرصدة أو يوم العمل. حدّث الدفتر وأعد العد.'
            : 'رفض الخادم التسوية. راجع العد والسبب.';
      });
      return;
    }
    await _readStatus(key, retryIfAbsent: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final review = _review;
    final locked =
        review != null || _unknown || _blocked || _busy || _restoring;
    return PopScope(
      canPop: !_busy && !_unknown,
      child: Scaffold(
        appBar: AppBar(title: const Text('تسوية جرد مدققة')),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('مراجعة التسوية', style: theme.textTheme.headlineSmall),
                  const Text(
                    'يُرحّل الفرق الموقّع إلى حسابات التسوية في اليوم المفتوح. الأرصدة السابقة تبقى كما هي.',
                  ),
                  if (!widget.writesEnabled)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text('الاشتراك منتهٍ. العرض للقراءة فقط.'),
                    ),
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _message!,
                      key: const Key('correction-message'),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('correction-reason'),
                    controller: _reason,
                    readOnly: locked || !widget.writesEnabled,
                    maxLength: 1000,
                    maxLines: 3,
                    decoration: ledgerFieldDecoration(
                      context,
                      label: 'سبب التسوية',
                    ),
                  ),
                  Text('النقد المعدود', style: theme.textTheme.titleMedium),
                  for (final method in CashMethod.canonicalOrder) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${_method(method.code)} في الدفتر: ${displayPounds(_pounds(_map(widget.book['cash'])[method.code]))}',
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: Key('correction-cash-${method.code}'),
                      controller: _cash[method.code],
                      readOnly: locked || !widget.writesEnabled,
                      textDirection: TextDirection.ltr,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: ledgerFieldDecoration(
                        context,
                        label: 'المعدود ',
                      ),
                    ),
                  ],
                  for (var index = 0; index < _bookStock.length; index++) ...[
                    const SizedBox(height: 12),
                    Text(
                      'عيار ${_bookStock[index]['karat']} · الدفتر ${_grams(_bookStock[index]['milligrams'])} جرام · ${_bookStock[index]['count']} قطعة',
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: Key('correction-grams-$index'),
                      controller: _stockGrams[index],
                      readOnly: locked || !widget.writesEnabled,
                      textDirection: TextDirection.ltr,
                      decoration: ledgerFieldDecoration(
                        context,
                        label: 'الوزن المعدود بالجرام',
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: Key('correction-count-$index'),
                      controller: _stockCounts[index],
                      readOnly: locked || !widget.writesEnabled,
                      textDirection: TextDirection.ltr,
                      decoration: ledgerFieldDecoration(
                        context,
                        label: 'العدد المعدود',
                      ),
                    ),
                  ],
                  if (review != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      color: theme.colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('الفروق الموقّعة'),
                            for (final method in CashMethod.canonicalOrder)
                              if (review.cashDeltas[method.code] != BigInt.zero)
                                Text(
                                  '${_method(method.code)}: ${_moneyLabel(review.cashDeltas[method.code]!)}',
                                ),
                            for (final line in review.stockDeltas)
                              Text(
                                'عيار ${line.karat}: ${_gramLabel(line.milligrams)} جرام · ${_countLabel(line.count!)} قطعة',
                              ),
                            for (final line in review.scrapDeltas)
                              Text(
                                'الكسر عيار ${line.karat}: ${_gramLabel(line.milligrams)} جرام',
                              ),
                            const Text(
                              'يلزم عدّ فعلي جديد مطابق بعد التسوية قبل التقفيل.',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        bottomNavigationBar: widget.writesEnabled && !_blocked
            ? SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: FilledButton(
                    key: Key(
                      _unknown
                          ? 'correction-check-status'
                          : review == null
                          ? 'correction-review'
                          : 'correction-confirm',
                    ),
                    onPressed: _busy
                        ? null
                        : _unknown
                        ? _reconcile
                        : review == null
                        ? _prepareReview
                        : _submit,
                    child: Text(
                      _busy
                          ? 'بانتظار تأكيد الخادم'
                          : _unknown
                          ? 'التحقق من الحالة'
                          : review == null
                          ? 'مراجعة التسوية'
                          : 'تأكيد التسوية',
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  Map<String, BigInt> _bookCash() {
    final cash = _map(widget.book['cash']);
    return {
      for (final method in CashMethod.canonicalOrder)
        method.code: cash.containsKey(method.code)
            ? _wire(cash[method.code])
            : BigInt.zero,
    };
  }
}

List<Map<String, Object?>> _rows(Object? value) => value is List
    ? [
        for (final row in value)
          if (row is Map) Map<String, Object?>.from(row),
      ]
    : const [];

Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const {};

String _pounds(Object? value) {
  if (value is! String) return '';
  final parsed = Piastres.parseWire(value);
  return parsed is Accepted<Piastres> ? parsed.value.poundsText : '';
}

String _grams(Object? value) {
  if (value is! String) return '';
  final parsed = Milligrams.parseWire(value);
  return parsed is Accepted<Milligrams> ? parsed.value.gramsText : '';
}

BigInt _wire(Object? value) {
  if (value is! String) return BigInt.zero;
  final parsed = BigInt.tryParse(value);
  return parsed ?? BigInt.zero;
}

String _method(String code) => switch (code) {
  'cash' => 'نقدي',
  'instant_transfer' => 'تحويل فوري',
  'wallet' => 'محفظة',
  'card' => 'بطاقة',
  _ => code,
};

Object? _canonicalCounts(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonicalCounts(value[key])};
  }
  if (value is List) return value.map(_canonicalCounts).toList();
  return value;
}

String _moneyLabel(BigInt value) =>
    '\u2066${displayPounds(signedPoundsText(value))}\u2069';
String _gramLabel(BigInt value) => '\u2066${signedGramsText(value)}\u2069';
String _countLabel(BigInt value) => '\u2066$value\u2069';
