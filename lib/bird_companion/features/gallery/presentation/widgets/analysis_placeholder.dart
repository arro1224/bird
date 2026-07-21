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
        AnalysisState.processing => '正在识别',
        AnalysisState.failed => '未能完成识别',
        AnalysisState.skipped => '已跳过',
        AnalysisState.lowConfidence => '识别结果不确定',
        AnalysisState.completed => '已完成',
        _ => '待分析',
      }),
    ),
  );
}
