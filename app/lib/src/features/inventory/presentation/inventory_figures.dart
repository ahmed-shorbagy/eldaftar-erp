import 'package:flutter/material.dart';

import '../../../theme/amount_format.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/cash_input.dart';
import '../../daily_ledger/domain/opening_issue.dart';
import '../../daily_ledger/domain/quantities.dart';
import '../../daily_ledger/presentation/ledger_balance_sections.dart';
import '../domain/inventory_item_grid.dart';

String _count(BigInt value) => value.toString().replaceAllMapped(
  RegExp(r'\B(?=(\d{3})+(?!\d))'),
  (_) => ',',
);

/// Horizontal figure carousel for «الجرد الفوري» (ADR 0044 C-D5).
class InventoryFigureCarousel extends StatefulWidget {
  const InventoryFigureCarousel({
    super.key,
    required this.figures,
    this.onCashPrice,
  });

  final List<InventoryFigure> figures;
  final ValueChanged<BigInt?>? onCashPrice;

  @override
  State<InventoryFigureCarousel> createState() =>
      _InventoryFigureCarouselState();
}

class _InventoryFigureCarouselState extends State<InventoryFigureCarousel> {
  final _controller = ScrollController();
  var _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _askPrice() async {
    final field = TextEditingController();
    final price = await showDialog<BigInt?>(
      context: context,
      builder: (context) {
        var error = false;
        return StatefulBuilder(
          builder: (context, setDialogState) => Directionality(
            textDirection: TextDirection.rtl,
            child: AlertDialog(
              title: const Text('أدخل سعر الجرام'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    key: const Key('inventory-cash-price'),
                    controller: field,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [CashInputFormatter()],
                    decoration: InputDecoration(
                      labelText: 'سعر الجرام',
                      errorText: error
                          ? 'أدخل سعرًا صحيحًا أكبر من صفر.'
                          : null,
                    ),
                    autofocus: true,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء'),
                ),
                FilledButton(
                  key: const Key('inventory-cash-price-calc'),
                  onPressed: () {
                    final parsed = Piastres.parsePounds(field.text.trim());
                    if (parsed is! Accepted<Piastres> ||
                        parsed.value.value <= BigInt.zero) {
                      setDialogState(() => error = true);
                      return;
                    }
                    Navigator.pop(context, parsed.value.value);
                  },
                  child: const Text('احسب'),
                ),
              ],
            ),
          ),
        );
      },
    );
    field.dispose();
    if (price != null) widget.onCashPrice?.call(price);
  }

  @override
  Widget build(BuildContext context) {
    final figures = widget.figures;
    if (figures.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      key: const Key('inventory-figures'),
      builder: (context, constraints) {
        final visible = constraints.maxWidth >= 600 ? 4 : 2;
        final gap = AppTokens.spaceSm;
        final tileWidth =
            (constraints.maxWidth - gap * (visible - 1)) / visible;
        final pageWidth = constraints.maxWidth;
        return Column(
          children: [
            SizedBox(
              height: MediaQuery.textScalerOf(
                context,
              ).scale(148).clamp(148, 196),
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification.metrics.axis != Axis.horizontal) {
                    return false;
                  }
                  final page = (notification.metrics.pixels / pageWidth)
                      .round()
                      .clamp(0, (figures.length / visible).ceil() - 1);
                  if (page != _page) setState(() => _page = page);
                  return false;
                },
                child: ListView.separated(
                  key: const Key('inventory-figures-page'),
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  itemCount: figures.length,
                  separatorBuilder: (_, _) => SizedBox(width: gap),
                  itemBuilder: (context, index) =>
                      SizedBox(width: tileWidth, child: _tile(figures[index])),
                ),
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < (figures.length / visible).ceil(); i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _page
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outlineVariant,
                      ),
                      child: const SizedBox(width: 8, height: 8),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _tile(InventoryFigure figure) {
    final String value;
    final String unit;
    if (figure.id == 'cash') {
      final cash = Piastres.parseWire(figure.count!.toString());
      value = cash is Accepted<Piastres>
          ? displayPounds(cash.value.poundsText)
          : '—';
      unit = 'جنيه';
    } else if (figure.cashCalculator && figure.awaitingPrice) {
      value = 'اضغط للحساب';
      unit = '';
    } else if (figure.id == 'bullion_count') {
      value = _count(figure.count ?? BigInt.zero);
      unit = 'قطعة';
    } else {
      value = displayGrams(figure.milligrams.toString());
      unit = 'جرام';
    }
    final tile = LedgerMetricTile(
      key: Key('inventory-figure-${figure.id}'),
      compact: true,
      label: figure.label,
      value: value,
      unit: unit,
      icon: figure.cashCalculator
          ? Icons.calculate_outlined
          : Icons.scale_outlined,
      tone: LedgerMetricTone.primary,
    );
    if (!figure.cashCalculator) return tile;
    return InkWell(
      key: const Key('inventory-figure-cash-calc'),
      onTap: _askPrice,
      borderRadius: BorderRadius.circular(12),
      child: tile,
    );
  }
}
