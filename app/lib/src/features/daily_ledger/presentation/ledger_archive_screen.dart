import 'package:flutter/material.dart';

import '../../../theme/app_tokens.dart';
import '../../reports/application/report_gateway.dart';
import '../../reports/domain/financial_day_report.dart';
import '../application/financial_gateway.dart';
import '../application/ledger_date_gateway.dart';
import '../application/ledger_line_items.dart';
import 'financial_operation_screen.dart';
import 'ledger_date_screen.dart';
import 'opening_copy.dart';

/// U18: «مقفول · فُتح 09:30 · أُقفل 21:15». A close after midnight names its
/// date; an older server without a close time shows the opening only.
String archiveDaySubtitle(ReportDay day) {
  final opened = 'مقفول · فُتح ${day.openedAtShop.substring(11, 16)}';
  final closed = day.closedAtShop;
  if (closed == null) return opened;
  final time = closed.substring(11, 16);
  final closedDate = closed.substring(0, 10);
  return closedDate == day.openedAtShop.substring(0, 10)
      ? '$opened · أُقفل $time'
      : '$opened · أُقفل ${formatServerDate(closedDate)} $time';
}

/// Read-only list of closed financial days. Nothing here reopens a day.
class LedgerArchiveScreen extends StatefulWidget {
  const LedgerArchiveScreen({
    super.key,
    required this.reportGateway,
    required this.dateGateway,
    required this.financialGateway,
    required this.userId,
    required this.shopId,
    required this.canRead,
    this.syncTicks,
    this.initialDate,
  });

  final ReportGateway reportGateway;
  final LedgerDateGateway dateGateway;
  final FinancialGateway financialGateway;
  final String userId;
  final String shopId;
  final bool Function() canRead;
  final Listenable? syncTicks;
  final String? initialDate;

  @override
  State<LedgerArchiveScreen> createState() => _LedgerArchiveScreenState();
}

class _LedgerArchiveScreenState extends State<LedgerArchiveScreen> {
  List<ReportDay> _days = const [];
  bool _loading = true;
  bool _failed = false;
  bool _openedInitial = false;

  @override
  void initState() {
    super.initState();
    widget.syncTicks?.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.syncTicks?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final days = await widget.reportGateway.reportDays(
        widget.userId,
        widget.shopId,
      );
      if (!mounted) return;
      final closed =
          [
            for (final day in days)
              if (day.status == 'closed') day,
          ]..sort((a, b) {
            final byDate = b.date.compareTo(a.date);
            if (byDate != 0) return byDate;
            return b.openedAtShop.compareTo(a.openedAtShop);
          });
      // Every closed day is its own entry, even two on one calendar date.
      setState(() {
        _days = closed;
        _loading = false;
      });
      final initial = widget.initialDate;
      if (initial != null && !_openedInitial) {
        _openedInitial = true;
        for (final day in closed) {
          if (day.date == initial) {
            await _open(day);
            break;
          }
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _open(ReportDay day) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => LedgerDateScreen(
          gateway: widget.dateGateway,
          userId: widget.userId,
          shopId: widget.shopId,
          canRead: widget.canRead,
          initialDate: day.date,
          dayId: day.id,
          syncTicks: widget.syncTicks,
          loadItems: (id) async {
            final operation = await widget.financialGateway.operation(
              callerUserId: widget.userId,
              operationId: id,
            );
            return ledgerLineItemsFromPayload(operation['payload']);
          },
          onOperation: (line) async {
            await Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => FinancialOperationScreen(
                  gateway: widget.financialGateway,
                  userId: widget.userId,
                  shopId: widget.shopId,
                  canRead: widget.canRead,
                  canWrite: () => false,
                  line: line,
                  syncTicks: widget.syncTicks,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('الدفاتر')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTokens.contentMaxWidth,
            ),
            child: _loading
                ? const LinearProgressIndicator()
                : _failed
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('تعذر تحميل الدفاتر. أعد المحاولة.'),
                        TextButton(
                          onPressed: _load,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  )
                : _days.isEmpty
                ? const Center(child: Text('لا توجد أيام مقفولة بعد.'))
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      for (var index = 0; index < _days.length; index++) ...[
                        if (index == 0 ||
                            formatLedgerMonth(_days[index].date) !=
                                formatLedgerMonth(_days[index - 1].date))
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 4),
                            child: Text(
                              formatLedgerMonth(_days[index].date),
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                        ListTile(
                          key: Key(
                            index > 0 &&
                                    _days[index - 1].date == _days[index].date
                                ? 'ledger-archive-${_days[index].id}'
                                : 'ledger-archive-${_days[index].date}',
                          ),
                          title: Text(formatLedgerHeading(_days[index].date)),
                          subtitle: Text(archiveDaySubtitle(_days[index])),
                          trailing: const Icon(Icons.chevron_left),
                          onTap: () => _open(_days[index]),
                        ),
                      ],
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
