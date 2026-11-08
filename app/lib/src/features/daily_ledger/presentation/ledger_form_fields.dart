import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/cash_input.dart';
import '../../../theme/gram_input.dart';

/// Decimal money and weight keyboard (number pad with decimal separator).
const TextInputType ledgerDecimalKeyboard = TextInputType.numberWithOptions(
  decimal: true,
);

/// Whole-count keyboard (number pad without letters).
const TextInputType ledgerIntegerKeyboard = TextInputType.number;

/// Signed decimal keyboard for inventory corrections that allow negatives.
const TextInputType ledgerSignedDecimalKeyboard =
    TextInputType.numberWithOptions(decimal: true, signed: true);

/// Filled outline field used by the daily ledger forms.
///
/// Labels stay on the outline (persistent) so empty and filled fields match.
InputDecoration ledgerFieldDecoration(
  BuildContext context, {
  required String label,
  String? helper,
  String? hint,
}) {
  return InputDecoration(
    labelText: label.trim(),
    helperText: helper,
    hintText: hint,
    alignLabelWithHint: true,
    floatingLabelBehavior: FloatingLabelBehavior.always,
    contentPadding: const EdgeInsetsDirectional.fromSTEB(16, 18, 16, 18),
  );
}

/// Money field: LTR digits, cash grouping, and a decimal number keyboard.
TextField ledgerMoneyField({
  Key? key,
  required BuildContext context,
  required TextEditingController controller,
  required String label,
  bool readOnly = false,
  bool signed = false,
  String? helper,
  String? hint,
  int? maxLines = 1,
  TextInputAction? textInputAction,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
  FocusNode? focusNode,
  List<TextInputFormatter>? extraFormatters,
}) {
  return TextField(
    key: key,
    controller: controller,
    focusNode: focusNode,
    readOnly: readOnly,
    maxLines: maxLines,
    textDirection: TextDirection.ltr,
    keyboardType: signed ? ledgerSignedDecimalKeyboard : ledgerDecimalKeyboard,
    textInputAction: textInputAction,
    autocorrect: false,
    enableSuggestions: false,
    inputFormatters: [
      CashInputFormatter(signed: signed),
      ...?extraFormatters,
    ],
    decoration: ledgerFieldDecoration(
      context,
      label: label,
      helper: helper,
      hint: hint,
    ),
    onChanged: onChanged,
    onSubmitted: onSubmitted,
  );
}

/// Weight-in-grams field with a decimal number keyboard.
TextField ledgerGramsField({
  Key? key,
  required BuildContext context,
  required TextEditingController controller,
  required String label,
  bool readOnly = false,
  String? helper,
  List<TextInputFormatter>? inputFormatters,
  TextInputAction? textInputAction,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
  FocusNode? focusNode,
}) {
  return TextField(
    key: key,
    controller: controller,
    focusNode: focusNode,
    readOnly: readOnly,
    textDirection: TextDirection.ltr,
    keyboardType: ledgerDecimalKeyboard,
    textInputAction: textInputAction,
    autocorrect: false,
    enableSuggestions: false,
    inputFormatters:
        inputFormatters ?? const [GramInputFormatter(decimalPlaces: 3)],
    decoration: ledgerFieldDecoration(context, label: label, helper: helper),
    onChanged: onChanged,
    onSubmitted: onSubmitted,
  );
}

/// Piece-count field with an integer number keyboard.
TextField ledgerCountField({
  Key? key,
  required BuildContext context,
  required TextEditingController controller,
  required String label,
  bool readOnly = false,
  String? helper,
  List<TextInputFormatter>? inputFormatters,
  TextInputAction? textInputAction,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
  FocusNode? focusNode,
}) {
  return TextField(
    key: key,
    controller: controller,
    focusNode: focusNode,
    readOnly: readOnly,
    textDirection: TextDirection.ltr,
    keyboardType: ledgerIntegerKeyboard,
    textInputAction: textInputAction,
    autocorrect: false,
    enableSuggestions: false,
    inputFormatters:
        inputFormatters ?? const [GramInputFormatter(decimalPlaces: 0)],
    decoration: ledgerFieldDecoration(context, label: label, helper: helper),
    onChanged: onChanged,
    onSubmitted: onSubmitted,
  );
}

/// Places two fields in a row when the row is wide enough, and stacks them otherwise.
class LedgerFieldPair extends StatelessWidget {
  const LedgerFieldPair({
    super.key,
    required this.first,
    required this.second,
    this.breakpoint = 440,
  });

  final Widget first;
  final Widget second;
  final double breakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: 12), second],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 12),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

/// Compact closing count. The column header is the label, so the field has none.
class ClosingCountCell extends StatelessWidget {
  const ClosingCountCell({
    super.key,
    required this.controller,
    required this.semanticsLabel,
    this.fieldKey,
    this.readOnly = false,
    this.weight = false,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String semanticsLabel;
  final Key? fieldKey;
  final bool readOnly;
  final bool weight;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel,
      child: SizedBox(
        width: weight ? 80 : 64,
        child: TextField(
          key: fieldKey,
          controller: controller,
          readOnly: readOnly,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          textInputAction: textInputAction,
          keyboardType: weight
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.number,
          inputFormatters: weight
              ? const [GramInputFormatter(decimalPlaces: 3)]
              // Converts Arabic-Indic digits to ASCII first, then caps at 9999.
              : [
                  const GramInputFormatter(decimalPlaces: 0),
                  LengthLimitingTextInputFormatter(4),
                ],
          onSubmitted: onSubmitted,
          decoration: ledgerFieldDecoration(context, label: ' ').copyWith(
            labelText: null,
            floatingLabelBehavior: FloatingLabelBehavior.never,
            isDense: true,
            hintText: weight ? 'جم' : null,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 8,
              horizontal: 4,
            ),
          ),
        ),
      ),
    );
  }
}

/// Type / count / optional weight for a closing-count row.
///
/// One line of three fields when the row is at least [oneLineBreakpoint]
/// wide; otherwise type+count on the first line and weight on the second.
class LedgerCountFields extends StatelessWidget {
  const LedgerCountFields({
    super.key,
    required this.type,
    required this.count,
    required this.weight,
    this.oneLineBreakpoint = 400,
  });

  final Widget type;
  final Widget count;
  final Widget weight;
  final double oneLineBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= oneLineBreakpoint) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: type),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: count),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: weight),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: type),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: count),
              ],
            ),
            const SizedBox(height: 8),
            weight,
          ],
        );
      },
    );
  }
}
