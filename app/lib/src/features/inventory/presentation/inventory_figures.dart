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
    final price = await showDialog<BigInt?>(
      context: context,
      builder: (context) => const _CashPriceDialog(),
    );
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
        final pageWidth = constraints.maxWidth;
        // Each slot carries half a gap on both sides, so `visible` slots are
        // exactly one viewport wide and page snapping lands on whole tiles.
        final slotWidth = pageWidth / visible;
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
                // The ambient RTL direction already starts a horizontal list
                // at the right edge, so the first figure («عيار 18», C-D5)
                // is the rightmost tile; `reverse` used to put it on the left.
                child: ListView.builder(
                  key: const Key('inventory-figures-page'),
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  physics: const PageScrollPhysics(),
                  itemCount: figures.length,
                  itemBuilder: (context, index) => SizedBox(
                    width: slotWidth,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: gap / 2),
                      child: _tile(figures[index]),
                    ),
                  ),
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

/// Asks for the gram price. It owns its controller so the field is not
/// disposed while the dialog's exit animation still rebuilds it.
class _CashPriceDialog extends StatefulWidget {
  const _CashPriceDialog();

  @override
  State<_CashPriceDialog> createState() => _CashPriceDialogState();
}

class _CashPriceDialogState extends State<_CashPriceDialog> {
  final _field = TextEditingController();
  var _error = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _submit() {
    // The field groups digits («2,500»); parse the plain value.
    final parsed = Piastres.parsePounds(cashInputValue(_field.text));
    if (parsed is! Accepted<Piastres> || parsed.value.value <= BigInt.zero) {
      setState(() => _error = true);
      return;
    }
    Navigator.pop(context, parsed.value.value);
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      title: const Text('أدخل سعر الجرام'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('inventory-cash-price'),
            controller: _field,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: const [CashInputFormatter()],
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'سعر الجرام',
              errorText: _error ? 'أدخل سعرًا صحيحًا أكبر من صفر.' : null,
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
          onPressed: _submit,
          child: const Text('احسب'),
        ),
      ],
    ),
  );
}
