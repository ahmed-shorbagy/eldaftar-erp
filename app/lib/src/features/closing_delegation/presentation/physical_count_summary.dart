import 'package:flutter/material.dart';
import '../../../theme/amount_format.dart';

class PhysicalCountSummary extends StatelessWidget {
  const PhysicalCountSummary({super.key, required this.observations});
  final Map<String, Object?> observations;
  String _weight(Object? value) =>
      value is String ? displayGoldEffect(BigInt.parse(value)) : 'لم يُوزن';
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final raw in observations['stock'] as List)
        ListTile(
          title: Text('${(raw as Map)['item_name']} · عيار ${raw['karat']}'),
          subtitle: Text(
            'العدد: ${raw['count']} · الوزن: ${_weight(raw['milligrams'])}',
          ),
        ),
      for (final raw in observations['scrap'] as List)
        ListTile(
          title: Text('كسر عيار ${(raw as Map)['karat']}'),
          subtitle: Text(_weight(raw['milligrams'])),
        ),
    ],
  );
}
