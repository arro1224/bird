import 'package:flutter/material.dart';

class CopyConfirmDialog extends StatelessWidget {
  const CopyConfirmDialog({super.key, required this.onConfirm});
  final VoidCallback onConfirm;
  @override
  Widget build(BuildContext c) => AlertDialog(
    title: const Text('确认创建复制任务？'),
    content: const Text('盒子将复制原图并生成对应 XMP，不会删除相机卡原片。'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
      FilledButton(
        onPressed: () {
          Navigator.pop(c);
          onConfirm();
        },
        child: const Text('确认复制'),
      ),
    ],
  );
}
