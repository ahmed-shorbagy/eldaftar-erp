import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../theme/app_tokens.dart';

/// Keeps the owner's action button reachable while the ledger scrolls.
class LedgerQuickActions extends StatefulWidget {
  const LedgerQuickActions({
    super.key,
    required this.shopId,
    required this.child,
    required this.panelBuilder,
    required this.enabled,
  });
  final String shopId;
  final Widget child;
  final WidgetBuilder panelBuilder;
  final bool enabled;

  @override
  State<LedgerQuickActions> createState() => _LedgerQuickActionsState();
}

class _LedgerQuickActionsState extends State<LedgerQuickActions> {
  final _portal = OverlayPortalController();
  Offset _position = const Offset(0, 1);
  bool _edited = false;
  Future<void> _saveTail = Future<void>.value();
  String get _key => 'ledger_action_position_${widget.shopId}';

  @override
  void initState() {
    super.initState();
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.enabled) _portal.show();
    });
  }

  @override
  void didUpdateWidget(covariant LedgerQuickActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shopId != widget.shopId) {
      _position = const Offset(0, 1);
      _edited = false;
      _load();
    }
    if (widget.enabled != oldWidget.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.enabled ? _portal.show() : _portal.hide();
      });
    }
  }

  Future<void> _load() async {
    final key = _key;
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getStringList(key);
      if (!mounted || _edited || key != _key || value?.length != 2) return;
      final x = double.tryParse(value![0]);
      final y = double.tryParse(value[1]);
      if (x == null || y == null || !x.isFinite || !y.isFinite) return;
      setState(() => _position = Offset(x.clamp(0, 1), y.clamp(0, 1)));
    } catch (_) {
      /* Position preference does not alter financial data. */
    }
  }

  void _save() {
    _edited = true;
    final key = _key;
    final position = [_position.dx.toString(), _position.dy.toString()];
    _saveTail = _saveTail.then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(key, position);
      } catch (_) {
        /* Keep the current position for this session. */
      }
    });
  }

  Future<void> _open() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: BoxConstraints(
      maxWidth: AppTokens.contentMaxWidth,
      maxHeight: MediaQuery.sizeOf(context).height * 0.9,
    ),
    builder: (sheet) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'إجراءات سريعة',
                    style: Theme.of(sheet).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  key: const Key('ledger-close-quick-actions'),
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.of(sheet).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    widget.panelBuilder(sheet),
                    const SizedBox(height: 16),
                    const Divider(),
                    ExpansionTile(
                      title: const Text('موضع زر الإجراءات'),
                      children: [
                        Wrap(
                          spacing: 8,
                          children: [
                            for (final corner in const [
                              ('أعلى اليمين', Offset(1, 0)),
                              ('أعلى اليسار', Offset(0, 0)),
                              ('أسفل اليمين', Offset(1, 1)),
                              ('أسفل اليسار', Offset(0, 1)),
                            ])
                              TextButton(
                                onPressed: () {
                                  setState(() => _position = corner.$2);
                                  _save();
                                  Navigator.of(sheet).pop();
                                },
                                child: Text(corner.$1),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => OverlayPortal(
    controller: _portal,
    overlayChildBuilder: (context) => Positioned.fill(
      child: LayoutBuilder(
        builder: (context, bounds) {
          // SafeArea may remove route padding; keep the physical system insets
          // when positioning in the root overlay above workspace navigation.
          final view = View.of(context);
          final padding = EdgeInsets.fromViewPadding(
            view.viewPadding,
            view.devicePixelRatio,
          );
          final top = padding.top + kToolbarHeight + 8;
          final bottom =
              padding.bottom +
              88 +
              (MediaQuery.textScalerOf(context).scale(AppTokens.detailSize) -
                      AppTokens.detailSize)
                  .clamp(0, 80); // Clear the workspace navigation.
          final width = (bounds.maxWidth - 80).clamp(1.0, double.infinity);
          final height = (bounds.maxHeight - top - bottom - 56).clamp(
            1.0,
            double.infinity,
          );
          return Stack(
            children: [
              Positioned(
                left: 12 + _position.dx * width,
                top: top + _position.dy * height,
                child: GestureDetector(
                  onPanUpdate: (event) => setState(
                    () => _position = Offset(
                      (_position.dx + event.delta.dx / width).clamp(0, 1),
                      (_position.dy + event.delta.dy / height).clamp(0, 1),
                    ),
                  ),
                  onPanEnd: (_) => _save(),
                  child: FloatingActionButton(
                    key: const Key('ledger-quick-actions'),
                    heroTag: null,
                    tooltip: 'إجراءات سريعة',
                    onPressed: _open,
                    child: const Icon(Icons.bolt),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
    child: widget.child,
  );
}
