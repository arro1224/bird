import 'package:flutter/material.dart';

class SortSheet extends StatelessWidget {
  const SortSheet({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext c) => Column(
    mainAxisSize: MainAxisSize.min,
    children: ['captured_at_desc', 'score_desc', 'confidence_desc']
        .map(
          (v) => RadioListTile(
            value: v,
            groupValue: value,
            tileColor: Colors.transparent,
            selectedTileColor: Colors.transparent,
            onChanged: (x) {
              onChanged(x!);
              Navigator.pop(c);
            },
            title: Text(switch (v) {
              'score_desc' => '评分从高到低',
              'confidence_desc' => '置信度从高到低',
              _ => '拍摄时间最新',
            }),
          ),
        )
        .toList(),
  );
}
