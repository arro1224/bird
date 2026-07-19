import 'package:flutter/material.dart';
import 'package:aves/bird_companion/app/theme/app_colors.dart';

class SortSheet extends StatelessWidget {
  const SortSheet({super.key, required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext c) => ColoredBox(
    color: AppColors.paper,
    child: SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(20),
            child: Text('排序方式', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
          ),
          for (final option in ['captured_at_desc', 'score_desc', 'recommended_desc', 'confidence_desc'])
            ListTile(
              leading: Icon(option == value ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: AppColors.brand),
              onTap: () {
                onChanged(option);
                Navigator.pop(c);
              },
              title: Text(switch (option) {
                'score_desc' => '评分从高到低',
                'confidence_desc' => '置信度从高到低',
                'recommended_desc' => 'AI 推荐优先',
                _ => '拍摄时间最新',
              }),
            ),
        ],
      ),
    ),
  );
}
