import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import '../../../theme/app_tokens.dart';
import '../application/debt_statement_flow.dart';
import '../application/debt_statement_gateway.dart';
import '../data/debt_statement_platform.dart';
import '../domain/debt_rules.dart';
import 'debt_statement_pdf.dart';

typedef StatementRasterizer = Future<List<Uint8List>> Function(Uint8List);
Future<List<Uint8List>> rasterDebtStatement(Uint8List bytes) async {
  final pages = <Uint8List>[];
  try {
    await for (final page in Printing.raster(bytes, dpi: 100)) {
      pages.add(await page.toPng());
    }
    return pages;
  } catch (_) {
    for (final p in pages) {
      p.fillRange(0, p.length, 0);
    }
    rethrow;
  }
}

class DebtStatementScreen extends StatefulWidget {
  const DebtStatementScreen({
    super.key,
    required this.gateway,
    required this.userId,
    required this.shopId,
    required this.sourceKind,
    required this.sourceId,
    required this.canRead,
    this.syncTicks,
    this.platform,
    this.render = buildDebtStatementPdf,
    this.raster = rasterDebtStatement,
  });
  final DebtStatementGateway gateway;
  final String userId, shopId, sourceId;
  final DebtSourceKind sourceKind;
  final bool Function() canRead;
  final Listenable? syncTicks;
  final DebtStatementPlatform? platform;
  final StatementRenderer render;
  final StatementRasterizer raster;
  @override
  State<DebtStatementScreen> createState() => _DebtStatementScreenState();
}

class _DebtStatementScreenState extends State<DebtStatementScreen>
    with WidgetsBindingObserver {
  late DebtStatementFlow _flow;
  late DebtStatementPlatform _platform;
  Timer? _sessionWatch;
  List<Uint8List>? _pages;
  StatementCapabilities _caps = const StatementCapabilities();
  String _message = 'جارٍ إعداد كشف الحساب من الخادم…';
  bool _preparing = true, _handoff = false;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.syncTicks?.addListener(_invalidate);
    _platform = widget.platform ?? NativeDebtStatementPlatform();
    _createFlow();
    _prepare();
    _sessionWatch = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_flow.authorized || (_flow.statement != null && !_flow.current)) {
        _invalidate();
      }
    });
  }

  void _createFlow() => _flow = DebtStatementFlow(
    gateway: widget.gateway,
    platform: _platform,
    render: widget.render,
    userId: widget.userId,
    shopId: widget.shopId,
    sourceKind: widget.sourceKind,
    sourceId: widget.sourceId,
    canRead: () => mounted && widget.canRead(),
  );
  @override
  void didUpdateWidget(DebtStatementScreen old) {
    super.didUpdateWidget(old);
    if (old.syncTicks != widget.syncTicks) {
      old.syncTicks?.removeListener(_invalidate);
      widget.syncTicks?.addListener(_invalidate);
    }
    if (old.gateway != widget.gateway ||
        old.userId != widget.userId ||
        old.shopId != widget.shopId ||
        old.sourceId != widget.sourceId ||
        old.sourceKind != widget.sourceKind) {
      _invalidate();
      _createFlow();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_handoff) _invalidate();
  }

  void _clearPages() {
    for (final p in _pages ?? <Uint8List>[]) {
      PaintingBinding.instance.imageCache.evict(
        MemoryImage(p),
        includeLive: true,
      );
      p.fillRange(0, p.length, 0);
    }
    _pages = null;
  }

  void _invalidate() {
    if (_pages == null && !_preparing && _flow.statement == null) return;
    _generation++;
    _flow.invalidate();
    _clearPages();
    if (mounted) {
      setState(() {
        _preparing = false;
        _message =
            'تغيّرت البيانات أو الجلسة. أعد إعداد الكشف قبل الحفظ أو المشاركة.';
      });
    }
  }

  Future<void> _prepare() async {
    if (_flow.busy || _preparing && _flow.statement != null) return;
    final generation = ++_generation;
    _clearPages();
    setState(() {
      _preparing = true;
      _message = 'جارٍ إعداد كشف الحساب من الخادم…';
    });
    final result = await _flow.prepare();
    if (!mounted || generation != _generation) return;
    if (result != StatementOutcome.prepared) {
      setState(() {
        _preparing = false;
        _message = 'تعذر إعداد الكشف. تحقق من الاتصال والصلاحية وأعد المحاولة.';
      });
      return;
    }
    List<Uint8List>? owned;
    try {
      final pages = await widget.raster(_flow.bytes!);
      owned = pages;
      if (!mounted || generation != _generation || !_flow.current) {
        for (final p in pages) {
          p.fillRange(0, p.length, 0);
        }
        return;
      }
      if (pages.isEmpty) throw StateError('empty_preview');
      final caps = await _platform.capabilities();
      if (!mounted || generation != _generation || !_flow.current) {
        for (final p in pages) {
          p.fillRange(0, p.length, 0);
        }
        return;
      }
      setState(() {
        _pages = pages;
        _caps = caps;
        _preparing = false;
        _message =
            'تم إعداد الكشف. راجع الصفحات قبل اختيار حفظ أو مشاركة أو طباعة.';
      });
      owned = null;
    } catch (_) {
      for (final p in owned ?? <Uint8List>[]) {
        p.fillRange(0, p.length, 0);
      }
      if (!mounted || generation != _generation) return;
      _flow.invalidate();
      setState(() {
        _preparing = false;
        _message = 'تعذر عرض صفحات الكشف. أعد الإعداد للمحاولة مجددًا.';
      });
    }
  }

  Future<void> _act(StatementAction action) async {
    if (_handoff || _preparing || _pages == null) return;
    setState(() {
      _handoff = true;
      _message = 'جارٍ التحقق من صلاحية الكشف وحداثته…';
    });
    final result = await _flow.handoff(action);
    if (!mounted) return;
    if (result == StatementOutcome.stale || _flow.bytes == null) _clearPages();
    setState(() {
      _handoff = false;
      _message = switch (result) {
        StatementOutcome.prepared => 'تم إعداد الكشف.',
        StatementOutcome.saved => 'تم حفظ الملف في المكان الذي اخترته.',
        StatementOutcome.handedOff =>
          'جرت محاولة تسليم الملف للنظام؛ النتيجة الخارجية غير مؤكدة. لا يمكن تأكيد المشاركة أو الطباعة الفعلية.',
        StatementOutcome.cancelled =>
          'أُلغي اختيار النظام. لم يُؤكَّد حفظ أو طباعة.',
        StatementOutcome.unavailable => 'هذا الإجراء غير متاح على هذا الجهاز.',
        StatementOutcome.stale =>
          'تغيّر الكشف أو فقدت الجلسة صلاحيتها. أعد الإعداد وراجع الصفحات مجددًا.',
        StatementOutcome.busy => 'جارٍ تنفيذ طلب سابق.',
        StatementOutcome.failed =>
          'تعذر إتمام الإجراء. أعد المحاولة بعد التحقق من الاتصال.',
      };
    });
  }

  @override
  void dispose() {
    _generation++;
    _sessionWatch?.cancel();
    widget.syncTicks?.removeListener(_invalidate);
    WidgetsBinding.instance.removeObserver(this);
    _flow.invalidate();
    _clearPages();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _flow.statement;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('كشف حساب دين')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppTokens.contentMaxWidth,
              ),
              child: ListView(
                padding: const EdgeInsets.all(AppTokens.spaceMd),
                children: [
                  if (s != null) ...[
                    Text(
                      s.shopName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(s.partyName),
                    Text(
                      '${statementSource(s.sourceKind)} • المتبقي: ${statementAmount(s, s.remaining)}',
                    ),
                    Text(
                      'وقت اللقطة بالمحل: \u2066${s.snapshotAtShop.replaceFirst('T', ' ')}\u2069',
                    ),
                  ],
                  const Text(statementScope),
                  const SizedBox(height: AppTokens.spaceMd),
                  Semantics(
                    liveRegion: true,
                    child: Text(_message, key: const Key('statement-status')),
                  ),
                  if (_preparing || _handoff)
                    const Padding(
                      padding: EdgeInsets.all(AppTokens.spaceMd),
                      child: LinearProgressIndicator(),
                    ),
                  const SizedBox(height: AppTokens.spaceSm),
                  Wrap(
                    spacing: AppTokens.spaceSm,
                    runSpacing: AppTokens.spaceSm,
                    children: [
                      _button(
                        'إعداد كشف جديد',
                        !_preparing && !_handoff ? _prepare : null,
                        'statement-prepare',
                      ),
                      if (_pages != null && _caps.save)
                        _button(
                          'حفظ الملف',
                          !_handoff ? () => _act(StatementAction.save) : null,
                          'statement-save',
                        ),
                      if (_pages != null && _caps.share)
                        _button(
                          'مشاركة الملف',
                          !_handoff ? () => _act(StatementAction.share) : null,
                          'statement-share',
                        ),
                      if (_pages != null && _caps.print)
                        _button(
                          'طباعة النظام',
                          !_handoff ? () => _act(StatementAction.print) : null,
                          'statement-print',
                        ),
                    ],
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  if (_pages != null)
                    for (var i = 0; i < _pages!.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppTokens.spaceMd,
                        ),
                        child: InteractiveViewer(
                          minScale: 1,
                          maxScale: 4,
                          child: Image.memory(
                            _pages![i],
                            key: ValueKey('statement-page-$i'),
                            semanticLabel:
                                'صفحة ${i + 1} من ${_pages!.length} من كشف حساب الدين',
                            gaplessPlayback: false,
                          ),
                        ),
                      ),
                  if (s != null && _pages != null)
                    ExpansionTile(
                      title: const Text('قراءة نص السجل'),
                      children: [
                        Text(
                          'الأصل: ${statementAmount(s, s.original)} • المسدد: ${statementAmount(s, s.settled)} • الملغى: ${statementAmount(s, s.cancelled)} • المتبقي: ${statementAmount(s, s.remaining)}',
                        ),
                        for (final e in s.history)
                          ListTile(
                            title: Text(e.label),
                            subtitle: Text(
                              '${e.actorName} • \u2066${e.atShop}\u2069\n${statementAmount(s, e.cancelled > BigInt.zero ? e.cancelled : e.amount)}${e.reason == null ? '' : '\n${e.reason}'}',
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _button(String label, VoidCallback? tap, String key) => OutlinedButton(
    key: Key(key),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, AppTokens.minControlSize),
    ),
    onPressed: tap,
    child: Text(label),
  );
}
