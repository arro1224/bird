import 'package:flutter/material.dart';

class BatchFilterBar extends StatelessWidget {
  const BatchFilterBar({super.key, required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String?> onChanged;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SegmentedButton<String?>(
      segments: const [
        ButtonSegment(value: null, label: Text('全部')),
        ButtonSegment(value: 'in_progress', label: Text('进行中')),
        ButtonSegment(value: 'review', label: Text('待挑选')),
        ButtonSegment(value: 'failed', label: Text('异常')),
      ],
      selected: {value},
      emptySelectionAllowed: true,
      showSelectedIcon: false,
      onSelectionChanged: (v) => onChanged(v.isEmpty ? null : v.first),
    ),
  );
}
