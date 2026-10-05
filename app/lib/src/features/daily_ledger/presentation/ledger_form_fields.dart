import 'package:flutter/material.dart';

/// Filled outline field used by the daily ledger forms.
InputDecoration ledgerFieldDecoration(
  BuildContext context, {
  required String label,
  String? helper,
}) {
  return InputDecoration(
    labelText: label,
    helperText: helper,
    alignLabelWithHint: true,
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
