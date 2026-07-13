import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:flutter/material.dart';

class CopyModeCard extends StatelessWidget {
  const CopyModeCard({super.key, required this.mode, required this.selected, required this.onTap, this.estimate});
  final String mode;
  final bool selected;
  final VoidCallback onTap;
  final CopyEstimate? estimate;
  @override
  Widget build(BuildContext context) {
    final title = switch (mode) {
      'keep' => '仅复制保留',
      'all' => '全量复制',
      'dual' => '双轨复制',
      _ => mode,
    };
    final subtitle = estimate == null ? '选择后由盒子重新估算' : '${estimate!.fileCount} 张 · ${_formatBytes(estimate!.requiredBytes)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        color: selected ? AppColors.brand : Colors.white,
        child: InkWell(
          borderRadius: BorderRadius.circular(26),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 21),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: selected ? Colors.white : null),
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(color: selected ? const Color(0xFFD9F0D8) : Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                Icon(selected ? Icons.circle : Icons.circle_outlined, color: selected ? Colors.white : AppColors.brand, size: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatBytes(int bytes) => bytes >= 1024 * 1024 * 1024 ? '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB' : '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB';
}
