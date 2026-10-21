import 'package:flutter/material.dart';

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
