import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:flutter/material.dart';

class RecognitionPanel extends StatelessWidget {
  const RecognitionPanel({super.key, required this.value});

  final RecognitionResult? value;

  @override
  Widget build(BuildContext context) {
    final candidates = value?.candidates.take(3).toList() ?? const <SpeciesCandidate>[];
    final first = candidates.isEmpty ? null : candidates.first;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.eco_outlined, color: AppColors.brand),
                SizedBox(width: 8),
                Text('AI 分析结果', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ],
            ),
            const Divider(height: 24),
            if (first == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: Text('暂无识别结果')),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('识别物种', style: TextStyle(color: AppColors.inkMuted)),
                        const SizedBox(height: 8),
                        Text(first.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 16),
                        const Text('置信度', style: TextStyle(color: AppColors.inkMuted)),
                        Text(
                          '${(first.confidence * 100).round()}%',
                          style: const TextStyle(fontSize: 30, color: AppColors.brand, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  Container(width: 1, height: 112, color: AppColors.outline),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Top 3 候选', style: TextStyle(color: AppColors.inkMuted)),
                        const SizedBox(height: 5),
                        for (var index = 0; index < candidates.length; index++)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 12,
                              backgroundColor: index == 0 ? AppColors.brand : AppColors.mist,
                              foregroundColor: index == 0 ? Colors.white : AppColors.inkMuted,
                              child: Text('${index + 1}', style: const TextStyle(fontSize: 11)),
                            ),
                            title: Text(candidates[index].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            trailing: Text('${(candidates[index].confidence * 100).round()}%'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            if (value?.isLowConfidence == true)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.amberLight, borderRadius: BorderRadius.circular(10)),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: AppColors.pending),
                    SizedBox(width: 8),
                    Expanded(child: Text('当前识别置信度较低，建议结合原图和其他候选鸟种人工确认。')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
