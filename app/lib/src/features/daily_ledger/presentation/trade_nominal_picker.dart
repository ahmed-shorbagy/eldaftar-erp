import 'package:flutter/material.dart';

import '../../../theme/amount_format.dart';
import '../../../theme/app_tokens.dart';
import '../../../theme/gram_input.dart';
import '../domain/nominal_weight_suggestions.dart';

Future<List<NominalSelection>?> showTradeNominalPicker(
  BuildContext context, {
  required String category,
  required List<NominalWeightSuggestion> suggestions,
}) => showModalBottomSheet<List<NominalSelection>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  constraints: BoxConstraints(
    maxWidth: AppTokens.contentMaxWidth,
    maxHeight: MediaQuery.sizeOf(context).height * .84,
  ),
  builder: (_) =>
      TradeNominalPicker(category: category, suggestions: suggestions),
);

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
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
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
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'اختر الأنواع وحدد عدد كل نوع. الوزن المقترح قابل للتعديل قبل التأكيد.',
                  ),
                  const SizedBox(height: 12),
                  for (final entry in widget.suggestions.indexed) ...[
                    Card(
                      color: _selected.contains(entry.$1)
                          ? theme.colorScheme.primaryContainer
                          : null,
                      child: Column(
                        children: [
                          CheckboxListTile(
                            key: Key('nominal-select-${entry.$1}'),
                            title: Text(entry.$2.label),
                            subtitle: Text('${entry.$2.grams} جرام للقطعة'),
                            value: _selected.contains(entry.$1),
                            onChanged: (selected) => setState(() {
                              selected == true
                                  ? _selected.add(entry.$1)
                                  : _selected.remove(entry.$1);
                              _error = null;
                            }),
                          ),
                          if (_selected.contains(entry.$1))
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: TextField(
                                key: Key('nominal-count-${entry.$1}'),
                                controller: _counts[entry.$1],
                                textDirection: TextDirection.ltr,
                                keyboardType: TextInputType.number,
                                inputFormatters: const [
                                  GramInputFormatter(decimalPlaces: 0),
                                ],
                                decoration: InputDecoration(
                                  labelText: 'العدد',
                                  helperText: switch (NominalSelection.tryCreate(
                                    entry.$2,
                                    _counts[entry.$1].text,
                                  )) {
                                    final selection? =>
                                      'الوزن الإجمالي المقترح: ${displayGrams(selection.milligrams.gramsText)} جرام',
                                    _ => 'أدخل عدداً صحيحاً موجباً',
                                  },
                                ),
                                onChanged: (_) => setState(() => _error = null),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_error != null)
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('nominal-apply'),
                  onPressed: _apply,
                  child: const Text('إضافة الاختيارات'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
