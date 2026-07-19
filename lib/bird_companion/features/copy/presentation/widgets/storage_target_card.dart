import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:aves/bird_companion/features/copy/domain/copy_repository.dart';
import 'package:flutter/material.dart';

class StorageTargetCard extends StatelessWidget {
  const StorageTargetCard({super.key, required this.target, required this.selected, required this.onTap});

  final StorageTarget target;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final used = target.totalBytes <= 0 ? 0.0 : ((target.totalBytes - target.freeBytes) / target.totalBytes).clamp(0.0, 1.0);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? AppColors.brand : AppColors.outline, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: target.online ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: AppColors.mist,
                    child: Icon(Icons.storage_rounded, color: AppColors.brand),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(target.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  Text(target.online ? '${_formatBytes(target.freeBytes)} 可用' : '未连接', style: TextStyle(color: target.online ? AppColors.inkMuted : AppColors.danger)),
                  const SizedBox(width: 6),
                  Icon(selected ? Icons.check_circle : Icons.chevron_right, color: selected ? AppColors.brand : AppColors.inkMuted),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: used, minHeight: 7, borderRadius: BorderRadius.circular(8), backgroundColor: AppColors.mist),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatBytes(int bytes) {
  const gb = 1024 * 1024 * 1024;
  const tb = gb * 1024;
  if (bytes >= tb) return '${(bytes / tb).toStringAsFixed(1)} TB';
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB';
}
