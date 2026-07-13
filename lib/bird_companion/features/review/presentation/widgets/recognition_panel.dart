import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:flutter/material.dart';

class RecognitionPanel extends StatelessWidget {
  const RecognitionPanel({super.key, required this.value});
  final RecognitionResult? value;
  @override
  Widget build(BuildContext c) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('鸟种识别', style: Theme.of(c).textTheme.titleMedium),
          for (final x in value?.candidates ?? const [])
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(x.name),
              subtitle: const Text('AI 置信度'),
              trailing: Text('${(x.confidence * 100).round()}%'),
            ),
        ],
      ),
    ),
  );
}
