import 'package:flutter/material.dart';

import '../../../theme/whatsapp_icon.dart';
import '../application/daily_ledger_view.dart';
import '../application/financial_gateway.dart';
import 'financial_operation_screen.dart';
import 'opening_copy.dart';

class PendingInvoiceSendsScreen extends StatefulWidget {
  const PendingInvoiceSendsScreen({
    super.key,
    required this.gateway,
    required this.userId,
    this.syncTicks,
  });

  final FinancialGateway gateway;
  final String userId;
  final Listenable? syncTicks;

  @override
  State<PendingInvoiceSendsScreen> createState() =>
      _PendingInvoiceSendsScreenState();
}

class _PendingInvoiceSendsScreenState extends State<PendingInvoiceSendsScreen> {
  final _items = <PendingInvoice>[];
  int? _nextBefore;
  bool _loading = false;
  bool _failed = false;
  bool _loaded = false;
  bool _syncQueued = false;

  @override
  void initState() {
    super.initState();
    widget.syncTicks?.addListener(_onSync);
    _load(reset: true);
  }

  @override
  void didUpdateWidget(covariant PendingInvoiceSendsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.syncTicks != widget.syncTicks) {
      oldWidget.syncTicks?.removeListener(_onSync);
      widget.syncTicks?.addListener(_onSync);
    }
  }

  void _onSync() {
    if (!mounted) return;
    if (_loading) {
      _syncQueued = true;
      return;
    }
    _load(reset: true);
  }

  @override
  void dispose() {
    widget.syncTicks?.removeListener(_onSync);
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    final gateway = widget.gateway;
    if (gateway is! InvoiceDispatchGateway || _loading) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await (gateway as InvoiceDispatchGateway)
          .pendingInvoiceSends(
            callerUserId: widget.userId,
            beforeSequence: reset ? null : _nextBefore,
          );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _nextBefore = page.nextBeforeSequence;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (_syncQueued) {
          _syncQueued = false;
          _load(reset: true);
        }
      }
    }
  }

  Future<void> _open(PendingInvoice item) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => FinancialOperationScreen(
          gateway: widget.gateway,
          userId: widget.userId,
          syncTicks: widget.syncTicks,
          line: LedgerFeedLine(
            kind: item.kind,
            labelAr: item.kind == 'sale' ? 'بيع' : 'شراء',
            operationId: item.operationId,
            actorDisplayName: '',
            occurredAt: '',
            occurredAtCairo: item.occurredAtCairo,
          ),
        ),
      ),
    );
    if (mounted) await _load(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('فواتير تنتظر تأكيد الإرسال')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _loading && !_loaded
                ? const Center(child: CircularProgressIndicator())
                : _failed && !_loaded
                ? Center(
                    child: TextButton.icon(
                      onPressed: () => _load(reset: true),
                      icon: const Icon(Icons.refresh),
                      label: const Text('تعذر تحميل الفواتير. إعادة المحاولة'),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _load(reset: true),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Text(
                          'فواتير العمليات المؤكدة التي لم يؤكد المالك إرسالها عبر واتساب.',
                          style: theme.textTheme.bodyMedium,
                        ),
                        if (_loading) const LinearProgressIndicator(),
                        if (_failed)
                          TextButton.icon(
                            onPressed: () => _load(reset: true),
                            icon: const Icon(Icons.refresh),
                            label: const Text('تعذر التحديث. إعادة المحاولة'),
                          ),
                        if (_items.isEmpty && !_loading) ...[
                          const SizedBox(height: 32),
                          const Center(
                            child: Text('لا توجد فواتير بانتظار تأكيد الإرسال'),
                          ),
                        ],
                        for (final item in _items)
                          Card(
                            child: ListTile(
                              onTap: () => _open(item),
                              leading: IconTheme(
                                data: IconThemeData(
                                  color: theme.colorScheme.primary,
                                ),
                                child: const WhatsappIcon(),
                              ),
                              title: Text(
                                '${item.kind == 'sale' ? 'بيع' : 'شراء'} رقم ${item.shopSequence}',
                              ),
                              subtitle: Text(
                                '${item.customerName.isEmpty ? 'دون اسم عميل' : item.customerName}\n'
                                '${formatServerCairoTimestamp(item.occurredAtCairo)}',
                              ),
                              isThreeLine: true,
                              trailing: const Icon(Icons.chevron_left),
                            ),
                          ),
                        if (_nextBefore != null)
                          OutlinedButton(
                            onPressed: _loading
                                ? null
                                : () => _load(reset: false),
                            child: const Text('عرض المزيد'),
                          ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
