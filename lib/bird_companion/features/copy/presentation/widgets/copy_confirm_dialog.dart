import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

class CopyConfirmDialog extends StatelessWidget {
  const CopyConfirmDialog({
    super.key,
    required this.onConfirm,
    required this.fileCount,
    required this.requiredBytes,
    required this.targetName,
    required this.xmpEnabled,
    this.lowBatteryPercent,
  });

  final VoidCallback onConfirm;
  final int fileCount;
  final int requiredBytes;
  final String targetName;
  final bool xmpEnabled;
  final int? lowBatteryPercent;

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const CircleAvatar(
      backgroundColor: AppColors.brandLight,
      child: Icon(Icons.help_outline, color: AppColors.brand),
    ),
    title: const Text('确认开始复制？'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('即将复制 $fileCount 张照片到目标存储'),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.mist, borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              _Row(label: '目标存储', value: targetName),
              _Row(label: '预计用量', value: _formatBytes(requiredBytes)),
              _Row(label: '照片编辑信息', value: xmpEnabled ? '同时保存' : '不保存'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text('不会删除相机卡中的原始照片', style: TextStyle(color: AppColors.pending)),
        if (lowBatteryPercent != null) ...[
          const SizedBox(height: 12),
          Container(
            key: const Key('copy-low-battery-warning'),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.amberLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.battery_alert_rounded,
                  color: AppColors.pending,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '盒子电量仅剩 $lowBatteryPercent%，建议连接电源后再复制。',
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
    actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
    actions: [
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              key: const Key('copy-confirm-cancel'),
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              key: const Key('copy-confirm-submit'),
              onPressed: () {
                Navigator.pop(context);
                onConfirm();
              },
              child: const Text('确认开始复制'),
            ),
          ),
        ],
      ),
    ],
  );
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: AppColors.inkMuted)),
        ),
        Flexible(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );
}

String _formatBytes(int bytes) => bytes >= 1024 * 1024 * 1024 ? '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(1)} GB' : '${(bytes / 1024 / 1024).toStringAsFixed(0)} MB';
