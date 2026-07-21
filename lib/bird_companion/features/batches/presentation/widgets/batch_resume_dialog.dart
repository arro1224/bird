import 'package:flutter/material.dart';

class BatchResumeDialog extends StatelessWidget {
  const BatchResumeDialog({super.key, required this.onConfirm});
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('继续处理上次拍摄？'),
    content: const Text('盒子会从上次停止的位置继续导入和识别照片。'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      FilledButton(
        onPressed: () {
          Navigator.pop(context);
          onConfirm();
        },
        child: const Text('恢复'),
      ),
    ],
  );
}
