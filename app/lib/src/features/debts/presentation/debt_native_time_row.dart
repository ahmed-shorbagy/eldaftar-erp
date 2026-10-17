import 'dart:async';
import 'package:flutter/material.dart';
import '../../../theme/app_tokens.dart';
import '../application/debt_native_gateway.dart';
import '../application/debt_reminder_coordinator.dart';
import '../application/debt_reminder_device.dart';
import '../application/debt_gateway.dart';
import 'debt_native_screen.dart';

class DebtNativeTimeRow extends StatefulWidget {
  const DebtNativeTimeRow({
    super.key,
    required this.gateway,
    required this.userId,
    required this.shopId,
    required this.summary,
    required this.canRead,
    required this.open,
    this.syncTicks,
    this.reminders,
  });
  final DebtNativeGateway gateway;
  final String userId, shopId;
  final DebtSummary summary;
  final bool Function() canRead;
  final VoidCallback open;
  final Listenable? syncTicks;
  final DebtReminderCoordinator? reminders;
  @override
  State<DebtNativeTimeRow> createState() => _DebtNativeTimeRowState();
}

class _DebtNativeTimeRowState extends State<DebtNativeTimeRow>
    with WidgetsBindingObserver {
  DebtNativeDetail? _data;
  bool _loading = true;
  int _epoch = 0;
  Timer? _poll;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.syncTicks?.addListener(_read);
    _poll = Timer.periodic(const Duration(seconds: 45), (_) => _read());
    _read();
  }

  @override
  void didUpdateWidget(DebtNativeTimeRow old) {
    super.didUpdateWidget(old);
    if (old.syncTicks != widget.syncTicks) {
      old.syncTicks?.removeListener(_read);
      widget.syncTicks?.addListener(_read);
    }
    if (old.summary != widget.summary ||
        old.userId != widget.userId ||
        old.shopId != widget.shopId ||
        old.gateway != widget.gateway) {
      _read();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _read();
  }

  @override
  void dispose() {
    _epoch++;
    _poll?.cancel();
    widget.syncTicks?.removeListener(_read);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _read() async {
    if (!mounted) return;
    final epoch = ++_epoch,
        user = widget.userId,
        shop = widget.shopId,
        source = widget.summary,
        session = widget.gateway.nativeSession(widget.userId);
    setState(() {
      _loading = true;
      _data = null;
    });
    try {
      if (!widget.canRead() || session == null) throw StateError('access');
      final d = await widget.gateway.readNative(
        userId: user,
        shopId: shop,
        sourceKind: source.sourceKind,
        sourceId: source.sourceId,
      );
      if (!mounted || epoch != _epoch) return;
      if (!widget.canRead() ||
          session != widget.gateway.nativeSession(user) ||
          user != widget.userId ||
          shop != widget.shopId ||
          d.row.due.shopId != shop ||
          d.row.due.summary.sourceId != source.sourceId ||
          d.row.due.summary.sourceKind != source.sourceKind) {
        throw StateError('access');
      }
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _data = null;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (_loading) const LinearProgressIndicator(),
      Text(
        _data == null
            ? (_loading
                  ? 'جارٍ قراءة وقت التذكير…'
                  : 'وقت التذكير غير محدث؛ افتح التفاصيل لإعادة القراءة.')
            : 'وقت التذكير: \u2066${_data!.row.time ?? 'بلا تذكير'}\u2069',
        key: const Key('debt-native-time'),
      ),
      if (widget.reminders != null)
        StreamBuilder<ReminderDeviceReport>(
          stream: widget.reminders!.changes,
          initialData: widget.reminders!.report,
          builder: (context, snapshot) => Text(
            deviceReminderText(
              snapshot.data!.rows[widget.summary.debtKey] ??
                  snapshot.data!.state,
            ),
          ),
        ),
      OutlinedButton(
        key: const Key('debt-native-open'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, AppTokens.minControlSize),
        ),
        onPressed: widget.canRead() ? widget.open : null,
        child: const Text('وقت تذكير الدين وحالة الجهاز'),
      ),
    ],
  );
}
