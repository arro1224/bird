import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:flutter/material.dart';

class CopyModeCard extends StatelessWidget {
  const CopyModeCard({super.key, required this.mode, required this.selected, required this.onTap, this.estimate});

  final String mode;
  final bool selected;
  final VoidCallback? onTap;
  final CopyEstimate? estimate;

  @override
  Widget build(BuildContext context) {
    final title = switch (mode) {
      'keep' => '仅复制保留照片',
      'all' => '全量复制',
      'dual' => '双轨复制',
      _ => mode,
    };
    final subtitle = switch (mode) {
      'keep' => '仅复制经过审阅并标记为保留或精选的照片',
      'all' => '复制批次中的所有照片，不做筛选',
      'dual' => '复制保留照片，同时创建完整备份',
      _ => '由盒子重新估算复制范围',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? AppColors.brandLight.withValues(alpha: .55) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            child: Row(
              children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? AppColors.brand : AppColors.inkMuted, size: 27),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                          ),
                          if (mode == 'keep')
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: AppColors.brand, borderRadius: BorderRadius.circular(8)),
                              child: const Text('推荐', style: TextStyle(color: Colors.white, fontSize: 10)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(subtitle, style: const TextStyle(color: AppColors.inkMuted, fontSize: 12)),
                    ],
                  ),
                ),
                if (selected && estimate != null)
                  Text(
                    '${estimate!.fileCount} 张',
                    style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w800),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
