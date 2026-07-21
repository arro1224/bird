import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/presentation/user_facing_text.dart';
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
                Text('鸟种识别结果', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
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
                        const Text('可能是', style: TextStyle(color: AppColors.inkMuted)),
                        const SizedBox(height: 8),
                        Text(first.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 16),
                        const Text('识别度', style: TextStyle(color: AppColors.inkMuted)),
                        Text(
                          UserFacingText.recognitionCertainty(first.confidence),
                          style: const TextStyle(fontSize: 24, color: AppColors.brand, fontWeight: FontWeight.w800),
                        ),
                        Text('${(first.confidence * 100).round()}%', style: const TextStyle(color: AppColors.inkMuted)),
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
                        const Text('其他可能的鸟种', style: TextStyle(color: AppColors.inkMuted)),
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
                            trailing: Text(UserFacingText.recognitionCertainty(candidates[index].confidence)),
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
                    Expanded(child: Text('系统不太确定这是什么鸟，建议结合原图和其他结果自行确认。')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
