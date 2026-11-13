import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../theme/app_tokens.dart';
import '../../support/presentation/support_screen.dart' show supportDateText;
import '../domain/broadcast_models.dart';

/// Arabic copy for the owner message inbox (ADR 0048).
abstract final class BroadcastCopy {
  static const title = 'الرسائل';
  static const empty = 'لا توجد رسائل حاليًا.';
  static const loadError = 'تعذر تحميل الرسائل. حاول مجددًا.';
  static const retry = 'إعادة المحاولة';
  static const unread = 'جديدة';
  static const openLink = 'فتح الرابط';
  static const readFailed =
      'تعذر تسجيل قراءة الرسالة. ستبقى جديدة حتى تُفتح مرة أخرى.';
  static const accessLost = 'لم تعد هذه الرسائل متاحة لهذا الحساب.';
  static String unreadCount(int count) =>
      count == 1 ? 'رسالة جديدة واحدة' : '$count رسائل جديدة';
}

class BroadcastInboxScreen extends StatefulWidget {
  const BroadcastInboxScreen({
    super.key,
    required this.gateway,
    this.initial,
    this.onChanged,
  });

  final BroadcastGateway gateway;

  /// The inbox already loaded by the workspace, shown while refreshing.
  final BroadcastInbox? initial;

  /// Called with the latest inbox after loads and reads.
  final ValueChanged<BroadcastInbox>? onChanged;

  @override
  State<BroadcastInboxScreen> createState() => _BroadcastInboxScreenState();
}

class _BroadcastInboxScreenState extends State<BroadcastInboxScreen> {
  BroadcastInbox? _inbox;
  String? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _inbox = widget.initial;
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final inbox = await widget.gateway.listMine();
      if (!mounted || generation != _generation) return;
      setState(() {
        _inbox = inbox;
        _loading = false;
      });
      widget.onChanged?.call(inbox);
    } on BroadcastException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        if (error.failure == BroadcastFailure.unauthorized) {
          _inbox = null;
          _error = BroadcastCopy.accessLost;
        } else {
          _error = BroadcastCopy.loadError;
        }
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = BroadcastCopy.loadError;
      });
    }
  }

  Future<void> _open(OwnerBroadcast item) async {
    final inbox = _inbox;
    if (inbox == null) return;
    final readFuture = item.isUnread ? _markRead(item) : null;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BroadcastDetailScreen(
          item: item,
          timeZone: inbox.timeZone,
          readResult: readFuture,
        ),
      ),
    );
  }

  Future<bool> _markRead(OwnerBroadcast item) async {
    try {
      final result = await widget.gateway.markRead(item.id);
      if (!mounted) return true;
      final current = _inbox;
      if (current != null) {
        final next = current.withRead(item.id, result.readAt);
        setState(() => _inbox = next);
        widget.onChanged?.call(next);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inbox = _inbox;
    return Scaffold(
      appBar: AppBar(title: const Text(BroadcastCopy.title)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTokens.contentMaxWidth,
            ),
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                key: const Key('broadcast-inbox-list'),
                padding: const EdgeInsets.all(AppTokens.spaceMd),
                children: [
                  if (inbox != null && inbox.unreadCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
                      child: Text(
                        BroadcastCopy.unreadCount(inbox.unreadCount),
                        key: const Key('broadcast-unread-count'),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  if (_loading && inbox == null)
                    const Padding(
                      padding: EdgeInsets.all(AppTokens.spaceXl),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null && inbox == null)
                    Padding(
                      padding: const EdgeInsets.all(AppTokens.spaceLg),
                      child: Column(
                        children: [
                          Text(
                            _error!,
                            key: const Key('broadcast-inbox-error'),
                            textAlign: TextAlign.center,
                          ),
                          if (_error == BroadcastCopy.loadError) ...[
                            const SizedBox(height: AppTokens.spaceSm),
                            FilledButton(
                              onPressed: _load,
                              child: const Text(BroadcastCopy.retry),
                            ),
                          ],
                        ],
                      ),
                    )
                  else if (inbox == null || inbox.items.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(AppTokens.spaceXl),
                      child: Center(child: Text(BroadcastCopy.empty)),
                    )
                  else ...[
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppTokens.spaceSm,
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    for (final item in inbox.items)
                      _BroadcastTile(
                        key: Key('broadcast-${item.id}'),
                        item: item,
                        timeZone: inbox.timeZone,
                        onTap: () => _open(item),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BroadcastTile extends StatelessWidget {
  const _BroadcastTile({
    super.key,
    required this.item,
    required this.timeZone,
    required this.onTap,
  });

  final OwnerBroadcast item;
  final String timeZone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppTokens.spaceSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.cardRadius),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: AppTokens.minControlSize,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spaceMd),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.titleAr,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: item.isUnread
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.bodyAr,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        supportDateText(item.startsAt, timeZone),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (item.isUnread) ...[
                  const SizedBox(width: AppTokens.spaceSm),
                  Chip(
                    key: Key('broadcast-unread-${item.id}'),
                    label: const Text(BroadcastCopy.unread),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    labelStyle: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                    side: BorderSide.none,
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

class BroadcastDetailScreen extends StatefulWidget {
  const BroadcastDetailScreen({
    super.key,
    required this.item,
    required this.timeZone,
    this.readResult,
  });

  final OwnerBroadcast item;
  final String timeZone;

  /// Resolves to false when marking the message read failed.
  final Future<bool>? readResult;

  @override
  State<BroadcastDetailScreen> createState() => _BroadcastDetailScreenState();
}

class _BroadcastDetailScreenState extends State<BroadcastDetailScreen> {
  bool _readFailed = false;

  @override
  void initState() {
    super.initState();
    widget.readResult?.then((ok) {
      if (mounted && !ok) setState(() => _readFailed = true);
    });
  }

  Future<void> _openLink() async {
    final uri = Uri.tryParse(widget.item.linkUrl ?? '');
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    return Scaffold(
      appBar: AppBar(title: const Text(BroadcastCopy.title)),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: AppTokens.contentMaxWidth,
            ),
            child: ListView(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              children: [
                Text(
                  item.titleAr,
                  key: const Key('broadcast-detail-title'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  supportDateText(item.startsAt, widget.timeZone),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: AppTokens.spaceMd),
                SelectableText(
                  item.bodyAr,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
                if (item.linkUrl != null) ...[
                  const SizedBox(height: AppTokens.spaceMd),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FilledButton.icon(
                      key: const Key('broadcast-detail-link'),
                      onPressed: _openLink,
                      icon: const Icon(Icons.open_in_new),
                      label: const Text(BroadcastCopy.openLink),
                    ),
                  ),
                ],
                if (_readFailed) ...[
                  const SizedBox(height: AppTokens.spaceMd),
                  Text(
                    BroadcastCopy.readFailed,
                    key: const Key('broadcast-read-failed'),
                    style: TextStyle(color: theme.colorScheme.error),
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
