import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:flutter/material.dart';

class AnalysisPlaceholder extends StatelessWidget {
  const AnalysisPlaceholder({super.key, required this.state});
  final AnalysisState state;
  @override
  Widget build(BuildContext c) => ColoredBox(
    color: Theme.of(c).colorScheme.surfaceContainerHighest,
    child: Center(
      child: Text(switch (state) {
        AnalysisState.processing => '分析中',
        AnalysisState.failed => '分析失败',
        AnalysisState.skipped => '已跳过',
        AnalysisState.lowConfidence => '低置信度',
        AnalysisState.completed => '已完成',
        _ => '待分析',
      }),
    ),
  );
}
