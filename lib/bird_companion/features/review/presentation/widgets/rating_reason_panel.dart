import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:flutter/material.dart';

class RatingReasonPanel extends StatelessWidget {
  const RatingReasonPanel({super.key, required this.value});
  final RatingResult? value;
  @override
  Widget build(BuildContext c) => Card(
    child: ListTile(title: const Text('推荐评分'), subtitle: Text(value?.reasonTags.join(' · ') ?? '暂无评分原因'), trailing: Text(value?.totalScore.toStringAsFixed(1) ?? '-')),
  );
}
