import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/amount_format.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/gram_input.dart';
import '../domain/nominal_weight_suggestions.dart';
import '../domain/opening_issue.dart';
import '../domain/quantities.dart';

Future<List<NominalSelection>?> showTradeNominalPicker(
  BuildContext context, {
  required String category,
  required List<NominalWeightSuggestion> suggestions,
}) {
  final body = TradeNominalPicker(category: category, suggestions: suggestions);
  final size = MediaQuery.sizeOf(context);
  if (size.width >= AppTokens.wideBreakpoint) {
    return showDialog<List<NominalSelection>>(
      context: context,
      builder: (_) => Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: AppTokens.contentMaxWidth,
            maxHeight: size.height * .84,
          ),
          child: body,
        ),
      ),
    );
  }
  return showModalBottomSheet<List<NominalSelection>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: BoxConstraints(
      maxWidth: AppTokens.contentMaxWidth,
      maxHeight: size.height * .84,
    ),
    builder: (_) => body,
  );
}

class TradeNominalPicker extends StatefulWidget {
  const TradeNominalPicker({
    super.key,
    required this.category,
    required this.suggestions,
  });
  final String category;
  final List<NominalWeightSuggestion> suggestions;

  @override
  State<TradeNominalPicker> createState() => _TradeNominalPickerState();
}

class _TradeNominalPickerState extends State<TradeNominalPicker> {
  final _selected = <int>{};
  late final _counts = [
    for (final _ in widget.suggestions) TextEditingController(text: '1'),
  ];
  String? _error;

  @override
  void dispose() {
    for (final count in _counts) {
      count.dispose();
    }
    super.dispose();
  }

  void _toggle(int index) {
    setState(() {
      if (_selected.contains(index)) {
        _selected.remove(index);
        _counts[index].text = '1';
      } else {
        _selected.add(index);
        if (_counts[index].text.trim().isEmpty) _counts[index].text = '1';
      }
      _error = null;
    });
  }

  void _setCount(int index, String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    setState(() {
      _counts[index].text = digits.isEmpty ? '' : digits;
      _counts[index].selection = TextSelection.collapsed(
        offset: _counts[index].text.length,
      );
      _error = null;
    });
  }

  void _bump(int index, int delta) {
    final parsed = PieceCount.parseWire(_counts[index].text);
    final current = parsed is Accepted<PieceCount>
        ? parsed.value.value.toInt()
        : 0;
    final next = (current + delta).clamp(1, 9999);
    _setCount(index, '$next');
  }

  Milligrams? get _totalMilligrams {
    var sum = BigInt.zero;
    for (final index in _selected) {
      final line = NominalSelection.tryCreate(
        widget.suggestions[index],
        _counts[index].text,
      );
      if (line == null) return null;
      sum += line.milligrams.value;
    }
    if (_selected.isEmpty) return null;
    final parsed = Milligrams.parseWire(sum.toString());
    return parsed is Accepted<Milligrams> ? parsed.value : null;
  }

  void _apply() {
    final result = <NominalSelection>[];
    for (final index in _selected.toList()..sort()) {
      final line = NominalSelection.tryCreate(
        widget.suggestions[index],
        _counts[index].text,
      );
      if (line == null) {
        setState(
          () => _error =
              'أدخل عدداً صحيحاً موجباً لكل نوع، وراجع الوزن الإجمالي.',
        );
        return;
      }
      result.add(line);
    }
    if (result.isEmpty) {
      setState(() => _error = 'اختر نوعاً واحداً على الأقل.');
      return;
    }
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = _totalMilligrams;
    final ordered = _selected.toList()..sort();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.category == 'coin'
                        ? 'الجنيهات والأعداد'
                        : 'السبائك والأعداد',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'إغلاق',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceMd,
                AppTokens.spaceMd,
                AppTokens.spaceMd,
                AppTokens.spaceMd,
              ),
              children: [
                Text(
                  'اختر أكثر من نوع. اضغط الشريحة مرة للاختيار، ثم عدّل العدد بعلامة ×.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                Wrap(
                  spacing: AppTokens.spaceSm,
                  runSpacing: AppTokens.spaceSm,
                  children: [
                    for (final entry in widget.suggestions.indexed)
                      _DenominationChip(
                        key: Key('nominal-select-${entry.$1}'),
                        label: entry.$2.label,
                        grams: entry.$2.grams,
                        selected: _selected.contains(entry.$1),
                        count: _selected.contains(entry.$1)
                            ? _counts[entry.$1].text
                            : null,
                        onTap: () => _toggle(entry.$1),
                      ),
                  ],
                ),
                if (ordered.isNotEmpty) ...[
                  const SizedBox(height: AppTokens.spaceLg),
                  Text(
                    'الأعداد المختارة',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  for (final index in ordered) ...[
                    _SelectedQuantityRow(
                      key: Key('nominal-qty-row-$index'),
                      index: index,
                      label: widget.suggestions[index].label,
                      controller: _counts[index],
                      unitGrams: widget.suggestions[index].grams,
                      onMinus: () => _bump(index, -1),
                      onPlus: () => _bump(index, 1),
                      onChanged: (value) => _setCount(index, value),
                      onClear: () => _toggle(index),
                    ),
                    const SizedBox(height: AppTokens.spaceSm),
                  ],
                ],
                if (_error != null) ...[
                  const SizedBox(height: AppTokens.spaceSm),
                  Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceMd,
                AppTokens.spaceSm,
                AppTokens.spaceMd,
                AppTokens.spaceMd,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    total == null
                        ? 'الوزن المقترح: —'
                        : 'الوزن المقترح: ${displayGrams(total.gramsText)} جرام',
                    key: const Key('nominal-total'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'الوزن قابل للتعديل بعد الإضافة.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  FilledButton(
                    key: const Key('nominal-apply'),
                    onPressed: _apply,
                    child: Text(
                      ordered.isEmpty
                          ? 'إضافة الاختيارات'
                          : 'إضافة ${ordered.length == 1 ? 'النوع' : '${ordered.length} أنواع'}',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DenominationChip extends StatelessWidget {
  const _DenominationChip({
    super.key,
    required this.label,
    required this.grams,
    required this.selected,
    required this.onTap,
    this.count,
  });

  final String label;
  final String grams;
  final bool selected;
  final String? count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final countText = (count == null || count!.isEmpty) ? '1' : count!;
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      selectedColor: scheme.primaryContainer,
      checkmarkColor: scheme.primary,
      side: BorderSide(
        color: selected ? scheme.primary : scheme.outline,
        width: selected ? 1.4 : 1,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.minControlSize / 2),
      ),
      padding: const EdgeInsetsDirectional.fromSTEB(4, 6, 10, 6),
      avatar: selected
          ? CircleAvatar(
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  '×$countText',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onPrimary,
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            )
          : null,
      label: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
            ),
          ),
          Text(
            '${displayGrams(grams)} جرام',
            style: theme.textTheme.labelSmall?.copyWith(
              color: selected
                  ? scheme.onPrimaryContainer.withValues(alpha: .85)
                  : scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedQuantityRow extends StatelessWidget {
  const _SelectedQuantityRow({
    super.key,
    required this.index,
    required this.label,
    required this.controller,
    required this.unitGrams,
    required this.onMinus,
    required this.onPlus,
    required this.onChanged,
    required this.onClear,
  });

  final int index;
  final String label;
  final TextEditingController controller;
  final String unitGrams;
  final VoidCallback onMinus;
  final VoidCallback onPlus;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selection = NominalSelection.tryCreate(
      NominalWeightSuggestion(
        label: label,
        grams: unitGrams,
        category: 'coin',
        fromCatalog: false,
      ),
      controller.text,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(AppTokens.fieldRadius),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'إزالة',
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 20),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _QtyButton(
                  key: Key('nominal-count-$index-minus'),
                  icon: Icons.remove_rounded,
                  onPressed: onMinus,
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 88,
                  child: Directionality(
                    textDirection: TextDirection.ltr,
                    child: TextField(
                      key: Key('nominal-count-$index'),
                      controller: controller,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        const GramInputFormatter(decimalPlaces: 0),
                        LengthLimitingTextInputFormatter(4),
                      ],
                      decoration: InputDecoration(
                        isDense: true,
                        prefixText: '× ',
                        prefixStyle: theme.textTheme.titleMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppTokens.fieldRadius,
                          ),
                        ),
                      ),
                      onChanged: onChanged,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _QtyButton(
                  key: Key('nominal-count-$index-plus'),
                  icon: Icons.add_rounded,
                  onPressed: onPlus,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    selection == null
                        ? 'أدخل عدداً صحيحاً'
                        : '${displayGrams(selection.milligrams.gramsText)} جرام',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: selection == null
                          ? scheme.error
                          : scheme.onSurfaceVariant,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  const _QtyButton({super.key, required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox.square(
          dimension: AppTokens.minControlSize,
          child: Icon(icon, color: scheme.primary),
        ),
      ),
    );
  }
}
