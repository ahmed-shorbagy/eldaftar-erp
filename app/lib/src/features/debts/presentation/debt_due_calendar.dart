import 'package:flutter/material.dart';
import '../../../theme/app_tokens.dart';
import '../domain/debt_calendar_date.dart';

const _months = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];
const _weekdays = [
  'الاثنين',
  'الثلاثاء',
  'الأربعاء',
  'الخميس',
  'الجمعة',
  'السبت',
  'الأحد',
];

/// Calendar editing only. The initial/current date always comes from the
/// authorized server snapshot; no device clock classifies the obligation.
class DebtDueCalendarDialog extends StatefulWidget {
  const DebtDueCalendarDialog({super.key, required this.initial});
  final DebtCalendarDate initial;
  @override
  State<DebtDueCalendarDialog> createState() => _DebtDueCalendarDialogState();
}

class _DebtDueCalendarDialogState extends State<DebtDueCalendarDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _text;
  late DebtCalendarDate _selected;
  late int _year, _month;
  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _year = _selected.calendar.year;
    _month = _selected.calendar.month;
    _text = TextEditingController(text: _selected.wire);
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _select(DebtCalendarDate date) {
    setState(() {
      _selected = date;
      _year = date.calendar.year;
      _month = date.calendar.month;
      _text.text = date.wire;
    });
  }

  DebtCalendarDate _day(int day) => DebtCalendarDate.parse(
    '${_year.toString().padLeft(4, '0')}-${_month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}',
  )!;
  int get _days {
    for (var n = 31; n >= 28; n--) {
      if (DebtCalendarDate.parse(
            '${_year.toString().padLeft(4, '0')}-${_month.toString().padLeft(2, '0')}-$n',
          ) !=
          null) {
        return n;
      }
    }
    return 28;
  }

  void _shift(int delta) {
    final index = (_year - 1) * 12 + _month - 1 + delta;
    if (index < 0 || index >= 9999 * 12) return;
    setState(() {
      _year = index ~/ 12 + 1;
      _month = index % 12 + 1;
    });
  }

  Widget _button(String text, VoidCallback? tap, {Key? key}) => OutlinedButton(
    key: key,
    onPressed: tap,
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(
        AppTokens.minControlSize,
        AppTokens.minControlSize,
      ),
    ),
    child: Text(text),
  );
  Widget _choice(int day, {required bool grid}) {
    final date = _day(day), selected = date.wire == _selected.wire;
    return Semantics(
      selected: selected,
      label: '${_weekdays[date.calendar.weekday - 1]} ${date.wire}',
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: OutlinedButton(
          key: Key('due-calendar-day-${date.wire}'),
          onPressed: () => _select(date),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(
              AppTokens.minControlSize,
              AppTokens.minControlSize,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            backgroundColor: selected
                ? Theme.of(context).colorScheme.primaryContainer
                : null,
            foregroundColor: selected
                ? Theme.of(context).colorScheme.onPrimaryContainer
                : null,
          ),
          child: Text(
            grid
                ? '\u2066$day\u2069'
                : '${_weekdays[date.calendar.weekday - 1]} · \u2066${date.wire}\u2069',
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: 560,
        maxHeight: MediaQuery.sizeOf(context).height * .9,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.spaceMd),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'اختر موعد الاستحقاق',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppTokens.spaceMd),
            Flexible(
              child: LayoutBuilder(
                builder: (context, box) {
                  final grid =
                      box.maxWidth >= 420 &&
                      MediaQuery.textScalerOf(context).scale(16) <= 21;
                  return ListView(
                    padding: const EdgeInsets.only(top: AppTokens.spaceMd),
                    shrinkWrap: true,
                    children: [
                      Form(
                        key: _form,
                        child: TextFormField(
                          key: const Key('due-calendar-input'),
                          controller: _text,
                          textDirection: TextDirection.ltr,
                          decoration: const InputDecoration(
                            labelText: 'تاريخ الاستحقاق',
                            helperText: 'سنة-شهر-يوم',
                            errorMaxLines: 3,
                          ),
                          validator: (value) =>
                              DebtCalendarDate.parse(value ?? '') == null
                              ? 'أدخل تاريخًا صحيحًا.'
                              : null,
                          onChanged: (value) {
                            final date = DebtCalendarDate.parse(value);
                            if (date != null) {
                              setState(() {
                                _selected = date;
                                _year = date.calendar.year;
                                _month = date.calendar.month;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: AppTokens.spaceMd),
                      Text(
                        '${_months[_month - 1]} · \u2066$_year\u2069',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Wrap(
                        spacing: AppTokens.spaceSm,
                        runSpacing: AppTokens.spaceSm,
                        children: [
                          _button(
                            'الشهر السابق',
                            _year == 1 && _month == 1 ? null : () => _shift(-1),
                            key: const Key('due-calendar-previous'),
                          ),
                          _button(
                            'الشهر التالي',
                            _year == 9999 && _month == 12
                                ? null
                                : () => _shift(1),
                            key: const Key('due-calendar-next'),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppTokens.spaceSm),
                      if (grid)
                        GridView.count(
                          crossAxisCount: 7,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: [
                            for (var day = 1; day <= _days; day++)
                              _choice(day, grid: true),
                          ],
                        )
                      else ...[
                        for (var day = 1; day <= _days; day++)
                          _choice(day, grid: false),
                      ],
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppTokens.spaceSm,
              runSpacing: AppTokens.spaceSm,
              children: [
                _button(
                  'إلغاء',
                  () => Navigator.of(context).pop(),
                  key: const Key('due-calendar-cancel'),
                ),
                _button('اختيار', () {
                  if (_form.currentState!.validate()) {
                    Navigator.of(
                      context,
                    ).pop(DebtCalendarDate.parse(_text.text));
                  }
                }, key: const Key('due-calendar-confirm')),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
