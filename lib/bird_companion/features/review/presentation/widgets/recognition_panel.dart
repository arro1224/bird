import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:aves/bird_companion/core/presentation/user_facing_text.dart';
import 'package:flutter/material.dart';

class RecognitionPanel extends StatelessWidget {
  const RecognitionPanel({super.key, required this.value, this.currentSpeciesId, this.currentSpecies});
  final RecognitionResult? value;
  final String? currentSpeciesId, currentSpecies;

  @override
  Widget build(BuildContext context) {
    final verified = value?.isOriginalVerified != false;
    final candidates = verified ? value?.candidates ?? const <SpeciesCandidate>[] : const <SpeciesCandidate>[];
    final manual = currentSpecies?.trim();
    final hasManual = manual?.isNotEmpty == true || currentSpeciesId?.isNotEmpty == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('鸟种识别结果', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            if (hasManual) ...[
              const SizedBox(height: 12),
              const Text(
                '人工修正',
                style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700),
              ),
              Text(
                manual?.isNotEmpty == true ? manual! : '已设置人工鸟种',
                key: const ValueKey('recognition-current-species'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const Text('人工修正没有模型置信度；下方保留 AI 原始候选与概率。', style: TextStyle(color: AppColors.inkMuted)),
            ],
            const Divider(height: 24),
            const Text('AI 原始候选', style: TextStyle(fontWeight: FontWeight.w700)),
            if (!verified) const Text('旧缓存中的 AI 原始结果需联网刷新后核对。', style: TextStyle(color: AppColors.pending)),
            if (candidates.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('暂无 AI 识别结果')),
            for (var index = 0; index < candidates.length; index++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: index == 0 ? AppColors.brand : AppColors.mist,
                      foregroundColor: index == 0 ? Colors.white : AppColors.inkMuted,
                      child: Text('${index + 1}', style: const TextStyle(fontSize: 11)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            candidates[index].name,
                            key: !hasManual && index == 0 ? const ValueKey('recognition-current-species') : null,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (candidates[index].latinName?.isNotEmpty == true)
                            Text(
                              candidates[index].latinName!,
                              softWrap: true,
                              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.inkMuted),
                            ),
                          if (candidates[index].englishName?.isNotEmpty == true) Text(candidates[index].englishName!, softWrap: true, style: const TextStyle(fontSize: 12, color: AppColors.inkMuted)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      UserFacingText.recognitionPercent(candidates[index].confidence),
                      key: ValueKey('ai-candidate-confidence-$index'),
                      style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            if (value?.isLowConfidence == true)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('AI 结果待确认，建议结合原图核对。', style: TextStyle(color: AppColors.pending)),
              ),
          ],
        ),
      ),
    );
  }
}
