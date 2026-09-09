import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

class ReviewConflictBanner extends StatelessWidget {
  const ReviewConflictBanner({
    super.key,
    required this.saving,
    required this.onUseRemote,
    required this.onKeepDraft,
  });

  final bool saving;
  final VoidCallback onUseRemote;
  final VoidCallback onKeepDraft;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    liveRegion: true,
    label: '盒子中有更新，本机草稿尚未同步',
    child: Container(
      key: const Key('review-conflict-banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.amberLight,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.warning.withValues(alpha: .35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.sync_problem_rounded, color: AppColors.warning),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '盒子中有更新，本机草稿尚未同步',
                  style: TextStyle(
                    color: AppColors.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '载入盒子版本会丢弃当前冲突草稿；保留草稿不会覆盖盒子。',
            style: TextStyle(color: AppColors.inkMuted),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: saving ? null : onUseRemote,
                child: const Text('载入盒子最新版本'),
              ),
              FilledButton.tonal(
                onPressed: saving ? null : onKeepDraft,
                child: const Text('保留本机草稿'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
