import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/app/theme/app_spacing.dart';
import 'package:aves/bird_companion/core/models/photo_models.dart';
import 'package:flutter/material.dart';

class RatingReasonPanel extends StatelessWidget {
  const RatingReasonPanel({super.key, required this.value, this.currentScore});

  final RatingResult? value;
  final double? currentScore;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bar_chart_rounded, color: AppColors.brand),
              const SizedBox(width: AppSpacing.xs),
              const Expanded(
                child: Text('详细指标', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              Text(
                (currentScore ?? value?.totalScore)?.toStringAsFixed(1) ?? '—',
                key: const ValueKey('rating-current-score'),
                style: const TextStyle(color: AppColors.brand, fontSize: 30, fontWeight: FontWeight.w800),
              ),
              const Text(' / 5', style: TextStyle(color: AppColors.inkMuted)),
            ],
          ),
          const Divider(height: AppSpacing.lg),
          if (value == null)
            const Text('盒子尚未返回评分', style: TextStyle(color: AppColors.inkMuted))
          else ...[
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (value!.qualityScore != null) _Metric(icon: Icons.high_quality_outlined, label: '总体质量', value: value!.qualityScore!),
                if (value!.eyeScore != null) _Metric(icon: Icons.remove_red_eye_outlined, label: '鸟眼', value: value!.eyeScore!),
                if (value!.compositionScore != null) _Metric(icon: Icons.crop_free_rounded, label: '画面安排', value: value!.compositionScore!),
              ],
            ),
            if (value!.reasonTags.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: value!.reasonTags.map((reason) => Chip(label: Text(reason))).toList(),
              ),
            ],
          ],
        ],
      ),
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final double value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minWidth: 104),
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
    decoration: BoxDecoration(color: AppColors.brandLight.withValues(alpha: .65), borderRadius: BorderRadius.circular(AppSpacing.radiusCompact)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: AppColors.brand),
        const SizedBox(width: 6),
        Text(
          '$label ${value.toStringAsFixed(1)}',
          style: const TextStyle(color: AppColors.brandDark, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}
