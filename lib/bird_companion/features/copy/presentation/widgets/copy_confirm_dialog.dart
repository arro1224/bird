import 'package:aves/bird_companion/app/theme/app_colors.dart';
import 'package:flutter/material.dart';

class CopyConfirmDialog extends StatelessWidget {
  const CopyConfirmDialog({super.key, required this.onConfirm, required this.fileCount, required this.requiredBytes, required this.targetName, required this.xmpEnabled});

  final VoidCallback onConfirm;
  final int fileCount;
  final int requiredBytes;
  final String targetName;
  final bool xmpEnabled;

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
              _Row(label: 'XMP 设置', value: xmpEnabled ? '生成同名 XMP' : '不生成'),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text('不会删除相机卡中的原始照片', style: TextStyle(color: AppColors.pending)),
      ],
    ),
    actions: [
      OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(
        onPressed: () {
          Navigator.pop(context);
          onConfirm();
        },
        child: const Text('确认开始复制'),
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
